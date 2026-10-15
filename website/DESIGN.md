---
name: Voco marketing website
description: An editorial, product-first introduction to local voice dictation for Mac.
colors:
  canvas: "#111213"
  white: "#eeece8"
  orange: "#ff742f"
  muted: "#a2a3a4"
  line: "#303132"
  stage: "#171819"
  window: "#242627"
  app-surface: "#191b1c"
  footer: "#1a1b1b"
  button-ink: "#151616"
typography:
  display:
    fontFamily: "Manrope, -apple-system, sans-serif"
    fontSize: "clamp(72px, 7.5vw, 108px)"
    fontWeight: 500
    lineHeight: 1.04
    letterSpacing: "-0.04em"
  statement:
    fontFamily: "Manrope, -apple-system, sans-serif"
    fontSize: "clamp(30px, 3.65vw, 51px)"
    lineHeight: 1.45
    letterSpacing: "-0.035em"
  body:
    fontFamily: "Manrope, -apple-system, sans-serif"
    fontSize: "14px"
    lineHeight: 1.7
  action:
    fontFamily: "Manrope, -apple-system, sans-serif"
    fontSize: "13px"
    fontWeight: 700
rounded:
  pill: "999px"
  stage: "14px"
  window: "12px"
  video: "10px"
  screenshot: "6px"
spacing:
  desktop-gutter: "60px"
  compact-gutter: "40px"
  mobile-gutter: "24px"
components:
  button-primary:
    backgroundColor: "{colors.white}"
    textColor: "{colors.button-ink}"
    rounded: "{rounded.pill}"
    padding: "0 24px"
    typography: "{typography.action}"
  voice-stage:
    backgroundColor: "{colors.stage}"
    rounded: "{rounded.stage}"
    height: "530px"
  demo-window:
    backgroundColor: "{colors.window}"
    rounded: "{rounded.window}"
    width: "570px"
    height: "295px"
---

# Design System: Voco marketing website

## Overview

The direction is “Don't lose the thought.” Large editorial type opens onto a working text destination, with orange voice traces crossing a near-black stage. Spacious reading sections alternate with closer product evidence: a recorded interface walkthrough and inspectable screenshots. The maker's statement and oversized closing wordmark give the page a personal ending.

This system applies only to `website/`. Root `DESIGN.md` and `.impeccable/design.json` belong to the desktop app. `src/style.css`, `index.html`, and `src/main.js` are authoritative for the current website; `REBUILD.md` records its direction. The former sculptural Fn key has been removed. Small shortcut keycaps remain instructional elements.

## Colors

Near-black canvas and soft white establish the editorial field. Orange emphasizes “thought,” voice traces, shortcut illustrations, focus, privacy emphasis, and the footer wordmark. It is not a large section fill. Muted gray supports explanatory copy; thin tonal lines separate steps, questions, and closing sections.

Use the stage, window, app-section, and footer tones to distinguish scenes. The illustrative destination layers a #242627 document over #171819; the real interface chapter sits on #191b1c. Do not transfer marketing compositions into desktop screens.

## Typography

Manrope is bundled locally as a variable font (200–800) with Apple/system sans-serif fallbacks. Display headings use weight 500 and tight tracking. The hero uses the display token; its supporting introduction is 21px/1.55 on wide screens. Major section headings vary by composition: flow 65px, app 59px, privacy 77px, download 56px. The thought statement uses its own slower 1.45 line height.

Explanatory paragraphs commonly use 14px/1.7, becoming 13px on phones. Final CSS overrides raise captions, microcopy, and hero footnotes to 11px desktop and generally 10px mobile; stage status is 9px mobile. Read the entire cascade before copying an earlier selector's smaller font size. Primary actions use 13px/700; navigation uses 13px. The giant footer wordmark uses weight 650 and `clamp(180px, 32vw, 500px)`.

## Layout

The main shell is centered at a maximum 1280px with 60px horizontal padding. The header and hero reach 1440px; the header is 100px tall. Hero copy and supporting action share a row, followed by a 530px full-width voice stage inset 28px. The demo window is centered absolutely inside it, followed by its floating control pill and bottom sample selector/status.

The scroll sequence is hero → thought statement → shortcut walkthrough → recording and screenshot gallery → local privacy → maker statement → FAQ → download → footer. The thought chapter has 150px top and bottom padding. The shortcut walkthrough uses two columns with a 100px gap; its introduction sticks at top 100px while the three steps scroll. The recording has a 220px side column and fluid video, followed by a wide screenshot gallery. Privacy details use three columns. Thin dividers and generous section padding carry the rhythm without a repeated card grid.

