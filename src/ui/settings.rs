//! Settings: output quality, speech models, system access, and dictation help.

use super::home::model_size;
use super::kit::{self, icon};
use super::*;

const TABS: [(SettingsTab, &str); 4] = [
    (SettingsTab::Output, "Output"),
    (SettingsTab::Models, "Models"),
    (SettingsTab::Access, "Access"),
    (SettingsTab::Dictation, "Dictation"),
];

/// A titled group of settings rows.
fn group(title: &'static str, body: impl IntoElement) -> Div {
    div()
        .flex()
        .flex_col()
        .gap(px(10.))
        .child(kit::section_title(title))
        .child(body)
}

fn row_text(title: impl Into<SharedString>, detail: impl Into<SharedString>) -> Div {
    div()
        .flex_1()
        .min_w_0()
        .flex()
        .flex_col()
        .gap(px(3.))
        .child(
            div()
                .text_size(px(13.))
                .font_weight(FontWeight::MEDIUM)
                .child(title.into()),
        )
        .child(kit::hint(detail))
}

fn settings_row() -> Div {
    div()
        .flex()
        .items_center()
        .gap(px(14.))
        .px(px(18.))
        .py(px(16.))
}

fn rule() -> Div {
    div().h(px(1.)).bg(rgb(LINE))
}

impl VocoApp {
    pub(super) fn settings(&self, window: &mut Window, cx: &mut Context<Self>) -> Div {
        let panel = match self.tab {
            SettingsTab::Output => self.output(window, cx),
            SettingsTab::Models => self.models(cx),
            SettingsTab::Access => self.access(cx),
            SettingsTab::Dictation => self.dictation(),
        };
        div()
            .flex()
            .flex_col()
            .gap(px(24.))
            .child(kit::page_header(
                "Settings",
                "A few thoughtful choices. Everything stays on this Mac.",
            ))
            .child(div().flex().child(self.tabs(cx)))
            .child(panel)
    }

    /// A segmented control. Arrow keys move between tabs; Home and End jump.
    fn tabs(&self, cx: &mut Context<Self>) -> Div {
        let mut tabs = div()
            .track_focus(&self.settings_focus)
            .on_key_down(cx.listener(|app, event: &KeyDownEvent, _, cx| {
                let index = app.tab as usize;
                let next = match event.keystroke.key.as_str() {
                    "right" | "down" => (index + 1) % TABS.len(),
                    "left" | "up" => (index + TABS.len() - 1) % TABS.len(),
                    "home" => 0,
                    "end" => TABS.len() - 1,
                    _ => return,
                };
                app.tab = TABS[next].0;
                cx.stop_propagation();
                cx.notify();
            }))
            .flex()
            .gap(px(2.))
            .p(px(3.))
            .rounded(px(10.))
            .bg(rgb(RAISED))
            .border_1()
            .border_color(rgb(LINE));
        for (tab, label) in TABS {
            let selected = self.tab == tab;
            tabs = tabs.child(
                Button::new(label)
                    .ghost()
                    .rounded(px(7.))
                    .h(px(30.))
                    .px(px(16.))
                    .when(selected, |button| button.bg(rgb(CONTROL_HOVER)))
                    .child(
                        div()
                            .text_size(px(12.5))
                            .font_weight(FontWeight::MEDIUM)
                            .text_color(rgb(if selected { TEXT } else { MUTED }))
                            .child(label),
                    )
                    .on_click(cx.listener(move |app, _, _, cx| {
                        app.tab = tab;
                        cx.notify();
                    })),
            );
        }
        tabs
    }

