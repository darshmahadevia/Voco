---
name: Voco
description: Native macOS dictation with minimal microphone status and live writing.
typography:
  title:
    fontFamily: "system-ui"
    fontSize: "28pt"
    fontWeight: 600
  setup-description:
    fontFamily: "system-ui"
    fontSize: "14pt"
    fontWeight: 400
  setup-label:
    fontFamily: "system-ui"
    fontSize: "13pt"
    fontWeight: 600
  body:
    fontFamily: "system-ui"
    fontSize: "12pt"
    fontWeight: 400
  transcript:
    fontFamily: "system-ui"
    fontSize: "14pt"
    fontWeight: 400
  utility-hint:
    fontFamily: "system-ui"
    fontSize: "11pt"
    fontWeight: 400
rounded:
  pill: "full"
  recovery: "20pt"
spacing:
  compact: "4pt"
  tight: "6pt"
  status: "8pt"
  icon-label: "10pt"
  content: "12pt"
  permission-icon-gap: "14pt"
  row-padding: "16pt"
  pill-vertical: "11pt"
  pill-horizontal: "16pt"
  section: "24pt"
  window-padding: "30pt"
components:
  listening-pill:
    rounded: "{rounded.pill}"
    padding: "11pt 16pt"
    width: "50pt"
  continuous-pill:
    width: "80pt"
  recovery-pill:
    width: "340pt"
  setup-window:
    padding: "30pt"
    width: "550pt"
  setup-row-button:
    size: "small"
  recovery-copy-button:
    size: "small"
  recovery-dismiss-button:
    size: "small"
---

# Voco design

Voco writes live words into the active field. The microphone capsule is centered at the bottom of the active display and never takes keyboard focus. It shows no transcript during normal capture.

Hold mode uses a 50pt-wide capsule; continuous listening uses an 80pt capsule with a stop control. Widths include 16pt horizontal padding. Vertical padding is 11pt, the microphone is 14pt, and a 12pt outer inset accommodates the shadow. Regular material follows the system appearance. The shadow uses black opacity 0.16, radius 10pt, and a 4pt vertical offset.

Normal status does not observe transcript changes. Fields without live correction support show Buffered in a 108pt capsule, or 112pt in continuous mode. A tooltip explains insertion after release or a pause.

Recovery expands to 340pt with a 20pt corner radius, retained text capped at three lines, an explanation, and Copy text and Dismiss buttons. Recovery text is 14pt with head truncation. A 0.16-second ease-out transition respects Reduce Motion.

Setup is a 550pt native window with 30pt padding. It contains English speech, Keyboard access, the hold-key selector, Fn + Space instructions, phrase pause duration, and transcript retention. Permission requests return to this window. Settings and Copy last transcript are also in the menu-bar icon.

Use system fonts, SF Symbols, semantic colors, native controls, and the system appearance. Live corrections modify only Voco's inserted range. Caret movement, document edits, or field changes stop automatic writing. Escape stops capture without removing typed words.
