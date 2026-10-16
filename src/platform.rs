#![cfg(target_os = "macos")]

use anyhow::{Context, Result, anyhow, ensure};
use block2::RcBlock;
use core_foundation::{
    base::{CFRange, CFType, CFTypeRef, TCFType},
    boolean::CFBoolean,
    dictionary::CFDictionary,
    runloop::{CFRunLoop, kCFRunLoopDefaultMode},
    string::{CFString, CFStringRef},
    url::CFURL,
};
use core_graphics::event::{
    CGEvent, CGEventFlags, CGEventTap, CGEventTapLocation, CGEventTapOptions, CGEventTapPlacement,
    CGEventType, CallbackResult, EventField,
};
use crossbeam_channel::Sender;
use objc2::{
    MainThreadMarker, MainThreadOnly, class, msg_send,
    rc::Retained,
    runtime::{AnyObject, Bool, ProtocolObject},
    sel,
};
use objc2_app_kit::{
    NSApplication, NSApplicationActivationPolicy, NSBackingStoreType, NSBox, NSBoxType, NSColor,
    NSEventMask, NSFont, NSPanel, NSPasteboard, NSPasteboardItem, NSPasteboardTypeString,
    NSPasteboardWriting, NSScreen, NSSecureTextField, NSTextAlignment, NSTextField, NSTextView,
    NSTitlePosition, NSView, NSWindow, NSWindowCollectionBehavior, NSWindowStyleMask, NSWorkspace,
};
use objc2_foundation::{
    NSArray, NSDate, NSDefaultRunLoopMode, NSPoint, NSRange, NSRect, NSSize, NSString, NSURL,
};
use std::{
    cell::RefCell,
    ffi::c_void,
    path::PathBuf,
    sync::{
        Arc, Once,
        atomic::{AtomicBool, AtomicU8, Ordering},
    },
    thread::{self, JoinHandle},
    time::{Duration, Instant},
};

use crate::gesture::{Action, HoldGesture, KeyEvent};

const INSERTION_MARKER: i64 = 0x564F434F;
const MODIFIERS: CGEventFlags = CGEventFlags::from_bits_retain(0x001E0000);

type AXElementRef = *const c_void;

#[link(name = "ApplicationServices", kind = "framework")]
unsafe extern "C" {
    fn AXIsProcessTrusted() -> u8;
    fn AXIsProcessTrustedWithOptions(options: *const c_void) -> u8;
    fn AXUIElementCreateApplication(pid: i32) -> AXElementRef;
    fn AXUIElementGetTypeID() -> usize;
    fn AXUIElementCopyAttributeValue(
        element: AXElementRef,
        attribute: CFStringRef,
        value: *mut CFTypeRef,
    ) -> i32;
    fn AXUIElementSetAttributeValue(
        element: AXElementRef,
        attribute: CFStringRef,
        value: CFTypeRef,
    ) -> i32;
    fn AXUIElementIsAttributeSettable(
        element: AXElementRef,
        attribute: CFStringRef,
        settable: *mut u8,
    ) -> i32;
    fn AXUIElementSetMessagingTimeout(element: AXElementRef, timeout: f32) -> i32;
    fn AXValueGetTypeID() -> usize;
    fn AXValueGetValue(value: CFTypeRef, value_type: u32, output: *mut c_void) -> u8;
}

#[link(name = "CoreGraphics", kind = "framework")]
unsafe extern "C" {
    fn CGEventSourceFlagsState(state: i32) -> u64;
    fn CGEventSourceCreate(state: i32) -> CFTypeRef;
    fn CGEventCreateKeyboardEvent(source: CFTypeRef, key: u16, down: bool) -> CFTypeRef;
    fn CGEventSetFlags(event: CFTypeRef, flags: u64);
    fn CGEventSetIntegerValueField(event: CFTypeRef, field: u32, value: i64);
    fn CGEventPostToPid(pid: i32, event: CFTypeRef);
}

#[link(name = "AVFoundation", kind = "framework")]
unsafe extern "C" {}

