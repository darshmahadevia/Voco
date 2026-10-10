---
name: Voco
description: A compact macOS dictation window with a dashboard and guided first run.
colors:
  accent: "#ff742f"
  accent-strong: "#ff965f"
  accent-soft: "#24160f"
  button-text: "#15100b"
  text-primary: "#f1f1ef"
  text-secondary: "#a5a5a5"
  text-tertiary: "#969696"
  line: "#292929"
  surface: "#080808"
  surface-muted: "#1b1b1b"
  success: "#88a9ff"
  danger: "#ff737b"
typography:
  display:
    fontFamily: '"Manrope", -apple-system, sans-serif'
    fontSize: "56px"
    fontWeight: 500
    lineHeight: 1.04
    letterSpacing: "-0.04em"
  display-accent:
    fontFamily: '"Pixelify Sans", sans-serif'
    fontSize: "56px"
    fontWeight: 400
    letterSpacing: "-0.02em"
  setup-accent:
    fontFamily: '"Instrument Serif", Georgia, serif'
    fontSize: "1.18em"
    fontWeight: 400
    letterSpacing: "-0.02em"
  brand:
    fontFamily: '"Manrope", -apple-system, sans-serif'
    fontSize: "22px"
    fontWeight: 750
    letterSpacing: "-0.04em"
  body:
    fontFamily: '"Manrope", -apple-system, sans-serif'
    fontSize: "13px"
    fontWeight: 400
  supporting:
    fontFamily: '"Manrope", -apple-system, sans-serif'
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.4
  label:
    fontFamily: '"Manrope", -apple-system, sans-serif'
    fontSize: "12px"
    fontWeight: 650
  utility:
    fontFamily: '"Manrope", -apple-system, sans-serif'
    fontSize: "12px"
    fontWeight: 600
    lineHeight: 1
  transcript:
    fontFamily: '"Manrope", -apple-system, sans-serif'
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.6
rounded:
  preview: "6px"
  control: "7px"
  navigation: "8px"
  icon: "9px"
  reminder: "12px"
  onboarding: "14px"
  recovery: "16px"
  pill: "999px"
  circle: "50%"
spacing:
  sidebar-width: "148px"
  sidebar-compact: "132px"
  content-gutter: "22px"
  content-gutter-wide: "22px"
  content-gutter-compact: "16px"
  content-gutter-mobile: "20px"
  setup-panel: "24px"
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.button-text}"
    typography: "{typography.utility}"
    rounded: "{rounded.control}"
    padding: "0 11px"
    height: "34px"
  button-secondary:
    backgroundColor: "{colors.surface-muted}"
    textColor: "{colors.text-primary}"
    typography: "{typography.utility}"
    rounded: "{rounded.control}"
    padding: "0 11px"
    height: "34px"
  button-quiet:
    backgroundColor: "transparent"
    textColor: "{colors.accent-strong}"
    typography: "{typography.utility}"
    rounded: "{rounded.control}"
    padding: "0 7px"
    height: "32px"
  sidebar-active:
    backgroundColor: "#202020"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.navigation}"
    padding: "0 14px"
    height: "43px"
  transcript-switch:
    backgroundColor: "transparent"
    rounded: "12px"
    width: "44px"
    height: "34px"
  practice-field:
    backgroundColor: "#090909"
    textColor: "{colors.text-primary}"
    rounded: "8px"
    padding: "18px"
    width: "100%"
  home-voice-core:
    backgroundColor: "#121212"
    rounded: "{rounded.circle}"
    size: "140px"
  status-pill:
    backgroundColor: "#151515"
    textColor: "{colors.text-primary}"
    typography: "{typography.utility}"
    rounded: "{rounded.pill}"
    padding: "0 19px"
    height: "46px"
  recovery-pill:
    backgroundColor: "#151515"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.recovery}"
    padding: "14px"
    width: "min(100%, 352px)"
---

# Design System: Voco

## Overview

**Creative North Star: "Focused Voice Workspace"**

Voco pairs a compact desktop dashboard with a guided first run. Home shows readiness, the Fn / Globe shortcut, and the optional latest transcript. Settings hold model, access, shortcut, and transcript controls. A separate four-step setup takes a new user from welcome to a first dictation.

Black surfaces and fine gray borders carry the interface. Orange marks actions, the wordmark, and voice activity. Manrope handles interface text. Pixelify Sans emphasizes the second Home headline line. Instrument Serif stays in the setup headlines. The black app tile and sidebar repeat a five-capsule V mark with varied bar heights and centers that trace the V. The sidebar mark is 26px by 20px; the menu-bar template centers a 17px-wide mark in a 22px canvas. The floating pill stays compact while dictation runs and shows transcript text only when recovery needs attention.

