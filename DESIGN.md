---
name: Voco
description: A quiet local voice workspace for your Mac.
colors:
  canvas: "#0A0A0A"
  panel: "#0F0F0F"
  raised: "#151515"
  control: "#1E1E1E"
  control-hover: "#262626"
  line: "#202020"
  line-strong: "#2E2E2E"
  accent: "#FF742F"
  accent-deep: "#C95524"
  accent-soft: "rgba(255, 116, 47, 0.12)"
  text-primary: "#F2F0EC"
  text-secondary: "#B9B8B5"
  text-tertiary: "#929497"
  text-faint: "#5F6164"
  button-text: "#0A0A0A"
  success: "#9FD1AD"
  danger: "#FF9D9D"
  text-selection: "#803C1B"
typography:
  page-title:
    fontFamily: "Manrope"
    fontSize: "26px"
    fontWeight: 600
  feature-title:
    fontFamily: "Manrope"
    fontSize: "20px"
    fontWeight: 600
  metric:
    fontFamily: "Manrope"
    fontSize: "24px"
    fontWeight: 600
  card-title:
    fontFamily: "Manrope"
    fontSize: "15px"
    fontWeight: 600
  section:
    fontFamily: "Manrope"
    fontSize: "13px"
    fontWeight: 600
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
    fontSize: "12.5px"
    fontWeight: 500
rounded:
  key: "6px"
  navigation: "8px"
  tab: "7px"
  field: "10px"
  panel: "12px"
  card: "14px"
  pill: "999px"
spacing:
  sidebar: "208px"
  panel-inset: "8px"
  gutter: "36px"
  page-top: "34px"
  page-bottom: "40px"
  content-max: "880px"
  section-gap: "28px"
  tile-gap: "12px"
components:
  button-primary:
    backgroundColor: "{colors.text-primary}"
    textColor: "{colors.button-text}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "0 14px"
    height: "32px"
  button-secondary:
    backgroundColor: "{colors.control}"
    textColor: "{colors.text-primary}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "0 14px"
    height: "32px"
  card:
    backgroundColor: "{colors.raised}"
    rounded: "{rounded.card}"
  practice-field:
    backgroundColor: "{colors.raised}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.panel}"
    height: "96px"
---

# Design System: Voco

## Overview

Voco's direction is "Quiet Voice Workspace". The native Rust GPUI dashboard pairs a black window canvas with an inset graphite content panel, bundled Manrope, soft-white primary actions, and restrained orange voice details. Related content groups into raised cards with hairline borders. The window stays calm until something needs the user, and then it names the one next action.

