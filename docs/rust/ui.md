# Rust dashboard

The Rust dashboard preserves Voco's existing dark palette, Manrope typography, orange voice accents, four navigation destinations, setup actions, and local transcript recovery. egui replaces the browser implementation. Native macOS menus provide navigation shortcuts.

The first viewport has a narrow sidebar and a task area. Home leads with Fn/Globe guidance, then model and permission setup or a practice field and recent transcripts. Settings has Output, Models, Access, and Dictation tabs. A persistent footer reports session status and errors. The recording panel is an AppKit nonactivating panel controlled from Rust.

The static `Resources/Fonts/Manrope-Regular.ttf` is a weight-400 instance of the previously bundled variable Manrope font, generated with FontTools. The variable font's default weight was 200, which egui rendered too lightly in the first screenshot. The original font license is retained.

Screenshots from the real executable are created by `voco --verify-ui DIRECTORY`. The native capture runs through egui's screenshot event. The verification record describes the tested pages and known limitations.
