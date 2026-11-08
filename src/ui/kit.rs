//! Shared dashboard primitives. Every page composes these so spacing,
//! radii, and type stay consistent.

use super::*;

#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum Tone {
    /// Soft-white fill for the one action a surface is asking for.
    Primary,
    /// Graphite fill for ordinary actions.
    Secondary,
    /// No fill until hovered, for low-emphasis and inline actions.
    Ghost,
}

pub(super) fn icon(name: &'static str, size: f32, color: u32) -> Svg {
    svg()
        .path(name)
        .size(px(size))
        .flex_shrink_0()
        .text_color(rgb(color))
}

/// A raised surface for grouping related content.
pub(super) fn card() -> Div {
    div()
        .bg(rgb(RAISED))
        .border_1()
        .border_color(rgb(LINE))
        .rounded(px(14.))
}

pub(super) fn page_header(title: impl Into<SharedString>, detail: impl Into<SharedString>) -> Div {
    div()
        .flex()
        .flex_col()
        .gap(px(6.))
        .child(
            div()
                .text_size(px(26.))
                .line_height(px(34.))
                .font_weight(FontWeight::SEMIBOLD)
                .child(title.into()),
        )
        .child(
            div()
                .text_size(px(13.))
                .line_height(px(20.))
                .text_color(rgb(MUTED))
                .child(detail.into()),
        )
}

/// A section title with an optional trailing element, such as a hint or action.
pub(super) fn section_title(title: impl Into<SharedString>) -> Div {
    div()
        .flex()
        .items_center()
        .justify_between()
        .gap(px(12.))
        .min_h(px(32.))
        .child(
            div()
                .text_size(px(13.))
                .font_weight(FontWeight::SEMIBOLD)
                .child(title.into()),
        )
}

pub(super) fn hint(text: impl Into<SharedString>) -> Div {
    div()
        .text_size(px(12.))
        .line_height(px(18.))
        .text_color(rgb(MUTED))
        .child(text.into())
}

pub(super) fn keycap(label: impl IntoElement) -> Div {
    div()
        .h(px(24.))
        .min_w(px(24.))
        .px(px(7.))
        .flex()
        .items_center()
        .justify_center()
        .flex_shrink_0()
        .rounded(px(6.))
        .bg(rgb(0x1c1c1c))
        .border_1()
        .border_b_2()
        .border_color(rgb(0x383838))
        .text_size(px(11.5))
        .font_weight(FontWeight::MEDIUM)
        .text_color(rgb(TEXT))
        .child(label)
}

/// The Fn / Globe key, drawn the way it appears on Apple keyboards.
pub(super) fn fn_key() -> Div {
    keycap(
        div()
            .flex()
            .items_center()
            .gap(px(4.))
            .child("fn")
            .child(icon("globe", 11., TEXT)),
    )
}

/// A row of keycaps joined by plus signs, followed by what the shortcut does.
pub(super) fn shortcut(keys: Vec<Div>, label: impl Into<SharedString>) -> Div {
    let mut combo = div().flex().items_center().gap(px(5.));
    for (index, key) in keys.into_iter().enumerate() {
        if index > 0 {
            combo = combo.child(div().text_size(px(11.)).text_color(rgb(FAINT)).child("+"));
        }
        combo = combo.child(key);
    }
    div().flex().items_center().gap(px(10.)).child(combo).child(
        div()
            .text_size(px(12.))
            .text_color(rgb(TEXT_2))
            .child(label.into()),
    )
}

pub(super) fn dot(color: u32, size: f32) -> Div {
    div()
        .size(px(size))
        .flex_shrink_0()
        .rounded_full()
        .bg(rgb(color))
}

/// A small status label. `background` is an RGBA hex value.
pub(super) fn chip(label: impl Into<SharedString>, color: u32, background: u32) -> Div {
    div()
        .h(px(20.))
        .px(px(8.))
        .flex()
        .flex_shrink_0()
        .items_center()
        .gap(px(5.))
        .rounded_full()
        .bg(rgba(background))
        .text_size(px(11.))
        .font_weight(FontWeight::MEDIUM)
        .text_color(rgb(color))
        .child(label.into())
}

