//! Statistics: usage totals, recent daily activity, and the preferences
//! those totals depend on.

use super::home::{tile, tile_grid};
use super::kit;
use super::*;
use gpui_component::tooltip::Tooltip;

const CHART_DAYS: u64 = 14;
const CHART_HEIGHT: f32 = 132.;

impl VocoApp {
    pub(super) fn stats(&self, window: &mut Window, cx: &mut Context<Self>) -> Div {
        let compact = window.bounds().size.width < px(COMPACT_WIDTH);
        let settings = &self.controller.settings;
        let summary = settings.summary(chrono::Local::now().date_naive());
        let tiles = vec![
            tile(
                "Words dictated",
                kit::count(summary.words),
                kit::hint("All time").text_size(px(11.)),
            ),
            tile(
                "Time saved",
                kit::duration(summary.seconds_saved),
                kit::hint(format!("Versus typing at {} wpm", settings.typing_wpm))
                    .text_size(px(11.)),
            ),
            tile(
                "Sessions",
                kit::count(summary.sessions),
                kit::hint("Finished dictations").text_size(px(11.)),
            ),
            tile(
                "Best streak",
                kit::plural(summary.best_streak, "day", "days"),
                kit::hint(format!(
                    "Current {}",
                    kit::plural(summary.streak, "day", "days")
                ))
                .text_size(px(11.)),
            ),
        ];
        div()
            .flex()
            .flex_col()
            .gap(px(28.))
            .child(kit::page_header(
                "Statistics",
                "Usage totals stay on this Mac. Audio and transcript text never touch the disk.",
            ))
            .child(tile_grid(tiles, compact))
            .child(self.activity())
            .child(
                div()
                    .flex()
                    .flex_col()
                    .gap(px(10.))
                    .child(kit::section_title("Preferences"))
                    .child(
                        kit::card()
                            .overflow_hidden()
                            .child(self.stepper(
                                true,
                                "Daily word goal",
                                "Sets the target for Today and the line on the chart.",
                                format!("{} words", kit::count(u64::from(settings.daily_goal))),
                                settings.daily_goal <= 100,
                                settings.daily_goal >= 10_000,
                                cx,
                            ))
                            .child(div().h(px(1.)).bg(rgb(LINE)))
                            .child(self.stepper(
                                false,
                                "Your typing speed",
                                "Used to estimate the time dictation saves you.",
                                format!("{} wpm", settings.typing_wpm),
                                settings.typing_wpm <= 10,
                                settings.typing_wpm >= 200,
                                cx,
                            )),
                    ),
            )
    }

