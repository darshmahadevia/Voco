use anyhow::{Context as _, Result, ensure};
use gpui::{prelude::*, *};
use objc2::{
    MainThreadMarker, msg_send,
    rc::Retained,
    runtime::{AnyClass, AnyObject, Bool, ClassBuilder, Sel},
    sel,
};
use objc2_app_kit::{NSScreen, NSView, NSWindow, NSWindowCollectionBehavior};
use objc2_foundation::{NSPoint, NSString};
use raw_window_handle::{HasWindowHandle, RawWindowHandle};
use std::time::Instant;

pub struct Overlay {
    window: WindowHandle<VoicePill>,
    native: Retained<NSWindow>,
    visible: bool,
}

struct VoicePill {
    label: SharedString,
    level: f32,
    started: Instant,
}

impl Overlay {
    pub fn new(cx: &mut App) -> Result<Self> {
        let window = cx.open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(Bounds::centered(
                    None,
                    size(px(236.), px(60.)),
                    cx,
                ))),
                titlebar: None,
                kind: WindowKind::PopUp,
                window_background: WindowBackgroundAppearance::Transparent,
                show: false,
                focus: false,
                is_movable: false,
                is_resizable: false,
                is_minimizable: false,
                ..Default::default()
            },
            |_, cx| {
                cx.new(|_| VoicePill {
                    label: "Listening".into(),
                    level: 0.,
                    started: Instant::now(),
                })
            },
        )?;
        let native = window.update(cx, |_, window, _| -> Result<_> {
            let raw = window
                .window_handle()
                .map_err(|error| anyhow::anyhow!("Could not access the voice window. {error}"))?
                .as_raw();
            let RawWindowHandle::AppKit(handle) = raw else {
                anyhow::bail!("The voice pill requires a macOS window.");
            };
            // GPUI owns the view; retain its window while configuring native behavior.
            let native = unsafe {
                let view = handle.ns_view.as_ptr().cast::<NSView>();
                let native: *mut NSWindow = msg_send![view, window];
                Retained::retain(native).context("The voice pill has no native window.")?
            };
            let class = if let Some(class) = AnyClass::get(c"VocoVoicePanel") {
                class
            } else {
                let mut builder = ClassBuilder::new(c"VocoVoicePanel", native.class())
                    .context("Could not configure the voice pill.")?;
                // Only this GPUI panel loses activation; dashboard behavior is unchanged.
                unsafe {
                    builder.add_method(
                        sel!(canBecomeKeyWindow),
                        cannot_activate as extern "C-unwind" fn(_, _) -> _,
                    );
                    builder.add_method(
                        sel!(canBecomeMainWindow),
                        cannot_activate as extern "C-unwind" fn(_, _) -> _,
                    );
                }
                builder.register()
            };
            // The subclass adds no storage and preserves GPUI's window/delegate methods.
            unsafe { AnyObject::set_class(&native, class) };
            native.setTitle(&NSString::from_str("Voco Voice"));
            native.setIgnoresMouseEvents(true);
            native.setHidesOnDeactivate(false);
            native.setLevel(25);
            native.setHasShadow(false);
            native.setCollectionBehavior(
                NSWindowCollectionBehavior::CanJoinAllSpaces
                    | NSWindowCollectionBehavior::FullScreenAuxiliary
                    | NSWindowCollectionBehavior::Stationary
                    | NSWindowCollectionBehavior::IgnoresCycle,
            );
            Ok(native)
        })??;
        let this = Self {
            window,
            native,
            visible: false,
        };
        this.verify()?;
        Ok(this)
    }

    pub fn update(&mut self, label: &str, level: f32, visible: bool, cx: &mut App) {
        let label = match label {
            "Words saved for copying" => "Copy your words",
            label => label,
        };
        let level = if level.is_finite() {
            level.clamp(0., 1.)
        } else {
            0.
        };
        let _ = self.window.update(cx, |pill, _, cx| {
            if pill.label.as_ref() != label || (pill.level - level).abs() > 0.005 {
                pill.label = label.to_owned().into();
                pill.level = level;
                cx.notify();
            }
        });
        if visible {
            if let Some(screen) = MainThreadMarker::new().and_then(NSScreen::mainScreen) {
                let frame = screen.visibleFrame();
                self.native.setFrameOrigin(NSPoint::new(
                    frame.origin.x + (frame.size.width - 236.) / 2.,
                    frame.origin.y + 18.,
                ));
            }
            if !self.visible {
                self.native.orderFrontRegardless();
            }
        } else if self.visible {
            self.native.orderOut(None);
        }
        self.visible = visible;
    }

    pub fn verify(&self) -> Result<()> {
        ensure!(
            !self.native.canBecomeKeyWindow() && !self.native.canBecomeMainWindow(),
            "The GPUI voice pill can take editor focus."
        );
        ensure!(
            !self.native.isKeyWindow() && !self.native.isMainWindow(),
            "The GPUI voice pill took editor focus."
        );
        ensure!(
            self.native.ignoresMouseEvents(),
            "The GPUI voice pill intercepts mouse input."
        );
        Ok(())
    }

    pub fn window_number(&self) -> isize {
        self.native.windowNumber()
    }
}

extern "C-unwind" fn cannot_activate(_: &AnyObject, _: Sel) -> Bool {
    Bool::NO
}

impl Render for VoicePill {
    fn render(&mut self, window: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
        let listening = self.label.as_ref() == "Listening";
        let busy = matches!(self.label.as_ref(), "Starting" | "Transcribing");
        let waveform = div()
            .flex()
            .items_center()
            .justify_center()
            .gap(px(3.))
            .w(px(42.))
            .h(px(24.))
            .children([0.35, 0.65, 0.9, 1., 0.9, 0.65, 0.35].map(|envelope| {
                div()
                    .w(px(2.))
                    .h(px(if listening {
                        3. + self.level * envelope * 18.
                    } else {
                        3.
                    }))
                    .rounded_full()
                    .bg(rgb(0xff742f))
            }));
        let feedback = if busy {
            let phase = if crate::platform::reduced_motion() {
                0.
            } else {
                window.request_animation_frame();
                self.started.elapsed().as_secs_f32() * 5.
            };
            canvas(
                |_, _, _| (),
                move |bounds, _, window, _| {
                    let center = bounds.center();
                    let mut path = PathBuilder::stroke(px(1.7));
                    for index in 0..=24 {
                        let angle = phase + index as f32 / 24. * std::f32::consts::TAU * 0.7;
                        let position = point(
                            center.x + px(angle.cos() * 7.),
                            center.y + px(angle.sin() * 7.),
                        );
                        if index == 0 {
                            path.move_to(position);
                        } else {
                            path.line_to(position);
                        }
                    }
                    if let Ok(path) = path.build() {
                        window.paint_path(path, rgb(0xff742f));
                    }
                },
            )
            .w(px(42.))
            .h(px(24.))
            .into_any_element()
        } else {
            waveform.into_any_element()
        };
        div()
            .size_full()
            .flex()
            .items_center()
            .justify_center()
            .font_family("Manrope")
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap(px(8.))
                    .px(px(14.))
                    .h(px(38.))
                    .rounded_full()
                    .bg(rgb(0x191919))
                    .border_1()
                    .border_color(rgba(0xffffff18))
                    .text_size(px(12.))
                    .text_color(rgb(0xf2f0ec))
                    .child(feedback)
                    .child(div().w(px(116.)).child(self.label.clone())),
            )
    }
}

impl Drop for Overlay {
    fn drop(&mut self) {
        self.native.orderOut(None);
    }
}
