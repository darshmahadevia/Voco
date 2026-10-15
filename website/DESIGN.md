---
name: Voco marketing website
description: A warm, tactile introduction to local voice dictation for Mac.
colors:
  ivory: "#f6f4ee"
  ink: "#262720"
  sage: "#777e63"
  graphite: "#20231e"
  muted: "#65665d"
  orange: "#c74c16"
  line: "#dbdad1"
  demo-surface: "#2c3028"
typography:
  display:
    fontFamily: "Manrope, -apple-system, sans-serif"
    fontSize: "clamp(64px, 6.8vw, 90px)"
    fontWeight: 500
    lineHeight: 1.08
    letterSpacing: "-0.04em"
  headline:
    fontFamily: "Manrope, -apple-system, sans-serif"
    fontSize: "clamp(38px, 4.5vw, 60px)"
    fontWeight: 500
    lineHeight: 1.14
    letterSpacing: "-0.035em"
  body:
    fontFamily: "Manrope, -apple-system, sans-serif"
    fontSize: "14px"
    lineHeight: 1.75
  label:
    fontFamily: "Manrope, -apple-system, sans-serif"
    fontSize: "12px"
    fontWeight: 600
rounded:
  panel: "16px"
  screenshot: "12px"
  pill: "100px"
  key: "39px"
spacing:
  mobile-gutter: "24px"
  tablet-gutter: "36px"
  desktop-gutter: "64px"
components:
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.ivory}"
    rounded: "{rounded.pill}"
    padding: "0 25px"
    height: "54px"
  demo:
    backgroundColor: "{colors.demo-surface}"
    textColor: "{colors.ivory}"
    rounded: "{rounded.panel}"
    padding: "27px"
---

# Design System: Voco marketing website

## Overview

The direction is a little breathing room. A spacious, persuasive landing page makes dictation feel approachable through a tactile Fn key, plain language, and inspectable product evidence. Warm ivory and sage open the story; a graphite demonstration chapter gives the interaction its own stage.

This system applies only to `website/`. The root design documents describe the desktop app. Inspiration: [Beside’s hero](https://vibrant.design/website/pcyiyzl-beside-s-hero-section) for spaciousness and a tactile instrument; [Griffin](https://vibrant.design/website/yovgmpb-griffin-the-bank-you-can-build-on) for dark editorial sections and exploration. Preserve Voco’s own mark, Manrope, product behavior, and real captures.

## Colors

Ivory is the page canvas; ink carries reading and primary actions. Sage softens the hero’s second line. Graphite defines the demo chapter, where muted text, borders, and orange adapt for contrast. Orange marks small voice details and focus rather than filling large surfaces. CSS is the implementation source of truth.

## Typography

Bundle Manrope locally with system fallbacks. Use medium-weight, tightly tracked display type; body copy stays calm and short. Hero supporting copy is 21px/1.5; explanatory copy is generally 14px. Compact labels support the hierarchy without competing with headlines. Mobile display sizing is `clamp(51px, 13.1vw, 78px)`, with a further narrow-screen adjustment.

## Layout

Use a centered 1320px shell with 64px side gutters, reducing to 36px at 1050px and 24px at 640px. The desktop hero pairs copy with the Fn instrument; mobile stacks these. The dark chapter pairs steps with the demo, followed by an app gallery, privacy explanation, download requirements, FAQ, and oversized footer wordmark. Breakpoints at 800px and 360px refine intermediate and narrow layouts. Keep intentional whitespace while allowing controls and copy to wrap.

## Elevation & Depth

Most sections use flat color and thin dividers. Reserve structural shadows and dimensional gradients for the Fn key, floating transcript detail, actual app screenshots, and screenshot dialog. The key has stacked edge shadows and a restrained perspective tilt; it visibly depresses on hover or focus. Do not spread this material treatment to every container.

## Shapes

Primary actions are full pills. Demo, gallery stage, and download panels use soft rectangular corners; screenshots keep smaller corners. The 39px key silhouette and circular dial are the hero’s signature geometry. Borders stay quiet and tonal.

## Components

- **Navigation and actions:** compact wordmark, section anchors, and a persistent download entry. Mobile navigation uses an explicit expanded state and Escape dismissal. Primary buttons lift slightly on hover and compress on activation.
- **Fn instrument:** a real button, labeled for its demo action. Activation scrolls to the demonstration, starts playback, and places focus on its active control.
- **Demonstration:** a dark illustrative state machine with `idle → listening → transcribing → complete`. Email, note, and message samples reset playback when selected. Show the completed text together after transcription, matching actual insertion behavior. Support cancel, Escape, and replay; clear pending timers. Never request microphone access or imply that the sample is live recognition.
- **Product gallery:** real Home, Settings, and Stats renderer captures with descriptive captions and labeled sample data. Tabs use selected state, roving focus, arrow keys, Home, and End. “View full size” opens the selected screenshot in a native modal dialog with scrollable image detail, close control, Escape support, and return focus.
- **Download and FAQ:** state Apple Silicon, macOS 26+, English, model download during setup, and the early access build’s lack of Apple notarization. Use validated release links with usable static fallbacks. FAQ disclosures expose expanded state and keep closed contents inert.

## Do's and Don'ts

- **Do** make the page persuade through a clear interaction and authentic product evidence.
- **Do** preserve skip navigation, visible keyboard focus, semantic controls, useful image descriptions, and readable contrast in both chapters.
- **Do** honor reduced motion: remove travel and animated decoration; demo playback resolves immediately to its completed example.
- **Do** distinguish offline use after setup from the initial model download.
- **Don't** claim live browser dictation, guaranteed speed or accuracy, public source availability, or Apple notarization.
- **Don't** replace screenshots with invented product interfaces or turn the marketing palette into a desktop app redesign.
