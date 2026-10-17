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

const VOICE_DIAMETER: f32 = 38.;
const LABEL_WIDTH: f32 = 122.;
const LABEL_HEIGHT: f32 = 36.;
const SURFACE_GAP: f32 = 7.;
const WINDOW_MARGIN: f32 = 10.;
const WINDOW_WIDTH: f32 = VOICE_DIAMETER + SURFACE_GAP + LABEL_WIDTH + WINDOW_MARGIN * 2.;
const WINDOW_HEIGHT: f32 = 60.;
const BAR_BASELINE: f32 = 3.;

pub struct Overlay {
    window: WindowHandle<VoicePill>,
    native: Retained<NSWindow>,
    visible: bool,
}

struct VoicePill {
    label: SharedString,
    meter: VoiceMeter,
    started: Instant,
}

struct VoiceMeter {
    recent: [f32; 5],
    heights: [f32; 5],
    rendered_at: Instant,
}

impl VoiceMeter {
    fn new(now: Instant) -> Self {
        Self {
            recent: [0.; 5],
            heights: [BAR_BASELINE; 5],
            rendered_at: now,
        }
    }

    fn push(&mut self, level: f32) {
        let level = if level.is_finite() {
            level.clamp(0., 1.)
        } else {
            0.
        };
        self.recent.rotate_left(1);
        self.recent[4] = ((level - 0.012).max(0.) * 1.5).min(1.).sqrt();
    }

    fn sample(&mut self, now: Instant, reduced_motion: bool) -> ([f32; 5], bool) {
        let elapsed = now.duration_since(self.rendered_at).as_secs_f32().min(0.1);
        self.rendered_at = now;
        let mut settling = false;
        for (index, envelope) in [0.65, 0.85, 1., 0.85, 0.65].into_iter().enumerate() {
            let target = BAR_BASELINE + self.recent[index] * envelope * 19.;
            let height = &mut self.heights[index];
            if reduced_motion {
                *height = target;
                continue;
            }
            let duration = if target > *height { 0.035 } else { 0.110 };
            *height += (target - *height) * (1. - (-elapsed / duration).exp());
            if (target - *height).abs() < 0.02 {
                *height = target;
            } else {
                settling = true;
            }
        }
        (self.heights, settling)
    }
}

