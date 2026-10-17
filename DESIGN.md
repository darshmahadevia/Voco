---
name: Voco
description: A quiet local voice workspace for your Mac.
colors:
  surface: "#0A0A0A"
  sidebar: "#0A0A0A"
  surface-raised: "#141414"
  surface-muted: "#202020"
  accent: "#FF742F"
  accent-strong: "#ffb58f"
  accent-soft: "#38251d"
  text-primary: "#f2f0ec"
  text-secondary: "#b9b8b5"
  text-tertiary: "#929497"
  button-text: "#1c1d1f"
  line: "#282828"
  line-strong: "#414141"
  control-hover: "#2b2b2b"
  success: "#b9cbbd"
  danger: "#ff9d9d"
  text-selection: "#803c1b"
typography:
  headline:
    fontFamily: "Manrope"
    fontSize: "34px"
    fontWeight: 500
  title:
    fontFamily: "Manrope"
    fontSize: "23px"
    fontWeight: 400
  body:
    fontFamily: "Manrope"
    fontSize: "13px"
    fontWeight: 400
  supporting:
    fontFamily: "Manrope"
    fontSize: "12px"
    fontWeight: 400
  label:
    fontFamily: "Manrope"
    fontSize: "12px"
    fontWeight: 500
  wordmark:
    fontFamily: "Manrope"
    fontSize: "31px"
    fontWeight: 600
rounded:
  key: "7px"
  field: "12px"
  navigation: "10px"
  pill: "999px"
spacing:
  sidebar: "174px"
  gutter: "36px"
  page-top: "34px"
  page-bottom: "30px"
  footer-gutter: "32px"
  tab-gap: "24px"
components:
  button-primary:
    backgroundColor: "{colors.text-primary}"
    textColor: "{colors.surface}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "0 15px"
    height: "34px"
  voice-workspace:
    backgroundColor: "{colors.surface}"
    rounded: "0px"
    padding: "18px 0"
  practice-field:
    backgroundColor: "{colors.surface-raised}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.field}"
    height: "86px"
---

# Design System: Voco

## Overview

Voco's established direction is "Quiet Voice Workspace". Its native Rust GPUI dashboard uses a black canvas, soft-white primary actions, bundled Manrope, and restrained orange voice details. Fine rules separate content without large cards.

