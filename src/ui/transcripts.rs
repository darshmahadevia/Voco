//! Transcripts: searchable recent dictations, kept in memory only.

use super::kit::{self, icon};
use super::*;

impl VocoApp {
    pub(super) fn transcript_count(&self, cx: &App) -> usize {
        let search = self.search.read(cx).value().to_lowercase();
        self.controller
            .history
            .iter()
            .filter(|row| row.text.to_lowercase().contains(&search))
            .count()
    }

    pub(super) fn transcripts_page(&self, window: &mut Window, cx: &mut Context<Self>) -> Div {
        let total = self.controller.history.len();
        let searching = !self.search.read(cx).value().is_empty();
        let matches = self.transcript_count(cx);
        div()
            .flex()
            .flex_col()
            .gap(px(24.))
            .child(
                div()
                    .flex()
                    .items_end()
                    .justify_between()
                    .gap(px(16.))
                    .child(kit::page_header(
                        "Transcripts",
                        "Recent dictations stay in memory until you quit. Nothing is written to disk.",
                    ))
                    .child(
                        kit::chip(
                            kit::plural(total as u64, "dictation", "dictations"),
                            TEXT_2,
                            0xffffff0f,
                        )
                        .mb(px(4.)),
                    ),
            )
            .child(
                div()
                    .flex()
                    .flex_col()
                    .gap(px(10.))
                    .child(
                        Input::new(&self.search)
                            .prefix(icon("search", 14., MUTED))
                            .cleanable(true)
                            .h(px(38.))
                            .rounded(px(10.))
                            .bg(rgb(RAISED)),
                    )
                    .when(searching, |column| {
                        column.child(kit::hint(format!(
                            "{} of {} match · Esc clears",
                            matches, total
                        )))
                    }),
            )
            .child(self.transcript_list(50, window, cx))
    }

    /// Recent transcripts as one grouped list, or a helpful empty state.
    pub(super) fn transcript_list(
        &self,
        limit: usize,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Div {
        let search = self.search.read(cx).value().to_lowercase();
        let filtering = self.page == Page::Transcripts;
        let rows = self
            .controller
            .history
            .iter()
            .filter(|row| !filtering || row.text.to_lowercase().contains(&search))
            .take(limit)
            .collect::<Vec<_>>();
        if rows.is_empty() {
            let (icon_name, title, detail) = if !self.controller.settings.keep_last_transcript {
                (
                    "lock",
                    "Recent words are off",
                    "Turn on Keep recent transcripts in Settings → Output to see dictations here.",
                )
            } else if filtering && !search.is_empty() {
                (
                    "search",
                    "No matches",
                    "Try a different word. Search covers every recent dictation.",
                )
            } else {
                (
                    "wave",
                    "Your next thought belongs here",
                    "Finished dictations appear here and stay until you quit Voco.",
                )
            };
            return kit::card().child(kit::empty_state(icon_name, title, detail));
        }
        let count = rows.len();
        let mut list = kit::card().overflow_hidden().flex().flex_col();
        for (index, row) in rows.into_iter().enumerate() {
            let text = row.text.clone();
            let key = SharedString::from(format!("copy-{index}"));
            let copied = self.copied(&key);
            list = list.child(
                div()
                    .flex()
                    .items_start()
                    .gap(px(16.))
                    .pl(px(20.))
                    .pr(px(12.))
                    .py(px(14.))
                    .when(index + 1 < count, |row| {
                        row.border_b_1().border_color(rgb(LINE))
                    })
                    .hover(|row| row.bg(rgb(0x181818)))
                    .child(
                        div()
                            .w(px(68.))
                            .flex_shrink_0()
                            .pt(px(4.))
                            .text_size(px(11.))
                            .text_color(rgb(MUTED))
                            .child(row.time.clone()),
                    )
                    .child(
                        div()
                            .flex_1()
                            .min_w_0()
                            .pt(px(2.))
                            .text_size(px(13.))
                            .line_height(px(22.))
                            .child(literal_text(
                                SharedString::from(format!("transcript-text-{index}")),
                                &row.text,
                                window,
                                cx,
                            )),
                    )
                    .child(self.icon_button(
                        key.clone(),
                        if copied { "check" } else { "copy" },
                        if copied { SUCCESS } else { MUTED },
                        if copied { "Copied" } else { "Copy" },
                        cx,
                        move |app, _, _| app.copy_from(Some(key.clone()), &text),
                    )),
            );
        }
        list
    }
}