pub(super) fn success_chip(label: impl Into<SharedString>) -> Div {
    chip(label, SUCCESS, SUCCESS_SOFT).child(icon("check", 11., SUCCESS))
}

/// A thin horizontal progress meter.
pub(super) fn meter(fraction: f32, color: u32) -> Div {
    div()
        .h(px(4.))
        .w_full()
        .rounded_full()
        .bg(rgb(LINE_STRONG))
        .overflow_hidden()
        .child(
            div()
                .h_full()
                .rounded_full()
                .w(relative(if fraction.is_finite() {
                    fraction.clamp(0., 1.)
                } else {
                    0.
                }))
                .bg(rgb(color)),
        )
}

/// A round marker with an icon, used beside permission and safety rows.
pub(super) fn icon_well(name: &'static str, color: u32, background: u32) -> Div {
    div()
        .size(px(34.))
        .flex_shrink_0()
        .flex()
        .items_center()
        .justify_center()
        .rounded(px(10.))
        .bg(rgba(background))
        .child(icon(name, 17., color))
}

/// A centered message for lists with nothing to show yet.
pub(super) fn empty_state(
    icon_name: &'static str,
    title: impl Into<SharedString>,
    detail: impl Into<SharedString>,
) -> Div {
    div()
        .flex()
        .flex_col()
        .items_center()
        .gap(px(6.))
        .py(px(36.))
        .px(px(24.))
        .text_center()
        .child(
            div()
                .mb(px(6.))
                .size(px(40.))
                .flex()
                .items_center()
                .justify_center()
                .rounded_full()
                .bg(rgb(CONTROL))
                .child(icon(icon_name, 18., MUTED)),
        )
        .child(
            div()
                .text_size(px(13.))
                .font_weight(FontWeight::MEDIUM)
                .child(title.into()),
        )
        .child(hint(detail).max_w(px(360.)))
}

/// Formats a whole number with thousands separators.
pub(super) fn count(value: u64) -> String {
    let digits = value.to_string();
    let mut result = String::with_capacity(digits.len() + digits.len() / 3);
    for (index, digit) in digits.chars().enumerate() {
        if index > 0 && (digits.len() - index).is_multiple_of(3) {
            result.push(',');
        }
        result.push(digit);
    }
    result
}

/// Formats saved time as minutes, or hours and minutes past the first hour.
pub(super) fn duration(seconds: f64) -> String {
    let minutes = (seconds.max(0.) / 60.).floor() as u64;
    if minutes < 60 {
        format!("{minutes} min")
    } else if minutes.is_multiple_of(60) {
        format!("{} h", minutes / 60)
    } else {
        format!("{} h {} min", minutes / 60, minutes % 60)
    }
}

pub(super) fn plural(value: u64, one: &str, many: &str) -> String {
    format!("{} {}", count(value), if value == 1 { one } else { many })
}

impl VocoApp {
    pub(super) fn button(
        &self,
        id: impl Into<ElementId>,
        label: impl Into<SharedString>,
        tone: Tone,
        cx: &mut Context<Self>,
        action: impl Fn(&mut Self, &mut Window, &mut Context<Self>) + 'static,
    ) -> Button {
        self.button_with_icon(id, None, label, tone, cx, action)
    }

