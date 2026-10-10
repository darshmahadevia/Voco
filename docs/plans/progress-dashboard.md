# Voco progress dashboard

Extend Home in the existing black, orange, Manrope and Pixelify Sans design. Keep readiness and Fn / Globe guidance visible above progress.

- Show total words, estimated typing time saved, and current / best streak.
- A compact month calendar highlights completed dictation days. Previous months and individual day details are available.
- A daily goal defaults to 500 words and can be changed. A successful, nonempty dictation qualifies for a streak independently of the goal.
- Unlock badges for a first dictation, 1,000 and 10,000 words, a seven-day best streak, and an hour saved. Celebrate goal completion subtly with reduced-motion support.
- Save only daily word counts, elapsed dictation time, session counts and goal preferences locally. Do not save audio or transcript content. Track at native completion, including when Home is closed or transcript retention is off.
- Explain time saved as words / configurable typing WPM minus elapsed dictation and processing time, clamped to zero. Default 40 WPM is a configurable estimate, not a measured typing speed.

States: honest zero-state; illustrative browser preview labeled as sample data; future calendar days disabled; interrupted / empty / failed sessions excluded; month and day changes work with local dates and DST; goal changes and restart persistence verified.

Later ideas: weekly challenges, personal-best days, optional XP and levels.

## Implemented behavior and validation

Home keeps readiness and Fn / Globe guidance above the new progress view. The desktop and mobile captures at `.impeccable/review/desktop.png` and `.impeccable/review/mobile.png` show the extension using the incumbent black surfaces, orange activity accents, Manrope and Pixelify Sans heading treatment, fine dividers, and restrained rounded panels. At narrow widths, the activity calendar and daily goal stack while the summary remains readable.

The dashboard shows lifetime words, estimated typing time saved, current and best streaks, a month calendar with selectable past days, a configurable daily goal, and five milestones: first dictation, 1,000 words, 10,000 words, a seven-day best streak, and an estimated hour saved. The goal defaults to 500 words; the typing estimate defaults to 40 WPM. A completed dictation qualifies for a streak without meeting the word goal. Browser preview progress is sample data, labeled as such; preference edits in preview stay in the preview.

`NativeCoordinator.completeDictation` records usage after successful text insertion. `UsageStats.record` excludes sessions with no countable words or invalid elapsed time; failed, interrupted, and recovery sessions do not reach that recording path. The completion date comes from `Date()` and `Calendar.current` when native completion records the session, so it follows the Mac's local calendar. Elapsed time runs from dictation start through completion, including processing and insertion. Estimated typing time is `words ÷ typing WPM × 60`; saved time subtracts elapsed session seconds and is clamped to zero.

Only per-day word totals, elapsed seconds, session counts, the daily goal, and typing WPM are persisted locally in `UserDefaults` under `usageStats.v1`. Audio and transcript text are not part of that record. Usage starts with the new stats store; it does not reconstruct earlier days from any retained transcript. Native recording is independent of whether Home is open and still works when latest-transcript retention is off.

Validation passed: `npm run typecheck`; `npm test` (14 tests); `npm run build:native`; `npx electron-vite build`; `npm run verify:renderer`; `bash scripts/check-deferred-dictation.sh` (all three model fixtures, including its usage assertions); `bash scripts/check-audio-callback.sh`; and the `UsageStatsSmoke` compile and run using `swiftc native/Sources/UsageStats.swift native/Tests/UsageStatsSmoke.swift -o /tmp/voco-usage-stats-smoke` followed by `/tmp/voco-usage-stats-smoke`.

Home header refinement: show `Welcome, {userName}` using the Mac account name, followed by `Hold Fn / Globe to speak. Release to paste.` Remove the Home voice mark and marketing headline. Show operational status only when setup, loading, capture, or recovery needs attention. Browser preview uses a sample name.