**Key Characteristics:**
- Black and gray surfaces with a restrained orange accent.
- Compact desktop window and guided first-run setup.
- Manrope interface text, a Pixelify Sans Home headline, and Instrument Serif setup headlines.
- Optional latest transcript held in memory until quit.

## Colors

The main palette stays black and gray. Orange marks actions and voice activity; blue and red stay limited to status feedback.

### Primary
- **Warm orange:** Primary actions, the wordmark dot, focus outlines, and waveform bars.
- **Light orange:** Button hover states and quiet actions.
- **Dark orange tint:** Active voice state and the preview notice.

### Secondary
- **Ready blue:** Readiness text and its check mark.
- **Error red:** Error messages.

### Neutral
- **Near black:** Main app canvas.
- **Dark gray:** Secondary controls and keyboard keys.
- **Off-white:** Primary text and action labels.
- **Middle gray:** Supporting and quiet text.
- **Light gray:** Section dividers and borders.

**The Restrained Accent Rule.** Keep orange on actions, the wordmark, focus, and voice activity. Large surfaces stay black or neutral gray.

## Typography

**Display Font:** Bundled Manrope variable font, weights 200–800.
**Body Font:** Manrope, with -apple-system and sans-serif fallbacks.
**Label/Mono Font:** No separate typeface.

**Character:** Manrope carries interface copy and the first Home headline line. Pixelify Sans carries the second Home line at the same size as the first. Instrument Serif appears on emphasized setup headline lines.

### Hierarchy
- **Display** (500): The Manrope first line of the Home headline.
- **Display accent** (Pixelify Sans, 400): The second Home headline line, sized to match the first. Instrument Serif remains the setup accent.
- **Brand** (750, 22px): Sidebar wordmark.
- **Body** (400, 13px): Main interface copy.
- **Supporting** (400, 12px, 1.4): Descriptions and setup copy.
- **Label** (650, 12px): Section labels.
- **Utility** (600, 12px): Buttons and short status labels.
- **Transcript** (400, 15px, 1.6): The optional latest transcript on Home.

**The Bundled Font Rule.** Use the bundled Manrope, Pixelify Sans, and Instrument Serif files with their declared fallbacks. Pixelify Sans comes from the official Google Fonts repository (commit 8b0a1d0f5983c89bc2b93f1b5fb55f9e252744b5) and includes its OFL license in the packaged licenses.

## Layout

Voco starts in the menu bar on every launch with the dashboard hidden. Clicking the icon opens a menu with Open Dashboard, Transcripts, and Settings. Their shortcuts are ⌘1, ⌘2, and ⌘, while Voco is focused. The macOS window opens at 960 by 720px, with a 720 by 520px minimum and a 960 by 720px maximum. It cannot maximize or enter full screen. Onboarding and the workspace share the same bounds; finishing setup does not resize the window. Closing hides the window, and Voco stays available in the menu bar.

The workspace uses a 148px sidebar, reducing to 132px at widths of 760px and below. The title bar and navigation stay fixed. Content scrolls inside the window with 22px gutters, reducing to 16px at the minimum size. Home preserves the readiness header, three usage totals, yearly calendar, daily goal and milestone columns, and recent transcripts. Calendar cells have a fixed 7px height to keep the year compact. The full Stats page adds session totals and achievement progress.

Page headings use 24px Manrope. Metric values use 22–28px; descriptions and controls use 12–13px, and compact metadata uses 11px. Main panels use 12px corners; transcript rows and controls use 7–8px corners. The native window provides the outer frame, without another frame around the entire app.

Setup keeps its centered introduction and task area, with a 34px heading and 13px introduction. Its step title and count sit in a compact header. Back and the named next action stay at the bottom alongside progress and a visible status explanation. The speech-model step uses explanatory text on the left and all three models on the right, with the recommended option first. Model choices scroll independently when needed; keyboard help scrolls inside its task area. The practice field has a fixed 100px height. Recent transcripts have a searchable session view; Home shows up to three excerpts and links to the full list.

## Elevation & Depth

Most pages use flat surfaces and fine borders. The floating pill uses a soft shadow (0 8px 24px rgba(0, 0, 0, 0.35)); the transcript switch thumb uses a small shadow (0 1px 3px rgba(0, 0, 0, 0.24)). Do not add glows to large surfaces.

## Shapes

Buttons have gently rounded corners (7px), navigation items use 8px, and keyboard controls use 9px. The onboarding workspace has 14px corners. The floating pill is fully rounded; recovery uses 16px corners. The dashboard voice mark uses concentric circles. Inputs and excerpt panels use 8px corners. Focus outlines remain visible.

## Components

### Buttons
Primary actions use orange with a dark label. Secondary actions use a dark gray fill and fine border. Quiet actions use light orange text. Hover changes color; keyboard focus uses an orange outline. Disabled controls use 58% opacity.

