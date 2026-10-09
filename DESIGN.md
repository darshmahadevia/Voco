---
name: Voco
description: A focused macOS dictation workspace with a wide dashboard and guided first run.
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
    fontSize: "clamp(52px, 5vw, 62px)"
    fontWeight: 500
    lineHeight: 1.04
    letterSpacing: "-0.04em"
  display-accent:
    fontFamily: '"Pixelify Sans", sans-serif'
    fontSize: "clamp(52px, 5vw, 62px)"
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
    lineHeight: 1.85
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
  sidebar-width: "194px"
  sidebar-compact: "72px"
  content-gutter: "48px"
  content-gutter-wide: "72px"
  content-gutter-compact: "30px"
  content-gutter-mobile: "20px"
  setup-panel: "30px"
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
    padding: "0 5px"
    height: "26px"
  sidebar-active:
    backgroundColor: "#202020"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.navigation}"
    padding: "0 14px"
    height: "43px"
  transcript-switch:
    backgroundColor: "#454545"
    rounded: "12px"
    width: "34px"
    height: "20px"
  practice-field:
    backgroundColor: "#090909"
    textColor: "{colors.text-primary}"
    rounded: "8px"
    padding: "18px"
    width: "100%"
  home-voice-core:
    backgroundColor: "#121212"
    rounded: "{rounded.circle}"
    size: "170px"
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
    padding: "16px"
    width: "min(100%, 352px)"
---

# Design System: Voco

## Overview

**Creative North Star: "Focused Voice Workspace"**

Voco pairs a wide desktop dashboard with a guided first run. Home shows readiness, the Fn / Globe shortcut, and the optional latest transcript. Settings hold model, access, shortcut, and transcript controls. A separate four-step setup takes a new user from welcome to a first dictation.

Black surfaces and fine gray borders carry the interface. Orange marks actions, the wordmark, and voice activity. Manrope handles interface text. Pixelify Sans emphasizes the second Home headline line. Instrument Serif stays in the setup headlines. The black app tile and orange waveform repeat the same mark. The floating pill stays compact while dictation runs and shows transcript text only when recovery needs attention.

**Key Characteristics:**
- Black and gray surfaces with a restrained orange accent.
- Wide dashboard and guided first-run setup.
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
- **Transcript** (400, 15px, 1.85): The optional latest transcript on Home.

**The Bundled Font Rule.** Use the bundled Manrope, Pixelify Sans, and Instrument Serif files with their declared fallbacks. Pixelify Sans comes from the official Google Fonts repository (commit 8b0a1d0f5983c89bc2b93f1b5fb55f9e252744b5) and includes its OFL license in the packaged licenses.

## Layout

The native window opens at 1120 by 780px and has an 820 by 640px minimum. Desktop uses a permanent 194px left sidebar and a centered content column with 48px gutters. The content area grows to 1200px; windows at 1500px and wider use 72px gutters. Below 1050px, content gutters shrink to 30px.

The dashboard centers a vertical hero with the waveform above a large two-line heading. The latest transcript stays visible below the hero with a copy button. Settings is available in the sidebar. Setup uses a two-column copy and workspace layout, then stacks below 800px. At 600px and below, the sidebar becomes a 72px icon rail, the centered hero scales down, and content gutters shrink to 14px.

**The Wide Workspace Rule.** Keep the dashboard and setup content open on desktop. Stack their columns only at the implemented responsive breakpoints.

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
The hero centers a circular voice mark above a two-line headline and shortcut or setup action. Manrope carries the first line, and the equally sized Pixelify Sans line carries the second. The bars animate visibly inside the circle while ready and stop with reduced motion. During listening, eleven bars scale with the square root of microphone volume and settle through a spring (stiffness 500, damping 32, mass 0.35). While listening above 0.015, each nested fill pulses independently at a staggered interval. At silence, the bars rest at 3px. Reduced motion removes the pulse and makes spring transitions immediate. The lower panel keeps the optional latest transcript visible. Its copy button animates the icon and label after a successful clipboard write, then returns to its idle state. Copy errors retain the words and allow retry. Empty and disabled-retention states keep the panel visible and disable copying. The transcript remains in memory until quit and can be turned off in Settings.

### First-time setup
The four steps are Welcome, Speech model, App permissions, and Your first words. Setup explains the offline model, tracks download progress, requests microphone and keyboard access, and keeps an Explore the app link available. The practice step accepts dictation in a text field and has an expandable Fn / Globe guide for macOS keyboard conflicts. Keep a neutral startup view until the first native state arrives, then choose the initial page once. Route to Home when setup has been seen, or when the model is loading or ready and microphone, accessibility, and shortcut permissions are present. When those permissions are present but the model is still loading, Home says "Loading speech model" and shows no setup prompt. Native actions stay disabled in browser preview.

### Settings
Model, access, shortcut, and transcript preferences appear as flat sections with divider lines. The optional transcript switch controls whether Home keeps the latest transcript in memory.

### Dictation pill
The 46px capsule shows the waveform and a short status. It does not show partial transcript text during capture.

### Recovery
Recovery expands to a maximum width of 352px. It shows an explanation, up to three lines of transcript text, and Copy transcript and dismiss actions.

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
