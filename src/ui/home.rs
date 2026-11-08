//! Home: setup, shortcut guidance, today's progress, practice, and recent words.

use super::kit::{self, icon};
use super::*;
use chrono::Timelike;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Step {
    Done,
    Current,
    Upcoming,
}

fn greeting() -> &'static str {
    match chrono::Local::now().hour() {
        5..=11 => "Good morning",
        12..=16 => "Good afternoon",
        17..=21 => "Good evening",
        _ => "Hello, night owl",
    }
}

pub(super) fn model_size(id: ModelId) -> &'static str {
    match id {
        ModelId::Moonshine => "257 MB",
        ModelId::Parakeet => "661 MB",
        ModelId::Whisper => "1.6 GB",
    }
}

fn step_marker(state: Step, number: usize) -> Div {
    let marker = div()
        .size(px(24.))
        .flex_shrink_0()
        .flex()
        .items_center()
        .justify_center()
        .rounded_full()
        .text_size(px(11.))
        .font_weight(FontWeight::SEMIBOLD);
    match state {
        Step::Done => marker
            .bg(rgba(SUCCESS_SOFT))
            .child(icon("check", 13., SUCCESS)),
        Step::Current => marker
            .border_1()
            .border_color(rgb(ORANGE))
            .text_color(rgb(ORANGE))
            .child(number.to_string()),
        Step::Upcoming => marker
            .border_1()
            .border_color(rgb(LINE_STRONG))
            .text_color(rgb(MUTED))
            .child(number.to_string()),
    }
}

/// The static voice sculpture beside the shortcut guidance. It is decoration
/// and never reflects microphone activity.
fn artwork() -> Div {
    let mut sculpture = div()
        .w(px(234.))
        .h(px(150.))
        .flex_shrink_0()
        .flex()
        .flex_col()
        .justify_center()
        .overflow_hidden()
        .font_family("Menlo")
        .text_size(px(7.))
        .line_height(px(6.));
    for row in 0..24 {
        let mut line = String::new();
        for col in 0..48 {
            let x = col as f32 / 47.;
            let y = row as f32;
            let center = 12. + (x * 6.8 - 1.2).sin() * 6.;
            let width = 2. + (x * std::f32::consts::PI).sin() * 4.;
            let delta = (y - center).abs();
            let glyph = if delta < width {
                if (col + row) % 5 == 0 {
                    ':'
                } else if delta > width - 1.5 {
                    '.'
                } else {
                    '+'
                }
            } else {
                ' '
            };
            line.push(glyph);
        }
        sculpture = sculpture.child(
            div()
                .text_color(rgb(if row < 12 { ORANGE } else { ORANGE_DEEP }))
                .whitespace_nowrap()
                .child(line),
        );
    }
    sculpture
}

/// A metric with its label above and optional supporting detail below.
pub(super) fn tile(label: &str, value: String, detail: impl IntoElement) -> Div {
    kit::card()
        .flex_1()
        .min_w_0()
        .p(px(16.))
        .flex()
        .flex_col()
        .gap(px(6.))
        .child(
            div()
                .text_size(px(12.))
                .text_color(rgb(MUTED))
                .child(label.to_owned()),
        )
        .child(
            div()
                .text_size(px(24.))
                .line_height(px(30.))
                .font_weight(FontWeight::SEMIBOLD)
                .truncate()
                .child(value),
        )
        .child(detail)
}

/// Lays tiles out in one row, or two rows of two in a compact window.
pub(super) fn tile_grid(tiles: Vec<Div>, compact: bool) -> Div {
    let gap = px(12.);
    if !compact {
        return div().flex().gap(gap).children(tiles);
    }
    let mut grid = div().flex().flex_col().gap(gap);
    let mut tiles = tiles.into_iter();
    loop {
        let row: Vec<Div> = tiles.by_ref().take(2).collect();
        if row.is_empty() {
            break;
        }
        grid = grid.child(div().flex().gap(gap).children(row));
    }
    grid
}

impl VocoApp {
    pub(super) fn today_words(&self) -> u64 {
        let today = chrono::Local::now().format("%Y-%m-%d").to_string();
        self.controller
            .settings
            .days
            .get(&today)
            .map_or(0, |day| day.words)
    }

