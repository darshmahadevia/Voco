---
name: Voco
description: A quiet local voice workspace for your Mac.
colors:
  surface: "#171819"
  sidebar: "#111213"
  surface-raised: "#202123"
  surface-muted: "#2b2d2f"
  accent: "#FF742F"
  accent-strong: "#ffb58f"
  accent-soft: "#38251d"
  text-primary: "#f2f0ec"
  text-secondary: "#b9b8b5"
  text-tertiary: "#929497"
  button-text: "#1c1d1f"
  line: "#303234"
  success: "#b9cbbd"
  danger: "#ff9d9d"
  text-selection: "#803c1b"
typography:
  display:
    fontFamily: "Manrope, -apple-system, sans-serif"
    fontSize: "38px"
    fontWeight: 500
    lineHeight: 1.18
    letterSpacing: "-0.03em"
  greeting:
    fontFamily: "Manrope, -apple-system, sans-serif"
    fontSize: "32px"
    fontWeight: 500
    lineHeight: 1.25
    letterSpacing: "-0.03em"
  headline:
    fontFamily: "Manrope, -apple-system, sans-serif"
    fontSize: "30px"
    fontWeight: 500
    lineHeight: 1.3
    letterSpacing: "-0.035em"
  title:
    fontFamily: "Manrope, -apple-system, sans-serif"
    fontSize: "17px"
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
  navigation: "10px"
  segment: "9px"
  workspace: "16px"
  pill: "999px"
spacing:
  sidebar: "148px"
  gutter: "26px"
  gutter-compact: "24px"
  gutter-narrow: "18px"
  section: "26px"
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
    padding: "18px 20px"
  practice-field:
    backgroundColor: "{colors.surface-raised}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.field}"
    padding: "16px"
    height: "100px"
---

# Design System: Voco

## Overview

**Creative North Star: "Quiet Voice Workspace"**

Graphite surfaces, soft white buttons, and restrained orange details establish the dark minimal direction. Voco feels calm and personal, with a clear place to speak and small, readable signs of readiness. Bundled Manrope supplies every text role.