The composition draws on [Vibrant Design](https://vibrant.design/) and its Maple Research ASCII posters. Home combines dictation guidance with a static orange glyph sculpture. Status and recovery stay visible below the scrolling page.

## Colors

### Primary

Orange `#FF742F` identifies voice feedback, download progress, the wordmark dot, the selected Settings tab, and small emphasis. Soft white `text-primary` fills primary actions, with the black canvas color for labels.

### Neutral

`surface` and `sidebar` share `#0A0A0A`, including the live footer and Home guidance. Graphite is reserved for small controls, selected navigation, and fields. Practice and search fields use `surface-raised`. Fine `line` dividers separate flat content.

Native supporting text and placeholders use `text-tertiary` at `#929497`. Sage `success` signals readiness in the footer. Soft red `danger` identifies errors. Status text accompanies semantic color.

The palette retains the brand's secondary, selection, and semantic tokens. Their presence does not require every token to appear on every page.

## Typography

The app bundles Manrope Regular, Medium, and SemiBold at weights 400, 500, and 600. Manrope supplies headings, labels, keyboard hints, transcript text, and the floating pill. Menlo appears only in the decorative ASCII artwork.

Page headings use 34px Medium. Settings panel introductions use 23px, model and permission titles use 19px, and Home guidance uses 22px. Body text is 13px, buttons and supporting copy are usually 12px, and small metadata is 10–11px. Usage totals use 28px. Transcript text uses native literal input rendering, with no Markdown interpretation.

## Layout

The dashboard opens at 1080 × 800px and has an 820 × 640px minimum. A permanent 174px sidebar holds Home, Transcripts, and Statistics, with Settings anchored at the bottom. Navigation retains its labels at compact sizes.

The main page scrolls independently with 36px horizontal gutters, 34px top spacing, and 30px bottom spacing. The footer sits outside that scroll area with 32px horizontal and 16px vertical padding. Below 960px window width, Home hides its decorative artwork and preserves the dictation guidance. Other content keeps the same sidebar and gutters.

Home starts with a page heading and description. A ruled guidance row pairs Fn and Globe instructions with the artwork. Three flat usage totals follow, then a setup action when a model or permission is missing, an 86px practice field, and up to three recent transcripts.

Transcripts provides a native search field, a Clear button, the filtered count, and up to 50 complete transcript rows. Each row has a 64px time column, selectable literal text, and Copy. Empty messages distinguish disabled retention, an unmatched search, and a new session.

Statistics shows real usage totals, session count, best streak, and controls for daily word goal and typing speed. Settings shows one of four labeled panels at a time. Setup actions live in Home and Settings rather than a separate onboarding rail.

## Elevation & Depth

The dashboard stays flat. A fine sidebar border, section rules, and vertical metric separators establish structure. Graphite marks selected navigation and fields. Recovery uses a warm dark panel above the footer. The floating pill uses a `#191919` fill and a faint white border, without a native window shadow.

## Shapes

Voco's brand mark is a continuous voice wave with a cursive v at its center. A short entry wave flows into the deep v and rises into a smaller trailing wave. Use the single smooth orange stroke in `Resources/Brand/voco-mark.svg`, with rounded terminals and continuous curves. Keep it static, preserve its proportions, and leave the viewBox's clear space intact. The wordmark remains Manrope with its orange dot. The Dock icon places the mark on a graphite tile; the menu bar uses a monochrome template. The master SVG and prebuilt PNG and ICNS assets live in `Resources`. Asset regeneration is separate from the Rust application build.

Actions, search, and the floating pill are fully rounded. Navigation uses 10px corners. Practice and recovery panels use 12px corners. The Home guidance stays flat. The Fn key uses 7px corners and a doubled lower border. Settings tabs use straight orange underlines.

## Components

### Controls and navigation

Shared action buttons are 34px high with 15px horizontal padding and 12px labels. Primary actions use soft white. Other actions use native GPUI component styling. The theme provides an orange focus ring. Sidebar rows are 40px high with 17px outline icons and immediate tonal selection.

Practice and search use focused native input state for selection, Unicode editing, and composition. Transcript and recovery words use selectable, noneditable native inputs. Preserve literal punctuation, code, and line breaks. Copy feedback appears in the footer after clipboard success. Search clears with Escape while focused; Clear also returns focus to the field.

### Voice guidance and live status

Home's 234 × 150px ASCII sculpture is static decoration, independent of microphone activity. The persistent footer shows controller status, readiness color, notices, and local-processing or copy feedback. During capture and pending transcription it offers Cancel with an Escape hint.

Recovery adds a warm panel above status on every page. It shows the saved words in a bounded scrolling area, the error explanation, Copy your words when text exists, and Dismiss. Recovery stays reachable while the page scrolls. Failed insertion words remain available even when recent transcript retention is off.

The floating indicator is a persistent native nonactivating, mouse-transparent window at the bottom center of the current screen. It preserves the editor's focus and floats above ordinary windows while staying out of native fullscreen Spaces and Split View tiles. When idle, it shows a 7px dot and a 48 × 7px line with translucent dark fills and faint white outlines. The same shapes expand over 220ms into the active indicator and collapse when dictation ends. Reversing activity mid-transition preserves the current geometry. Settled idle requests no animation frames. Reduce Motion snaps directly between states.

The active indicator pairs a 38px black voice circle with a separate 122 × 36px black status capsule, spaced 7px apart. Both use a faint outline. The 12px Manrope label is centered within the status capsule. Five narrow orange waveform bars show recent measured microphone energy while Listening, with stronger response to quiet speech and smooth attack and release. Silence returns the bars to their baseline. Starting and Transcribing use a rotating orange arc inside the circle. Other states use still baseline bars. Status changes retain the same footprint. No partial transcript appears during capture.

### Settings

Output, Models, Access, and Dictation are labeled tabs with one visible panel. The selected tab persists while navigating within the current window session. Arrow keys cycle tabs; Home and End select the first and last. Selection changes the orange underline immediately.

Output uses three separate pill buttons for Fast, Balanced, and Accurate, with a soft-white selected action and a description below. Output choices are disabled during dictation with a visible explanation. Accurate explains that it adds punctuation and capitalization with Apple's on-device FoundationModels and keeps Balanced cleanup if unavailable. Keep recent words uses an On or Off button. Turning retention off clears recent text immediately.

Models shows a name, version, language, size, and one action per row. Download progress uses a thin orange bar. Preserve loading, cancellation, retry, fresh-download, and idle-only model changes. Access shows microphone and keyboard permission actions, Fn and Globe troubleshooting, Reveal Voco, and Check again. Dictation explains the shortcuts, safe insertion, and local processing.

Statistics uses minus and plus buttons for preferences. Daily word goal changes in steps of 100 within 100–10,000 words. Typing speed changes in steps of 10 within 10–200 words per minute. Settings apply immediately.

### Motion and accessibility

Page and Settings-tab arrival use a 160ms GPUI animation with quintic ease-out. Opacity resolves from 0.75 to 1 while the top offset reduces from 4px to zero. Navigation and commands take effect immediately. Respect the macOS reduced-motion setting by showing page content immediately and keeping the processing arc still. Measured waveform feedback continues to reflect actual microphone energy.

Preserve keyboard access, native text selection and composition, visible focus, clear status labels, and complete recovery text. Keep decorative artwork separate from status feedback.

## Do's and Don'ts

- Do keep orange concentrated in voice activity and small details.
- Do preserve the black canvas, labeled sidebar, and persistent status and recovery area.
- Do use native literal inputs for practice, search, transcripts, and recovery words.
- Do preserve optional recent transcripts in memory until quit. Disabling retention clears them.
- Don't add pixel or serif accent fonts, orange primary buttons, neon grids, or large glows.
- Don't animate synthetic microphone activity or reveal partial transcript text during capture.
- Don't add persistent audio or transcript storage.
- Don't describe browser CSS controls, spring transitions, or disclosures as native GPUI behavior.
