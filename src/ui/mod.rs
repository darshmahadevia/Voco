//! Native GPUI dashboard: app lifecycle, tray, and verification live here;
//! page rendering lives in the child modules.

mod chrome;
mod home;
mod kit;
mod settings;
mod stats;
mod transcripts;

use crate::overlay::{Overlay, RecordingIntent};
use crate::{
    controller::{Controller, EngineStatus},
    domain::{ModelId, OutputMode, Session},
    models, platform,
};
use anyhow::Result;
use gpui::{prelude::*, *};
use gpui_component::{
    Disableable, Root, Theme, ThemeMode,
    button::{Button, ButtonVariants},
    input::{Input, InputState},
};
use kit::Tone;
use std::{
    path::PathBuf,
    time::{Duration, Instant},
};
use tray_icon::{
    TrayIcon, TrayIconBuilder,
    menu::{Menu, MenuEvent, MenuItem, PredefinedMenuItem, Submenu},
};

// Surfaces, from the window canvas up to interactive controls.
const CANVAS: u32 = 0x0a0a0a;
const PANEL: u32 = 0x0f0f0f;
const RAISED: u32 = 0x151515;
const CONTROL: u32 = 0x1e1e1e;
const CONTROL_HOVER: u32 = 0x262626;
// Hairlines.
const LINE: u32 = 0x202020;
const LINE_STRONG: u32 = 0x2e2e2e;
// Text.
const TEXT: u32 = 0xf2f0ec;
const TEXT_2: u32 = 0xb9b8b5;
const MUTED: u32 = 0x929497;
const FAINT: u32 = 0x5f6164;
// Voice and semantic colors.
const ORANGE: u32 = 0xff742f;
const ORANGE_DEEP: u32 = 0xc95524;
const ORANGE_SOFT: u32 = 0xff742f1f;
const SUCCESS: u32 = 0x9fd1ad;
const SUCCESS_SOFT: u32 = 0x9fd1ad1f;
const DANGER: u32 = 0xff9d9d;

const SIDEBAR_WIDTH: f32 = 208.;
const COMPACT_WIDTH: f32 = 960.;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Page {
    Home,
    Transcripts,
    Stats,
    Settings,
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum SettingsTab {
    Output,
    Models,
    Access,
    Dictation,
}

pub struct VocoApp {
    controller: Controller,
    page: Page,
    tab: SettingsTab,
    settings_focus: FocusHandle,
    tray: TrayIcon,
    _application_menu: Menu,
    copy_menu: MenuItem,
    overlay: Overlay,
    visible: bool,
    practice: Entity<InputState>,
    search: Entity<InputState>,
    copied_until: Option<Instant>,
    /// The copy control that most recently succeeded, for inline feedback.
    copied_key: Option<SharedString>,
    verification: Option<Verification>,
}
struct Verification {
    directory: PathBuf,
    started: Instant,
    stage: usize,
    practice_verified: bool,
    close_verified: bool,
    stage_started: Instant,
    capture: Option<std::sync::mpsc::Receiver<std::result::Result<(), String>>>,
}

fn literal_text(id: SharedString, value: &str, window: &mut Window, cx: &mut App) -> Input {
    let state = window.use_keyed_state(id, cx, |window, cx| {
        InputState::new(window, cx).auto_grow(1, 12)
    });
    if state.read(cx).value().as_ref() != value {
        state.update(cx, |input, cx| {
            input.set_value(value.to_owned(), window, cx)
        });
    }
    Input::new(&state)
        .appearance(false)
        .disabled(true)
        .p(px(0.))
        .text_size(px(13.))
        .text_color(rgb(TEXT))
}

struct Assets;
impl AssetSource for Assets {
    fn load(&self, path: &str) -> Result<Option<std::borrow::Cow<'static, [u8]>>> {
        macro_rules! icons {
            ($($name:literal),* $(,)?) => {
                match path {
                    "mark" => include_bytes!("../../Resources/Brand/voco-mark.svg").as_slice(),
                    $($name => include_bytes!(concat!("../../Resources/Icons/", $name, ".svg")).as_slice(),)*
                    _ => return Ok(None),
                }
            };
        }
        let bytes: &'static [u8] = icons!(
            "home",
            "transcripts",
            "stats",
            "settings",
            "globe",
            "search",
            "copy",
            "check",
            "mic",
            "keyboard",
            "lock",
            "download",
            "arrow-right",
            "arrow-up-right",
            "plus",
            "minus",
            "alert",
            "zap",
            "sparkle",
            "wave",
            "shield",
            "cpu",
            "cursor",
        );
        Ok(Some(std::borrow::Cow::Borrowed(bytes)))
    }
    fn list(&self, _: &str) -> Result<Vec<SharedString>> {
        Ok(vec![])
    }
}