At 1100px, shell gutters become 40px and typography/gaps tighten. At 800px, the recording becomes one column, its side note disappears, and the video loses its perspective tilt. At 640px, shell gutters are 24px, the hero stacks, the mobile menu replaces desktop navigation, the walkthrough introduction stops sticking, and privacy, questions, and download arrangements stack. The stage becomes 455px high with 12px outer insets and a fluid window; status and sample controls stack. Mobile display is `clamp(65px, 15.9vw, 95px)`; at 360px it becomes 61px and waveform bars disappear. Preserve these scene-specific adjustments rather than scaling the desktop canvas uniformly.

## Elevation & Depth

Reading sections stay flat. Product surfaces provide selective depth: the demo window has `0 30px 70px -20px #0009`, the floating voice control `0 12px 30px -10px #0008`, and video `15px 30px 50px -20px #0007`. The demo window starts at −2° and settles upright while listening. The video frame uses `perspective(1200px) rotateY(-4deg)` and faces forward on hover or focus within. Gallery screenshots remain flat inside a tonal surround. The full-size native dialog uses a dark, blurred backdrop.

## Shapes

Actions and the voice-control pill are fully rounded. The stage uses 14px corners (10px on mobile), demo window and gallery surround 12px, video 10px, screenshot image 6px. Shortcut keycaps use a 6px radius and heavier bottom border. A simple outlined laptop with an orange-brown orbit marks local processing. The maker signature uses a quiet circular dot, with a large orange quotation mark beside the statement.

## Components

- **Navigation and actions:** the wordmark pairs the real Voco mark with a small orange period. Primary soft-white buttons have a 54px minimum height, lift 3px on hover, and scale to .98 on activation. The compact header action is 39px high. Mobile navigation exposes `aria-expanded`, closes on link selection or Escape, and closes when returning to desktop width. Preserve skip navigation and the orange 2px focus outline with 6px offset.
- **Illustrative dictation:** one state holds sample, phase, and timer. The message, idea, and email samples each supply a destination, context, title, and complete transcript. `idle → listening (2300ms) → transcribing (850ms) → complete` replaces the active placeholder with the entire transcript together. Idle already shows the sample transcript so the destination is understandable before interaction. Replay disables while active and moves focus to Cancel; cancellation, sample switching, or a hidden document clears pending playback. Escape cancels within the stage. Status updates are polite live announcements. No microphone is requested; this is a simulation, not live recognition.
- **Motion:** the canvas draws 22 orange strands, with more energy while listening. Animation is bounded by stage visibility, document visibility, an approximately 32ms frame interval, and device-pixel ratio capped at 2. CSS scroll effects require a viewport at least 900px wide and support for `animation-timeline: view()`: the statement brightens from #777 to soft white over `entry 10% cover 45%`, and the recording theater rises 40px over `entry 0% entry 80%`. Unsupported browsers retain readable static content. Reduced motion disables CSS animation/transitions and smooth scrolling, removes the recording tilt, draws a static canvas, and completes demo playback immediately. This is progressive enhancement; the text does not depend on animation.
- **Recorded interface walkthrough:** A poster play button starts the recording, enables native video controls, and moves keyboard focus to the video. Playback failures retain the retry button and describe the screenshot fallback. Inline playback, metadata preload, and opt-in English captions accompany the recording. Without JavaScript, native controls remain available. The visible disclosure reads “Recorded interface preview · Sample data · Native dictation inactive.” Do not present it as a recording of active native speech recognition. No autoplay is set.
- **Gallery:** actual Home, Settings, and Stats captures appear under “Workspace,” “Your preferences,” and “Your progress.” Captions distinguish sample transcripts/statistics. Tabs use roving focus, selected state, Arrow keys, Home, and End. Full-size inspection opens the selected image in a native modal with matching alt text, close and Escape support, backdrop dismissal, body scroll lock, and return focus.
- **Privacy and maker:** distinguish the initial model download from offline recognition afterward. Audio is not saved; optional recent transcripts stay in memory until quit. The maker statement names Darsh Mahadevia and describes the independent, subscription-free project. Closing composition includes a back-to-top link, enormous orange wordmark with soft-white period, privacy and release-history links, and maker credit.
- **FAQ and download:** native `details`/`summary` controls provide the FAQ. State Apple Silicon, macOS 26+, English, model download and permissions during setup, and the build's lack of Apple notarization. Validated `release.json` metadata can update the static download and installation-help links; failure leaves those links usable and adds a status message. Do not hard-code a release version into the design system.

## Do's and Don'ts

- **Do** preserve large product scenes, short human copy, editorial whitespace, and the personal closing composition.
- **Do** use real recorded and captured interfaces with sample-data disclosures.
- **Do** keep full-transcript insertion, cancellation, keyboard access, reduced motion, and static download fallbacks intact.
- **Do** describe offline use as available after model setup and keep early-access installation limitations visible.
- **Don't** reintroduce the removed Fn sculpture or turn the page into a uniform grid of feature cards.
- **Don't** imply browser microphone capture, guaranteed speed/accuracy, public source availability, or Apple notarization.
- **Don't** overwrite the desktop app's root design documents when refreshing this website system.