    /// Words per day for the last two weeks, with the daily goal marked.
    fn activity(&self) -> Div {
        let settings = &self.controller.settings;
        let today = chrono::Local::now().date_naive();
        let goal = u64::from(settings.daily_goal);
        let days: Vec<(chrono::NaiveDate, u64)> = (0..CHART_DAYS)
            .rev()
            .filter_map(|offset| today.checked_sub_days(chrono::Days::new(offset)))
            .map(|date| {
                let words = settings
                    .days
                    .get(&date.format("%Y-%m-%d").to_string())
                    .map_or(0, |day| day.words);
                (date, words)
            })
            .collect();
        let total: u64 = days.iter().map(|(_, words)| words).sum();
        let active = days.iter().filter(|(_, words)| *words > 0).count();
        let peak = days.iter().map(|(_, words)| *words).max().unwrap_or(0);
        // Leave headroom above the taller of the best day and the goal.
        let scale = (peak.max(goal) as f32 * 1.15).max(1.);
        let goal_offset = goal as f32 / scale * CHART_HEIGHT;

        let mut bars = div()
            .relative()
            .h(px(CHART_HEIGHT))
            .flex()
            .items_end()
            .gap(px(6.))
            .child(
                div()
                    .absolute()
                    .left_0()
                    .right_0()
                    .bottom(px(goal_offset))
                    .border_t_1()
                    .border_dashed()
                    .border_color(rgb(LINE_STRONG)),
            );
        for (index, (date, words)) in days.iter().copied().enumerate() {
            let is_today = date == today;
            let height = if words == 0 {
                3.
            } else {
                (words as f32 / scale * CHART_HEIGHT).max(6.)
            };
            let color = match (is_today, words) {
                (true, _) => ORANGE,
                (false, 0) => LINE_STRONG,
                (false, words) if words >= goal => 0x8a5034,
                _ => 0x4a4a4a,
            };
            let label = format!(
                "{} · {}",
                date.format("%a, %b %-d"),
                kit::plural(words, "word", "words")
            );
            bars = bars.child(
                div()
                    .id(("activity-day", index))
                    .flex_1()
                    .h_full()
                    .flex()
                    .items_end()
                    .tooltip(move |window, cx| Tooltip::new(label.clone()).build(window, cx))
                    .child(
                        div()
                            .w_full()
                            .h(px(height))
                            .rounded_t(px(4.))
                            .rounded_b(px(2.))
                            .bg(rgb(color)),
                    ),
            );
        }
        let mut labels = div().flex().gap(px(6.)).mt(px(8.));
        for (date, _) in &days {
            labels = labels.child(
                div()
                    .flex_1()
                    .text_center()
                    .text_size(px(10.))
                    .text_color(rgb(if *date == today { TEXT } else { FAINT }))
                    .child(if *date == today {
                        "Today".to_owned()
                    } else {
                        date.format("%a").to_string().chars().take(1).collect()
                    }),
            );
        }
        let legend = |color: u32, label: &'static str| {
            div()
                .flex()
                .items_center()
                .gap(px(6.))
                .text_size(px(11.))
                .text_color(rgb(MUTED))
                .child(div().size(px(8.)).rounded(px(2.)).bg(rgb(color)))
                .child(label)
        };
        kit::card()
            .p(px(20.))
            .flex()
            .flex_col()
            .gap(px(18.))
            .child(
                div()
                    .flex()
                    .items_start()
                    .justify_between()
                    .gap(px(16.))
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .gap(px(3.))
                            .child(
                                div()
                                    .text_size(px(15.))
                                    .font_weight(FontWeight::SEMIBOLD)
                                    .child("Last 14 days"),
                            )
                            .child(kit::hint(format!(
                                "{} across {}",
                                kit::plural(total, "word", "words"),
                                kit::plural(active as u64, "active day", "active days"),
                            ))),
                    )
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(14.))
                            .child(legend(ORANGE, "Today"))
                            .child(legend(0x8a5034, "Goal met"))
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .gap(px(6.))
                                    .text_size(px(11.))
                                    .text_color(rgb(MUTED))
                                    .child(
                                        div()
                                            .w(px(12.))
                                            .border_t_1()
                                            .border_dashed()
                                            .border_color(rgb(MUTED)),
                                    )
                                    .child(format!("Goal {}", kit::count(goal))),
                            ),
                    ),
            )
            .child(div().child(bars).child(labels))
    }

    #[allow(clippy::too_many_arguments)]
    fn stepper(
        &self,
        goal: bool,
        title: &'static str,
        detail: &'static str,
        value: String,
        at_minimum: bool,
        at_maximum: bool,
        cx: &mut Context<Self>,
    ) -> Div {
        let change = move |app: &mut Self, up: bool| {
            let settings = &mut app.controller.settings;
            if goal {
                settings.daily_goal = if up {
                    (settings.daily_goal + 100).min(10_000)
                } else {
                    settings.daily_goal.saturating_sub(100).max(100)
                };
            } else {
                settings.typing_wpm = if up {
                    (settings.typing_wpm + 10).min(200)
                } else {
                    settings.typing_wpm.saturating_sub(10).max(10)
                };
            }
            app.controller.save();
        };
        let prefix = if goal { "goal" } else { "speed" };
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
                            .text_size(px(13.))
                            .font_weight(FontWeight::MEDIUM)
                            .child(title),
                    )
                    .child(kit::hint(detail)),
            )
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap(px(2.))
                    .p(px(3.))
                    .rounded_full()
                    .bg(rgb(CONTROL))
                    .child(kit::unavailable(
                        self.icon_button(
                            SharedString::from(format!("{prefix}-minus")),
                            "minus",
                            TEXT,
                            "Decrease",
                            cx,
                            move |app, _, _| change(app, false),
                        )
                        .rounded(px(999.))
                        .w(px(28.))
                        .h(px(28.)),
                        at_minimum,
                    ))
                    .child(
                        div()
                            .w(px(104.))
                            .text_center()
                            .text_size(px(12.5))
                            .font_weight(FontWeight::MEDIUM)
                            .child(value),
                    )
                    .child(kit::unavailable(
                        self.icon_button(
                            SharedString::from(format!("{prefix}-plus")),
                            "plus",
                            TEXT,
                            "Increase",
                            cx,
                            move |app, _, _| change(app, true),
                        )
                        .rounded(px(999.))
                        .w(px(28.))
                        .h(px(28.)),
                        at_maximum,
                    )),
            )
    }
}