    pub(super) fn button_with_icon(
        &self,
        id: impl Into<ElementId>,
        leading: Option<&'static str>,
        label: impl Into<SharedString>,
        tone: Tone,
        cx: &mut Context<Self>,
        action: impl Fn(&mut Self, &mut Window, &mut Context<Self>) + 'static,
    ) -> Button {
        let foreground = if tone == Tone::Primary { CANVAS } else { TEXT };
        let button = Button::new(id)
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap(px(6.))
                    .text_color(rgb(foreground))
                    .when_some(leading, |row, name| row.child(icon(name, 14., foreground)))
                    .child(label.into()),
            )
            .rounded(px(999.))
            .h(px(32.))
            .px(px(14.))
            .text_size(px(12.5))
            .font_weight(FontWeight::MEDIUM)
            .text_color(rgb(foreground))
            .on_click(cx.listener(move |app, _, window, cx| {
                action(app, window, cx);
                cx.notify();
            }));
        match tone {
            Tone::Primary => button.primary(),
            Tone::Secondary => button,
            Tone::Ghost => button.ghost(),
        }
    }

    /// A square, icon-only ghost action with a tooltip naming it.
    pub(super) fn icon_button(
        &self,
        id: impl Into<ElementId>,
        name: &'static str,
        color: u32,
        tooltip: &'static str,
        cx: &mut Context<Self>,
        action: impl Fn(&mut Self, &mut Window, &mut Context<Self>) + 'static,
    ) -> Button {
        Button::new(id)
            .ghost()
            .rounded(px(8.))
            .w(px(30.))
            .h(px(30.))
            .p(px(0.))
            .tooltip(tooltip)
            .child(icon(name, 15., color))
            .on_click(cx.listener(move |app, _, window, cx| {
                action(app, window, cx);
                cx.notify();
            }))
    }

    /// A focusable, clickable surface for rich layouts. `Button` wraps its
    /// children in an auto-width row, so full-width rows and wrapping cards
    /// use this instead. Enter and Space activate it, and keyboard focus
    /// draws an orange ring; pointer clicks do not move focus.
    pub(super) fn pressable(
        &self,
        id: impl Into<ElementId>,
        window: &mut Window,
        cx: &mut Context<Self>,
        action: impl Fn(&mut Self, &mut Window, &mut Context<Self>) + 'static,
    ) -> Stateful<Div> {
        let id: ElementId = id.into();
        let focus = window
            .use_keyed_state(id.clone(), cx, |_, cx| cx.focus_handle())
            .read(cx)
            .clone()
            .tab_stop(true);
        let action = std::rc::Rc::new(action);
        let on_key = action.clone();
        div()
            .id(id)
            .track_focus(&focus)
            .border_1()
            .border_color(rgba(0x00000000))
            .focus(|style| style.border_color(rgb(ORANGE)))
            .on_mouse_down(MouseButton::Left, |_, window, _| window.prevent_default())
            .on_click(cx.listener(move |app, _, window, cx| {
                action(app, window, cx);
                cx.notify();
            }))
            .on_key_down(cx.listener(move |app, event: &KeyDownEvent, window, cx| {
                if matches!(event.keystroke.key.as_str(), "enter" | "space") {
                    on_key(app, window, cx);
                    cx.stop_propagation();
                    cx.notify();
                }
            }))
    }

    /// An on/off switch. It is a focusable button, so Tab and Space work.
    pub(super) fn toggle(
        &self,
        id: impl Into<ElementId>,
        on: bool,
        cx: &mut Context<Self>,
        action: impl Fn(&mut Self, &mut Window, &mut Context<Self>) + 'static,
    ) -> Button {
        Button::new(id)
            .ghost()
            .rounded(px(999.))
            .w(px(42.))
            .h(px(26.))
            .p(px(0.))
            .child(
                div()
                    .w(px(38.))
                    .h(px(22.))
                    .p(px(2.))
                    .flex()
                    .items_center()
                    .when(on, |track| track.justify_end())
                    .rounded_full()
                    .bg(rgb(if on { ORANGE } else { LINE_STRONG }))
                    .child(div().size(px(18.)).rounded_full().bg(rgb(if on {
                        0xffffff
                    } else {
                        TEXT_2
                    }))),
            )
            .on_click(cx.listener(move |app, _, window, cx| {
                action(app, window, cx);
                cx.notify();
            }))
    }
}

/// Dims and disables an action that is unavailable right now.
pub(super) fn unavailable(button: Button, disabled: bool) -> Button {
    button
        .disabled(disabled)
        .when(disabled, |button| button.opacity(0.4))
}

#[cfg(test)]
mod tests {
    // A glob import would bring in `gpui::test`, which shadows `#[test]`.
    use super::{count, duration};

    #[test]
    fn counts_use_thousands_separators() {
        assert_eq!(count(0), "0");
        assert_eq!(count(999), "999");
        assert_eq!(count(1000), "1,000");
        assert_eq!(count(1234567), "1,234,567");
    }

    #[test]
    fn durations_read_naturally() {
        assert_eq!(duration(59.), "0 min");
        assert_eq!(duration(60. * 42.), "42 min");
        assert_eq!(duration(60. * 120.), "2 h");
        assert_eq!(duration(60. * 135.), "2 h 15 min");
        assert_eq!(duration(-5.), "0 min");
    }
}