    fn output(&self, window: &mut Window, cx: &mut Context<Self>) -> Div {
        let active = self.controller.session.active();
        let current = self.controller.settings.output_mode;
        let mut options = div().flex().gap(px(10.));
        for (mode, icon_name, label, detail) in [
            (
                OutputMode::Fast,
                "zap",
                "Fast",
                "The speech model's original transcript, with nothing added.",
            ),
            (
                OutputMode::Balanced,
                "wave",
                "Balanced",
                "Removes fillers and spoken restarts. Quotes, code, links, and numbers stay intact.",
            ),
            (
                OutputMode::Accurate,
                "sparkle",
                "Accurate",
                "Adds punctuation and capitals with Apple's on-device models. Falls back to Balanced.",
            ),
        ] {
            let selected = current == mode;
            options = options.child(
                self.pressable(label, window, cx, move |app, _, _| {
                    if !app.controller.session.active() {
                        app.controller.settings.output_mode = mode;
                        app.controller.save();
                    }
                })
                .flex_1()
                .min_w_0()
                .p(px(16.))
                .rounded(px(12.))
                .border_color(rgb(if selected { ORANGE } else { LINE }))
                .bg(rgb(if selected { 0x1d140f } else { RAISED }))
                .when(!selected && !active, |card| {
                    card.hover(|card| card.bg(rgb(0x191919)).border_color(rgb(LINE_STRONG)))
                })
                .when(active && !selected, |card| card.opacity(0.5))
                .child(
                    div()
                        .w_full()
                        .flex()
                        .flex_col()
                        .gap(px(10.))
                        .child(
                            div()
                                .flex()
                                .items_center()
                                .justify_between()
                                .child(icon(icon_name, 18., if selected { ORANGE } else { TEXT_2 }))
                                .child(
                                    // A radio indicator mirrors the selected state.
                                    div()
                                        .size(px(16.))
                                        .flex()
                                        .items_center()
                                        .justify_center()
                                        .rounded_full()
                                        .border_1()
                                        .border_color(rgb(if selected {
                                            ORANGE
                                        } else {
                                            LINE_STRONG
                                        }))
                                        .when(selected, |radio| radio.child(kit::dot(ORANGE, 8.))),
                                ),
                        )
                        .child(
                            div()
                                .text_size(px(13.5))
                                .font_weight(FontWeight::SEMIBOLD)
                                .text_color(rgb(TEXT))
                                .child(label),
                        )
                        .child(
                            div()
                                .text_size(px(12.))
                                .line_height(px(18.))
                                .text_color(rgb(MUTED))
                                .whitespace_normal()
                                .child(detail),
                        ),
                ),
            );
        }
        let keep = self.controller.settings.keep_last_transcript;
        div()
            .flex()
            .flex_col()
            .gap(px(28.))
            .child(group(
                "Output quality",
                div()
                    .flex()
                    .flex_col()
                    .gap(px(10.))
                    .child(options)
                    .child(if active {
                        div()
                            .flex()
                            .items_center()
                            .gap(px(6.))
                            .text_size(px(12.))
                            .text_color(rgb(ORANGE))
                            .child(icon("alert", 13., ORANGE))
                            .child("Finish dictating to change output quality.")
                    } else {
                        kit::hint("Changes apply to your next dictation.")
                    }),
            ))
            .child(group(
                "History",
                kit::card()
                    .child(
                        settings_row()
                            .child(row_text(
                                "Keep recent transcripts",
                                "Held in memory until Voco quits. Turning this off clears them now.",
                            ))
                            .child(self.toggle("retention", keep, cx, |app, _, _| {
                                app.controller
                                    .set_retention(!app.controller.settings.keep_last_transcript)
                            })),
                    )
                    .child(rule())
                    .child(
                        settings_row()
                            .child(kit::icon_well("shield", SUCCESS, SUCCESS_SOFT))
                            .child(row_text(
                                "Recovery is always on",
                                "If insertion fails, your words wait here for you to copy, even with history off.",
                            )),
                    ),
            ))
    }

