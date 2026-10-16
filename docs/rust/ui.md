# Native dashboard

GPUI renders Voco's dashboard and floating voice pill. The interface uses Metal, the bundled Manrope font, a black canvas, graphite controls, soft-white primary buttons, and orange voice details. Native GPUI input components handle editing, selection, and composition.

A fixed sidebar gives Home, Transcripts, Statistics, and Settings stable locations. Home pairs shortcut guidance with an orange ASCII ribbon, followed by real usage totals, a practice field, and recent words. Missing setup has a direct action to the relevant settings panel. Settings retains Output, Models, Access, and Dictation tabs. Transcripts has search, complete text, and exact clipboard copying.

The live footer and recovery panel sit outside page scrolling. The floating voice pill uses measured audio levels during capture and a separate progress indicator during transcription. Its macOS panel cannot become key or main and ignores pointer input. Page arrivals and the progress indicator respect macOS Reduce Motion.

`voco --verify-ui DIRECTORY` captures the real native windows and exercises practice selection replacement and dashboard lifecycle. The [GPUI verification record](../gpui/verification.md) records the current results and limits. Earlier egui results remain historical evidence in the [Rust migration record](verification.md).

The [direction brief](../gpui/direction.md) explains the composition and alternatives. The [design system](../../DESIGN.md) owns shared colors, typography, and visual constraints.
