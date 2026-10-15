---
name: Voco
description: A quiet local voice workspace for your Mac.
colors:
  surface: "#151617"
  sidebar: "#111213"
  surface-raised: "#1c1e20"
  surface-muted: "#26282b"
  accent: "#f49667"
  accent-strong: "#ffb68e"
  accent-soft: "#30231e"
  text-primary: "#f2f0ec"
  text-secondary: "#b2b1b0"
  text-tertiary: "#929497"
  button-text: "#1c1d1f"
  line: "#303235"
  success: "#b9cbbd"
  danger: "#ff9d9d"
typography:
  display:
    fontFamily: "Manrope, -apple-system, sans-serif"
    fontSize: "38px"
    fontWeight: 500
    lineHeight: 1.18
    letterSpacing: "-0.04em"
  greeting:
    fontFamily: "Manrope, -apple-system, sans-serif"
    fontSize: "34px"
    fontWeight: 500
    lineHeight: 1.25
    letterSpacing: "-0.04em"
  headline:
    fontFamily: "Manrope, -apple-system, sans-serif"
    fontSize: "30px"
    fontWeight: 500
    lineHeight: 1.3
    letterSpacing: "-0.035em"
  title:
    fontFamily: "Manrope, -apple-system, sans-serif"
    fontSize: "19px"
    fontWeight: 500
    letterSpacing: "-0.025em"
  body:
    fontFamily: "Manrope, -apple-system, sans-serif"
    fontSize: "13px"
    fontWeight: 400
  supporting:
    fontFamily: "Manrope, -apple-system, sans-serif"
    fontSize: "12px"
    lineHeight: 1.6
  label:
    fontFamily: "Manrope, -apple-system, sans-serif"
    fontSize: "11px"
    fontWeight: 650
rounded:
  key: "7px"
  field: "12px"
  workspace: "16px"
  pill: "999px"
spacing:
  sidebar: "172px"
  gutter: "34px"
  gutter-compact: "24px"
  gutter-narrow: "18px"
  section: "26px"
  workspace-padding: "25px"
components:
  button-primary:
    backgroundColor: "{colors.text-primary}"
    textColor: "{colors.button-text}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "0 15px"
    height: "34px"
  button-secondary:
    backgroundColor: "{colors.surface-muted}"
    textColor: "{colors.text-primary}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "0 15px"
    height: "34px"
  button-quiet:
    backgroundColor: "transparent"
    textColor: "{colors.text-secondary}"
    rounded: "{rounded.pill}"
    padding: "0 9px"
    height: "34px"
  voice-workspace:
    backgroundColor: "{colors.surface-raised}"
    rounded: "{rounded.workspace}"
    padding: "{spacing.workspace-padding}"
  practice-field:
    backgroundColor: "{colors.surface-raised}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.field}"
    padding: "16px"
    height: "100px"
  status-chip:
    backgroundColor: "{colors.surface-muted}"
    textColor: "{colors.text-secondary}"
    rounded: "{rounded.pill}"
    padding: "7px 11px"
---

# Design System: Voco

## Overview

**Creative North Star: “Quiet Voice Workspace”**

Dark minimal: graphite surfaces, soft white buttons, restrained orange details. Voco feels calm and personal, with a clear place to speak and small, readable signs of readiness. Bundled Manrope supplies every text role.

