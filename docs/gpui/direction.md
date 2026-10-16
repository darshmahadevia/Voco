# GPUI dashboard direction

Voco is a daily dictation workspace for a Mac. Its dashboard should make the next action clear while keeping speech setup, recent words, and recovery within reach.

## Native implementation

Replace egui/eframe with GPUI. Keep the existing dictation controller, speech workers, model installer, and macOS integration. Use one root GPUI entity for navigation and controller ownership. Page and settings-tab enums identify the visible content. Give editable fields their own focused input state so Unicode selections and composition can be validated before practice insertion.

The dashboard keeps its tray menu and close-to-hide behavior. Closing a window must not stop dictation. Recovery and session status remain outside page scrolling. Model downloads, permissions, retention, output modes, search, and clipboard actions must operate on real application state.

## Composition

Use the existing black canvas, bundled Manrope, soft-white primary controls, and restrained orange voice details. Refine this identity with a composed sidebar, generous heading spacing, custom voice artwork, precise rules, and consistent control sizing.

The first viewport leads with the dictation task and Fn guidance. An orange voice sculpture occupies the adjacent space. It is decorative, separate from measured microphone activity. Real usage totals and recent transcripts follow. Setup has a visible next action when a model or permission is missing.

Settings retains four labeled panels. Transcript browsing retains search and complete text. Statistics uses stored usage totals rather than illustrative data. Empty, loading, unavailable, recovery, and error states belong to the same visual system.

## Alternatives considered

A permanent sidebar gives Home, Transcripts, Stats, and Settings stable locations. It also leaves room for setup and a persistent footer in the existing compact desktop footprint. This is the chosen structure.

A centered studio with top navigation could give a large Fn control more prominence. It consumes vertical space and would move history and setup into secondary drawers. Those costs do not suit the existing workflow.

## Verification

Build and inspect the real GPUI executable. Capture all four pages, settings panels, and a compact window. Verify practice selection replacement, changed-field refusal, search, clipboard feedback, and close/reopen behavior. Keep hardware permission and microphone limitations explicit.

The visual reference is [Vibrant Design](https://vibrant.design/), including its curated Maple Research ASCII posters. The reference informs composition and voice artwork rather than introducing a web renderer.