The visual direction draws on [vibrant.design](https://vibrant.design/) for restrained dark surfaces and controls. Motion adapts patterns from [transitions.dev](https://transitions.dev/): a moving navigation selection, brief page arrivals, and compact text and icon swaps. These are inspirations adapted to Voco’s desktop workflow.

**Key Characteristics:**

- Tonal graphite layers with compact shortcut guidance and a persistent live footer.
- Fully rounded soft-white primary controls.
- Orange used sparingly for voice activity, progress, and emphasis.
- Flat statistics and divided transcript rows.

## Colors

### Primary

Orange `#FF742F` (`accent`) identifies live voice feedback, progress, the wordmark dot, and small emphasis. Its lighter and darker companions support notices and badges. Soft white (`text-primary`) fills primary actions; primary buttons do not use orange.

### Neutral

`surface` is the main graphite canvas; `sidebar` is a deeper navigation plane. `surface-raised` holds the Home voice workspace and practice field. `surface-muted` supports secondary controls. Primary, secondary, and tertiary text form a deliberate reading hierarchy; `line` separates flat sections.

Sage (`success`) signals readiness and completed actions. Soft red (`danger`) identifies errors. Pair semantic color with text or an icon.

## Typography

Use the bundled Manrope variable font (200–800), with -apple-system and sans-serif fallbacks. All headings, labels, keyboard hints, and transcript text share this family.

Setup headlines use the display role, with orange on the second line. Home uses the greeting role; other page headings use headline. Voice workspace headings use title. Supporting text is usually 10–12px and transcript rows use 13px with 1.7 line-height. Metrics use 28px with tabular numerals. Preserve readable text wrapping and selectable transcripts.

## Layout

The desktop shell has a 148px sidebar and a separately scrolling content area with 26px horizontal gutters. Content is centered up to 860px wide. At widths of 800px and below, gutters become 24px. At 600px and below, the sidebar becomes a 64px icon rail and gutters 18px; retain accessible navigation labels. Wide previews at 1200px use 52px gutters. Short windows reduce vertical spacing. Below 580px in height, Home omits its introductory tagline and secondary voice heading so the latest copy action fits above the footer.

Home starts with a personalized greeting and an All stats link, followed by compact tonal keyboard guidance. Three flat usage totals and recent transcript rows follow. The dedicated Stats page owns the activity calendar, daily goal, and milestones. The Transcripts page provides session search, complete selectable text, and a 64px time gutter that stacks above the text on narrow screens.

A live footer sits outside the scrolling page on Home, Transcripts, Stats, and Settings. Guided setup uses its own action rail and omits the footer unless a transcript needs recovery. Its normal state has a minimum height of 52px, with microphone status and shortcut guidance. Recovery adds a bounded transcript panel above the live footer and keeps the copy action reachable across pages.

Setup has four steps: Welcome, Speech model, App permissions, and Your first words. Keep the header and bottom action rail outside the scrolling task area. Back, the named next action, progress, and the available Explore link stay reachable. On desktop, the model explanation and separately scrolling model list sit side by side. Narrow layouts stack them and scroll the task area. Preserve the 100px practice field and its contents between steps.

## Elevation & Depth

Use tonal layering for structural depth. Home’s workspace is lighter than the canvas, and navigation is darker. Settings, statistics, and transcript lists stay flat with fine dividers. The floating pill uses `0 8px 24px #0005, inset 0 1px 0 #ffffff12`. The live footer uses a border and a tonal background. Avoid decorative glow.

## Shapes

Voco’s brand mark is a continuous, rounded V that follows the flow of a voice wave. Use the single smooth orange stroke in `Resources/Brand/voco-mark.svg`, with round terminals and a gently curved valley. Keep it static, preserve its proportions, and leave the viewBox’s clear space intact. The wordmark remains Manrope with its orange dot. The Dock icon places the mark on a graphite tile; the menu bar uses a monochrome template. Run `npm run build:icons` to regenerate the app and menu-bar assets from the master SVG.

Primary and secondary actions, search fields, chips, and status capsules are fully rounded. Navigation selections use 10px corners. Voice and recovery workspaces use 16px corners; practice fields use 12px corners and selected output options use 9px. Keyboard keys use 7px corners and a doubled lower border. Keep visible orange focus outlines offset from controls.

## Components

### Controls and navigation

Primary actions pair soft white with dark labels and brighten to white on hover. Secondary actions use muted graphite; quiet actions use secondary text. Buttons press to 0.97 scale and disabled controls use 45% opacity. Keyboard focus uses a 2px orange outline with 4px offset.

The sidebar selection moves between main navigation destinations using a shared rounded background and a spring (stiffness 420, damping 36). Settings remains anchored at the bottom. Page arrival lasts 160ms, resolving opacity from 0.7 to 1 and 4px vertical displacement. Navigation mounts the destination immediately without waiting for an outgoing page. Status text swaps resolve 3px displacement and opacity over 120ms. Neither transition blurs the page or status text. Copy feedback appears only after clipboard success and includes a retryable error state.

### Voice guidance and live status

Home uses a compact shortcut panel with a cropped orange ASCII voice ribbon inspired by the [Maple Research posters on Vibrant](https://vibrant.design/). The artwork is static and decorative, separate from microphone feedback. The persistent live footer and floating dictation pill share their status language. Orange waveform bars respond only to measured microphone energy during capture. Silence returns them to a still baseline; processing uses a spinner and short status text. Do not show partial transcript text while capturing. Preserve recovery’s complete copy action and separately scrolling explanation and transcript. The standard pill reserves a 58px symbol slot and a 134px label slot so state changes keep its footprint stable. Keep one persistent polite live region outside the animated visual labels. The floating recovery panel changes shape with a spring using stiffness 380, damping 32, and mass 0.8.

### Setup and Settings

Model rows separate the name and description from version and download size. An orange selection indicator identifies the current model. Show one action per row and avoid duplicate readiness labels. Preserve permission guidance, loading, retry, cancellation, and practice blockers. Settings apply immediately, with no save or Done action. Output, Models, Access, and Dictation are labeled tabs with one visible panel. Arrow keys wrap between tabs; Home and End select the first and last tabs. Keep inactive panels hidden and preserve command state above them. An orange underline moves between tabs, with immediate changes under reduced motion. Above 1000px, each panel pairs a compact introduction column with its controls. Smaller windows stack these groups. Output quality uses a three-part segmented radio group, a quiet selected background, and one selected description below the choices. Detailed cleanup behavior and caveats stay in a disclosure. The transcript switch has a 44px by 34px hit area and a 180ms thumb transition using the standard movement easing.

### Motion and accessibility

Use brief, purposeful state transitions. Standard CSS timing is 160ms for control changes and 180ms for general changes, with `cubic-bezier(.16, 1, .3, 1)` for movement. Respect reduced motion: remove travel and blur, disable decorative transitions and repeated animation, and update measured microphone feedback immediately. Keep keyboard focus, accessible control names, polite status announcements, and error alerts.

## Do's and Don'ts

- **Do** keep orange concentrated in voice activity and small details.
- **Do** preserve compact Home guidance and keep live status outside the scrolling page.
- **Do** keep setup actions reachable while its task content scrolls.
- **Do** preserve dictation behavior and optional transcripts held in memory until quit; disabling retention clears them.
- **Don't** reintroduce pixel or serif accent fonts, orange primary buttons, neon grids, or large glows.
- **Don't** animate synthetic microphone activity or reveal partial transcript text during capture.
- **Don't** add persistent audio or transcript storage, or make browser previews imply native actions are active.
