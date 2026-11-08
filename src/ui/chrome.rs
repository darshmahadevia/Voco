//! Window chrome: sidebar navigation, the inset content panel, and the
//! persistent status bar with recovery.

use super::kit::{self, icon};
use super::*;

impl VocoApp {
    fn sidebar(&self, window: &mut Window, cx: &mut Context<Self>) -> Div {
        div()
            .w(px(SIDEBAR_WIDTH))
            .flex_shrink_0()
            .h_full()
            .flex()
            .flex_col()
            .px(px(12.))
            .pb(px(14.))
            .child(
                // The transparent title bar sits over this area, so it moves the window.
                div()
                    .id("titlebar-drag")
                    .h(px(86.))
                    .flex()
                    .items_end()
                    .px(px(10.))
                    .pb(px(22.))
                    .on_mouse_down(MouseButton::Left, |_, window, _| window.start_window_move())
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(9.))
                            .child(
                                svg()
                                    .path("mark")
                                    .w(px(27.))
                                    .h(px(21.))
                                    .text_color(rgb(ORANGE)),
                            )
                            .child(
                                div()
                                    .text_size(px(20.))
                                    .line_height(px(24.))
                                    .font_weight(FontWeight::SEMIBOLD)
                                    .child("voco"),
                            ),
                    ),
            )
            .child(
                div()
                    .flex()
                    .flex_col()
                    .gap(px(2.))
                    .child(self.nav(Page::Home, window, cx))
                    .child(self.nav(Page::Transcripts, window, cx))
                    .child(self.nav(Page::Stats, window, cx)),
            )
            .child(div().flex_1())
            .child(self.engine_card(window, cx))
            .child(div().h(px(6.)))
            .child(self.nav(Page::Settings, window, cx))
    }

    fn nav(&self, page: Page, window: &mut Window, cx: &mut Context<Self>) -> Stateful<Div> {
        let (icon_name, label, shortcut) = match page {
            Page::Home => ("home", "Home", "⌘1"),
            Page::Transcripts => ("transcripts", "Transcripts", "⌘2"),
            Page::Stats => ("stats", "Statistics", "⌘3"),
            Page::Settings => ("settings", "Settings", "⌘,"),
        };
        // Transcripts shows how many dictations are held instead of its shortcut.
        let history = self.controller.history.len();
        let badge = (page == Page::Transcripts && history > 0).then_some(history);
        let selected = self.page == page;
        self.pressable(
            SharedString::from(format!("nav-{page:?}")),
            window,
            cx,
            move |app, _, _| app.page = page,
        )
        .rounded(px(8.))
        .w_full()
        .h(px(34.))
        .px(px(10.))
        .flex()
        .items_center()
        .gap(px(10.))
        .map(|row| {
            if selected {
                row.bg(rgb(CONTROL))
            } else {
                row.hover(|row| row.bg(rgb(0x161616)))
            }
        })
        .child(
            div()
                .flex_1()
                .flex()
                .items_center()
                .gap(px(10.))
                .child(icon(icon_name, 16., if selected { ORANGE } else { MUTED }))
                .child(
                    div()
                        .flex_1()
                        .text_size(px(13.))
                        .font_weight(FontWeight::MEDIUM)
                        .text_color(rgb(if selected { TEXT } else { TEXT_2 }))
                        .child(label),
                )
                .child(match badge {
                    Some(count) => div()
                        .min_w(px(20.))
                        .h(px(18.))
                        .px(px(6.))
                        .flex()
                        .items_center()
                        .justify_center()
                        .rounded_full()
                        .bg(rgb(if selected { LINE_STRONG } else { CONTROL }))
                        .text_size(px(10.5))
                        .font_weight(FontWeight::MEDIUM)
                        .text_color(rgb(TEXT_2))
                        .child(count.to_string()),
                    None => div()
                        .text_size(px(11.))
                        .text_color(rgb(FAINT))
                        .child(shortcut),
                }),
        )
    }

    /// The selected model and its state, one click from model settings.
    fn engine_card(&self, window: &mut Window, cx: &mut Context<Self>) -> Stateful<Div> {
        let controller = &self.controller;
        let model = controller.settings.selected_model;
        let downloading = controller.download.as_ref().filter(|d| d.id == model);
        let (color, state) = match (&controller.engine, downloading) {
            (_, Some(download)) => (
                ORANGE,
                format!("Downloading {:.0}%", download.progress * 100.),
            ),
            (EngineStatus::Ready, _) => (SUCCESS, "Ready".into()),
            (EngineStatus::Loading, _) => (ORANGE, "Loading…".into()),
            (EngineStatus::Missing, _) => (FAINT, "Not downloaded".into()),
            (EngineStatus::Error(_), _) => (DANGER, "Needs attention".into()),
        };
        let mode = match controller.settings.output_mode {
            OutputMode::Fast => "Fast",
            OutputMode::Balanced => "Balanced",
            OutputMode::Accurate => "Accurate",
        };
        self.pressable("engine-card", window, cx, |app, _, _| {
            app.page = Page::Settings;
            app.tab = SettingsTab::Models;
        })
        .w_full()
        .px(px(12.))
        .py(px(10.))
        .rounded(px(10.))
        .border_color(rgb(LINE))
        .hover(|card| card.bg(rgb(0x141414)))
        .tooltip(|window, cx| {
            gpui_component::tooltip::Tooltip::new("Speech model settings").build(window, cx)
        })
        .child(
            div()
                .w_full()
                .flex()
                .flex_col()
                .gap(px(3.))
                .child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(7.))
                        .child(kit::dot(color, 6.))
                        .child(
                            div()
                                .text_size(px(12.5))
                                .font_weight(FontWeight::MEDIUM)
                                .text_color(rgb(TEXT))
                                .child(model.label()),
                        ),
                )
                .child(
                    div()
                        .pl(px(13.))
                        .text_size(px(11.))
                        .text_color(rgb(MUTED))
                        .child(format!("{state} · {mode}")),
                ),
        )
    }

    fn recovery(
        &self,
        message: &str,
        text: &str,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Div {
        div()
            .mx(px(16.))
            .mb(px(12.))
            .p(px(16.))
            .flex()
            .flex_col()
            .gap(px(12.))
            .rounded(px(12.))
            .bg(rgb(0x1a110c))
            .border_1()
            .border_color(rgba(0xff742f40))
            .child(
                div()
                    .flex()
                    .items_start()
                    .gap(px(10.))
                    .child(icon("alert", 16., ORANGE).mt(px(1.)))
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .gap(px(2.))
                            .child(
                                div()
                                    .text_size(px(13.))
                                    .font_weight(FontWeight::SEMIBOLD)
                                    .child("Your dictation needs attention"),
                            )
                            .child(kit::hint(message.to_owned())),
                    ),
            )
            .when(!text.is_empty(), |panel| {
                panel.child(
                    div()
                        .id("recovery-text")
                        .max_h(px(120.))
                        .overflow_y_scroll()
                        .p(px(12.))
                        .rounded(px(8.))
                        .bg(rgba(0x0000004d))
                        .child(literal_text("recovery-words".into(), text, window, cx)),
                )
            })
            .child(
                div()
                    .flex()
                    .gap(px(8.))
                    .when(!text.is_empty(), |row| {
                        row.child(self.button_with_icon(
                            "recover",
                            Some("copy"),
                            "Copy your words",
                            Tone::Primary,
                            cx,
                            |app, _, _| {
                                app.controller.copy_recovery();
                                if !matches!(app.controller.session, Session::Recovery { .. }) {
                                    app.copied_until =
                                        Some(Instant::now() + Duration::from_secs(2));
                                    app.copied_key = None;
                                }
                            },
                        ))
                    })
                    .child(
                        self.button("dismiss", "Dismiss", Tone::Ghost, cx, |app, _, _| {
                            app.controller.cancel()
                        }),
                    ),
            )
    }

    fn status_bar(&self, window: &mut Window, cx: &mut Context<Self>) -> Div {
        let controller = &self.controller;
        let session = &controller.session;
        let capturing = matches!(
            session,
            Session::Armed | Session::Listening { .. } | Session::Finishing
        );
        let color = match (session, &controller.engine) {
            (Session::Recovery { .. }, _) => ORANGE,
            _ if capturing => ORANGE,
            (_, EngineStatus::Error(_)) => DANGER,
            _ if controller.ready() => SUCCESS,
            _ => ORANGE,
        };
        let mut bar = div().flex_shrink_0().flex().flex_col();
        if let Session::Recovery { message, text } = session {
            bar = bar.child(self.recovery(message, text, window, cx));
        }
        if !controller.notice.is_empty() {
            bar = bar.child(
                div()
                    .flex()
                    .items_start()
                    .gap(px(8.))
                    .px(px(20.))
                    .py(px(10.))
                    .border_t_1()
                    .border_color(rgb(LINE))
                    .child(icon("alert", 13., MUTED).mt(px(2.)))
                    .child(kit::hint(controller.notice.clone())),
            );
        }
        let listening = matches!(session, Session::Listening { .. });
        let level = controller.level();
        let trailing = if capturing {
            div()
                .flex()
                .items_center()
                .gap(px(8.))
                .child(
                    Button::new("cancel-session")
                        .ghost()
                        .rounded(px(999.))
                        .h(px(28.))
                        .px(px(10.))
                        .on_click(cx.listener(|app, _, _, cx| {
                            app.controller.cancel();
                            cx.notify();
                        }))
                        .child(
                            div()
                                .flex()
                                .items_center()
                                .gap(px(8.))
                                .text_size(px(12.))
                                .text_color(rgb(TEXT))
                                .child("Cancel")
                                .child(kit::keycap("esc").h(px(20.))),
                        ),
                )
                .into_any_element()
        } else if self
            .copied_until
            .is_some_and(|until| until > Instant::now())
        {
            div()
                .flex()
                .items_center()
                .gap(px(6.))
                .text_size(px(12.))
                .text_color(rgb(SUCCESS))
                .child(icon("check", 13., SUCCESS))
                .child("Copied to clipboard")
                .into_any_element()
        } else {
            div()
                .flex()
                .items_center()
                .gap(px(6.))
                .text_size(px(11.5))
                .text_color(rgb(MUTED))
                .child(icon("lock", 12., MUTED))
                .child("Processed on your Mac")
                .into_any_element()
        };
        bar.child(
            div()
                .h(px(46.))
                .flex()
                .items_center()
                .justify_between()
                .gap(px(16.))
                .px(px(20.))
                .border_t_1()
                .border_color(rgb(LINE))
                .child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(10.))
                        .min_w_0()
                        .child(
                            // A soft halo around the dot shows that a session is live.
                            div()
                                .size(px(14.))
                                .flex()
                                .items_center()
                                .justify_center()
                                .rounded_full()
                                .when(capturing, |halo| halo.bg(rgba(0xff742f2e)))
                                .child(kit::dot(color, 7.)),
                        )
                        .child(
                            div()
                                .text_size(px(12.5))
                                .font_weight(FontWeight::MEDIUM)
                                .truncate()
                                .child(controller.status().to_owned()),
                        )
                        .when(listening, |row| {
                            // Measured microphone energy only, never synthetic motion.
                            row.child(
                                div()
                                    .w(px(56.))
                                    .child(kit::meter(level.max(0.).sqrt(), ORANGE)),
                            )
                        }),
                )
                .child(trailing),
        )
    }
}