#[link(name = "CoreText", kind = "framework")]
unsafe extern "C" {
    fn CTFontManagerRegisterFontsForURL(url: CFTypeRef, scope: u32, error: *mut CFTypeRef) -> bool;
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Permissions {
    pub microphone: bool,
    pub accessibility: bool,
}

fn microphone_status() -> isize {
    // AVMediaTypeAudio is the documented four-character media type "soun".
    unsafe {
        msg_send![class!(AVCaptureDevice), authorizationStatusForMediaType: &*NSString::from_str("soun")]
    }
}

pub fn permissions() -> Permissions {
    Permissions {
        microphone: microphone_status() == 3,
        accessibility: unsafe { AXIsProcessTrusted() != 0 },
    }
}

pub fn shortcut_modifiers_down() -> bool {
    // Combined-session flags include physical Fn/Globe as well as shortcut modifiers.
    (unsafe { CGEventSourceFlagsState(0) })
        & (MODIFIERS | CGEventFlags::CGEventFlagSecondaryFn).bits()
        != 0
}

pub fn request_microphone() -> Result<()> {
    match microphone_status() {
        3 => Ok(()),
        0 => {
            let completion = RcBlock::new(|_granted: Bool| {});
            // AVFoundation copies the block until its asynchronous completion.
            unsafe {
                let _: () = msg_send![class!(AVCaptureDevice), requestAccessForMediaType: &*NSString::from_str("soun"), completionHandler: &*completion];
            }
            Ok(())
        }
        _ => open_privacy(true),
    }
}

pub fn request_accessibility() -> Result<()> {
    if permissions().accessibility {
        return Ok(());
    }
    let options = CFDictionary::from_CFType_pairs(&[(
        CFString::new("AXTrustedCheckOptionPrompt").as_CFType(),
        CFBoolean::true_value().as_CFType(),
    )]);
    unsafe {
        AXIsProcessTrustedWithOptions(options.as_CFTypeRef());
    }
    open_privacy(false)
}

pub fn open_privacy(microphone: bool) -> Result<()> {
    let pane = if microphone {
        "Microphone"
    } else {
        "Accessibility"
    };
    let string = NSString::from_str(&format!(
        "x-apple.systempreferences:com.apple.preference.security?Privacy_{pane}"
    ));
    let url =
        NSURL::URLWithString(&string).context("Could not construct the System Settings URL.")?;
    ensure!(
        NSWorkspace::sharedWorkspace().openURL(&url),
        "Could not open System Settings."
    );
    Ok(())
}

pub fn copy_text(text: &str) -> Result<()> {
    let pasteboard = NSPasteboard::generalPasteboard();
    pasteboard.clearContents();
    // This framework constant is a process-lifetime NSString.
    ensure!(
        pasteboard.setString_forType(&NSString::from_str(text), unsafe { NSPasteboardTypeString }),
        "Could not copy the transcript."
    );
    Ok(())
}

pub fn hide_dock() {
    if let Some(main) = MainThreadMarker::new() {
        NSApplication::sharedApplication(main)
            .setActivationPolicy(NSApplicationActivationPolicy::Accessory);
    }
}

pub fn activate_dashboard() {
    if let Some(main) = MainThreadMarker::new() {
        let app = NSApplication::sharedApplication(main);
        #[allow(deprecated)]
        app.activateIgnoringOtherApps(true);
    }
}

pub fn show_app() -> Result<()> {
    let executable = std::env::current_exe().context("Could not locate Voco.")?;
    let installed = executable
        .ancestors()
        .find(|path| path.extension().is_some_and(|extension| extension == "app"))
        .map(PathBuf::from)
        .or_else(|| {
            [
                PathBuf::from("/Applications/Voco.app"),
                PathBuf::from(std::env::var_os("HOME")?).join("Applications/Voco.app"),
            ]
            .into_iter()
            .find(|path| path.is_dir())
        })
        .context("Voco.app is not installed. Move Voco to Applications first.")?;
    ensure!(
        NSWorkspace::sharedWorkspace().selectFile_inFileViewerRootedAtPath(
            Some(&NSString::from_str(&installed.to_string_lossy())),
            &NSString::from_str("")
        ),
        "Could not reveal Voco in Finder."
    );
    Ok(())
}

enum Element {
    Remote(CFType),
    Local(Retained<AnyObject>),
}

impl Element {
    fn application(pid: i32) -> Result<Self> {
        // Create returns one retained AX object. CFType releases it exactly once.
        let raw = unsafe { AXUIElementCreateApplication(pid) };
        ensure!(!raw.is_null(), "Could not access the focused application.");
        let element = Self::Remote(unsafe { CFType::wrap_under_create_rule(raw) });
        // Bound calls into an unresponsive application's Accessibility server.
        unsafe {
            AXUIElementSetMessagingTimeout(raw, 0.25);
        }
        Ok(element)
    }

    fn raw(&self) -> Result<AXElementRef> {
        match self {
            Self::Remote(value) => Ok(value.as_CFTypeRef()),
            Self::Local(_) => Err(anyhow!(
                "The local text field does not expose an AX client handle."
            )),
        }
    }

    fn same_as(&self, other: &Self) -> bool {
        match (self, other) {
            (Self::Remote(left), Self::Remote(right)) => left == right,
            (Self::Local(left), Self::Local(right)) => std::ptr::eq(&**left, &**right),
            _ => false,
        }
    }

    fn attribute(&self, name: &str) -> Result<CFType> {
        let name = CFString::new(name);
        let mut raw = std::ptr::null();
        // Copy transfers a +1 reference only on success.
        let error = unsafe {
            AXUIElementCopyAttributeValue(self.raw()?, name.as_concrete_TypeRef(), &mut raw)
        };
        ensure!(
            error == 0 && !raw.is_null(),
            "Could not read the text field. Accessibility returned {error}."
        );
        Ok(unsafe { CFType::wrap_under_create_rule(raw) })
    }

    fn set(&self, name: &str, value: &CFType) -> Result<()> {
        let name = CFString::new(name);
        let error = unsafe {
            AXUIElementSetAttributeValue(
                self.raw()?,
                name.as_concrete_TypeRef(),
                value.as_CFTypeRef(),
            )
        };
        ensure!(
            error == 0,
            "The text field rejected insertion. Accessibility returned {error}."
        );
        Ok(())
    }

    fn string(&self, name: &str) -> Result<String> {
        if let Self::Local(element) = self {
            // AccessKit's NSAccessibility objects live in this process and are read on the main thread.
            let value: Option<Retained<AnyObject>> = unsafe {
                match name {
                    "AXRole" => msg_send![&**element, accessibilityRole],
                    "AXSubrole" => msg_send![&**element, accessibilitySubrole],
                    "AXValue" => msg_send![&**element, accessibilityValue],
                    _ => None,
                }
            };
            return value
                .and_then(|value| value.downcast::<NSString>().ok())
                .map(|value| value.to_string())
                .context("The local text field has no readable text value.");
        }
        self.attribute(name)?
            .downcast_into::<CFString>()
            .map(|value| value.to_string())
            .context("The text field returned an unsupported value.")
    }

    fn selection(&self) -> Result<Selection> {
        if let Self::Local(element) = self {
            let range: NSRange = unsafe { msg_send![&**element, accessibilitySelectedTextRange] };
            ensure!(
                range.location != usize::MAX,
                "The local text field has no readable selection."
            );
            return Ok(Selection {
                location: range.location,
                length: range.length,
            });
        }
        let value = self.attribute("AXSelectedTextRange")?;
        // Runtime type checks precede interpreting an opaque AXValue as CFRange.
        ensure!(
            value.type_of() == unsafe { AXValueGetTypeID() },
            "The text field has no readable selection."
        );
        let mut range = CFRange {
            location: 0,
            length: 0,
        };
        ensure!(
            unsafe {
                AXValueGetValue(value.as_CFTypeRef(), 4, (&mut range as *mut CFRange).cast())
            } != 0,
            "Could not read the text selection."
        );
        ensure!(
            range.location >= 0 && range.length >= 0,
            "The text selection is invalid."
        );
        Ok(Selection {
            location: range.location as usize,
            length: range.length as usize,
        })
    }

    fn is_web_editor(&self) -> bool {
        let mut parent = self.attribute("AXParent").ok();
        for _ in 0..64 {
            let Some(value) = parent else {
                break;
            };
            if value.type_of() != unsafe { AXUIElementGetTypeID() } {
                break;
            }
            let element = Element::Remote(value);
            if element
                .string("AXRole")
                .is_ok_and(|role| role == "AXWebArea")
            {
                return true;
            }
            parent = element.attribute("AXParent").ok();
        }
        false
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Selection {
    location: usize,
    length: usize,
}

pub struct FocusTarget {
    pid: i32,
    element: Element,
    selection: Selection,
    value: Option<String>,
}

pub fn dashboard_visible() -> bool {
    MainThreadMarker::new().is_some_and(|main| {
        NSApplication::sharedApplication(main)
            .windows()
            .iter()
            .any(|window| window.title().to_string() == "Voco" && window.isVisible())
    })
}

pub fn voco_is_focused() -> bool {
    frontmost_pid().is_ok_and(|pid| pid == std::process::id() as i32)
}

fn frontmost_pid() -> Result<i32> {
    NSWorkspace::sharedWorkspace()
        .frontmostApplication()
        .map(|app| app.processIdentifier())
        .context("No application has keyboard focus.")
}

fn focused_element(pid: i32) -> Result<Element> {
    if pid == std::process::id() as i32 {
        let main =
            MainThreadMarker::new().context("Read the practice field on the main thread.")?;
        let app = NSApplication::sharedApplication(main);
        let window = app
            .keyWindow()
            .context("The Voco dashboard has no focused window.")?;
        let responder = window
            .firstResponder()
            .context("Click inside the practice field before dictating.")?;
        if responder.downcast_ref::<NSTextView>().is_some() {
            let field_editor: Bool = unsafe { msg_send![&*responder, isFieldEditor] };
            if field_editor.as_bool() {
                let delegate: Option<Retained<AnyObject>> =
                    unsafe { msg_send![&*responder, delegate] };
                ensure!(
                    delegate.is_none_or(|delegate| delegate
                        .downcast_ref::<NSSecureTextField>()
                        .is_none()),
                    "Voco cannot insert into a password field."
                );
            }
        }
        // Reading the responder directly avoids sending synchronous AX IPC back to our own event loop.
        let focused: Option<Retained<AnyObject>> =
            unsafe { msg_send![&*responder, accessibilityFocusedUIElement] };
        return focused.map(Element::Local).context(
            "The practice field's Accessibility tree is not ready. Click it and try again.",
        );
    }
    let application = Element::application(pid)?;
    let _ = application.set(
        "AXManualAccessibility",
        &CFBoolean::true_value().as_CFType(),
    );
    let value = application.attribute("AXFocusedUIElement")?;
    ensure!(
        value.type_of() == unsafe { AXUIElementGetTypeID() },
        "No text field has keyboard focus."
    );
    Ok(Element::Remote(value))
}

impl FocusTarget {
    pub fn capture() -> Result<Self> {
        ensure!(
            permissions().accessibility,
            "Allow Accessibility access to insert text."
        );
        let pid = frontmost_pid()?;
        let element = focused_element(pid)?;
        validate_text_field(&element)?;
        let selection = element.selection()?;
        let value = element.string("AXValue").ok();
        Ok(Self {
            pid,
            element,
            selection,
            value,
        })
    }

    fn validate(&self) -> Result<()> {
        ensure!(
            permissions().accessibility,
            "Accessibility permission was turned off. Copy your transcript instead."
        );
        ensure!(
            frontmost_pid()? == self.pid,
            "The focused application changed. Copy your transcript instead."
        );
        let current = focused_element(self.pid)?;
        ensure!(
            self.element.same_as(&current),
            "The focused text field changed. Copy your transcript instead."
        );
        validate_text_field(&current)?;
        ensure!(
            current.selection()? == self.selection,
            "The text selection changed. Copy your transcript instead."
        );
        if let Some(before) = &self.value {
            ensure!(
                current.string("AXValue")? == *before,
                "The text field changed while recording. Copy your transcript instead."
            );
        }
        Ok(())
    }

    pub fn insert(&self, text: &str) -> Result<()> {
        if text.is_empty() {
            return Ok(());
        }
        self.validate()?;
        // Fn release and other physical modifiers must settle before synthetic typing.
        ensure!(
            !shortcut_modifiers_down(),
            "Release shortcut keys before inserting. Copy your transcript instead."
        );
        self.validate()?;
        let expected = self
            .value
            .as_ref()
            .map(|before| replace_selection(before, self.selection, text))
            .transpose()?;
        if let Element::Local(element) = &self.element {
            ensure!(
                element.downcast_ref::<NSTextView>().is_some(),
                "This local field does not support native text insertion."
            );
            let allowed: Bool = unsafe {
                msg_send![&**element, isAccessibilitySelectorAllowed: sel!(setAccessibilitySelectedText:)]
            };
            ensure!(
                allowed.as_bool(),
                "Apply practice dictation directly to the dashboard text field."
            );
            self.validate()?;
            unsafe {
                let _: () =
                    msg_send![&**element, setAccessibilitySelectedText: &*NSString::from_str(text)];
            }
            self.verify_write(text, expected.as_deref(), false)?;
            return Ok(());
        }
        let name = CFString::new("AXSelectedText");
        let mut writable = 0;
        let web = self.element.is_web_editor();
        let direct = self.element.raw().ok().is_some_and(|raw| {
            !web && unsafe {
                AXUIElementIsAttributeSettable(raw, name.as_concrete_TypeRef(), &mut writable)
            } == 0
                && writable != 0
        });
        if direct {
            self.validate()?;
            self.element
                .set("AXSelectedText", &CFString::new(text).as_CFType())?;
            self.verify_write(text, expected.as_deref(), false)?;
            return Ok(());
        }
        self.validate()?;
        let clipboard = ClipboardLease::stage(text)?;
        self.validate()?;
        post_paste(self.pid)?;
        self.verify_write(text, expected.as_deref(), web)?;
        drop(clipboard);
        Ok(())
    }

    fn verify_write(&self, text: &str, expected: Option<&str>, web: bool) -> Result<()> {
        let Some(expected) = expected else {
            // Without readable text there is no safe proof of delivery or safe retry.
            thread::sleep(Duration::from_millis(250));
            return Err(anyhow!(
                "The application does not expose readable text. Check whether the transcript was inserted before pasting again."
            ));
        };
        let deadline = Instant::now() + Duration::from_secs(1);
        loop {
            ensure!(
                frontmost_pid()? == self.pid,
                "The focused application changed during insertion. Check the field before pasting again."
            );
            let current = focused_element(self.pid)?;
            ensure!(
                self.element.same_as(&current),
                "The text field changed during insertion. Check the field before pasting again."
            );
            if let Ok(after) = self.element.string("AXValue") {
                let collapsed = Selection {
                    location: self.selection.location + text.encode_utf16().count(),
                    length: 0,
                };
                let changed = self.value.as_deref() != Some(after.as_str())
                    || current
                        .selection()
                        .is_ok_and(|selection| selection == collapsed);
                let matches = text_matches(&after, expected, web)
                    || (web
                        && self.value.as_deref() == Some("\n")
                        && self.selection
                            == (Selection {
                                location: 0,
                                length: 0,
                            })
                        && text_matches(&after, text, true));
                if matches && changed {
                    return Ok(());
                }
            }
            ensure!(
                Instant::now() < deadline,
                "The application did not accept the entire transcript. Check the field before copying it. Voco did not retry insertion."
            );
            thread::sleep(Duration::from_millis(25));
        }
    }
}

fn text_matches(actual: &str, expected: &str, web: bool) -> bool {
    if !web {
        return actual == expected;
    }
    let mut actual = actual.encode_utf16();
    let mut expected = expected.encode_utf16();
    loop {
        match (actual.next(), expected.next()) {
            (None, None) => return true,
            (Some(left), Some(right)) if left == right || (left == 0x00A0 && right == 0x0020) => {}
            _ => return false,
        }
    }
}

struct ClipboardLease {
    pasteboard: Retained<NSPasteboard>,
    saved: Vec<Retained<NSPasteboardItem>>,
    our_change: isize,
}

impl ClipboardLease {
    fn stage(text: &str) -> Result<Self> {
        Self::stage_on(NSPasteboard::generalPasteboard(), text)
    }

    fn stage_on(pasteboard: Retained<NSPasteboard>, text: &str) -> Result<Self> {
        let initial_change = pasteboard.changeCount();
        let mut saved = Vec::new();
        if let Some(items) = pasteboard.pasteboardItems() {
            for item in items.iter() {
                let copy = NSPasteboardItem::new();
                for kind in item.types().iter() {
                    let data = item.dataForType(&kind).context("The clipboard contains data Voco cannot preserve. Copy the transcript manually.")?;
                    ensure!(
                        copy.setData_forType(&data, &kind),
                        "Could not preserve the current clipboard."
                    );
                }
                saved.push(copy);
            }
        }
        ensure!(
            pasteboard.changeCount() == initial_change,
            "The clipboard changed. Try inserting again."
        );
        let our_change = pasteboard.clearContents();
        let mut lease = Self {
            pasteboard,
            saved,
            our_change,
        };
        let written = lease
            .pasteboard
            .setString_forType(&NSString::from_str(text), unsafe { NSPasteboardTypeString });
        lease.our_change = lease.pasteboard.changeCount();
        ensure!(written, "Could not prepare the transcript for pasting.");
        Ok(lease)
    }

    fn restore(&self) {
        if self.pasteboard.changeCount() != self.our_change {
            return;
        }
        self.pasteboard.clearContents();
        if !self.saved.is_empty() {
            let objects: Vec<Retained<ProtocolObject<dyn NSPasteboardWriting>>> = self
                .saved
                .iter()
                .cloned()
                .map(ProtocolObject::from_retained)
                .collect();
            let _ = self
                .pasteboard
                .writeObjects(&NSArray::from_retained_slice(&objects));
        }
    }
}

impl Drop for ClipboardLease {
    fn drop(&mut self) {
        self.restore();
    }
}

fn post_paste(pid: i32) -> Result<()> {
    // Every Create result is adopted into CFType before another fallible operation.
    let source = unsafe { CGEventSourceCreate(-1) };
    ensure!(
        !source.is_null(),
        "Could not create a text insertion source."
    );
    let source = unsafe { CFType::wrap_under_create_rule(source) };
    let down = unsafe { CGEventCreateKeyboardEvent(source.as_CFTypeRef(), 9, true) };
    ensure!(!down.is_null(), "Could not create a text insertion event.");
    let down = unsafe { CFType::wrap_under_create_rule(down) };
    let up = unsafe { CGEventCreateKeyboardEvent(source.as_CFTypeRef(), 9, false) };
    ensure!(!up.is_null(), "Could not create a text insertion event.");
    let up = unsafe { CFType::wrap_under_create_rule(up) };
    // Quartz borrows these retained events while posting. Key-up releases Command.
    unsafe {
        for event in [&down, &up] {
            CGEventSetFlags(event.as_CFTypeRef(), 0);
            CGEventSetIntegerValueField(
                event.as_CFTypeRef(),
                EventField::EVENT_SOURCE_USER_DATA,
                INSERTION_MARKER,
            );
        }
        CGEventSetFlags(down.as_CFTypeRef(), CGEventFlags::CGEventFlagCommand.bits());
        CGEventPostToPid(pid, down.as_CFTypeRef());
        CGEventPostToPid(pid, up.as_CFTypeRef());
    }
    Ok(())
}

fn validate_text_field(element: &Element) -> Result<()> {
    ensure!(
        !element
            .string("AXSubrole")
            .is_ok_and(|role| role == "AXSecureTextField"),
        "Voco cannot insert into a password field."
    );
    ensure!(
        matches!(
            element.string("AXRole")?.as_str(),
            "AXTextField" | "AXTextArea" | "AXComboBox"
        ),
        "Click inside a text field before dictating."
    );
    Ok(())
}

fn replace_selection(before: &str, selection: Selection, text: &str) -> Result<String> {
    let mut units: Vec<u16> = before.encode_utf16().collect();
    ensure!(
        selection.location <= units.len() && selection.length <= units.len() - selection.location,
        "The text selection is out of range."
    );
    units.splice(
        selection.location..selection.location + selection.length,
        text.encode_utf16(),
    );
    String::from_utf16(&units).context("The selection splits a Unicode character.")
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ShortcutStatus {
    Running,
    PermissionRequired,
    Retrying,
    Stopped,
}

pub struct ShortcutMonitor {
    stop: Arc<AtomicBool>,
    restart: Arc<AtomicBool>,
    status: Arc<AtomicU8>,
    thread: Option<JoinHandle<()>>,
}

impl ShortcutMonitor {
    pub fn status(&self) -> ShortcutStatus {
        match self.status.load(Ordering::Acquire) {
            0 => ShortcutStatus::Running,
            1 => ShortcutStatus::PermissionRequired,
            2 => ShortcutStatus::Retrying,
            _ => ShortcutStatus::Stopped,
        }
    }

    pub fn is_running(&self) -> bool {
        self.status() == ShortcutStatus::Running
    }

    pub fn retry(&self) {
        self.restart.store(true, Ordering::Release);
    }
}

impl Drop for ShortcutMonitor {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Release);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

#[derive(Default)]
struct TapGesture {
    hold: HoldGesture,
    consumed_space: bool,
}

impl TapGesture {
    fn handle(
        &mut self,
        event_type: CGEventType,
        event: &CGEvent,
        sender: &Sender<Action>,
    ) -> CallbackResult {
        if event.get_integer_value_field(EventField::EVENT_SOURCE_USER_DATA) == INSERTION_MARKER {
            return CallbackResult::Keep;
        }
        let flags = event.get_flags();
        let code = event.get_integer_value_field(EventField::KEYBOARD_EVENT_KEYCODE);
        let space = code == 49;
        let down = matches!(event_type, CGEventType::KeyDown);
        let up = matches!(event_type, CGEventType::KeyUp);
        let trigger = flags.contains(CGEventFlags::CGEventFlagSecondaryFn);
        let other = flags.intersects(MODIFIERS);
        if down && code == 53 {
            let _ = sender.try_send(Action::Escape);
        }
        let consume = space && ((down && trigger && !other) || self.consumed_space);
        if down && consume {
            self.consumed_space = true;
        }
        if space && up {
            self.consumed_space = false;
        }
        if let Some(action) = self.hold.update(KeyEvent {
            trigger_down: trigger,
            other_modifier: other,
            key_pressed: down,
            space_pressed: space && down,
            space_released: space && up,
            repeat: event.get_integer_value_field(EventField::KEYBOARD_EVENT_AUTOREPEAT) != 0,
        }) {
            let _ = sender.try_send(action);
        }
        if consume {
            CallbackResult::Drop
        } else {
            CallbackResult::Keep
        }
    }
}

pub fn start_shortcuts(sender: Sender<Action>) -> Result<ShortcutMonitor> {
    ensure!(
        permissions().accessibility,
        "Allow Accessibility access to enable Fn shortcuts."
    );
    let stop = Arc::new(AtomicBool::new(false));
    let restart = Arc::new(AtomicBool::new(false));
    let status = Arc::new(AtomicU8::new(2));
    let (ready_tx, ready_rx) = crossbeam_channel::bounded(1);
    let worker_stop = Arc::clone(&stop);
    let worker_restart = Arc::clone(&restart);
    let worker_status = Arc::clone(&status);
    let worker = thread::Builder::new().name("voco-shortcuts".into()).spawn(move || {
        let mut ready = Some(ready_tx);
        while !worker_stop.load(Ordering::Acquire) {
            if !permissions().accessibility {
                worker_status.store(1, Ordering::Release);
                if let Some(ready) = ready.take() { let _ = ready.send(Err(anyhow!("Accessibility access is required for Fn shortcuts."))); }
                thread::sleep(Duration::from_millis(250));
                continue;
            }
            worker_restart.store(false, Ordering::Release);
            let callback_restart = Arc::clone(&worker_restart);
            let callback_status = Arc::clone(&worker_status);
            let callback_sender = sender.clone();
            let gesture = RefCell::new(TapGesture::default());
            let tap = CGEventTap::new(CGEventTapLocation::Session, CGEventTapPlacement::HeadInsertEventTap, CGEventTapOptions::Default,
                vec![CGEventType::FlagsChanged, CGEventType::KeyDown, CGEventType::KeyUp],
                move |_, kind, event| {
                    if matches!(kind, CGEventType::TapDisabledByTimeout | CGEventType::TapDisabledByUserInput) {
                        callback_status.store(2, Ordering::Release);
                        callback_restart.store(true, Ordering::Release);
                        let _ = callback_sender.try_send(Action::Cancelled);
                        return CallbackResult::Keep;
                    }
                    gesture.borrow_mut().handle(kind, event, &callback_sender)
                });
            let Ok(tap) = tap else {
                worker_status.store(2, Ordering::Release);
                if let Some(ready) = ready.take() { let _ = ready.send(Err(anyhow!("macOS could not enable Fn shortcuts. Check Accessibility permission, then retry."))); }
                for _ in 0..4 {
                    if worker_stop.load(Ordering::Acquire) { break; }
                    thread::sleep(Duration::from_millis(250));
                }
                continue;
            };
            let Ok(source) = tap.mach_port().create_runloop_source(0) else {
                if let Some(ready) = ready.take() { let _ = ready.send(Err(anyhow!("Could not start the shortcut event loop."))); }
                worker_status.store(3, Ordering::Release);
                return;
            };
            let runloop = CFRunLoop::get_current();
                let mode = unsafe { kCFRunLoopDefaultMode };
            runloop.add_source(&source, mode);
            tap.enable();
            worker_status.store(0, Ordering::Release);
            if let Some(ready) = ready.take() { let _ = ready.send(Ok(())); }
            while !worker_stop.load(Ordering::Acquire) && !worker_restart.load(Ordering::Acquire) {
                CFRunLoop::run_in_mode(mode, Duration::from_millis(250), false);
                if !permissions().accessibility {
                    worker_status.store(1, Ordering::Release);
                    let _ = sender.try_send(Action::Cancelled);
                    break;
                }
            }
            runloop.remove_source(&source, mode);
            drop(tap);
        }
        worker_status.store(3, Ordering::Release);
    }).context("Could not start the shortcut monitor thread.")?;
    let monitor = ShortcutMonitor {
        stop,
        restart,
        status,
        thread: Some(worker),
    };
    ready_rx
        .recv_timeout(Duration::from_secs(5))
        .context("The shortcut monitor did not start.")??;
    Ok(monitor)
}

pub struct Overlay {
    panel: Retained<NSPanel>,
    label: Retained<NSTextField>,
    waveform: Retained<NSTextField>,
    visible: bool,
}

impl Overlay {
    pub fn new() -> Result<Self> {
        let main =
            MainThreadMarker::new().context("Create the dictation overlay on the main thread.")?;
        let bounds = NSRect::new(NSPoint::new(0.0, 0.0), NSSize::new(280.0, 54.0));
        let panel = NSPanel::initWithContentRect_styleMask_backing_defer(
            NSPanel::alloc(main),
            bounds,
            NSWindowStyleMask::Borderless | NSWindowStyleMask::NonactivatingPanel,
            NSBackingStoreType::Buffered,
            false,
        );
        // Retained owns the panel. Closing it must not trigger AppKit's extra release.
        unsafe {
            panel.setReleasedWhenClosed(false);
        }
        panel.setFloatingPanel(true);
        panel.setBecomesKeyOnlyIfNeeded(true);
        panel.setHidesOnDeactivate(false);
        panel.setIgnoresMouseEvents(true);
        panel.setLevel(25);
        panel.setCollectionBehavior(
            NSWindowCollectionBehavior::CanJoinAllSpaces
                | NSWindowCollectionBehavior::FullScreenAuxiliary
                | NSWindowCollectionBehavior::Stationary
                | NSWindowCollectionBehavior::IgnoresCycle,
        );
        panel.setOpaque(false);
        panel.setBackgroundColor(Some(&NSColor::clearColor()));
        panel.setHasShadow(true);
        let background = NSBox::initWithFrame(NSBox::alloc(main), bounds);
        background.setBoxType(NSBoxType::Custom);
        background.setBorderWidth(0.0);
        background.setTitlePosition(NSTitlePosition::NoTitle);
        background.setContentViewMargins(NSSize::new(0.0, 0.0));
        background.setCornerRadius(27.0);
        background.setFillColor(&NSColor::colorWithSRGBRed_green_blue_alpha(
            0.09, 0.105, 0.12, 0.97,
        ));
        let label = NSTextField::labelWithString(&NSString::from_str("Listening"), main);
        label.setFrame(NSRect::new(
            NSPoint::new(20.0, 17.0),
            NSSize::new(150.0, 21.0),
        ));
        label.setFont(Some(&overlay_font(14.0)));
        label.setTextColor(Some(&NSColor::whiteColor()));
        let waveform = NSTextField::labelWithString(&NSString::from_str("▁▂▃▂▁"), main);
        waveform.setFrame(NSRect::new(
            NSPoint::new(178.0, 17.0),
            NSSize::new(82.0, 23.0),
        ));
        waveform.setFont(Some(&NSFont::boldSystemFontOfSize(17.0)));
        waveform.setAlignment(NSTextAlignment::Center);
        waveform.setTextColor(Some(&NSColor::colorWithSRGBRed_green_blue_alpha(
            1.0,
            116.0 / 255.0,
            47.0 / 255.0,
            1.0,
        )));
        background.addSubview(&label);
        background.addSubview(&waveform);
        panel.setContentView(Some(&background));
        Ok(Self {
            panel,
            label,
            waveform,
            visible: false,
        })
    }

    pub fn update(&mut self, label: &str, level: f32, visible: bool) {
        self.label.setStringValue(&NSString::from_str(label));
        let amplitude = if level.is_finite() {
            level.clamp(0.0, 1.0)
        } else {
            0.0
        };
        let heights = ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];
        let bars: String = [0.35, 0.65, 0.9, 1.0, 0.9, 0.65, 0.35]
            .into_iter()
            .map(|envelope| heights[(amplitude * envelope * 7.0).round() as usize])
            .collect();
        self.waveform.setStringValue(&NSString::from_str(&bars));
        if visible {
            if let Some(screen) = NSScreen::mainScreen(MainThreadMarker::from(&*self.panel)) {
                let frame = screen.visibleFrame();
                self.panel.setFrameOrigin(NSPoint::new(
                    frame.origin.x + (frame.size.width - 280.0) / 2.0,
                    frame.origin.y + 24.0,
                ));
            }
            if !self.visible {
                self.panel.orderFrontRegardless();
            }
        } else if self.visible {
            self.panel.orderOut(None);
        }
        self.visible = visible;
    }
}

fn overlay_font(size: f64) -> Retained<NSFont> {
    static REGISTER: Once = Once::new();
    REGISTER.call_once(|| {
        let bundled = std::env::current_exe().ok().and_then(|path| {
            path.ancestors()
                .find(|parent| {
                    parent
                        .extension()
                        .is_some_and(|extension| extension == "app")
                })
                .map(|bundle| bundle.join("Contents/Resources/Fonts/Manrope-Regular.ttf"))
        });
        let path = bundled.filter(|path| path.is_file()).unwrap_or_else(|| {
            PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("Resources/Fonts/Manrope-Regular.ttf")
        });
        if let Some(url) = CFURL::from_path(&path, false) {
            // Process-scope registration borrows the URL. No CFError is requested.
            unsafe {
                CTFontManagerRegisterFontsForURL(url.as_CFTypeRef(), 1, std::ptr::null_mut());
            }
        }
    });
    NSFont::fontWithName_size(&NSString::from_str("Manrope-Regular"), size)
        .unwrap_or_else(|| NSFont::systemFontOfSize(size))
}

pub fn verify_insertion() -> Result<serde_json::Value> {
    let main = MainThreadMarker::new().context("Run insertion verification on the main thread.")?;
    ensure!(
        permissions().accessibility,
        "Insertion verification requires Accessibility permission for this executable."
    );
    let app = NSApplication::sharedApplication(main);
    app.setActivationPolicy(NSApplicationActivationPolicy::Regular);
    app.finishLaunching();
    let bounds = NSRect::new(NSPoint::new(0.0, 0.0), NSSize::new(520.0, 260.0));
    let window = unsafe {
        NSWindow::initWithContentRect_styleMask_backing_defer(
            NSWindow::alloc(main),
            bounds,
            NSWindowStyleMask::Titled | NSWindowStyleMask::Closable,
            NSBackingStoreType::Buffered,
            false,
        )
    };
    unsafe {
        window.setReleasedWhenClosed(false);
    }
    struct VerificationWindow(Retained<NSWindow>);
    impl Drop for VerificationWindow {
        fn drop(&mut self) {
            self.0.orderOut(None);
            self.0.close();
        }
    }
    let window = VerificationWindow(window);
    window
        .0
        .setTitle(&NSString::from_str("Voco insertion verification"));
    let root = NSView::initWithFrame(NSView::alloc(main), bounds);
    let first = NSTextView::initWithFrame(
        NSTextView::alloc(main),
        NSRect::new(NSPoint::new(10.0, 145.0), NSSize::new(500.0, 100.0)),
    );
    let second = NSTextView::initWithFrame(
        NSTextView::alloc(main),
        NSRect::new(NSPoint::new(10.0, 70.0), NSSize::new(500.0, 60.0)),
    );
    let secure = NSSecureTextField::initWithFrame(
        NSSecureTextField::alloc(main),
        NSRect::new(NSPoint::new(10.0, 20.0), NSSize::new(400.0, 28.0)),
    );
    first.setString(&NSString::from_str("Before 😀 after"));
    second.setString(&NSString::from_str("Untouched"));
    root.addSubview(&first);
    root.addSubview(&second);
    root.addSubview(&secure);
    window.0.setContentView(Some(&root));
    window.0.makeKeyAndOrderFront(None);
    activate_dashboard();
    ensure!(
        window.0.makeFirstResponder(Some(&first)),
        "Could not focus the verification editor."
    );
    first.setSelectedRange(NSRange::new(7, 2));
    let deadline = Instant::now() + Duration::from_secs(2);
    while frontmost_pid()? != std::process::id() as i32 || app.keyWindow().is_none() {
        ensure!(
            Instant::now() < deadline,
            "macOS did not focus the verification window. PID={}, frontmost={:?}, active={}, key={}, window_key={}",
            std::process::id(),
            frontmost_pid(),
            app.isActive(),
            app.keyWindow().is_some(),
            window.0.isKeyWindow()
        );
        if let Some(event) = app.nextEventMatchingMask_untilDate_inMode_dequeue(
            NSEventMask::Any,
            Some(&NSDate::dateWithTimeIntervalSinceNow(0.025)),
            unsafe { NSDefaultRunLoopMode },
            true,
        ) {
            app.sendEvent(&event);
        }
        window.0.makeKeyWindow();
    }
    let target = FocusTarget::capture()?;
    let text = "Long Unicode dictation with 😀 café 日本語 and a newline.\n".repeat(40);
    target.insert(&text)?;
    let expected = format!("Before {text} after");
    ensure!(
        first.string().to_string() == expected,
        "The live editor did not contain the full Unicode transcript."
    );
    first.setSelectedRange(NSRange::new(0, 0));
    let target = FocusTarget::capture()?;
    first.setSelectedRange(NSRange::new(1, 0));
    ensure!(
        target.insert("SHOULD NOT INSERT").is_err(),
        "The changed-selection guard allowed insertion."
    );
    ensure!(
        first.string().to_string() == expected,
        "The changed-selection guard modified the editor."
    );
    let target = FocusTarget::capture()?;
    ensure!(
        window.0.makeFirstResponder(Some(&second)),
        "Could not focus the second verification editor."
    );
    ensure!(
        target.insert("SHOULD NOT INSERT").is_err(),
        "The changed-field guard allowed insertion."
    );
    ensure!(
        second.string().to_string() == "Untouched",
        "The changed-field guard modified the second editor."
    );
    ensure!(
        window.0.makeFirstResponder(Some(&secure)),
        "Could not focus the password verification field."
    );
    ensure!(
        FocusTarget::capture().is_err(),
        "The password-field guard allowed capture."
    );
    let mut overlay = Overlay::new()?;
    overlay.update("Listening", 0.5, true);
    ensure!(
        !overlay.panel.canBecomeKeyWindow() && !overlay.panel.canBecomeMainWindow(),
        "The recording panel can take keyboard focus."
    );
    ensure!(
        overlay.panel.ignoresMouseEvents(),
        "The recording panel intercepts mouse input."
    );
    ensure!(
        window.0.isKeyWindow(),
        "The recording panel stole keyboard focus."
    );
    overlay.update("Idle", 0.0, false);
    Ok(
        serde_json::json!({"status":"pass", "unicodeUtf16Units":text.encode_utf16().count(), "selectionReplacement":true, "changedSelectionRefused":true, "changedFieldRefused":true, "secureFieldRefused":true, "panelNonactivating":true, "panelIgnoresMouse":true, "panelPreservesFocus":true}),
    )
}

impl Drop for Overlay {
    fn drop(&mut self) {
        self.panel.orderOut(None);
        self.panel.close();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use core_graphics::event_source::{CGEventSource, CGEventSourceStateID};

    #[test]
    fn clipboard_lease_restores_every_representation() {
        let pasteboard = NSPasteboard::pasteboardWithUniqueName();
        let text_type = unsafe { NSPasteboardTypeString };
        let custom_type = NSString::from_str("app.voco.test.binary");
        let item = NSPasteboardItem::new();
        assert!(item.setString_forType(&NSString::from_str("Original 😀"), text_type));
        assert!(item.setData_forType(
            &objc2_foundation::NSData::with_bytes(&[0, 1, 255, 32]),
            &custom_type
        ));
        let objects = NSArray::from_retained_slice(&[
            ProtocolObject::<dyn NSPasteboardWriting>::from_retained(item),
        ]);
        assert!(pasteboard.writeObjects(&objects));
        let lease =
            ClipboardLease::stage_on(pasteboard.clone(), &"Long Unicode 😀\n".repeat(100)).unwrap();
        assert_eq!(
            pasteboard.stringForType(text_type).unwrap().to_string(),
            "Long Unicode 😀\n".repeat(100)
        );
        drop(lease);
        assert_eq!(
            pasteboard.stringForType(text_type).unwrap().to_string(),
            "Original 😀"
        );
        assert_eq!(
            pasteboard.dataForType(&custom_type).unwrap().to_vec(),
            [0, 1, 255, 32]
        );
    }

    #[test]
    fn clipboard_lease_preserves_a_new_copy() {
        let pasteboard = NSPasteboard::pasteboardWithUniqueName();
        let text_type = unsafe { NSPasteboardTypeString };
        assert!(pasteboard.setString_forType(&NSString::from_str("Before"), text_type));
        let lease = ClipboardLease::stage_on(pasteboard.clone(), "Transcript").unwrap();
        pasteboard.clearContents();
        assert!(
            pasteboard.setString_forType(&NSString::from_str("Copied while dictating"), text_type)
        );
        drop(lease);
        assert_eq!(
            pasteboard.stringForType(text_type).unwrap().to_string(),
            "Copied while dictating"
        );
    }

    #[test]
    fn replacement_uses_utf16_selection_offsets() {
        assert_eq!(
            replace_selection(
                "a😀b",
                Selection {
                    location: 1,
                    length: 2
                },
                "words"
            )
            .unwrap(),
            "awordsb"
        );
        assert!(
            replace_selection(
                "a😀b",
                Selection {
                    location: 2,
                    length: 1
                },
                "x"
            )
            .is_err()
        );
        assert!(
            replace_selection(
                "abc",
                Selection {
                    location: 4,
                    length: 0
                },
                "x"
            )
            .is_err()
        );
    }

    #[test]
    fn shortcut_callback_forwards_hold_chord_escape_and_ignores_our_events() {
        let (sender, receiver) = crossbeam_channel::unbounded();
        let mut gesture = TapGesture::default();
        let source = CGEventSource::new(CGEventSourceStateID::Private).unwrap();
        let event = CGEvent::new_keyboard_event(source, 63, true).unwrap();
        event.set_flags(CGEventFlags::CGEventFlagSecondaryFn);
        gesture.handle(CGEventType::FlagsChanged, &event, &sender);
        assert_eq!(receiver.try_recv().unwrap(), Action::Pressed);
        event.set_integer_value_field(EventField::KEYBOARD_EVENT_KEYCODE, 49);
        assert!(matches!(
            gesture.handle(CGEventType::KeyDown, &event, &sender),
            CallbackResult::Drop
        ));
        assert_eq!(receiver.try_recv().unwrap(), Action::ToggleContinuous);
        event.set_flags(CGEventFlags::empty());
        assert!(matches!(
            gesture.handle(CGEventType::KeyUp, &event, &sender),
            CallbackResult::Drop
        ));
        assert!(receiver.is_empty());
        event.set_integer_value_field(EventField::KEYBOARD_EVENT_KEYCODE, 53);
        gesture.handle(CGEventType::KeyDown, &event, &sender);
        assert_eq!(receiver.try_recv().unwrap(), Action::Escape);
        event.set_integer_value_field(EventField::EVENT_SOURCE_USER_DATA, INSERTION_MARKER);
        event.set_flags(CGEventFlags::CGEventFlagSecondaryFn);
        gesture.handle(CGEventType::FlagsChanged, &event, &sender);
        assert!(receiver.is_empty());
    }
}