### Navigation
The left sidebar holds the wordmark, Home, Settings, and setup when setup remains needed. The selected item uses a gray fill and an orange icon. At narrow widths, navigation becomes compact while preserving accessible labels. Home has no separate Settings link.

### Dashboard
Home shows readiness in a blue microphone badge with an accessible status label. Calendar cells keep a square aspect ratio as the window resizes. Home groups a compact welcome and readiness header, the Fn / Globe shortcut, usage totals, yearly calendar, daily goal, and milestone grid. A link opens the complete Stats page. Recent transcripts sit below the overview with copy buttons and a link to the session list. Home excerpts scroll for longer text; the full transcript view wraps the complete text and supports session search. Copy feedback appears after the clipboard write succeeds, with retry on failure. Empty and disabled-retention states explain how transcripts become available. Transcripts remain in memory until quit; turning retention off clears them.

### First-time setup
The four steps are Welcome, Speech model, App permissions, and Your first words. A step title and count show progress; labeled Back and next buttons navigate the sequence. Onboarding has no footer commentary or promotional notes. Model rows and permission controls show the state of each required step. Enter advances from a focused step heading when the next step is available. Setup shows all three speech models in a divided list beside the explanation, with the recommended option first. Each row shows its version, download size, status, and action. Downloads continue while the user grants permissions. Setup keeps an Explore the app link available once the selected model is ready. Practice explains unavailable dictation and links to the model or permission step. Its text field preserves words when moving between steps and has an expandable Fn / Globe guide for macOS keyboard conflicts. Keep a neutral startup view until the first native state arrives, then choose the initial page once. Route to Home when setup has been seen, or when the model is loading or ready and microphone, accessibility, and shortcut permissions are present. When those permissions are present but the model is still loading, Home says "Loading speech model" and shows no setup prompt. Native actions stay disabled in browser preview.

### Settings
Settings apply changes immediately and have no Done button. When ready, the footer pairs the microphone badge with the Fn / Globe shortcut. Speech model, Access, and Dictation appear as flat sections with divider lines. Dictation groups the shortcut and transcript preference. The optional transcript switch controls whether Home keeps the latest transcript in memory. Its 44px by 34px hit area surrounds the 34px by 20px track.

### Dictation pill
The 46px capsule shows a short status beside eleven rounded 3.5px bars in a 32px waveform. During capture, eleven bars respond to distinct measured frequency ranges from 80Hz to 6kHz in the latest microphone buffer. A Hann window and Goertzel analysis measure each band's RMS energy. The overall RMS noise floor is 0.003 with gain 12; each band removes a 0.0006 RMS floor with gain 30. Each bar combines 80% of its own band level with 20% of the overall microphone level, keeping quiet speech visible while letting voice pitch and consonants move the bars independently. The UI mixes the measured low and high bands into five voice features, then distributes each feature once on each half in different orders, with a strong center bar. This gives both halves equal activity instead of concentrating speech energy on the left. The peak feature drives amplitude through sqrt(1 - exp(-5 * peak)) in the pill and gain 3 on Home. Each bar uses 38% of that amplitude plus 62% scaled by its feature relative to the peak, keeping every bar present and preserving tall and short variation at loud volumes. Silent measurements return all bars to a still 1px baseline. Microphone frames publish every 40ms. Each bar follows its measured target continuously at the display frame rate, with slightly staggered 40–58ms rise and 85–99ms fall time constants. Changes settle without restarting a transition; there are no repeating pulses, random values, or synthetic wave profiles during capture. The bars return to the baseline when capture stops; processing shows the spinner. Reduced motion updates microphone feedback immediately. The capsule does not show partial transcript text during capture.

### Recovery
The 400px by 220px pill shows recovery in a panel up to 352px wide. The heading, dismiss control, and Copy transcript action stay outside a scrolling explanation, transcript excerpt, and error region. Home shows the full recovery text in a scrollable area and gives recovery precedence over readiness. Copy includes all retained words.

## Do's and Don'ts

### Do:
- **Do** use black surfaces, fine gray borders, and orange for actions and voice activity.
- **Do** keep blue and red for readiness and error feedback.
- **Do** keep the dashboard, setup flow, and flat settings groups distinct.
- **Do** retain keyboard focus and reduced-motion behavior.
- **Do** show latest transcript text only when the optional in-memory setting is on, or when recovery needs a copy action.

### Don't:
- **Don't** add neon grids, glow effects, or Tron-style panels.
- **Don't** add persistent transcript history or save audio and transcript text to disk.
- **Don't** show partial transcript text or a Buffered badge during capture.
- **Don't** add cards or shadows to settings groups.
- **Don't** make browser preview imply that native actions are active.
