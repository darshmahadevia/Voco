# Candidate A. A focused writing desk

Voco users should see their talk key, their latest words, and their progress without scanning a long column. The proposed Home has a large voice desk beside a compact usage column. Transcripts becomes a session browser. Settings gains a section index and a single readable column of grouped controls.

## Current architecture

`app/shared/protocol.ts` defines and validates `AppState`, `Command`, `NavigationPage`, and the preload `VocoApi`. Native state owns model readiness, capture, permissions, preferences, cleanup availability, and usage. The renderer must treat those values as authoritative.

`main.tsx` chooses the pill or desktop from the URL. `useAppState` subscribes before its initial state read and ignores an older read when a newer subscription event has arrived. It calls `retainTranscripts` to derive session history in renderer memory. Retention off clears history. There is no transcript archive or disk persistence to expose in a redesign.

`App` owns navigation and resolves `auto` to Home or onboarding. It subscribes to native navigation, preserves setup completion separately, resets the content scroll, and attempts to focus the destination heading. `useCommands` sends typed commands and owns pending and error feedback. Views currently create their own command hooks. A visual transition must never become the command owner.

`HomeView` renders the greeting, voice guidance, `PillStatus`, three totals, and recent transcripts. `TranscriptsView` filters session entries and retains copy feedback. `SettingsView` groups output quality, speech models, access, and dictation in one long column. `ModelChoices` already owns the meaningful download, cancel, restart, load, and use-model affordances. Keep it intact.

`ProgressDashboard.tsx` derives metrics from usage and owns calendar year, selected day, goal preferences, and milestones. The calendar already has arrow-key navigation. Keep Stats as a destination and retain its day detail, complete metric set, goal controls, and milestones.

`styles.css` owns graphite tokens, bundled Manrope, rounded controls, responsive sidebar widths, the main scroll container, and several CSS transitions. Motion already owns sidebar selection, arrival, status text, onboarding steps, recovery geometry, and measured waveform smoothing. Current page arrivals re-mount a keyed wrapper. They do not have a coordinated exit. CSS and Motion both affect controls, so explicit property ownership matters.

## Layout proposal

### Home

Use a 148px sidebar at desktop size and 26px content gutters. A small eyebrow says "YOUR VOICE WORKSPACE" above "Good afternoon, Alex." Place readiness beside that heading, rather than inside a second introductory paragraph.

Below the greeting, use a 1.7-to-1 two-column desk. The larger panel has "A thought. Then words.", generous empty space, a large Fn / Globe key, the two existing shortcut instructions, and the real live capsule. The smaller column has flat, divided usage figures. Keep the words-spoken number dominant and label saved time as an estimate. An "All activity" link opens Stats.

Below the desk, show the newest transcript as a wider reading row with metadata and a visible Copy button. Follow it with one compact previous row. The "View session" action opens Transcripts. Place the privacy statement beside the section title. Recovery replaces the normal desk instruction with `RecoveryContent`; its copy and dismiss actions remain visible. Missing readiness gets a named setup action in this same region.

At 720x520, the sidebar becomes 128px, desk padding becomes 18px, greeting becomes 28px, and the Home desk stays about 200px tall. The latest transcript starts in the first viewport. At content widths below 460px, the desk becomes one column and usage becomes one three-cell strip. The page scrolls vertically. Never hide the transcript section merely to fit the first viewport.

### Transcripts

Keep a fixed page header with "This session", the count, privacy copy, and search. At larger sizes, make a 190px list of transcript previews beside a full-text reading pane. The selected entry has a tonal background, timestamp, and word count. The pane has a small metadata header and a visible Copy action. Complete text wraps and remains selectable. Selection is local UI state keyed by `RecentTranscript.id`.

Use native buttons in a labelled navigation list for previews, with `aria-current` on the selected entry. Avoid pretending this is a tab interface with arrow-key behavior unless that behavior is fully implemented. Search filters previews immediately. Keep a selected result if it remains visible; otherwise select the first result. Empty search, retention off, and empty history each get precise copy. At 720px use a 160px preview list. Below 600px window width, render full-text rows in one column rather than creating an extra back stack. Copy remains available on each row.

### Settings