impl Render for VocoApp {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let content = match self.page {
            Page::Home => self.home(window, cx),
            Page::Settings => self.settings(window, cx),
            Page::Stats => self.stats(window, cx),
            Page::Transcripts => self.transcripts_page(window, cx),
        };
        let content = if platform::reduced_motion() {
            content.into_any_element()
        } else {
            content
                .with_animation(
                    SharedString::from(format!("page-{:?}-{}", self.page, self.tab as u8)),
                    Animation::new(Duration::from_millis(180)).with_easing(ease_out_quint()),
                    |element, progress| {
                        element
                            .opacity(0.7 + progress * 0.3)
                            .mt(px((1. - progress) * 6.))
                    },
                )
                .into_any_element()
        };
        div()
            .size_full()
            .flex()
            .bg(rgb(CANVAS))
            .text_color(rgb(TEXT))
            .font_family("Manrope")
            .text_size(px(13.))
            .on_key_down(cx.listener(|app, event: &KeyDownEvent, window, cx| {
                if app.page == Page::Transcripts
                    && event.keystroke.key == "escape"
                    && app.search.focus_handle(cx).is_focused(window)
                {
                    app.search
                        .update(cx, |input, cx| input.set_value("", window, cx));
                    cx.stop_propagation();
                    cx.notify();
                }
            }))
            .child(self.sidebar(window, cx))
            .child(
                div()
                    .flex_1()
                    .min_w_0()
                    .h_full()
                    .py(px(8.))
                    .pr(px(8.))
                    .child(
                        div()
                            .size_full()
                            .flex()
                            .flex_col()
                            .overflow_hidden()
                            .rounded(px(12.))
                            .bg(rgb(PANEL))
                            .border_1()
                            .border_color(rgb(LINE))
                            .child(
                                div()
                                    .id("page-scroll")
                                    .flex_1()
                                    .min_h_0()
                                    .overflow_y_scroll()
                                    .child(
                                        div()
                                            .w_full()
                                            .max_w(px(880.))
                                            .mx_auto()
                                            .px(px(36.))
                                            .pt(px(34.))
                                            .pb(px(40.))
                                            .child(content),
                                    ),
                            )
                            .child(self.status_bar(window, cx)),
                    ),
            )
    }
}