    pub(super) fn home(&self, window: &mut Window, cx: &mut Context<Self>) -> Div {
        let compact = window.bounds().size.width < px(COMPACT_WIDTH);
        let ready = self.controller.ready();
        let mut page = div().flex().flex_col().gap(px(28.)).child(kit::page_header(
            greeting(),
            if ready {
                "Hold fn in any app and say what you mean. Voco writes it at your cursor."
            } else {
                "A few quick steps and your voice can write anywhere on this Mac."
            },
        ));
        if !ready {
            page = page.child(self.setup(cx));
        }
        page.child(self.guidance(compact))
            .child(self.overview(compact))
            .child(
                div()
                    .flex()
                    .flex_col()
                    .gap(px(10.))
                    .child(
                        kit::section_title("Practice").child(
                            div()
                                .flex()
                                .items_center()
                                .gap(px(6.))
                                .child(kit::hint("Click inside, then hold"))
                                .child(kit::fn_key().h(px(20.))),
                        ),
                    )
                    .child(
                        Input::new(&self.practice)
                            .h(px(96.))
                            .rounded(px(12.))
                            .bg(rgb(RAISED)),
                    ),
            )
            .child(
                div()
                    .flex()
                    .flex_col()
                    .gap(px(10.))
                    .child(
                        kit::section_title("Recent").child(
                            self.button_with_icon(
                                "all-transcripts",
                                None,
                                "View all",
                                Tone::Ghost,
                                cx,
                                |app, _, _| app.page = Page::Transcripts,
                            )
                            .h(px(28.))
                            .child(icon("arrow-right", 13., TEXT_2)),
                        ),
                    )
                    .child(self.transcript_list(3, window, cx)),
            )
    }