The composition draws on [Vibrant Design](https://vibrant.design/) and its Maple Research ASCII posters. Home pairs keycap shortcut guidance with a static orange glyph sculpture. Status and recovery stay visible below the scrolling page.

## Colors

### Surfaces

Four steps build depth without shadows. `canvas` fills the window and sidebar. `panel` fills the inset content area. `raised` fills cards, fields, and the segmented control. `control` fills secondary buttons, keycaps, and the selected sidebar row; `control-hover` marks hover and the selected tab. `line` separates content inside cards and the panel; `line-strong` outlines fields, empty meters, and upcoming setup steps.

### Accent

Orange `#FF742F` identifies voice and attention: the brand mark, the selected sidebar icon, the current setup step, download progress, today's chart bar, the selected output card, the toggle's on state, the live status halo, and the focus ring. `accent-soft` tints wells and the selected output card. Soft white, never orange, fills primary buttons.

### Text and semantics

`text-primary` carries titles and values. `text-secondary` carries descriptions that read as content. `text-tertiary` (`#929497`, at least 4.5:1 on every surface) carries supporting copy and placeholders. `text-faint` is reserved for decorative hints such as sidebar shortcuts and chart day initials, which never carry information alone.

Sage `success` marks readiness, completed setup steps, granted permissions, and copy confirmation. Soft red `danger` marks errors. Semantic color always accompanies text or an icon.

## Typography

The app bundles Manrope Regular, Medium, and SemiBold at weights 400, 500, and 600. Menlo appears only in the decorative ASCII artwork.

Page titles use 26px SemiBold with a 13px tertiary description. Home's shortcut card title uses 20px. Metrics use 24px SemiBold. Card titles use 15px SemiBold, section titles 13px SemiBold, row titles 13px Medium. Body text is 13px, supporting copy 12px, buttons 12.5px Medium, and metadata 10–11px. Transcript text uses native literal input rendering, with no Markdown interpretation.

## Layout

The dashboard opens at 1080 × 800px and has an 820 × 640px minimum. A 208px sidebar sits on the canvas. The content panel is inset 8px from the top, right, and bottom edges, with 12px corners and a hairline border.

The sidebar's top 86px is a window drag region below the traffic lights and holds the voice mark with the `voco` wordmark. Home, Transcripts, and Statistics follow, each with its ⌘ shortcut; Transcripts shows its count instead while it holds dictations. The speech-model card and Settings anchor the bottom.

Inside the panel, the page scrolls independently. Content is capped at 880px and centered, with 36px gutters, 34px top spacing, 40px bottom spacing, and 28px between sections. The status bar sits outside the scroll area at the bottom of the panel. Below 960px window width, Home hides its artwork and metric tiles fall into two rows of two.

## Elevation & Depth

The dashboard uses tonal layering, not shadows: canvas, panel, raised card, control. Hairlines define edges. Home's shortcut card adds a subtle horizontal gradient from `raised` to a warm graphite behind the sculpture. Recovery uses an opaque warm panel with an orange hairline. The floating pill uses black fills and a faint outline, without a native window shadow.

## Shapes

Voco's brand mark is a continuous voice wave with a cursive v at its center. A short entry wave flows into the deep v and rises into a smaller trailing wave. Use the single smooth orange stroke in `Resources/Brand/voco-mark.svg`, with rounded terminals and continuous curves. Keep it static, preserve its proportions, and leave the viewBox's clear space intact. In the sidebar the mark leads a 20px SemiBold `voco` wordmark. The Dock icon places the mark on a graphite tile; the menu bar uses a monochrome template. The master SVG and prebuilt PNG and ICNS assets live in `Resources`.

Cards use 14px corners, the content panel and practice field 12px, search 10px, sidebar rows 8px, segmented tabs 7px, and keycaps 6px with a doubled lower border. Buttons, chips, steppers, toggles, and the floating pill are fully rounded. Icons are 24px outline drawings with a 1.6 stroke and round caps, in `Resources/Icons`.

## Components

### Controls

Buttons are 32px high with 14px horizontal padding and 12.5px Medium labels. Primary buttons are soft white for the single action a surface asks for. Secondary buttons are graphite. Ghost buttons stay unfilled until hovered. Icon buttons are 30px squares with a tooltip naming the action. Unavailable actions dim to 40% and ignore input.

Rich rows (sidebar navigation, the model card, output options) use the `pressable` primitive. It is focusable, activates on Enter or Space, and draws an orange 1px ring when focused from the keyboard. Pointer clicks do not move focus. The toggle is a 38 × 22px switch on a focusable button, orange when on.

Practice and search use native input state for selection, Unicode editing, and composition. Search carries a leading magnifier and a clear control, and Escape clears it while focused. Transcript and recovery words use selectable, noneditable native inputs that preserve literal punctuation, code, and line breaks.

### Home

The header greets by time of day. Its description changes once setup is complete.

When setup is incomplete, a "Finish setting up" card lists three live steps: download the selected model, allow the microphone, and allow Accessibility. Each step shows a marker (sage check when done, orange numbered ring when current, graphite when upcoming), a description, and its own action, with a primary button only on the current step. Downloads show inline progress with Cancel. The header shows "n of 3 done" with a segmented meter. Permission state refreshes every second, so steps complete without a reload.

The shortcut card shows keycaps for Hold fn, Fn + Space, and Esc beside the 234 × 150px ASCII sculpture. The sculpture is static decoration, independent of microphone activity.

Four tiles follow: Today (words against the daily goal, with a meter that turns sage once the goal is reached), Words dictated, Time saved, and Streak. Practice and up to three recent transcripts close the page.

### Transcripts

The header shows the held count as a chip. A search field filters up to 50 transcripts and shows "n of m match" while searching. Rows sit in one card: an 11px time column, selectable literal text, and a copy icon that turns into a sage check after a successful copy. Empty states use a round icon well with a title and one sentence, distinguishing retention off, no matches, and a new session.

### Statistics

Four tiles show words, time saved, sessions, and best streak from stored totals. The "Last 14 days" card charts words per day from stored daily totals. Today's bar is orange; days that met the goal are deep amber; other days are graphite; days without dictation show a 3px baseline. A dashed line marks the goal, each bar has a tooltip with its date and count, and a legend explains the colors. Preferences use pill steppers: daily goal moves in steps of 100 within 100–10,000, typing speed in steps of 10 within 10–200 wpm. Settings apply immediately.

### Settings

A segmented control switches between Output, Models, Access, and Dictation. Arrow keys cycle the tabs; Home and End select the first and last. The selected tab persists while the window stays open.

Output shows Fast, Balanced, and Accurate as three option cards with an icon, radio indicator, and description; the selected card has an orange border and warm tint. Output choices are unavailable during dictation, with an explanation. History pairs a "Keep recent transcripts" switch with a note that recovery is always on. Turning retention off clears recent text immediately.

Models shows a card per model with an icon well, a tag (Smallest, Quick, Largest), a description, and variant, language, and size. The active model has an orange outline and an "In use" chip. Downloads show a meter, the current file, and a percentage. Loading, cancellation, retry, fresh-download, and idle-only model changes are preserved. Model errors appear in a red-outlined card with Retry and Download a fresh copy.

Access lists Microphone and Accessibility with status chips or Allow access buttons. "If fn does nothing" gives four numbered steps with Open Keyboard Settings, Reveal Voco, and Check again. Dictation lists the shortcuts with keycaps, four safe-insertion guarantees, and a privacy card.

### Status bar and recovery

The 46px status bar shows a status dot and the controller status. During capture and pending transcription, the dot gains a soft orange halo and the bar offers Cancel with an esc keycap. While listening, a 56px meter shows measured microphone energy, never synthetic motion. Otherwise the right side confirms "Copied to clipboard" after a copy, or shows "Processed on your Mac". Notices appear in a strip above the bar.

Recovery adds a warm panel above the bar on every page. It shows the explanation, the saved words in a bounded scrolling well, Copy your words when text exists, and Dismiss. Failed insertion words stay available even when recent transcript retention is off.

### Floating indicator

The floating indicator is a persistent native nonactivating window at the bottom center of the current screen. It preserves the editor's focus and floats above ordinary windows while staying out of native fullscreen Spaces and Split View tiles. When idle, it shows a 7px dot and a 48 × 7px line with opaque black fills and muted gray outlines. The same shapes expand over 220ms into the active indicator and collapse when dictation ends. Reversing activity mid-transition preserves the current geometry. Hovering its 82 × 44px idle hit area expands the shapes and shows Start recording with a pointer cursor. Clicking starts hands-free recording; hovering while recording offers Finish recording. Starting, Transcribing, recovery, and held-key recording ignore clicks. Transparent margins pass mouse input through to other apps. The window never takes keyboard focus. Settled idle requests no animation frames. Reduce Motion snaps directly between states.

The active indicator pairs a 38px black voice circle with a separate 122 × 36px black status capsule, spaced 7px apart. Both use a faint outline. The 12px Manrope Medium label is centered within the status capsule. Five narrow orange waveform bars show recent measured microphone energy while Listening, with stronger response to quiet speech and smooth attack and release. Silence returns the bars to their baseline. Starting and Transcribing use a rotating orange arc inside the circle. Other states use still baseline bars. Status changes retain the same footprint. No partial transcript appears during capture.

### Motion and accessibility

Page and Settings-tab arrival use a 180ms GPUI animation with quintic ease-out. Opacity resolves from 0.7 to 1 while the top offset reduces from 6px to zero. Navigation and commands take effect immediately. Respect the macOS reduced-motion setting by showing page content immediately and keeping the processing arc still. Measured waveform and level feedback continue to reflect actual microphone energy.

Preserve keyboard access, visible focus, native text selection and composition, clear status labels, and complete recovery text. Keep decorative artwork separate from status feedback.

## Do's and Don'ts

- Do keep orange concentrated in voice activity, attention, and small details.
- Do give each surface at most one soft-white primary action.
- Do preserve the black canvas, labeled sidebar, and persistent status and recovery area.
- Do build metrics and charts only from stored usage totals, never illustrative data.
- Do use native literal inputs for practice, search, transcripts, and recovery words.
- Do preserve optional recent transcripts in memory until quit. Disabling retention clears them.
- Don't add pixel or serif accent fonts, orange primary buttons, neon grids, or large glows.
- Don't use drop shadows for depth; use the surface steps and hairlines.
- Don't animate synthetic microphone activity or reveal partial transcript text during capture.
- Don't add persistent audio or transcript storage.