pub fn run(root: PathBuf, show: bool, verification: Option<PathBuf>) -> Result<()> {
    let controller = Controller::new(root)?;
    Application::new().with_assets(Assets).run(move |cx| {
        gpui_component::init(cx);
        Theme::change(ThemeMode::Dark, None, cx);
        let theme = Theme::global_mut(cx);
        theme.font_family = "Manrope".into();
        theme.font_size = px(13.);
        let colors = &mut theme.colors;
        colors.background = rgb(CANVAS).into();
        colors.foreground = rgb(TEXT).into();
        colors.muted = rgb(CONTROL).into();
        colors.muted_foreground = rgb(MUTED).into();
        colors.input = rgb(LINE_STRONG).into();
        colors.border = rgb(LINE).into();
        colors.ring = rgb(ORANGE).into();
        colors.caret = rgb(ORANGE).into();
        colors.selection = rgb(0x803c1b).into();
        colors.primary = rgb(TEXT).into();
        colors.primary_hover = rgb(0xffffff).into();
        colors.primary_active = rgb(0xdcd9d3).into();
        colors.primary_foreground = rgb(CANVAS).into();
        colors.secondary = rgb(CONTROL).into();
        colors.secondary_hover = rgb(CONTROL_HOVER).into();
        colors.secondary_active = rgb(0x303030).into();
        colors.secondary_foreground = rgb(TEXT).into();
        colors.popover = rgb(0x1b1b1b).into();
        colors.popover_foreground = rgb(TEXT).into();
        colors.scrollbar_thumb = rgb(0x2a2a2a).into();
        colors.scrollbar_thumb_hover = rgb(0x3a3a3a).into();
        cx.text_system()
            .add_fonts(vec![
                std::borrow::Cow::Borrowed(include_bytes!(
                    "../../Resources/Fonts/Manrope-Regular.ttf"
                )),
                std::borrow::Cow::Borrowed(include_bytes!(
                    "../../Resources/Fonts/Manrope-Medium.ttf"
                )),
                std::borrow::Cow::Borrowed(include_bytes!(
                    "../../Resources/Fonts/Manrope-SemiBold.ttf"
                )),
            ])
            .expect("bundled Manrope font");
        let bounds = Bounds::centered(None, size(px(1080.), px(800.)), cx);
        cx.open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                titlebar: Some(TitlebarOptions {
                    title: Some("Voco".into()),
                    appears_transparent: true,
                    ..Default::default()
                }),
                window_min_size: Some(size(px(820.), px(640.))),
                show,
                focus: show,
                app_id: Some("org.vocoapp.Voco".into()),
                ..Default::default()
            },
            move |window, cx| {
                let view = cx.new(|cx| {
                    VocoApp::new(controller, show, verification, window, cx)
                        .expect("native dashboard")
                });
                let weak = view.downgrade();
                window.on_window_should_close(cx, move |_, cx| {
                    weak.update(cx, |app, cx| {
                        app.visible = false;
                        dashboard_visibility(false);
                        cx.notify();
                    })
                    .ok();
                    false
                });
                cx.new(|cx| Root::new(view, window, cx))
            },
        )
        .expect("Voco window");
        if show {
            cx.activate(true);
        }
    });
    Ok(())
}

fn dashboard_visibility(show: bool) {
    if let Some(main) = objc2::MainThreadMarker::new() {
        let app = objc2_app_kit::NSApplication::sharedApplication(main);
        for window in app
            .windows()
            .iter()
            .filter(|w| w.title().to_string() == "Voco")
        {
            if show {
                window.makeKeyAndOrderFront(None);
            } else {
                window.orderOut(None);
            }
        }
    }
    if show {
        platform::activate_dashboard();
    }
}