A sticky header shows "Settings" and "Changes apply immediately." A compact section index contains Output, Models, Access, and Dictation. At 960px, it occupies a 104px left column beside a 440px reading column. At 720px, it becomes a horizontal wrapping strip immediately under the heading. These are anchor links into one scrolling page, not conditional panels. Search and a Save action are unnecessary.

Output uses three compact radio rows with short summaries. The currently selected row is lighter graphite with a soft-white radio. Keep full cleanup caveats and availability below the choices, with optional explanatory detail in a disclosure only when it does not conceal active errors or unavailable-state information. Models retains all existing model rows and actions. Access groups microphone and keyboard permission statuses. Dictation groups shortcut guidance and the retention switch, with the exact "Turning this off clears them" consequence beside the switch.

Native settings updates apply on input. Active capture blockers, pending commands, errors, download progress, and restart guidance retain their current semantics. Section links scroll within `.workspace-main` with `scroll-margin-top` for the sticky header. Focus stays on the activated section link during navigation; direct keyboard activation can focus the target heading. Native Settings navigation focuses the page heading.

## Motion ownership

Use Motion for position, opacity, scale, and layout interpolation. Use CSS only for hover color, borders, and focus rings. Remove CSS transform transitions on any button with `whileTap`. No blur on full pages. It reduces text clarity during frequent navigation and is unnecessary for this layout.

The shared navigation background uses the existing spring with stiffness 420 and damping 36. The page boundary performs a 180ms entrance from opacity 0 and y 6. Mount the new page immediately. Do not use `mode="wait"` around commands or native state. Do not keep old interactive pages alongside new pages during exit. Preserve focus and scroll handling after the destination commits, independently of animation completion.

Home desk and settings groups use `layout="position"` only where their height changes. Avoid layout on the entire scrolling app or every transcript row. Status text uses `AnimatePresence initial={false} mode="popLayout"` and a 120ms opacity/y swap. Keep the accessible status text in a stable `role="status"` node so outgoing decorative text is not announced twice. Copy feedback animates after clipboard success, with a fixed-width button to prevent row movement. New transcripts get one 140ms arrival and no repeated stagger when filtering.

Keep the existing waveform sampler and measured-energy smoothing. Silence remains still. Processing uses its actual spinner. Recovery expands the capsule with its existing spring and preserves its independent scrolling text. Reduced motion removes travel, layout springs, repeated decorative animation, and animated scrolling. State and text update immediately.

## Data shape and caller sketch

Reuse `NavigationPage` and `RecentTranscript`; motion is presentation state. A settings section is a separate local identity, not a native navigation destination.

```tsx
type SettingsSection = 'output' | 'models' | 'access' | 'dictation';
type PageMotionProps = {
  page: NavigationPage;
  children: React.ReactNode;
};

function PageMotion({ page, children }: PageMotionProps) {
  const reduced = useReducedMotion();
  return <motion.div key={page}
    initial={reduced ? false : { opacity: 0, y: 6 }}
    animate={{ opacity: 1, y: 0 }}
    transition={{ duration: reduced ? 0 : 0.18, ease: [0.16, 1, 0.3, 1] }}>
    {children}
  </motion.div>;
}

// App still owns navigation and focus. Views still own typed commands.
<PageMotion page={currentPage}>
  <SettingsView state={state} loadError={error} />
</PageMotion>

// Input sends the command immediately. Motion reads the resulting state.
onChange={() => void updatePreferences(run, state.preferences, { outputMode: 'balanced' })}
```

The sketch is illustrative JSX, not a proposal to add a general motion framework. One page wrapper and a few shared transition constants are sufficient. The Model the Domain principle shaped the separate `SettingsSection` identity and reuse of the native page union. The existing protocol remains the source of capture and command truth.

## Verification for implementation

Drive ready, setup, downloading, recovery, listening, silent, finishing, and polishing previews. Inspect 960x720, 720x520, and 390px width. Verify that every Settings section and model action remains reachable. Tab through navigation, settings radios, retention, transcript search, and copy. Confirm the destination heading receives focus. Enable reduced motion and confirm immediate statuses, a still silent waveform, and no movement during navigation. Verify native commands fire once per activation before any transition completes. Verify retention off removes both list and reading-pane text in the same state update.

The static sketch includes Home, Transcripts, and Settings as consecutive viewport studies with inline CSS. Its copy explicitly labels native actions as inactive. No production behavior has changed.