impl Overlay {
    pub fn new(cx: &mut App) -> Result<Self> {
        let window = cx.open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(Bounds::centered(
                    None,
                    size(px(WINDOW_WIDTH), px(WINDOW_HEIGHT)),
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
                    meter: VoiceMeter::new(Instant::now()),
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
        let was_visible = self.visible;
        let _ = self.window.update(cx, |pill, _, cx| {
            let changed = pill.label.as_ref() != label;
            if !visible || !was_visible || changed {
                pill.meter = VoiceMeter::new(Instant::now());
            }
            if visible && label == "Listening" {
                pill.meter.push(level);
            }
            if changed {
                pill.label = label.to_owned().into();
            }
            if changed || visible {
                cx.notify();
            }
        });
        if visible {
            if let Some(screen) = MainThreadMarker::new().and_then(NSScreen::mainScreen) {
                let frame = screen.visibleFrame();
                self.native.setFrameOrigin(NSPoint::new(
                    frame.origin.x + (frame.size.width - f64::from(WINDOW_WIDTH)) / 2.,
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
        let reduced_motion = crate::platform::reduced_motion();
        let (heights, settling) = self.meter.sample(Instant::now(), reduced_motion);
        if listening && settling {
            window.request_animation_frame();
        }
        let waveform = div()
            .flex()
            .items_center()
            .justify_center()
            .gap(px(2.))
            .children(heights.map(|height| {
                div()
                    .w(px(2.))
                    .h(px(if listening { height } else { BAR_BASELINE }))
                    .rounded_full()
                    .bg(rgb(0xff742f))
            }));
        let feedback = if busy {
            let phase = if reduced_motion {
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
            .w(px(24.))
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
                    .gap(px(SURFACE_GAP))
                    .text_size(px(12.))
                    .text_color(rgb(0xf2f0ec))
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .justify_center()
                            .size(px(VOICE_DIAMETER))
                            .rounded_full()
                            .bg(rgb(0x000000))
                            .border_1()
                            .border_color(rgb(0x303030))
                            .child(feedback),
                    )
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .justify_center()
                            .w(px(LABEL_WIDTH))
                            .h(px(LABEL_HEIGHT))
                            .rounded_full()
                            .bg(rgb(0x000000))
                            .border_1()
                            .border_color(rgb(0x303030))
                            .text_center()
                            .child(self.label.clone()),
                    ),
            )
    }
}

impl Drop for Overlay {
    fn drop(&mut self) {
        self.native.orderOut(None);
    }
}

#[cfg(test)]
mod tests {
    use super::VoiceMeter;
    use std::time::{Duration, Instant};

    fn assert_heights(actual: [f32; 5], expected: [f32; 5]) {
        for (actual, expected) in actual.into_iter().zip(expected) {
            assert!((actual - expected).abs() < 0.002, "{actual} != {expected}");
        }
    }

    #[test]
    fn quiet_and_loud_speech_have_visible_range() {
        let now = Instant::now();
        let mut meter = VoiceMeter::new(now);
        for _ in 0..5 {
            meter.push(0.06);
        }
        assert_heights(
            meter.sample(now, true).0,
            [6.3139, 7.3336, 8.0982, 7.3336, 6.3139],
        );
        for _ in 0..5 {
            meter.push(1.);
        }
        assert_heights(meter.sample(now, true).0, [15.35, 19.15, 22., 19.15, 15.35]);
    }

    #[test]
    fn repeated_samples_advance_the_visible_history() {
        let now = Instant::now();
        let mut meter = VoiceMeter::new(now);
        meter.push(0.06);
        assert_heights(meter.sample(now, true).0, [3., 3., 3., 3., 6.3139]);
        meter.push(0.06);
        assert_heights(meter.sample(now, true).0, [3., 3., 3., 7.3336, 6.3139]);
    }

    #[test]
    fn smoothing_depends_on_elapsed_time_instead_of_frame_count() {
        let now = Instant::now();
        let mut one_frame = VoiceMeter::new(now);
        let mut two_frames = VoiceMeter::new(now);
        for _ in 0..5 {
            one_frame.push(1.);
            two_frames.push(1.);
        }
        two_frames.sample(now + Duration::from_millis(35), false);
        let (one, one_settling) = one_frame.sample(now + Duration::from_millis(70), false);
        let (two, two_settling) = two_frames.sample(now + Duration::from_millis(70), false);
        let expected = [13.6786, 16.9643, 19.4286, 16.9643, 13.6786];
        assert_heights(one, expected);
        assert_heights(two, expected);
        assert!(one_settling && two_settling);
    }

    #[test]
    fn silence_releases_then_stops_requesting_frames() {
        let now = Instant::now();
        let mut meter = VoiceMeter::new(now);
        for _ in 0..5 {
            meter.push(1.);
        }
        meter.sample(now, true);
        for _ in 0..5 {
            meter.push(0.);
        }
        let (releasing, settling) = meter.sample(now + Duration::from_millis(55), false);
        assert_heights(releasing, [10.4907, 12.7955, 14.5241, 12.7955, 10.4907]);
        assert!(settling);
        for frame in 2..=20 {
            meter.sample(now + Duration::from_millis(frame * 55), false);
        }
        let (silent, settling) = meter.sample(now + Duration::from_millis(1155), false);
        assert_heights(silent, [3.; 5]);
        assert!(!settling);
    }

    #[test]
    fn reduced_motion_uses_real_targets_without_settling() {
        let now = Instant::now();
        let mut meter = VoiceMeter::new(now);
        meter.push(1.);
        let (heights, settling) = meter.sample(now, true);
        assert_heights(heights, [3., 3., 3., 3., 15.35]);
        assert!(!settling);
    }

    #[test]
    fn long_render_pauses_do_not_skip_the_attack() {
        let now = Instant::now();
        let mut meter = VoiceMeter::new(now);
        for _ in 0..5 {
            meter.push(1.);
        }
        let (heights, settling) = meter.sample(now + Duration::from_secs(60), false);
        assert_heights(heights, [14.6407, 18.2225, 20.9088, 18.2225, 14.6407]);
        assert!(settling);
    }

    #[test]
    fn fresh_meter_discards_prior_session_and_keeps_first_new_sample() {
        let now = Instant::now();
        let mut meter = VoiceMeter::new(now);
        for _ in 0..5 {
            meter.push(1.);
        }
        meter.sample(now, true);
        meter = VoiceMeter::new(now);
        meter.push(0.06);
        assert_heights(meter.sample(now, true).0, [3., 3., 3., 3., 6.3139]);
    }

    #[test]
    fn invalid_and_room_noise_levels_stay_at_baseline() {
        let now = Instant::now();
        let mut meter = VoiceMeter::new(now);
        for level in [f32::NAN, f32::INFINITY, f32::NEG_INFINITY, -1., 0.01] {
            meter.push(level);
        }
        assert_heights(meter.sample(now, true).0, [3.; 5]);
        meter.push(2.);
        assert_heights(meter.sample(now, true).0, [3., 3., 3., 3., 15.35]);
    }
}
