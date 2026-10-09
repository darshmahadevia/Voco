# Home dashboard, settings, first-run setup, and dictation pill

Mode: Operate. Build path: code-led.

## Direction contract

THESIS: Voco is a focused macOS dictation workspace. Home shows readiness and shortcut guidance. Settings keep configuration together. A four-step setup takes new users to their first dictation.

OWN-WORLD: Use black surfaces, fine gray borders, restrained orange accents, bundled Manrope, and selective Instrument Serif headlines. The app tile and wordmark use a black field with an orange waveform mark.

STORY: Welcome the user, download the speech model, grant microphone and keyboard access, then practice in a text field. From Home, hold Fn / Globe in another app to dictate and release to finish.

STARTUP: Keep a neutral waiting view until the first native state arrives, then choose the initial page once. Route to Home when setup has been seen, or when the model is loading or ready and microphone, accessibility, and shortcut permissions are present. When those permissions are present but the model is still loading, Home shows "Loading speech model" without setup prompts.

VOICE: During listening, the eleven-bar mark scales with the square root of microphone volume, with spring transitions (stiffness 500, damping 32, mass 0.35). Its nested fills pulse independently at staggered intervals only while listening above 0.015. Silence leaves 3px bars. Reduced motion removes the pulse and makes spring transitions immediate.

FIRST VIEWPORT: On desktop, keep the 212px sidebar beside a wide main column. Home pairs its headline and shortcut or setup action with the voice mark, then places the optional latest transcript beside a short usage guide. The privacy note stays visible near the bottom.

FORM: Keep the desktop dashboard and setup flow open and quiet. Use orange for actions, focus, and voice activity. Keep settings sections flat with divider lines. Avoid neon grids, glow effects, and Tron styling.

RESPONSIVE: On smaller screens the sidebar becomes a top bar, dashboard sections stack, and setup content moves to one column.

SETUP: Keep Welcome, Speech model, App permissions, and Your first words visible as steps. The practice step includes an expandable Fn / Globe help section with the macOS Keyboard setting and Apple Dictation conflict guidance.

PREVIEW: Browser previews explain that native actions are inactive and disable permission and dictation controls.

RETENTION: Audio and transcript history are never saved to disk. The optional latest transcript stays in memory until quit; recovery text remains available for copying.