    fn models(&self, cx: &mut Context<Self>) -> Div {
        let controller = &self.controller;
        let busy = controller.session.active() || controller.download.is_some();
        let mut list = div().flex().flex_col().gap(px(10.));
        for id in ModelId::ALL {
            let installed = models::installed(&controller.root.join("models"), id);
            let selected = controller.settings.selected_model == id;
            let in_use = selected && matches!(controller.engine, EngineStatus::Ready);
            let loading = selected && matches!(controller.engine, EngineStatus::Loading);
            let download = controller.download.as_ref().filter(|d| d.id == id);
            let (variant, tag, detail) = match id {
                ModelId::Moonshine => (
                    "Medium Streaming",
                    "Smallest",
                    "The lightest download. A good place to start.",
                ),
                ModelId::Parakeet => (
                    "TDT 0.6B v2",
                    "Quick",
                    "NVIDIA's transducer model. Faster than Whisper in Voco's file benchmark.",
                ),
                ModelId::Whisper => (
                    "Large v3 Turbo",
                    "Largest",
                    "OpenAI's Whisper, accelerated with Metal on Apple Silicon.",
                ),
            };
            let action = if download.is_some() {
                self.button(
                    SharedString::from(format!("model-{id:?}")),
                    "Cancel",
                    Tone::Secondary,
                    cx,
                    move |app, _, _| app.controller.cancel_download(),
                )
                .into_any_element()
            } else if in_use {
                kit::success_chip("In use").into_any_element()
            } else if loading {
                kit::chip("Loading…", ORANGE, ORANGE_SOFT).into_any_element()
            } else {
                kit::unavailable(
                    self.button_with_icon(
                        SharedString::from(format!("model-{id:?}")),
                        (!installed).then_some("download"),
                        if installed { "Use model" } else { "Download" },
                        if installed {
                            Tone::Secondary
                        } else {
                            Tone::Primary
                        },
                        cx,
                        move |app, _, _| {
                            if !app.controller.session.active() && app.controller.download.is_none()
                            {
                                if installed {
                                    app.controller.load_model(id);
                                } else {
                                    app.controller.download_model(id);
                                }
                            }
                        },
                    ),
                    busy,
                )
                .into_any_element()
            };
            list = list.child(
                kit::card()
                    .p(px(18.))
                    .flex()
                    .flex_col()
                    .gap(px(14.))
                    .when(in_use, |card| card.border_color(rgba(0xff742f66)))
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(14.))
                            .child(kit::icon_well(
                                "cpu",
                                if in_use { ORANGE } else { TEXT_2 },
                                if in_use { ORANGE_SOFT } else { 0xffffff0d },
                            ))
                            .child(
                                div()
                                    .flex_1()
                                    .min_w_0()
                                    .flex()
                                    .flex_col()
                                    .gap(px(4.))
                                    .child(
                                        div()
                                            .flex()
                                            .items_center()
                                            .gap(px(8.))
                                            .child(
                                                div()
                                                    .text_size(px(15.))
                                                    .font_weight(FontWeight::SEMIBOLD)
                                                    .child(id.label()),
                                            )
                                            .child(kit::chip(tag, TEXT_2, 0xffffff0f))
                                            .when(installed && !in_use, |row| {
                                                row.child(kit::chip(
                                                    "Downloaded",
                                                    MUTED,
                                                    0xffffff08,
                                                ))
                                            }),
                                    )
                                    .child(kit::hint(detail))
                                    .child(div().text_size(px(11.)).text_color(rgb(FAINT)).child(
                                        format!("{variant} · English · {}", model_size(id)),
                                    )),
                            )
                            .child(action),
                    )
                    .when_some(download, |card, download| {
                        card.child(
                            div()
                                .flex()
                                .flex_col()
                                .gap(px(8.))
                                .child(kit::meter(download.progress, ORANGE))
                                .child(
                                    div()
                                        .flex()
                                        .justify_between()
                                        .text_size(px(11.))
                                        .text_color(rgb(MUTED))
                                        .child(download.file.clone())
                                        .child(
                                            div()
                                                .text_color(rgb(ORANGE))
                                                .child(format!("{:.0}%", download.progress * 100.)),
                                        ),
                                ),
                        )
                    }),
            );
        }
        let mut panel = div()
            .flex()
            .flex_col()
            .gap(px(14.))
            .child(group("Speech models", list))
            .child(kit::hint(
                "Models download once and then run offline. Switch models while dictation is idle.",
            ));
        if let EngineStatus::Error(message) = &controller.engine {
            panel = panel.child(
                kit::card()
                    .border_color(rgba(0xff9d9d40))
                    .p(px(18.))
                    .flex()
                    .flex_col()
                    .gap(px(14.))
                    .child(
                        div()
                            .flex()
                            .items_start()
                            .gap(px(10.))
                            .child(icon("alert", 16., DANGER).mt(px(1.)))
                            .child(
                                div()
                                    .text_size(px(12.5))
                                    .line_height(px(19.))
                                    .text_color(rgb(DANGER))
                                    .child(message.clone()),
                            ),
                    )
                    .child(
                        div()
                            .flex()
                            .gap(px(8.))
                            .child(self.button(
                                "retry",
                                "Retry loading",
                                Tone::Primary,
                                cx,
                                |app, _, _| {
                                    app.controller
                                        .load_model(app.controller.settings.selected_model)
                                },
                            ))
                            .child(self.button(
                                "redownload",
                                "Download a fresh copy",
                                Tone::Secondary,
                                cx,
                                |app, _, _| {
                                    if !app.controller.session.active()
                                        && app.controller.download.is_none()
                                    {
                                        app.controller
                                            .download_model(app.controller.settings.selected_model);
                                    }
                                },
                            )),
                    ),
            );
        }
        panel
    }

    fn access(&self, cx: &mut Context<Self>) -> Div {
        let permissions = &self.controller.permissions;
        let mut card = kit::card().overflow_hidden();
        for (index, (mic, icon_name, title, detail, granted)) in [
            (
                true,
                "mic",
                "Microphone",
                "Only listening while you hold fn or run hands-free dictation.",
                permissions.microphone,
            ),
            (
                false,
                "keyboard",
                "Accessibility",
                "Detects fn and inserts your words in the app you are using.",
                permissions.accessibility,
            ),
        ]
        .into_iter()
        .enumerate()
        {
            card = card.when(index > 0, |card| card.child(rule())).child(
                settings_row()
                    .child(kit::icon_well(
                        icon_name,
                        if granted { SUCCESS } else { TEXT_2 },
                        if granted { SUCCESS_SOFT } else { 0xffffff0d },
                    ))
                    .child(row_text(title, detail))
                    .child(if granted {
                        kit::success_chip("Allowed").into_any_element()
                    } else {
                        self.button_with_icon(
                            if mic { "mic" } else { "accessibility" },
                            None,
                            "Allow access",
                            Tone::Primary,
                            cx,
                            move |app, _, _| {
                                app.result(if mic {
                                    platform::request_microphone()
                                } else {
                                    platform::request_accessibility()
                                });
                            },
                        )
                        .child(icon("arrow-up-right", 12., CANVAS))
                        .into_any_element()
                    }),
            );
        }
        let shortcut_failed = permissions.accessibility && !self.controller.shortcut_running;
        let mut steps = div().flex().flex_col().gap(px(12.));
        for (number, text) in [
            "Open System Settings, then Keyboard.",
            "Set “Press Globe key to” to “Do Nothing”.",
            "Give Apple Dictation a different shortcut.",
            "In Accessibility, allow Voco itself. There is no separate helper.",
        ]
        .into_iter()
        .enumerate()
        {
            steps = steps.child(
                div()
                    .flex()
                    .items_start()
                    .gap(px(12.))
                    .child(
                        div()
                            .size(px(20.))
                            .flex_shrink_0()
                            .flex()
                            .items_center()
                            .justify_center()
                            .rounded_full()
                            .bg(rgb(CONTROL))
                            .text_size(px(10.5))
                            .font_weight(FontWeight::SEMIBOLD)
                            .text_color(rgb(TEXT_2))
                            .child((number + 1).to_string()),
                    )
                    .child(
                        div()
                            .pt(px(1.))
                            .text_size(px(12.5))
                            .line_height(px(19.))
                            .text_color(rgb(TEXT_2))
                            .child(text),
                    ),
            );
        }
        div()
            .flex()
            .flex_col()
            .gap(px(28.))
            .child(group("Permissions", card))
            .when(shortcut_failed, |panel| {
                panel.child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(8.))
                        .text_size(px(12.5))
                        .text_color(rgb(DANGER))
                        .child(icon("alert", 14., DANGER))
                        .child("Keyboard monitoring is unavailable. Check Accessibility and restart Voco."),
                )
            })
            .child(group(
                "If fn does nothing",
                kit::card()
                    .p(px(18.))
                    .flex()
                    .flex_col()
                    .gap(px(18.))
                    .child(steps)
                    .child(
                        div()
                            .flex()
                            .flex_wrap()
                            .gap(px(8.))
                            .child(self.button_with_icon(
                                "keyboard-settings",
                                Some("keyboard"),
                                "Open Keyboard Settings",
                                Tone::Secondary,
                                cx,
                                |app, _, _| app.result(platform::open_keyboard_settings()),
                            ))
                            .child(self.button("reveal", "Reveal Voco", Tone::Secondary, cx, |app, _, _| {
                                app.result(platform::show_app())
                            }))
                            .child(self.button("refresh-access", "Check again", Tone::Ghost, cx, |app, _, _| {
                                app.controller.refresh_permissions()
                            })),
                    ),
            ))
    }

    fn dictation(&self) -> Div {
        let shortcuts = kit::card()
            .overflow_hidden()
            .child(
                settings_row()
                    .child(row_text(
                        "Hold to dictate",
                        "Speak while holding, release to insert.",
                    ))
                    .child(kit::fn_key()),
            )
            .child(rule())
            .child(
                settings_row()
                    .child(row_text(
                        "Hands-free",
                        "Start, speak as long as you like, then press again to finish.",
                    ))
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(5.))
                            .child(kit::keycap("fn"))
                            .child(div().text_size(px(11.)).text_color(rgb(FAINT)).child("+"))
                            .child(kit::keycap("space")),
                    ),
            )
            .child(rule())
            .child(
                settings_row()
                    .child(row_text(
                        "Cancel",
                        "Stops recording or a pending transcription.",
                    ))
                    .child(kit::keycap("esc")),
            );
        let mut safety = div().flex().flex_col().gap(px(12.));
        for text in [
            "Inserts once, at your cursor, in the field where you started.",
            "Stops if the app, field, selection, or text changes before insertion.",
            "Never types into password fields, presses Return, or sends messages.",
            "If insertion fails, your words wait in Voco for you to copy.",
        ] {
            safety = safety.child(
                div()
                    .flex()
                    .items_start()
                    .gap(px(10.))
                    .child(icon("check", 14., SUCCESS).mt(px(2.)))
                    .child(
                        div()
                            .text_size(px(12.5))
                            .line_height(px(19.))
                            .text_color(rgb(TEXT_2))
                            .child(text),
                    ),
            );
        }
        div()
            .flex()
            .flex_col()
            .gap(px(28.))
            .child(group("Shortcuts", shortcuts))
            .child(group("Safe insertion", kit::card().p(px(18.)).child(safety)))
            .child(group(
                "Private by design",
                kit::card().child(
                    settings_row()
                        .items_start()
                        .child(kit::icon_well("lock", ORANGE, ORANGE_SOFT))
                        .child(row_text(
                            "Your voice never leaves this Mac",
                            "Recognition runs locally. Only model downloads use the internet. No account or API key. Audio stays in memory while processing, and recent transcripts disappear when you quit.",
                        )),
                ),
            ))
    }
}