fn request_dashboard_close() {
    unsafe extern "C" {
        static _dispatch_main_q: std::ffi::c_void;
        fn dispatch_async_f(
            queue: *const std::ffi::c_void,
            context: *mut std::ffi::c_void,
            work: extern "C" fn(*mut std::ffi::c_void),
        );
    }
    extern "C" fn close(_: *mut std::ffi::c_void) {
        if let Some(main) = objc2::MainThreadMarker::new() {
            for native in objc2_app_kit::NSApplication::sharedApplication(main)
                .windows()
                .iter()
                .filter(|w| w.title().to_string() == "Voco")
            {
                native.performClose(None);
            }
        }
    }
    unsafe {
        dispatch_async_f(&raw const _dispatch_main_q, std::ptr::null_mut(), close);
    }
}

impl VocoApp {
    fn new(
        controller: Controller,
        show: bool,
        verification: Option<PathBuf>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Result<Self> {
        let menu = Menu::new();
        menu.append(&MenuItem::with_id(
            "status",
            "Voco · Local dictation",
            false,
            None,
        ))?;
        menu.append(&PredefinedMenuItem::separator())?;
        for (id, label, shortcut) in [
            ("home", "Open Dashboard", "Cmd+1"),
            ("transcripts", "Transcripts", "Cmd+2"),
            ("stats", "Stats", "Cmd+3"),
            ("settings", "Settings…", "Cmd+Comma"),
        ] {
            menu.append(&MenuItem::with_id(id, label, true, Some(shortcut.parse()?)))?;
        }
        let copy_menu = MenuItem::with_id("copy", "Copy last transcript", false, None);
        menu.append(&copy_menu)?;
        menu.append(&PredefinedMenuItem::separator())?;
        menu.append(&MenuItem::with_id(
            "quit",
            "Quit Voco",
            true,
            Some("Cmd+Q".parse()?),
        ))?;
        let image = image::load_from_memory(include_bytes!(
            "../../Resources/Brand/voco-trayTemplate.png"
        ))?
        .into_rgba8();
        let (width, height) = image.dimensions();
        let icon = tray_icon::Icon::from_rgba(image.into_raw(), width, height)?;
        let tray = TrayIconBuilder::new()
            .with_icon(icon)
            .with_icon_as_template(true)
            .with_tooltip("Voco · Local dictation")
            .with_menu(Box::new(menu))
            .build()?;
        let application_menu = Menu::new();
        let app_menu = Submenu::new("Voco", true);
        app_menu.append(&MenuItem::with_id(
            "quit",
            "Quit Voco",
            true,
            Some("Cmd+Q".parse()?),
        ))?;
        application_menu.append(&app_menu)?;
        let navigation = Submenu::new("Navigate", true);
        for (id, label, shortcut) in [
            ("home", "Open Dashboard", "Cmd+1"),
            ("transcripts", "Transcripts", "Cmd+2"),
            ("stats", "Stats", "Cmd+3"),
            ("settings", "Settings…", "Cmd+Comma"),
        ] {
            navigation.append(&MenuItem::with_id(id, label, true, Some(shortcut.parse()?)))?;
        }
        application_menu.append(&navigation)?;
        let edit = Submenu::new("Edit", true);
        edit.append(&PredefinedMenuItem::undo(None))?;
        edit.append(&PredefinedMenuItem::redo(None))?;
        edit.append(&PredefinedMenuItem::separator())?;
        edit.append(&PredefinedMenuItem::cut(None))?;
        edit.append(&PredefinedMenuItem::copy(None))?;
        edit.append(&PredefinedMenuItem::paste(None))?;
        edit.append(&PredefinedMenuItem::select_all(None))?;
        application_menu.append(&edit)?;
        application_menu.init_for_nsapp();
        platform::hide_dock();
        let overlay = Overlay::new(cx)?;
        let mut controller = controller;
        if verification.is_some() {
            controller.history.push_back(crate::controller::Transcript { time: "Verify 09:41".into(), text: "Verification example. A thought can arrive in its own time, with room to breathe.".into() });
            controller.history.push_back(crate::controller::Transcript { time: "Verify 09:40".into(), text: "Verification literal. &copy; <tag> **words** 😀 café\n    Four leading spaces stay exactly as dictated.\nA second line, without changing your words.".into() });
        }
        let practice = cx.new(|cx| {
            InputState::new(window, cx)
                .multi_line(true)
                .placeholder("Click here, hold Fn, and let your thoughts flow…")
        });
        let search = cx.new(|cx| InputState::new(window, cx).placeholder("Search your words…"));
        cx.spawn_in(window, async move |this, cx| {
            loop {
                cx.background_executor()
                    .timer(Duration::from_millis(60))
                    .await;
                if this
                    .update_in(cx, |app, window, cx| app.tick(window, cx))
                    .is_err()
                {
                    break;
                }
            }
        })
        .detach();
        Ok(Self {
            controller,
            page: Page::Home,
            tab: SettingsTab::Output,
            settings_focus: cx.focus_handle(),
            tray,
            _application_menu: application_menu,
            copy_menu,
            overlay,
            visible: show,
            practice,
            search,
            copied_until: None,
            copied_key: None,
            verification: verification.map(|directory| Verification {
                directory,
                started: Instant::now(),
                stage: 0,
                practice_verified: false,
                close_verified: false,
                stage_started: Instant::now(),
                capture: None,
            }),
        })
    }
    fn show(&mut self, page: Page, window: &mut Window, cx: &mut Context<Self>) {
        self.page = page;
        self.visible = true;
        dashboard_visibility(true);
        window.activate_window();
        cx.notify();
    }
    fn copy(&mut self, text: &str) {
        self.copy_from(None, text);
    }
    /// Copies text and remembers which control asked, so that control can
    /// confirm success in place as well as in the status bar.
    fn copy_from(&mut self, key: Option<SharedString>, text: &str) {
        match platform::copy_text(text) {
            Ok(()) => {
                self.copied_until = Some(Instant::now() + Duration::from_secs(2));
                self.copied_key = key;
            }
            Err(error) => self.controller.notice = format!("Could not copy. {error}"),
        }
    }
    fn copied(&self, key: &str) -> bool {
        self.copied_until
            .is_some_and(|until| until > Instant::now())
            && self
                .copied_key
                .as_ref()
                .is_some_and(|copied| copied.as_ref() == key)
    }
    fn result(&mut self, result: Result<()>) {
        if let Err(error) = result {
            self.controller.notice = error.to_string();
        }
    }
    fn practice_target(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Option<crate::practice::PracticeTarget> {
        if !self.visible
            || self.page != Page::Home
            || !self.practice.focus_handle(cx).is_focused(window)
        {
            return None;
        }
        self.practice.update(cx, |input, cx| {
            if input.marked_text_range(window, cx).is_some() {
                return None;
            }
            let selection = input.selected_text_range(false, window, cx)?.range;
            let value = input.value();
            let to_chars = |offset| {
                let mut units = 0;
                value
                    .chars()
                    .take_while(|c| {
                        units += c.len_utf16();
                        units <= offset
                    })
                    .count()
            };
            crate::practice::PracticeTarget::capture(
                &value,
                to_chars(selection.start)..to_chars(selection.end),
            )
            .ok()
        })
    }
    fn apply_practice_update(
        &mut self,
        value: String,
        caret: usize,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.practice.update(cx, |input, cx| {
            let prefix: String = value.chars().take(caret).collect();
            let line = prefix.matches('\n').count() as u32;
            let character = prefix.rsplit('\n').next().unwrap_or("").chars().count() as u32;
            input.set_value(value, window, cx);
            input.set_cursor_position(
                gpui_component::input::Position { line, character },
                window,
                cx,
            );
        });
    }
    fn tick(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.controller.practice_snapshot = self.practice_target(window, cx);
        if let Some(intent) = self.overlay.take_intent()
            && RecordingIntent::for_session(&self.controller.session) == Some(intent)
        {
            self.controller
                .action(crate::gesture::Action::ToggleContinuous);
        }
        self.controller.tick();
        self.overlay.set_session(&self.controller.session, cx);
        if let Some((value, caret)) = self.controller.practice_update.take() {
            self.apply_practice_update(value, caret, window, cx);
        }
        if std::fs::remove_file(self.controller.root.join("show-dashboard")).is_ok() {
            self.show(Page::Home, window, cx);
        }
        while let Ok(event) = MenuEvent::receiver().try_recv() {
            match event.id.as_ref() {
                "home" => self.show(Page::Home, window, cx),
                "transcripts" => self.show(Page::Transcripts, window, cx),
                "stats" => self.show(Page::Stats, window, cx),
                "settings" => self.show(Page::Settings, window, cx),
                "copy" => {
                    if let Some(row) = self.controller.history.front() {
                        let text = row.text.clone();
                        self.copy(&text);
                    }
                }
                "quit" => cx.quit(),
                _ => {}
            }
        }
        if self.controller.show_dashboard {
            self.controller.show_dashboard = false;
            self.show(Page::Home, window, cx);
        }
        self.copy_menu
            .set_enabled(!self.controller.history.is_empty());
        let _ = self
            .tray
            .set_tooltip(Some(format!("Voco · {}", self.controller.status())));
        if let Some(stage @ (9 | 10)) = self
            .verification
            .as_ref()
            .map(|verification| verification.stage)
        {
            self.overlay.update(
                if stage == 9 {
                    "Listening"
                } else {
                    "Transcribing"
                },
                if stage == 9 { 0.42 } else { 0. },
                true,
                cx,
            );
        } else {
            self.overlay.update(
                self.controller.status(),
                self.controller.level(),
                self.controller.session.active(),
                cx,
            );
        }
        self.verify(window, cx);
        if self.visible {
            cx.notify();
        }
    }
    fn verify(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let Some(mut verification) = self.verification.take() else {
            return;
        };
        if verification.started.elapsed() > Duration::from_secs(90) {
            eprintln!("Native UI verification timed out");
            std::process::exit(1);
        }
        if let Some(receiver) = &verification.capture {
            match receiver.try_recv() {
                Ok(Ok(())) => {
                    verification.capture = None;
                    verification.stage += 1;
                    verification.stage_started = Instant::now();
                }
                Ok(Err(message)) => {
                    eprintln!("Native screenshot capture failed. {message}");
                    std::process::exit(1);
                }
                Err(std::sync::mpsc::TryRecvError::Empty) => {}
                Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                    eprintln!("Native screenshot worker stopped");
                    std::process::exit(1);
                }
            }
            self.verification = Some(verification);
            return;
        }
        let stage_delay = if matches!(verification.stage, 17 | 18) {
            Duration::from_secs(2)
        } else {
            Duration::from_millis(400)
        };
        if verification.stage_started.elapsed() < stage_delay {
            self.verification = Some(verification);
            return;
        }
        let fail = |message: &str| {
            eprintln!("{message}");
            std::process::exit(1);
        };
        match verification.stage {
            0..=10 | 15 => {
                let stage = verification.stage;
                match stage {
                    0 => self.page = Page::Home,
                    1 => self.page = Page::Transcripts,
                    2 => self.page = Page::Stats,
                    3..=6 => {
                        self.page = Page::Settings;
                        self.tab = [
                            SettingsTab::Output,
                            SettingsTab::Models,
                            SettingsTab::Access,
                            SettingsTab::Dictation,
                        ][stage - 3];
                    }
                    7 => {
                        self.page = Page::Home;
                        window.resize(size(px(820.), px(640.)));
                    }
                    8 => {
                        window.resize(size(px(1080.), px(800.)));
                        self.controller.session = Session::Recovery {
                            text: "Native verification recovery words.".into(),
                            message: "Verification scenario. Your words are safe to copy.".into(),
                        };
                    }
                    15 => self
                        .overlay
                        .verify_idle(cx)
                        .expect("persistent native idle overlay"),
                    9 | 10 => {
                        self.overlay.update(
                            if stage == 9 {
                                "Listening"
                            } else {
                                "Transcribing"
                            },
                            if stage == 9 { 0.42 } else { 0. },
                            true,
                            cx,
                        );
                    }
                    _ => {}
                }
                dashboard_visibility(true);
                let directory = verification.directory.clone();
                let number = if stage >= 9 {
                    self.overlay.window_number()
                } else {
                    objc2::MainThreadMarker::new()
                        .and_then(|main| {
                            objc2_app_kit::NSApplication::sharedApplication(main)
                                .windows()
                                .iter()
                                .find(|w| w.title().to_string() == "Voco")
                                .map(|w| w.windowNumber())
                        })
                        .expect("dashboard window number")
                };
                let (sender, receiver) = std::sync::mpsc::channel();
                verification.capture = Some(receiver);
                std::thread::spawn(move || {
                    std::thread::sleep(Duration::from_millis(350));
                    let index = if stage == 15 { 11 } else { stage };
                    let output = directory.join(format!("{index}.png"));
                    let result = std::process::Command::new("/usr/sbin/screencapture")
                        .args(["-x", "-o", "-l"])
                        .arg(number.to_string())
                        .arg(output)
                        .status()
                        .map_err(|error| error.to_string())
                        .and_then(|status| {
                            if status.success() {
                                Ok(())
                            } else {
                                Err(status.to_string())
                            }
                        });
                    let _ = sender.send(result);
                });
                self.verification = Some(verification);
                cx.notify();
                return;
            }
            11 => {
                self.search
                    .update(cx, |input, cx| input.set_value("literal", window, cx));
                if self.transcript_count(cx) != 1 {
                    fail("Transcript search did not filter literal text");
                }
                self.search
                    .update(cx, |input, cx| input.set_value("", window, cx));
                if self.transcript_count(cx) != 2 {
                    fail("Clearing transcript search did not restore rows");
                }
                self.controller.cancel();
                self.page = Page::Home;
                self.practice.update(cx, |input, cx| {
                    input.set_value("", window, cx);
                    input.replace_and_mark_text_in_range(
                        None,
                        "Before 😀 after",
                        Some(7..9),
                        window,
                        cx,
                    );
                    input.unmark_text(window, cx);
                    input.focus(window, cx);
                });
            }
            12 => {
                let target = self.practice_target(window, cx).unwrap_or_else(|| {
                    fail("Native practice focus capture failed");
                    unreachable!()
                });
                let (replacement, caret) = target
                    .replace(&target, "Rust")
                    .expect("Unicode replacement");
                self.apply_practice_update(replacement, caret, window, cx);
                let after = self
                    .practice_target(window, cx)
                    .expect("practice after replacement");
                let expected =
                    crate::practice::PracticeTarget::capture("Before Rust after", 11..11)
                        .expect("expected caret");
                verification.practice_verified =
                    self.practice.read(cx).value() == "Before Rust after" && after == expected;
                if !verification.practice_verified {
                    fail("Native practice replacement or caret failed");
                }
                if target.replace(&after, "Changed").is_ok() {
                    fail("Changed practice text was accepted");
                }
                self.apply_practice_update("Before Rust café 😀 after".into(), 18, window, cx);
                let unicode = self
                    .practice_target(window, cx)
                    .expect("Unicode caret snapshot");
                let expected_unicode =
                    crate::practice::PracticeTarget::capture("Before Rust café 😀 after", 18..18)
                        .expect("Unicode expected caret");
                if unicode != expected_unicode {
                    fail("Unicode caret was not preserved");
                }
                self.practice.update(cx, |input, cx| {
                    input.replace_and_mark_text_in_range(Some(0..0), "x", None, window, cx)
                });
                if self.practice_target(window, cx).is_some() {
                    fail("Composing input was accepted for dictation");
                }
                self.practice
                    .update(cx, |input, cx| input.unmark_text(window, cx));
                let native_key = objc2::MainThreadMarker::new().and_then(|main| {
                    objc2_app_kit::NSApplication::sharedApplication(main).keyWindow()
                });
                self.overlay.update("Listening", 0.4, true, cx);
                self.overlay.verify().expect("GPUI overlay focus safety");
                if !self.practice.focus_handle(cx).is_focused(window) {
                    fail("Overlay stole input focus");
                }
                let after_key = objc2::MainThreadMarker::new().and_then(|main| {
                    objc2_app_kit::NSApplication::sharedApplication(main).keyWindow()
                });
                if native_key != after_key {
                    fail("Overlay changed the native key window");
                }
                self.overlay.update("Ready", 0., false, cx);
            }
            13 => request_dashboard_close(),
            14 => {
                verification.close_verified = !platform::dashboard_visible();
                if !verification.close_verified {
                    fail("Closing did not hide the native dashboard");
                }
                let status = std::env::current_exe()
                    .and_then(|exe| std::process::Command::new(exe).arg("--show").status());
                if !status.is_ok_and(|s| s.success()) {
                    fail("Second-instance show failed");
                }
            }
            16 => {
                self.overlay
                    .verify_idle(cx)
                    .expect("settled idle before fullscreen");
                let main = objc2::MainThreadMarker::new().expect("main thread");
                let dashboard = objc2_app_kit::NSApplication::sharedApplication(main)
                    .windows()
                    .iter()
                    .find(|w| w.title().to_string() == "Voco")
                    .expect("dashboard window");
                dashboard.setCollectionBehavior(
                    (dashboard.collectionBehavior()
                        & !(objc2_app_kit::NSWindowCollectionBehavior::FullScreenAuxiliary
                            | objc2_app_kit::NSWindowCollectionBehavior::FullScreenNone))
                        | objc2_app_kit::NSWindowCollectionBehavior::FullScreenPrimary,
                );
                window.toggle_fullscreen();
            }
            17 => {
                let main = objc2::MainThreadMarker::new().expect("main thread");
                let dashboard = objc2_app_kit::NSApplication::sharedApplication(main)
                    .windows()
                    .iter()
                    .find(|w| w.title().to_string() == "Voco")
                    .expect("dashboard window");
                if !dashboard
                    .styleMask()
                    .contains(objc2_app_kit::NSWindowStyleMask::FullScreen)
                {
                    fail("Dashboard did not enter native fullscreen");
                }
                if self.overlay.on_active_space() {
                    window.toggle_fullscreen();
                    fail("Voice pill joined the native fullscreen Space");
                }
                window.toggle_fullscreen();
            }
            18 => {
                self.overlay
                    .verify_idle(cx)
                    .expect("persistent idle after fullscreen");
                if !self.overlay.on_active_space() {
                    fail("Voice pill did not return to the ordinary desktop Space");
                }
            }
            19 => {
                if !platform::dashboard_visible() {
                    fail("Second-instance show did not reveal dashboard");
                }
                for index in 0..12 {
                    if !verification
                        .directory
                        .join(format!("{index}.png"))
                        .is_file()
                    {
                        fail("Native page screenshot missing");
                    }
                }
                let report = serde_json::json!({"runtime":"rust", "ui":"gpui", "pagesRendered":4,"screenshots":12,"settingsTabsRendered":4,"compactWindow":true,"recoveryRendered":true,"trayCreated":true,"practiceInsertion":verification.practice_verified,"practiceRejectsChangedText":true,"practiceRejectsComposition":true,"overlayScreenshots":3,"overlayPersistentIdle":true,"overlayIdleSettled":true,"overlayExcludesNativeFullscreen":true,"overlayPreservesFocus":true,"overlayMousePassThroughOutsideControl":true,"closeHidesDashboard":verification.close_verified,"secondInstanceShow":true,"microphone":self.controller.permissions.microphone,"accessibility":self.controller.permissions.accessibility,"shortcut":self.controller.shortcut_running,"status":self.controller.status(),"transcriptSearch":true,"transcriptPersistence":false});
                std::fs::write(
                    verification.directory.join("report.json"),
                    serde_json::to_vec_pretty(&report).expect("report JSON"),
                )
                .expect("verification report");
                cx.quit();
            }
            _ => {}
        }
        verification.stage += 1;
        verification.stage_started = Instant::now();
        self.verification = Some(verification);
        cx.notify();
    }
}