    /// A live checklist that turns each missing requirement into one action.
    fn setup(&self, cx: &mut Context<Self>) -> Div {
        let controller = &self.controller;
        let model = controller.settings.selected_model;
        let done = [
            matches!(controller.engine, EngineStatus::Ready),
            controller.permissions.microphone,
            controller.permissions.accessibility && controller.shortcut_running,
        ];
        let completed = done.iter().filter(|done| **done).count();
        let current = done.iter().position(|done| !done);
        let state = |index: usize| {
            if done[index] {
                Step::Done
            } else if current == Some(index) {
                Step::Current
            } else {
                Step::Upcoming
            }
        };
        let tone = |index: usize| {
            if current == Some(index) {
                Tone::Primary
            } else {
                Tone::Secondary
            }
        };
        let busy = controller.session.active() || controller.download.is_some();

        // Step 1: the speech model.
        let download = controller.download.as_ref().filter(|d| d.id == model);
        let (model_detail, model_color): (String, u32) = match (&controller.engine, download) {
            (_, Some(download)) => (
                format!(
                    "Downloading {} · {:.0}% · {}",
                    model.label(),
                    download.progress * 100.,
                    download.file
                ),
                ORANGE,
            ),
            (EngineStatus::Ready, _) => {
                (format!("{} is installed and ready.", model.label()), MUTED)
            }
            (EngineStatus::Loading, _) => (format!("Loading {}…", model.label()), MUTED),
            (EngineStatus::Error(message), _) => (message.clone(), DANGER),
            (EngineStatus::Missing, _) => (
                format!(
                    "{} is {}. Recognition runs offline once it is downloaded.",
                    model.label(),
                    model_size(model)
                ),
                MUTED,
            ),
        };
        let model_action = match (&controller.engine, download) {
            (_, Some(_)) => Some(
                self.button(
                    "setup-cancel-download",
                    "Cancel",
                    Tone::Secondary,
                    cx,
                    |app, _, _| app.controller.cancel_download(),
                )
                .into_any_element(),
            ),
            (EngineStatus::Missing, _) => Some(
                div()
                    .flex()
                    .gap(px(6.))
                    .child(
                        self.button("setup-compare", "Compare", Tone::Ghost, cx, |app, _, _| {
                            app.page = Page::Settings;
                            app.tab = SettingsTab::Models;
                        }),
                    )
                    .child(kit::unavailable(
                        self.button_with_icon(
                            "setup-download",
                            Some("download"),
                            "Download",
                            tone(0),
                            cx,
                            move |app, _, _| {
                                if !app.controller.session.active()
                                    && app.controller.download.is_none()
                                {
                                    app.controller.download_model(model);
                                }
                            },
                        ),
                        busy,
                    ))
                    .into_any_element(),
            ),
            (EngineStatus::Error(_), _) => Some(
                self.button("setup-review-model", "Review", tone(0), cx, |app, _, _| {
                    app.page = Page::Settings;
                    app.tab = SettingsTab::Models;
                })
                .into_any_element(),
            ),
            _ => None,
        };

        // Step 3: Accessibility, which also starts the fn shortcut.
        let shortcut_failed = controller.permissions.accessibility && !controller.shortcut_running;
        let steps = [
            (
                "Download a speech model",
                model_detail,
                model_color,
                model_action,
                download.map(|d| d.progress),
            ),
            (
                "Allow the microphone",
                "Voco listens only while you hold fn or run hands-free dictation.".into(),
                MUTED,
                (!done[1]).then(|| {
                    self.button("setup-microphone", "Allow", tone(1), cx, |app, _, _| {
                        app.result(platform::request_microphone())
                    })
                    .into_any_element()
                }),
                None,
            ),
            (
                "Allow Accessibility",
                if shortcut_failed {
                    "Access is on, but the fn shortcut did not start. Quit and reopen Voco.".into()
                } else {
                    "Lets Voco notice fn and type your words at the cursor.".into()
                },
                if shortcut_failed { DANGER } else { MUTED },
                (!controller.permissions.accessibility).then(|| {
                    self.button("setup-accessibility", "Allow", tone(2), cx, |app, _, _| {
                        app.result(platform::request_accessibility())
                    })
                    .into_any_element()
                }),
                None,
            ),
        ];

        let mut progress = div().flex().gap(px(4.));
        for finished in done {
            progress = progress.child(
                div()
                    .w(px(22.))
                    .h(px(4.))
                    .rounded_full()
                    .bg(rgb(if finished { SUCCESS } else { LINE_STRONG })),
            );
        }
        let mut list = div().flex().flex_col();
        for (index, (title, detail, color, action, fraction)) in steps.into_iter().enumerate() {
            let state = state(index);
            list = list.child(
                div()
                    .flex()
                    .items_center()
                    .gap(px(14.))
                    .px(px(20.))
                    .py(px(14.))
                    .border_t_1()
                    .border_color(rgb(LINE))
                    .child(step_marker(state, index + 1))
                    .child(
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
                                    .text_color(rgb(if state == Step::Done { MUTED } else { TEXT }))
                                    .child(title),
                            )
                            .child(
                                div()
                                    .text_size(px(12.))
                                    .line_height(px(18.))
                                    .text_color(rgb(color))
                                    .child(detail),
                            )
                            .when_some(fraction, |column, fraction| {
                                column.child(div().mt(px(6.)).child(kit::meter(fraction, ORANGE)))
                            }),
                    )
                    .children(action),
            );
        }
        kit::card()
            .overflow_hidden()
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_between()
                    .gap(px(16.))
                    .px(px(20.))
                    .py(px(16.))
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .gap(px(3.))
                            .child(
                                div()
                                    .text_size(px(15.))
                                    .font_weight(FontWeight::SEMIBOLD)
                                    .child("Finish setting up"),
                            )
                            .child(kit::hint(
                                "No account and no cloud. Everything stays on this Mac.",
                            )),
                    )
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .items_end()
                            .gap(px(6.))
                            .child(
                                div()
                                    .text_size(px(11.))
                                    .text_color(rgb(MUTED))
                                    .child(format!("{completed} of 3 done")),
                            )
                            .child(progress),
                    ),
            )
            .child(list)
    }

    /// Shortcut guidance paired with the brand's voice sculpture.
    fn guidance(&self, compact: bool) -> Div {
        kit::card()
            .overflow_hidden()
            .bg(linear_gradient(
                90.,
                linear_color_stop(rgb(RAISED), 0.45),
                linear_color_stop(rgb(0x1b120c), 1.),
            ))
            .flex()
            .items_center()
            .justify_between()
            .gap(px(24.))
            .px(px(24.))
            .py(px(22.))
            .child(
                div()
                    .flex()
                    .flex_col()
                    .gap(px(16.))
                    .min_w_0()
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .gap(px(6.))
                            .child(
                                div()
                                    .text_size(px(20.))
                                    .line_height(px(26.))
                                    .font_weight(FontWeight::SEMIBOLD)
                                    .child("Hold fn. Speak. Release."),
                            )
                            .child(kit::hint(
                                "Your words land at the cursor, in the app you are already using.",
                            )),
                    )
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .gap(px(10.))
                            .child(kit::shortcut(
                                vec![kit::fn_key()],
                                "Hold to dictate, release to insert",
                            ))
                            .child(kit::shortcut(
                                vec![kit::keycap("fn"), kit::keycap("space")],
                                "Hands-free for longer thoughts",
                            ))
                            .child(kit::shortcut(
                                vec![kit::keycap("esc")],
                                "Cancel at any time",
                            )),
                    ),
            )
            .when(!compact, |card| card.child(artwork()))
    }

    fn overview(&self, compact: bool) -> Div {
        let settings = &self.controller.settings;
        let summary = settings.summary(chrono::Local::now().date_naive());
        let today = self.today_words();
        let goal = u64::from(settings.daily_goal);
        let reached = today >= goal;
        let tiles = vec![
            tile(
                "Today",
                kit::count(today),
                div()
                    .flex()
                    .flex_col()
                    .gap(px(7.))
                    .mt(px(2.))
                    .child(kit::meter(
                        today as f32 / goal.max(1) as f32,
                        if reached { SUCCESS } else { ORANGE },
                    ))
                    .child(
                        div()
                            .text_size(px(11.))
                            .text_color(rgb(if reached { SUCCESS } else { MUTED }))
                            .child(if reached {
                                "Daily goal reached".to_owned()
                            } else {
                                format!("of {} word goal", kit::count(goal))
                            }),
                    ),
            ),
            tile(
                "Words dictated",
                kit::count(summary.words),
                kit::hint(kit::plural(summary.sessions, "session", "sessions")).text_size(px(11.)),
            ),
            tile(
                "Time saved",
                kit::duration(summary.seconds_saved),
                kit::hint(format!("Versus typing at {} wpm", settings.typing_wpm))
                    .text_size(px(11.)),
            ),
            tile(
                "Streak",
                kit::plural(summary.streak, "day", "days"),
                kit::hint(format!(
                    "Best {}",
                    kit::plural(summary.best_streak, "day", "days")
                ))
                .text_size(px(11.)),
            ),
        ];
        tile_grid(tiles, compact)
    }
}