The visual direction draws on [vibrant.design](https://vibrant.design/) for restrained dark surfaces and controls. Motion adapts patterns from [transitions.dev](https://transitions.dev/): a moving navigation selection, brief cross-blur arrivals, and compact text and icon swaps. These are inspirations adapted to Voco’s desktop workflow.

**Key Characteristics:**
- Tonal graphite layers with generous space around the voice workspace.
- Fully rounded soft-white primary controls.
- Orange used sparingly for voice activity, progress, and emphasis.
- Flat statistics and divided transcript rows.

## Colors

### Primary

Warm orange (`accent`) identifies live voice feedback, progress, the wordmark dot, and small emphasis. Its lighter and darker companions support notices and badges. Soft white (`text-primary`) fills primary actions; primary buttons do not use orange.

### Neutral

`surface` is the main graphite canvas; `sidebar` is a deeper navigation plane. `surface-raised` holds the Home voice workspace and practice field. `surface-muted` supports secondary controls. Primary, secondary, and tertiary text form a deliberate reading hierarchy; `line` separates flat sections.

Sage (`success`) signals readiness and completed actions. Soft red (`danger`) identifies errors. Pair semantic color with text or an icon.

## Typography

Use the bundled Manrope variable font (200–800), with -apple-system and sans-serif fallbacks. All headings, labels, keyboard hints, and transcript text share this family.

Setup headlines use the display role, with orange on the second line. Home uses the greeting role; other page headings use headline. Voice workspace headings use title. Supporting text is usually 10–12px and transcript rows use 12px with 1.7 line-height (13px in the full session view). Metrics use 28px with tabular numerals. Preserve readable text wrapping and selectable transcripts.

## Layout

The desktop shell has a 172px sidebar and a separately scrolling content area with 34px horizontal gutters. Content is centered up to 860px wide. At widths of 800px and below, the sidebar becomes 144px and gutters 24px. At 600px and below, the sidebar becomes a 64px icon rail and gutters 18px; retain accessible navigation labels. Wide previews at 1200px use 52px gutters. Short windows reduce vertical spacing.

Home starts with a personalized greeting and readiness chip, followed by one tonal voice workspace with keyboard guidance and a live status capsule. Three flat usage totals and recent transcript rows follow. The dedicated Stats page owns the activity calendar, daily goal, and milestones; the Transcripts page provides session search and complete text.

Setup has four steps: Welcome, Speech model, App permissions, and Your first words. Keep the header and bottom action rail outside the scrolling task area. Back, the named next action, progress, and the available Explore link stay reachable. On desktop, the model explanation and separately scrolling model list sit side by side. Narrow layouts stack them and scroll the task area. Preserve the 100px practice field and its contents between steps.

## Elevation & Depth

Use tonal layering for structural depth. Home’s workspace is lighter than the canvas, and navigation is darker. Settings, statistics, and transcript lists stay flat with fine dividers. Shadows belong to capsules: Home uses `0 8px 18px #0003`; the floating pill uses `0 8px 24px #0005, inset 0 1px 0 #ffffff12`. Avoid decorative glow.

## Shapes

Primary and secondary actions, navigation selections, search fields, chips, and status capsules are fully rounded. Voice and recovery workspaces use 16px corners; practice fields and selected output options use 12px. Keyboard keys use 7px corners and a doubled lower border. Keep visible orange focus outlines offset from controls.

## Components

### Controls and navigation

Primary actions pair soft white with dark labels and brighten to white on hover. Secondary actions use muted graphite; quiet actions use secondary text. Buttons press to 0.97 scale and disabled controls use 45% opacity. Keyboard focus uses a 2px orange outline with 4px offset.

The sidebar selection moves between main navigation destinations using a shared rounded background and a spring (stiffness 420, damping 36). Settings remains anchored at the bottom. Page arrival lasts 240ms, resolving opacity, 6px vertical displacement, and 2px blur. Status text swaps resolve 5px displacement and 3px blur over 180ms. Copy feedback appears only after clipboard success and includes a retryable error state.

### Voice workspace and capsule

Home embeds the same live status language as the floating dictation capsule. Orange waveform bars respond only to measured microphone energy during capture. Silence returns them to a still baseline; processing uses a spinner and short status text. Do not show partial transcript text while capturing. Preserve recovery’s complete copy action and separately scrolling explanation and transcript.

### Setup and Settings

Model rows show version, size, recommendation, status, progress, and the available action. Preserve permission guidance, loading, retry, cancellation, and practice blockers. Settings apply immediately, with no save or Done action. Output quality, Speech model, Access, and Dictation use flat divided sections. Selected output options gain a quiet tonal background. The transcript switch has a 44px by 34px hit area and a spring-like thumb transition.

### Motion and accessibility

Use brief, purposeful state transitions. Standard CSS timing is 160ms for control changes and 250ms for general changes, with `cubic-bezier(.16, 1, .3, 1)` for movement. Respect reduced motion: remove travel and blur, disable decorative transitions and repeated animation, and update measured microphone feedback immediately. Keep keyboard focus, accessible control names, polite status announcements, and error alerts.

## Do's and Don'ts

- **Do** keep orange concentrated in voice activity and small details.
- **Do** preserve the greeting, tonal voice workspace, and live capsule as Home’s hierarchy.
- **Do** keep setup actions reachable while its task content scrolls.
- **Do** preserve dictation behavior and optional transcripts held in memory until quit; disabling retention clears them.
- **Don't** reintroduce pixel or serif accent fonts, orange primary buttons, neon grids, or large glows.
- **Don't** animate synthetic microphone activity or reveal partial transcript text during capture.
- **Don't** add persistent audio or transcript storage, or make browser previews imply native actions are active.
