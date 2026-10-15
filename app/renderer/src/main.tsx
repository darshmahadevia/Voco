import vocoMark from '../../../Resources/Brand/voco-mark.svg';
import { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { AnimatePresence, motion, useAnimationFrame, useMotionValue, useReducedMotion, type Transition } from 'motion/react';
import {
  ArrowLeft,
  Home,
  FileText,
  ChartNoAxesColumn,
  Globe,
  ArrowRight,
  Settings2,
  Check,
  Copy,
  ExternalLink,
  FolderOpen,
  Info,
  Keyboard,
  LoaderCircle,
  Mic,
  Search,
  RotateCw,
  X,
} from 'lucide-react';
import {
  type AppState,
  type Command,
  type Preferences,
  type OutputMode,
  navigationPageSchema,
  type NavigationPage,
} from '../../shared/protocol';
import { speechModels } from '../../shared/models';
import { initialState, isReady, isSetupComplete } from '../../shared/state';
import { ProgressDashboard, UsageTotals } from './ProgressDashboard';
import { sampleUsage } from '../../shared/usage';
import { retainTranscripts, type RecentTranscript } from './recent-transcripts';
import './styles.css';

type PreviewScenario = 'setup' | 'ready' | 'downloading' | 'recovery' | 'listening' | 'finishing' | 'polishing' | 'silent';
type AppPage = 'auto' | NavigationPage;

const query = new URLSearchParams(window.location.search);
const view = query.get('view') === 'pill' ? 'pill' : 'settings';
const previewScenario = parsePreviewScenario(query.get('preview'));
const preview = window.voco === undefined;
const previewState = createPreviewState(previewScenario);
document.documentElement.dataset.view = view;

const PILL_RECOVERY_TRANSITION = {
  type: 'spring',
  stiffness: 380,
  damping: 32,
  mass: 0.8,
} satisfies Transition;

function parsePreviewScenario(value: string | null): PreviewScenario {
  switch (value) {
    case 'ready':
    case 'downloading':
    case 'recovery':
    case 'listening':
    case 'finishing':
    case 'polishing':
    case 'silent':
      return value;
    default:
      return 'setup';
  }
}

function createPreviewState(scenario: PreviewScenario): AppState {
  const ready = {
    ...initialState,
    userName: 'Alex',
    usage: query.get('progress') === 'empty' ? initialState.usage : sampleUsage(),
    model: { kind: 'ready' },
    models: initialState.models.map((entry) => entry.id === initialState.selectedModel
      ? { ...entry, state: { kind: 'ready' as const } }
      : entry),
    permissions: { microphone: 'granted', accessibility: true, shortcut: true },
  } satisfies AppState;

  switch (scenario) {
    case 'ready':
      return ready;
    case 'downloading':
      return {
        ...initialState,
        model: { kind: 'downloading', progress: 0.42, file: 'encoder.bin' },
        models: initialState.models.map((entry) => entry.id === initialState.selectedModel
          ? { ...entry, state: { kind: 'downloading' as const, progress: 0.42, file: 'encoder.bin' } }
          : entry),
        permissions: { microphone: 'granted', accessibility: true, shortcut: true },
      };
    case 'recovery':
      return {
        ...ready,
        session: {
          kind: 'recovery',
          message: 'Voco could not finish writing this transcript.',
          text: 'Could you send me the notes from our meeting?',
        },
      };
    case 'finishing':
      return { ...ready, session: { kind: 'finishing' } };
    case 'polishing':
      return { ...ready, session: { kind: 'polishing' } };
    case 'silent':
      return { ...ready, session: { kind: 'listening' } };
    case 'listening':
      return {
        ...ready,
        session: { kind: 'listening' },
        audioLevel: 0.65,
        audioWaveform: [0.035, 0.09, 0.04, 0.16, 0.08, 0.28, 0.19, 0.12, 0.24, 0.06, 0.11],
      };
    case 'setup':
      return initialState;
  }
}

function useAppState(): { state: AppState | null; transcripts: RecentTranscript[]; error: string } {
  const [state, setState] = useState<AppState | null>(preview ? previewState : null);
  const [error, setError] = useState('');
  const [transcripts, setTranscripts] = useState<RecentTranscript[]>(() => preview && previewScenario !== 'setup' && query.get('progress') !== 'empty' ? [
    'Could you send me the notes from our meeting? I would like to review them before tomorrow.',
    'A quick reminder to update the project timeline and share the latest draft with the team.',
    'Writing feels a little easier when I can just say what I am thinking.',
    'Let’s find a time to catch up next week.',
  ].map((text, index) => ({ id: 4 - index, text, createdAt: Date.now() - index * 3_600_000 })) : []);

  useEffect(() => {
    const api = window.voco;
    if (!api) return;

    let active = true;
    let eventCount = 0;
    let previous: AppState | null = null;
    const receive = (nextState: AppState): void => {
      const prior = previous;
      previous = nextState;
      setTranscripts(entries => retainTranscripts({ entries, previous: prior, next: nextState, now: Date.now() }));
      setState(nextState);
    };
    const unsubscribe = api.subscribe((nextState) => {
      eventCount += 1;
      receive(nextState);
      setError('');
    });
    const eventCountAtRead = eventCount;
    void api.getState().then((nextState) => {
      if (active && eventCount === eventCountAtRead && nextState) receive(nextState);
    }).catch((caught: unknown) => {
      if (!active || eventCount !== eventCountAtRead) return;
      setError(caught instanceof Error ? caught.message : 'Voco could not read its current state.');
    });

    return () => {
      active = false;
      unsubscribe();
    };
  }, []);

  return { state, transcripts, error };
}

function useCommands(): {
  run: (command: Command) => Promise<void>;
  pending: Command['kind'] | null;
  error: string;
} {
  const [pending, setPending] = useState<Command['kind'] | null>(null);
  const [error, setError] = useState('');
  const busyRef = useRef(false);

  async function run(command: Command): Promise<void> {
    const api = window.voco;
    if (!api || busyRef.current) return;

    busyRef.current = true;
    setPending(command.kind);
    setError('');
    try {
      await api.command(command);
    } catch (caught: unknown) {
      setError(caught instanceof Error ? caught.message : 'Voco could not complete that action.');
    } finally {
      busyRef.current = false;
      setPending(null);
    }
  }

  return { run, pending, error };
}

function PreviewNotice(): React.JSX.Element | null {
  if (!preview) return null;
  const scenarioLabel = previewScenario === 'setup' ? 'setup' : `${previewScenario} state`;

  return (
    <div className="preview-notice" role="note">
      <span className="preview-dot" aria-hidden="true" />
      <span>Interface preview · {scenarioLabel}. Native actions are inactive.</span>
    </div>
  );
}

const NAVIGATION_ITEMS: Record<NavigationPage, { label: string; icon: React.ReactNode }> = {
  home: { label: 'Home', icon: <Home size={17} aria-hidden="true" /> },
  transcripts: { label: 'Transcripts', icon: <FileText size={17} aria-hidden="true" /> },
  stats: { label: 'Stats', icon: <ChartNoAxesColumn size={17} aria-hidden="true" /> },
  settings: { label: 'Settings', icon: <Settings2 size={17} aria-hidden="true" /> },
  onboarding: { label: 'Set up Voco', icon: <Mic size={17} aria-hidden="true" /> },
};

function AppSidebar({
  currentPage,
  showSetup,
  onNavigate,
}: {
  currentPage: NavigationPage;
  showSetup: boolean;
  onNavigate: (page: NavigationPage) => void;
}): React.JSX.Element {
  const navigationPages: NavigationPage[] = showSetup ? ['home', 'onboarding', 'transcripts', 'stats'] : ['home', 'transcripts', 'stats'];
  return <aside className="app-sidebar" aria-label="Voco workspace">
    <div className="sidebar-titlebar window-drag" aria-hidden="true" />
    <div className="sidebar-brand" aria-label="Voco">
      <img className="brand-icon" src={vocoMark} alt="" aria-hidden="true" />
      <span className="wordmark">voco<span className="wordmark-dot">.</span></span>
    </div>
    <nav className="sidebar-navigation" aria-label="Main navigation">
      {navigationPages.map((page) => {
        const item = NAVIGATION_ITEMS[page];
        return <button
          key={page}
          className={currentPage === page ? 'nav-item active' : 'nav-item'}
          type="button"
          aria-label={item.label}
          title={item.label}
          aria-current={currentPage === page ? 'page' : undefined}
          onClick={() => onNavigate(page)}
        >
          {item.icon}
          <span>{item.label}</span>
          {page === 'onboarding' && <span className="nav-dot" aria-hidden="true" />}
        </button>;
      })}
    </nav>
    <div className="sidebar-spacer" />
    <button className={`nav-item nav-settings${currentPage === 'settings' ? ' active' : ''}`} type="button" aria-label="Settings" title="Settings" aria-current={currentPage === 'settings' ? 'page' : undefined} onClick={() => onNavigate('settings')}>
      {NAVIGATION_ITEMS.settings.icon}<span>Settings</span>
    </button>
  </aside>;
}

function ActionError({ message }: { message: string }): React.JSX.Element | null {
  if (!message) return null;
  return <p className="action-error" role="alert">{message}</p>;
}

const OUTPUT_MODES = [
  { id: 'fast', name: 'Fast', description: 'Paste the speech model’s words without a cleanup pass.' },
  { id: 'balanced', name: 'Balanced', description: 'Remove fillers, tidy their punctuation, and apply spoken restarts locally.' },
  { id: 'accurate', name: 'Accurate', description: 'Start with Balanced, then add on-device AI formatting. Keep basic cleanup if AI cannot finish.' },
] satisfies { id: OutputMode; name: string; description: string }[];

function SettingsView({ state, loadError }: { state: AppState; loadError: string }): React.JSX.Element {
  const { run, pending, error } = useCommands();
  const ready = isReady(state);
  const canCopyLast = state.preferences.keepLastTranscript && state.lastTranscript.length > 0;

  return (
    <main className="settings-shell">
      <header className="settings-header">
        <div><h1>Settings</h1><p className="intro-copy">Make Voco work for you. Changes apply immediately.</p></div>
      </header>

      <section className="settings-section output-section" aria-labelledby="output-heading">
        <h2 className="section-heading" id="output-heading">Output quality</h2>
        <p className="row-description model-section-note">Speech recognition and cleanup run on your Mac. Choose how Voco prepares your words before pasting.</p>
        <div className="output-options" role="radiogroup" aria-labelledby="output-heading">
          {OUTPUT_MODES.map(mode => <label className="output-option" key={mode.id} data-selected={state.preferences.outputMode === mode.id}>
            <input type="radio" name="output-mode" value={mode.id} checked={state.preferences.outputMode === mode.id}
              disabled={preview || pending !== null || state.session.kind !== 'idle'}
              onChange={() => void updatePreferences(run, state.preferences, { outputMode: mode.id })} />
            <span><strong>{mode.name}</strong><span>{mode.description}</span></span>
          </label>)}
        </div>
        <p className="output-help">Balanced and Accurate remove spoken “um” and “uh” while preserving quotes, code, links, and units. Say “never mind” to restart the current sentence. Earlier completed sentences stay. Use Fast for literal dictation.</p>
        <p className="output-availability" role="status">{state.polishing.message} {state.polishing.kind === 'unavailable' && 'Accurate still applies Balanced cleanup when AI formatting is unavailable.'}</p>
        <p className="output-help">Cleanup can make mistakes. Review important text. Your selected speech model is used in every mode.</p>
      </section>

      <section className="settings-section" aria-labelledby="model-heading">
        <h2 className="section-heading" id="model-heading">Speech model</h2>
        <p className="row-description model-section-note">Choose which model Voco uses. Downloaded models stay available on this Mac.</p>
        <ModelChoices state={state} pending={pending} run={run} />
      </section>

      <section className="settings-section" aria-labelledby="access-heading">
        <h2 className="section-heading" id="access-heading">Access</h2>
        <PermissionRow
          icon={<Mic size={17} aria-hidden="true" />}
          title="Microphone"
          description="Needed to hear your dictation."
          status={microphoneStatus(state.permissions.microphone)}
          statusKind={state.permissions.microphone === 'granted' ? 'good' : 'neutral'}
        >
          {state.permissions.microphone === 'required' && (
            <Button disabled={preview || pending !== null} onClick={() => void run({ kind: 'requestMicrophone' })}>
              {pending === 'requestMicrophone' ? 'Opening…' : 'Allow'}
            </Button>
          )}
          {state.permissions.microphone === 'denied' && (
            <Button kind="secondary" disabled={preview || pending !== null} onClick={() => void run({ kind: 'openPrivacy', pane: 'microphone' })}>
              Open Settings <ExternalLink size={13} aria-hidden="true" />
            </Button>
          )}
        </PermissionRow>

        <PermissionRow
          icon={<Keyboard size={17} aria-hidden="true" />}
          title="Keyboard access"
          description="Allow your talk key and writing into other apps."
          status={keyboardStatus(state)}
          statusKind={state.permissions.accessibility && state.permissions.shortcut ? 'good' : 'neutral'}
        >
          {!state.permissions.accessibility && (
            <Button disabled={preview || pending !== null} onClick={() => void run({ kind: 'requestAccessibility' })}>
              {pending === 'requestAccessibility' ? 'Opening…' : 'Allow'}
            </Button>
          )}
          {state.permissions.accessibility && !state.permissions.shortcut && (
            <Button disabled={preview || pending !== null} onClick={() => void run({ kind: 'restart' })}>
              <RotateCw size={13} aria-hidden="true" /> Restart
            </Button>
          )}
        </PermissionRow>

        {!state.permissions.accessibility && (
          <details className="manual-access-help">
            <summary>Keyboard access still says off?</summary>
            <p>macOS may keep approval for an earlier Voco build. Remove the old Voco entry in Privacy &amp; Security, then add this copy from Finder and enable it.</p>
            <div className="manual-access-actions">
              <Button kind="quiet" disabled={preview || pending !== null} onClick={() => void run({ kind: 'openPrivacy', pane: 'accessibility' })}>
                Open Settings <ExternalLink size={13} aria-hidden="true" />
              </Button>
              <Button kind="quiet" disabled={preview || pending !== null} onClick={() => void run({ kind: 'showApp' })}>
                <FolderOpen size={14} aria-hidden="true" /> Show app in Finder
              </Button>
            </div>
          </details>
        )}
      </section>

      <section className="settings-section dictation-section" aria-labelledby="dictation-heading">
        <h2 className="section-heading" id="dictation-heading">Dictation</h2>
        <SettingRow title="Dictation shortcut" description="Hold Fn / Globe and release to paste. Or press Fn + Space to start, then again to paste.">
          <kbd>Fn / Globe</kbd>
        </SettingRow>
        <SettingRow title="Keep recent transcripts" description="Keep this session’s transcripts in memory until you quit. Turning this off clears them.">
          <button
            className="switch"
            type="button"
            role="switch"
            aria-checked={state.preferences.keepLastTranscript}
            aria-label="Keep recent transcripts"
            disabled={preview || pending !== null}
            onClick={() => void updatePreferences(run, state.preferences, { keepLastTranscript: !state.preferences.keepLastTranscript })}
          >
            <span className="switch-thumb" />
          </button>
        </SettingRow>
        {canCopyLast && (
          <div className="copy-last-row">
            <span>Latest transcript held in memory</span>
            <Button kind="quiet" disabled={preview || pending !== null} onClick={() => void run({ kind: 'copyLast' })}>
              <Copy size={14} aria-hidden="true" /> Copy last transcript
            </Button>
          </div>
        )}
      </section>

      <ActionError message={error || loadError} />
      {ready && (
        <footer className="settings-footer">
          <span className="dictation-status" data-ready="true" role="status">
            <Mic size={14} aria-hidden="true" /> Ready to dictate
          </span>
          <span className="settings-shortcut">Hold <kbd>Fn / Globe</kbd> to speak</span>
        </footer>
      )}
    </main>
  );
}


function microphoneStatus(status: AppState['permissions']['microphone']): string {
  switch (status) {
    case 'required': return 'Permission needed';
    case 'denied': return 'Permission off';
    case 'granted': return 'Allowed';
  }
}

function keyboardStatus(state: AppState): string {
  if (!state.permissions.accessibility) return 'Permission needed';
  if (!state.permissions.shortcut) return 'Restart needed';
  return 'Allowed';
}

type SpeechModelState = AppState['models'][number]['state'];

function ModelStatus({ model, selected }: { model: SpeechModelState | undefined; selected: boolean }): React.JSX.Element {
  if (!model) return <p className="model-status">Status unavailable</p>;
  switch (model.kind) {
    case 'missing':
      return <p className="model-status">Not downloaded</p>;
    case 'installed':
      return <p className="model-status">{selected ? 'Selected · not loaded' : 'Downloaded'}</p>;
    case 'downloading':
      return <p className="model-status">Downloading speech model…</p>;
    case 'loading':
      return <p className="model-status"><LoaderCircle className="spin" size={13} aria-hidden="true" /> Loading model…</p>;
    case 'ready':
      return <p className="model-status status-good">{selected ? 'Active and ready' : 'Ready to use'}</p>;
    case 'error':
      return <p className="model-status status-error">{model.message}</p>;
  }
}

function ModelChoices({
  state,
  pending,
  run,
  onboarding = false,
}: {
  state: AppState;
  pending: Command['kind'] | null;
  run: (command: Command) => Promise<void>;
  onboarding?: boolean;
}): React.JSX.Element {
  const downloading = state.model.kind === 'downloading' || state.models.some((entry) => entry.state.kind === 'downloading');
  const loading = state.model.kind === 'loading' || state.models.some((entry) => entry.state.kind === 'loading');
  const captureActive = state.session.kind === 'starting' || state.session.kind === 'listening' || state.session.kind === 'finishing' || state.session.kind === 'polishing';
  const canSelect = !preview && pending === null && !loading && !captureActive;
  const canDownload = !preview && pending === null && !downloading && !loading;

  const definitions = onboarding
    ? [...speechModels].sort((a, b) => Number(b.id === state.recommendedModel) - Number(a.id === state.recommendedModel))
    : speechModels;
  const rows = definitions.map((definition) => {
      const selected = definition.id === state.selectedModel;
      const modelState = selected
        ? state.model
        : state.models.find((entry) => entry.id === definition.id)?.state;
      const recommended = state.recommendedModel === definition.id;
      const activeFailureNeedsRestart = selected && modelState?.kind === 'error' && modelState.recovery === 'restart';

      let action: React.ReactNode = null;
      if (modelState?.kind === 'downloading') {
        action = <Button kind="secondary" disabled={preview || pending !== null} ariaLabel={`Cancel ${definition.name} download`} onClick={() => void run({ kind: 'cancelDownload' })}>Cancel</Button>;
      } else if (activeFailureNeedsRestart) {
        action = <Button disabled={preview || pending !== null} onClick={() => void run({ kind: 'restart' })}>Restart Voco</Button>;
      } else if (selected && modelState?.kind === 'ready') {
        action = <span className="model-current"><Check size={13} aria-hidden="true" /> In use</span>;
      } else if (selected && modelState?.kind === 'installed') {
        action = <Button disabled={!canSelect} onClick={() => void run({ kind: 'selectModel', modelId: definition.id })}>{pending === 'selectModel' ? 'Switching…' : 'Load model'}</Button>;
      } else if (!selected && (modelState?.kind === 'installed' || modelState?.kind === 'ready')) {
        action = <Button disabled={!canSelect} onClick={() => void run({ kind: 'selectModel', modelId: definition.id })}>{pending === 'selectModel' ? 'Switching…' : 'Use model'}</Button>;
      } else if (modelState?.kind === 'missing' || modelState?.kind === 'error') {
        action = <Button disabled={!canDownload} ariaLabel={`${modelState.kind === 'error' ? 'Retry' : 'Download'} ${definition.name}`} onClick={() => void run({ kind: 'downloadModel', modelId: definition.id })}>{pending === 'downloadModel' ? 'Starting…' : modelState.kind === 'error' ? 'Try again' : 'Download'}</Button>;
      } else if (selected) {
        action = <span className="model-current">Selected</span>;
      }

      return <div className="model-row" key={definition.id} data-model-id={definition.id}>
        <div className="model-copy">
          <div className="model-name-line">
            <p className="row-title">{definition.name}</p>
            <span className="model-version">{definition.version}</span>
            {recommended && <span className="model-recommended">Recommended</span>}
          </div>
          <p className="row-description">{definition.description}</p>
          <ModelStatus model={modelState} selected={selected} />
        </div>
        <div className="model-actions">{action}</div>
        {modelState?.kind === 'downloading' && <div className="download-progress">
          <progress value={modelState.progress} max={1} aria-label={`${definition.name} download progress`} />
          <span>{Math.round(modelState.progress * 100)}%</span>
        </div>}
      </div>;
    });
  return <div className="model-list">{rows}</div>;
}

function PermissionRow({
  icon,
  title,
  description,
  status,
  statusKind,
  children,
}: {
  icon: React.ReactNode;
  title: string;
  description: string;
  status: string;
  statusKind: 'good' | 'neutral';
  children?: React.ReactNode;
}): React.JSX.Element {
  return (
    <div className="permission-row">
      <span className="permission-icon">{icon}</span>
      <div className="permission-copy">
        <p className="row-title">{title}</p>
        <p className="row-description">{description}</p>
        <span className={`permission-status status-${statusKind}`}>{status}</span>
      </div>
      {children && <div className="permission-action">{children}</div>}
    </div>
  );
}

function SettingRow({
  title,
  description,
  children,
}: {
  title: string;
  description: string;
  children: React.ReactNode;
}): React.JSX.Element {
  return (
    <div className="setting-row">
      <div>
        <p className="row-title">{title}</p>
        <p className="row-description">{description}</p>
      </div>
      {children}
    </div>
  );
}

type ButtonKind = 'primary' | 'secondary' | 'quiet';

function Button({
  children,
  kind = 'primary',
  disabled = false,
  onClick,
  ariaLabel,
}: {
  children: React.ReactNode;
  kind?: ButtonKind;
  disabled?: boolean;
  onClick: () => void;
  ariaLabel?: string;
}): React.JSX.Element {
  return (
    <button className={`button button-${kind}`} type="button" disabled={disabled} onClick={onClick} aria-label={ariaLabel}>
      {children}
    </button>
  );
}

async function updatePreferences(
  run: (command: Command) => Promise<void>,
  current: Preferences,
  patch: Partial<Preferences>,
): Promise<void> {
  await run({ kind: 'setPreferences', preferences: { ...current, ...patch } });
}

function PillView({ state, loadError }: { state: AppState; loadError: string }): React.JSX.Element {
  const { run, pending, error } = useCommands();
  const reducedMotion = useReducedMotion();
  const session = state.session;

  return (
    <main className="pill-shell">
      {preview && <PreviewNotice />}
      <AnimatePresence mode="wait" initial={false}>
        <motion.section
          key={session.kind === 'recovery' ? 'recovery' : 'status'}
          className={`pill-card ${session.kind === 'recovery' ? 'pill-card-recovery' : ''}`}
          layout
          initial={reducedMotion ? false : { opacity: 0, y: 7, scale: 0.98 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={reducedMotion ? { opacity: 0 } : { opacity: 0, y: -5, scale: 0.985 }}
          transition={reducedMotion ? { duration: 0 } : PILL_RECOVERY_TRANSITION}
        >
          {session.kind === 'recovery' ? (
            <RecoveryContent session={session} preview={preview} pending={pending} run={run} error={error || loadError} />
          ) : (
            <PillStatus state={state} />
          )}
        </motion.section>
      </AnimatePresence>
      {session.kind !== 'recovery' && <ActionError message={error || loadError} />}
    </main>
  );
}

const WAVE_PROFILE = [0.28, 0.55, 0.82, 0.46, 1, 0.7, 0.92, 0.5, 0.76, 0.38, 0.6];
const SILENT_WAVE = WAVE_PROFILE.map(() => 0);

function balancedWaveform(samples: readonly number[], gain: number): number[] {
  const voices = [0, 1, 2, 3, 4].map(index => {
    const high = index === 4
      ? ((samples[9] ?? 0) + (samples[10] ?? 0)) / 2
      : samples[index + 5] ?? 0;
    return 0.65 * (samples[index] ?? 0) + 0.35 * high;
  });
  const peak = Math.max(...voices);
  if (peak === 0) return SILENT_WAVE;
  const amplitude = Math.sqrt(1 - Math.exp(-peak * gain));
  const heights = voices.map(voice => amplitude * (0.38 + 0.62 * voice / peak));
  return [0, 3, 1, 4, 2, 5, 3, 0, 4, 2, 1].map(index => index === 5 ? amplitude : heights[index] ?? 0);
}

function WaveformBar({ target, index, reducedMotion }: { target: number; index: number; reducedMotion: boolean }): React.JSX.Element {
  const scaleY = useMotionValue(target);
  useEffect(() => {
    if (reducedMotion) scaleY.set(target);
  }, [reducedMotion, scaleY, target]);
  useAnimationFrame((_time, delta) => {
    if (reducedMotion) return;
    const current = scaleY.get();
    if (current === target) return;
    const response = target > current ? 40 + (index % 4) * 6 : 85 + (index % 3) * 7;
    const next = current + (target - current) * (1 - Math.exp(-delta / response));
    scaleY.set(Math.abs(next - target) < 0.001 ? target : next);
  });
  return <motion.span style={{ scaleY }}><span className="waveform-energy" /></motion.span>;
}

function Waveform({ level, size, active = false, state }: { level: number; size: 'pill' | 'large'; active?: boolean; state?: AppState }): React.JSX.Element {
  const reducedMotion = useReducedMotion();
  const pill = size === 'pill';
  const samples = active ? state?.audioWaveform ?? SILENT_WAVE : SILENT_WAVE;
  const moving = samples.some(sample => sample > 0);
  const energies = active
    ? balancedWaveform(samples, pill ? 5 : 3)
    : WAVE_PROFILE.map(height => pill ? 0 : Math.sqrt(level) * height);
  const fullHeight = pill ? 32 : 52;
  const baseline = pill ? 1 : 3;
  return <span className={`waveform waveform-${size} ${moving ? 'waveform-active' : ''}`} aria-hidden="true">
    {energies.map((energy, index) => <WaveformBar
      key={index}
      index={index}
      target={(baseline + energy * (fullHeight - baseline)) / fullHeight}
      reducedMotion={Boolean(reducedMotion)}
    />)}
  </span>;
}

function PillStatus({ state }: { state: AppState }): React.JSX.Element {
  const { session } = state;
  let title: string;
  switch (session.kind) {
    case 'idle': title = isReady(state) ? 'Ready' : 'Finish setup'; break;
    case 'starting': title = 'Starting…'; break;
    case 'listening': title = 'Listening…'; break;
    case 'finishing': title = 'Transcribing…'; break;
    case 'polishing': title = 'Polishing…'; break;
    case 'recovery': title = 'Words saved'; break;
  }
  const processing = session.kind === 'starting' || session.kind === 'finishing' || session.kind === 'polishing';
  return <div className="pill-status" role="status" aria-live="polite">
    {processing ? <LoaderCircle className="spin pill-loader" size={18} aria-hidden="true" /> : <Waveform size="pill" state={state} level={session.kind === 'listening' ? state.audioLevel : 0} active={session.kind === 'listening'} />}
    <p className="pill-title">{title}</p>
  </div>;
}

function HomeView({ state, transcripts, loadError, onSetup, onTranscripts, onStats }: { state: AppState; transcripts: RecentTranscript[]; loadError: string; onSetup: () => void; onTranscripts: () => void; onStats: () => void }): React.JSX.Element {
  const ready = isReady(state);
  const setupComplete = isSetupComplete(state);
  const { run, pending, error } = useCommands();
  let status: string;
  switch (state.session.kind) {
    case 'listening': status = 'Listening'; break;
    case 'starting': status = 'Starting'; break;
    case 'finishing': status = 'Transcribing'; break;
    case 'polishing': status = 'Polishing locally'; break;
    case 'recovery': status = 'Transcript needs attention'; break;
    case 'idle': status = ready ? 'Ready to dictate' : setupComplete ? 'Loading speech model' : 'Setup needed'; break;
  }
  return <main className="dashboard">
    <div className="dashboard-overview">
    <section className="home-hero" aria-labelledby="home-heading">
      <h1 id="home-heading">{state.userName ? <>Hello, <span className="user-name">{state.userName}</span></> : 'Welcome to Voco'}</h1>
      <span className="dashboard-ready dictation-status" data-ready={ready && state.session.kind === 'idle'} role="status" aria-live="polite">
        {state.session.kind === 'starting' || state.session.kind === 'finishing' || state.session.kind === 'polishing' || (setupComplete && !ready)
          ? <LoaderCircle className="spin" size={14} aria-hidden="true" />
          : state.session.kind === 'recovery' || !ready ? <Info size={14} aria-hidden="true" /> : <Mic size={14} aria-hidden="true" />}
        {status}
      </span>
      <p className="hero-shortcut"><span>Hold</span><kbd>Fn <Globe size={16} aria-hidden="true" /></kbd><span>to speak. Release to paste.</span><span className="shortcut-alternative">Fn + Space to toggle</span></p>
      {!setupComplete && <button className="button button-primary setup-button" type="button" onClick={onSetup}>Finish setting up <ArrowRight size={16} /></button>}
    </section>
    {state.session.kind === 'recovery' && <div className="home-recovery"><RecoveryContent session={state.session} preview={preview} pending={pending} run={run} error={error || loadError} /></div>}
    <div className="dashboard-summary">
      <UsageTotals usage={state.usage} />
      <button type="button" className="text-link activity-link" onClick={onStats}>All stats <ArrowRight size={14} aria-hidden="true" /></button>
    </div>
    </div>
    {state.polishNotice && <p className="output-notice" role="status">{state.polishNotice}</p>}
    <TranscriptPanel entries={state.preferences.keepLastTranscript ? transcripts : []} latestText={state.lastTranscript} enabled={state.preferences.keepLastTranscript} onShowMore={onTranscripts} />
    {state.preferences.keepLastTranscript && state.lastRawTranscript && state.lastRawTranscript !== state.lastTranscript && <details className="original-transcript">
      <summary>Original speech transcript</summary>
      <p>{state.lastRawTranscript}</p>
      <CopyTranscriptButton text={state.lastRawTranscript} disabled={preview} latest={false} />
    </details>}
    {state.session.kind !== 'recovery' && <ActionError message={error || loadError} />}
  </main>;
}

type TranscriptCopyState =
  | { kind: 'idle' }
  | { kind: 'copying'; text: string }
  | { kind: 'copied'; text: string }
  | { kind: 'error'; text: string; message: string };

function TranscriptPanel({ entries, latestText, enabled, fullPage = false, onShowMore }: { entries: RecentTranscript[]; latestText: string; enabled: boolean; fullPage?: boolean; onShowMore?: () => void }): React.JSX.Element {
  const [search, setSearch] = useState('');
  const filtered = entries.filter(entry => entry.text.toLocaleLowerCase().includes(search.trim().toLocaleLowerCase()));
  const visible = fullPage ? filtered : entries.slice(0, 3);
  return <section className="transcript-panel" aria-labelledby="transcript-panel-heading">
    <div className="transcript-panel-header">
      <div className="transcript-heading-copy">
        <h2 id="transcript-panel-heading" tabIndex={-1}>Recent transcripts</h2>
        <span className="transcript-panel-status">{preview ? 'Sample transcripts · preview' : enabled ? 'Kept in memory until you quit' : 'Off in Settings'}</span>
      </div>
      <span className="transcript-count">{entries.length} {entries.length === 1 ? 'transcript' : 'transcripts'}</span>
    </div>
    {fullPage && entries.length > 0 && <label className="transcript-search"><Search size={16} aria-hidden="true" /><span className="visually-hidden">Search transcripts</span><input type="search" value={search} onChange={event => setSearch(event.target.value)} placeholder="Search this session" /></label>}
    {entries.length ? <><ol className="recent-transcript-list" id="recent-transcript-list">
      {visible.map((entry, index) => <li className="recent-transcript-row" key={entry.id}>
        <div className="recent-transcript-copy">
          <p className="last-transcript">{entry.text}</p>
          <div className="transcript-metadata"><span>{fullPage ? new Date(entry.createdAt).toLocaleString(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) : index === 0 ? 'Latest' : new Date(entry.createdAt).toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })}</span><span>{entry.text.trim().split(/\s+/).length} words</span></div>
        </div>
        <CopyTranscriptButton text={entry.text} disabled={false} latest={index === 0 && entry.text === latestText} />
      </li>)}
    </ol>{visible.length === 0 && <p className="transcript-search-empty" role="status">No transcripts match your search.</p>}</> : <div className="transcript-body transcript-empty">
      <FileText size={24} strokeWidth={1.4} aria-hidden="true" />
      <p className="transcript-empty-copy">{enabled ? 'Your dictations will appear here. Hold Fn / Globe to start.' : 'Turn on Keep recent transcripts in Settings to see them here.'}</p>
    </div>}
    {!fullPage && entries.length > 3 && <button type="button" className="show-transcripts" onClick={onShowMore}>
      View all {entries.length} transcripts<ArrowRight size={15} aria-hidden="true" />
    </button>}
  </section>;
}

function TranscriptsView({ state, transcripts, loadError }: { state: AppState; transcripts: RecentTranscript[]; loadError: string }): React.JSX.Element {
  return <main className="detail-page transcripts-page">
    <header className="detail-page-heading"><h1 tabIndex={-1}>Transcripts</h1><p>All your dictations from this session, ready to read and copy.</p></header>
    <TranscriptPanel entries={state.preferences.keepLastTranscript ? transcripts : []} latestText={state.lastTranscript} enabled={state.preferences.keepLastTranscript} fullPage />
    <ActionError message={loadError} />
  </main>;
}

function StatsView({ state, loadError }: { state: AppState; loadError: string }): React.JSX.Element {
  const { run, pending, error } = useCommands();
  return <main className="detail-page stats-page">
    <header className="detail-page-heading"><h1 tabIndex={-1}>Stats</h1><p>Your dictation activity and progress over time.</p></header>
    <ProgressDashboard usage={state.usage} preview={preview} run={run} pending={pending !== null} />
    <ActionError message={error || loadError} />
  </main>;
}

function CopyTranscriptButton({ text, disabled, latest = true }: { text: string; disabled: boolean; latest?: boolean }): React.JSX.Element {
  const reducedMotion = useReducedMotion();
  const [state, setState] = useState<TranscriptCopyState>({ kind: 'idle' });
  const activeRef = useRef(false);
  const mountedRef = useRef(true);
  const resetTimerRef = useRef<number | null>(null);
  const requestVersionRef = useRef(0);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      if (resetTimerRef.current !== null) window.clearTimeout(resetTimerRef.current);
    };
  }, []);

  useEffect(() => {
    requestVersionRef.current += 1;
    activeRef.current = false;
    if (resetTimerRef.current !== null) {
      window.clearTimeout(resetTimerRef.current);
      resetTimerRef.current = null;
    }
    setState((previous) => previous.kind === 'idle' ? previous : { kind: 'idle' });
  }, [text, disabled]);

  async function copyTranscript(): Promise<void> {
    if (disabled || !text || activeRef.current) return;
    if (resetTimerRef.current !== null) {
      window.clearTimeout(resetTimerRef.current);
      resetTimerRef.current = null;
    }
    const requestVersion = requestVersionRef.current;
    activeRef.current = true;
    setState({ kind: 'copying', text });
    try {
      if (window.voco && latest) {
        await window.voco.command({ kind: 'copyLast' });
      } else if (window.voco) {
        await window.voco.copyTranscript(text);
      } else {
        await navigator.clipboard.writeText(text);
      }
      if (!mountedRef.current || requestVersion !== requestVersionRef.current) return;
      setState({ kind: 'copied', text });
      resetTimerRef.current = window.setTimeout(() => {
        resetTimerRef.current = null;
        if (mountedRef.current && requestVersion === requestVersionRef.current) setState({ kind: 'idle' });
      }, 1800);
    } catch (caught: unknown) {
      if (!mountedRef.current || requestVersion !== requestVersionRef.current) return;
      setState({
        kind: 'error',
        text,
        message: caught instanceof Error && caught.message ? caught.message : 'Could not copy the transcript. Try again.',
      });
    } finally {
      if (requestVersion === requestVersionRef.current) activeRef.current = false;
    }
  }

  const currentState: TranscriptCopyState = state.kind !== 'idle' && state.text !== text ? { kind: 'idle' } : state;
  const label = currentState.kind === 'copying' ? 'Copying…' : currentState.kind === 'copied' ? 'Copied' : currentState.kind === 'error' ? 'Try again' : 'Copy transcript';
  const copied = currentState.kind === 'copied';
  return <div className="copy-transcript-wrap">
    <button
      className="copy-transcript-button"
      type="button"
      data-state={currentState.kind}
      disabled={disabled || state.kind === 'copying'}
      aria-label={label}
      title={label}
      onClick={() => void copyTranscript()}
    >
      <span className="t-icon-swap copy-icon-swap" data-state={copied ? 'b' : 'a'} aria-hidden="true">
        <span className="t-icon" data-icon="a"><Copy size={15} /></span>
        <span className="t-icon" data-icon="b"><Check size={15} /></span>
      </span>
      <span className="copy-button-label-slot" aria-live="polite" aria-atomic="true">
        <AnimatePresence initial={false} mode="wait">
          <motion.span
            className="copy-button-label"
            key={currentState.kind}
            initial={reducedMotion ? false : { opacity: 0, y: 4, filter: 'blur(2px)' }}
            animate={{ opacity: 1, y: 0, filter: 'blur(0px)' }}
            exit={reducedMotion ? { opacity: 0, y: 0, filter: 'blur(0px)' } : { opacity: 0, y: -4, filter: 'blur(2px)' }}
            transition={reducedMotion ? { duration: 0 } : { duration: 0.15, ease: 'easeInOut' }}
          >{label}</motion.span>
        </AnimatePresence>
      </span>
    </button>
    {currentState.kind === 'error' && <p className="copy-transcript-error" role="alert">{currentState.message}</p>}
  </div>;
}

type SetupStep = 'welcome' | 'model' | 'access' | 'practice';
const SETUP_STEPS: { id: SetupStep; title: string }[] = [{ id: 'welcome', title: 'Welcome' }, { id: 'model', title: 'Speech model' }, { id: 'access', title: 'App permissions' }, { id: 'practice', title: 'Your first words' }];

function OnboardingView({ state, loadError, onDone }: { state: AppState; loadError: string; onDone: () => void }): React.JSX.Element {
  const [step, updateStep] = useState<SetupStep>(() => {
    if (preview) return 'welcome';
    try {
      const saved = localStorage.getItem('voco.setup.step.v1');
      return saved === 'model' || saved === 'access' || saved === 'practice' ? saved : 'welcome';
    } catch { return 'welcome'; }
  });
  const [direction, setDirection] = useState(1);
  const practiceText = useRef('');
  const practiceFieldRef = useRef<HTMLTextAreaElement>(null);
  const headingRef = useRef<HTMLHeadingElement>(null);
  const hasNavigated = useRef(false);
  const reducedMotion = useReducedMotion();
  const { run, pending, error } = useCommands();
  const stepIndex = SETUP_STEPS.findIndex(item => item.id === step);

  function setStep(next: SetupStep): void {
    if (next === step) return;
    if (step === 'practice' && practiceFieldRef.current) practiceText.current = practiceFieldRef.current.value;
    setDirection(SETUP_STEPS.findIndex(item => item.id === next) > stepIndex ? 1 : -1);
    hasNavigated.current = true;
    updateStep(next);
    if (!preview) {
      try { localStorage.setItem('voco.setup.step.v1', next); } catch { return; }
    }
  }

  useEffect(() => {
    if (hasNavigated.current) headingRef.current?.focus({ preventScroll: true });
  }, [step]);

  const modelReady = state.model.kind === 'ready';
  const downloadingModel = state.models.find(entry => entry.state.kind === 'downloading');
  const modelInProgress = state.model.kind === 'downloading' || state.model.kind === 'loading' || downloadingModel !== undefined;
  const accessReady = state.permissions.microphone === 'granted' && state.permissions.accessibility && state.permissions.shortcut;
  const keyboardReady = state.permissions.accessibility && state.permissions.shortcut;
  const ready = isReady(state);
  let modelBlockerMessage: string | null;
  switch (state.model.kind) {
    case 'missing': modelBlockerMessage = downloadingModel ? 'The speech model is downloading. You can try dictation when it finishes.' : 'Download the speech model before trying dictation.'; break;
    case 'installed': modelBlockerMessage = 'Load the selected speech model before trying dictation.'; break;
    case 'downloading': modelBlockerMessage = 'The speech model is downloading. You can try dictation when it finishes.'; break;
    case 'loading': modelBlockerMessage = 'The speech model is loading. Your practice field will be ready in a moment.'; break;
    case 'error': modelBlockerMessage = 'The speech model needs attention. Go to the model step to try again or restart Voco.'; break;
    case 'ready': modelBlockerMessage = null; break;
  }
  const practiceBlocker = modelBlockerMessage
    ? { step: 'model', message: modelBlockerMessage, action: 'Go to speech model' } satisfies { step: SetupStep; message: string; action: string }
    : !accessReady
      ? { step: 'access', message: 'Allow microphone and keyboard access before trying dictation.', action: 'Go to app permissions' } satisfies { step: SetupStep; message: string; action: string }
      : null;
  const headings = {
    welcome: 'A little setup.\nA lot less typing.',
    model: 'Choose a\nspeech model.',
    access: 'A few permissions.\nYou are in control.',
    practice: 'Meet your new\nway to write.',
  };
  const descriptions = {
    welcome: 'Voco turns your voice into text, right where you are working. Dictation runs on your Mac.',
    model: 'Start with the recommended model for your Mac, or compare the options. You can change models anytime in Settings.',
    access: 'Voco needs to hear you and write into your apps. macOS asks for your approval for each permission.',
    practice: 'Click the field. Hold Fn / Globe and release to paste, or use Fn + Space to start and stop.',
  };
  const nextLabel = step === 'welcome' ? 'Get started' : step === 'model' ? 'Continue' : step === 'access' ? 'Try dictation' : 'Open Voco';
  const canContinue = step === 'welcome' || (step === 'model' && (modelReady || modelInProgress)) || (step === 'access' && accessReady) || (step === 'practice' && ready);

  function goForward(): void {
    if (!canContinue) return;
    if (step === 'practice') onDone();
    else setStep(SETUP_STEPS[stepIndex + 1]?.id ?? 'practice');
  }

  return <main className="onboarding" onKeyDown={event => {
    if (event.key === 'Enter' && event.target === headingRef.current) {
      event.preventDefault();
      goForward();
    }
  }}>
    <h1 className="visually-hidden">Set up Voco</h1>
    <header className="setup-header"><span className="wordmark">voco<span className="wordmark-dot">.</span></span><span className="setup-count">{SETUP_STEPS[stepIndex]?.title} · {stepIndex + 1} of {SETUP_STEPS.length}</span></header>
    <div className="setup-stage">
      <div className="setup-direction setup-previous">
        <button className="setup-arrow" type="button" aria-label="Previous step" title="Previous step" disabled={step === 'welcome'} onClick={() => setStep(SETUP_STEPS[Math.max(0, stepIndex - 1)]?.id ?? 'welcome')}><ArrowLeft size={16} aria-hidden="true" /><span>Back</span></button>
      </div>
      <motion.div
        key={step}
        className={`onboarding-layout${step === 'model' ? ' onboarding-layout-model' : ''}`}
        initial={hasNavigated.current && !reducedMotion ? { opacity: 0.45, x: direction * 8 } : false}
        animate={{ opacity: 1, x: 0 }}
        transition={{ duration: reducedMotion ? 0 : 0.25, ease: [0.22, 1, 0.36, 1] }}
      >
        <div className="onboarding-copy">
          <h2 ref={headingRef} tabIndex={-1}>{headings[step].split('\n').map((line, index) => <span key={line} className={index ? 'serif-line' : ''}>{line}</span>)}</h2>
          <p>{descriptions[step]}</p>
        </div>
        <section className={`setup-workspace setup-workspace-${step}`} aria-label={SETUP_STEPS[stepIndex]?.title}>
          {step === 'welcome' && <>
            <div className="welcome-shortcut"><kbd>fn <Globe size={16} /></kbd><span>Hold to speak. Release to paste.</span></div>
          </>}
          {step === 'model' && <>
            <h3>Available models</h3>
            <ModelChoices state={state} pending={pending} run={run} onboarding />
          </>}
          {step === 'access' && <>
            <h3>Allow access</h3>
            <PermissionRow icon={<Mic size={18} />} title="Microphone" description="To hear your words." status={microphoneStatus(state.permissions.microphone)} statusKind={state.permissions.microphone === 'granted' ? 'good' : 'neutral'}>
              {state.permissions.microphone !== 'granted' && <Button disabled={preview || pending !== null} onClick={() => void run(state.permissions.microphone === 'denied' ? { kind: 'openPrivacy', pane: 'microphone' } : { kind: 'requestMicrophone' })}>{pending === 'requestMicrophone' ? 'Requesting…' : state.permissions.microphone === 'denied' ? 'Open Settings' : 'Allow'}</Button>}
            </PermissionRow>
            <PermissionRow icon={<Keyboard size={18} />} title="Keyboard access" description="To use your shortcut and insert text." status={keyboardStatus(state)} statusKind={keyboardReady ? 'good' : 'neutral'}>
              {!state.permissions.accessibility ? <Button disabled={preview || pending !== null} onClick={() => void run({ kind: 'requestAccessibility' })}>Allow</Button> : !state.permissions.shortcut ? <Button disabled={preview || pending !== null} onClick={() => void run({ kind: 'restart' })}>Restart Voco</Button> : null}
            </PermissionRow>
            {!state.permissions.accessibility && <p className="setup-note">Turn on Voco in macOS Accessibility settings, then return here.</p>}
            {!state.permissions.accessibility && <details className="access-help">
              <summary>Can’t find Voco in System Settings?</summary>
              <p>Enable Voco in System Settings → Privacy &amp; Security → Accessibility. If it is missing, add the app shown in Finder.</p>
              <Button kind="quiet" disabled={preview || pending !== null} onClick={() => void run({ kind: 'showApp' })}><FolderOpen size={14} /> Show app in Finder</Button>
              <Button kind="quiet" disabled={preview || pending !== null} onClick={() => void run({ kind: 'refresh' })}><RotateCw size={14} /> Check again</Button>
            </details>}
          </>}
          {step === 'practice' && <>
            {practiceBlocker && <div className="practice-blocker" role="status">
              <p>{practiceBlocker.message}</p>
              <Button kind="secondary" onClick={() => setStep(practiceBlocker.step)}>{practiceBlocker.action} <ArrowRight size={15} /></Button>
            </div>}
            <div className="practice-heading"><kbd>fn <Globe size={16} /></kbd><span>Hold to speak, release to paste. Or use Fn + Space to start and stop.</span></div>
            <label className="visually-hidden" htmlFor="practice-text">Try your first dictation</label>
            <textarea ref={practiceFieldRef} id="practice-text" defaultValue={practiceText.current} placeholder="Click here and say something…" disabled={!ready} />
            {preview && <p className="setup-note">Dictation is available in the desktop app.</p>}
            <details className="practice-help">
              <summary>Set up your Fn / Globe key</summary>
              <p>In macOS System Settings → Keyboard, set “Press Globe key to” to “Do Nothing”. Turn off any Apple Dictation shortcut that uses the same key.</p>
            </details>
          </>}
          <ActionError message={error || loadError} />
        </section>
      </motion.div>
      <div className="setup-direction setup-next">
        <button className="setup-arrow setup-arrow-next" type="button" aria-label={nextLabel} title={nextLabel} disabled={!canContinue} onClick={goForward}><span>{nextLabel}</span><ArrowRight size={16} aria-hidden="true" /></button>
      </div>
    </div>
    <footer className="setup-footer">
      <ol className="setup-progress" aria-label="Setup steps">
        {SETUP_STEPS.map(item => <li key={item.id} aria-current={item.id === step ? 'step' : undefined}>
          <span className="visually-hidden">{item.title}</span>
        </li>)}
      </ol>
      {modelReady && <button className="text-link setup-explore" onClick={onDone}>Explore the app</button>}
    </footer>
  </main>;
}

function RecoveryContent({
  session,
  preview: isPreview,
  pending,
  run,
  error = '',
}: {
  session: Extract<AppState['session'], { kind: 'recovery' }>;
  preview: boolean;
  pending: Command['kind'] | null;
  run: (command: Command) => Promise<void>;
  error?: string;
}): React.JSX.Element {
  return (
    <div className="recovery-content">
      <div className="recovery-heading">
        <span className="recovery-icon" aria-hidden="true"><Info size={16} /></span>
        <div>
          <p className="pill-title">Transcript needs attention</p>
        </div>
        <Button kind="quiet" ariaLabel="Dismiss transcript recovery" disabled={isPreview || pending !== null} onClick={() => void run({ kind: 'cancel' })}>
          <X size={16} aria-hidden="true" />
        </Button>
      </div>
      <div className="recovery-body">
        <p className="recovery-message">{session.message}</p>
        {session.text && (
          <div className="recovery-transcript">
            {isPreview && <span className="preview-transcript-label">Example transcript · preview</span>}
            <p>{session.text}</p>
          </div>
        )}
        <ActionError message={error} />
      </div>
      <div className="recovery-actions">
        <Button kind="secondary" disabled={isPreview || pending !== null || session.text.length === 0} onClick={() => void run({ kind: 'copyRecovery' })}>
          <Copy size={14} aria-hidden="true" /> Copy transcript
        </Button>
      </div>
    </div>
  );
}

function StartupView({ error }: { error: string }): React.JSX.Element {
  const { run, pending, error: commandError } = useCommands();
  return <main className="startup-shell">
    <span className="wordmark">voco<span className="wordmark-dot">.</span></span>
    {error ? <><ActionError message={commandError || error} /><Button disabled={pending !== null} onClick={() => void run({ kind: 'restart' })}>Restart Voco</Button></> : <p role="status"><LoaderCircle className="spin" size={15} aria-hidden="true" /> Starting Voco…</p>}
  </main>;
}

function canResumeHome(state: AppState, setupSeen: boolean): boolean {
  const hasActiveModel = state.model.kind === 'ready' || state.model.kind === 'loading';
  return hasActiveModel && (setupSeen || isSetupComplete(state));
}

function App(): React.JSX.Element {
  const { state, transcripts, error } = useAppState();
  const [page, setPage] = useState<AppPage>(() => {
    const requested = navigationPageSchema.safeParse(query.get('page'));
    return requested.success ? requested.data : 'auto';
  });
  const [setupSeen, setSetupSeen] = useState(() => { try { return localStorage.getItem('voco.setup.v1') === 'seen'; } catch { return false; } });
  useEffect(() => {
    if (view === 'pill') return;
    return window.voco?.subscribeNavigation(setPage);
  }, []);
  useEffect(() => {
    if (!state) return;
    setPage(previous => previous === 'auto' ? canResumeHome(state, setupSeen) ? 'home' : 'onboarding' : previous);
  }, [state, setupSeen]);
  useEffect(() => {
    if (view === 'pill' || page === 'auto') return;
    window.scrollTo({ top: 0, behavior: 'instant' });
    document.querySelector('.workspace-main')?.scrollTo({ top: 0, behavior: 'instant' });
    document.querySelector<HTMLElement>('main h1')?.focus({ preventScroll: true });
  }, [page]);
  if (!state) return view === 'pill' ? <main className="pill-shell" /> : <StartupView error={error} />;
  if (view === 'pill') return <PillView state={state} loadError={error} />;
  const currentPage: NavigationPage = page === 'auto' ? canResumeHome(state, setupSeen) ? 'home' : 'onboarding' : page;
  function finishSetup(): void {
    if (!state || state.model.kind !== 'ready') return;
    try { localStorage.setItem('voco.setup.v1', 'seen'); } catch { /* Setup remains accessible without local storage. */ }
    setSetupSeen(true);
    setPage('home');
  }
  return <div className={`desktop-shell${currentPage === 'onboarding' ? ' desktop-shell-onboarding' : ' desktop-shell-workspace'}`}>
    {currentPage !== 'onboarding' && <AppSidebar
      currentPage={currentPage}
      showSetup={!isSetupComplete(state)}
      onNavigate={setPage}
    />}
    <div className="app-content">
      <div className="titlebar window-drag" aria-hidden="true" />
      <div className="workspace-main">
        <PreviewNotice />
        {currentPage === 'settings' ? <SettingsView state={state} loadError={error} /> : currentPage === 'onboarding' ? <OnboardingView state={state} loadError={error} onDone={finishSetup} /> : currentPage === 'transcripts' ? <TranscriptsView state={state} transcripts={transcripts} loadError={error} /> : currentPage === 'stats' ? <StatsView state={state} loadError={error} /> : <HomeView state={state} transcripts={transcripts} loadError={error} onSetup={() => setPage('onboarding')} onTranscripts={() => setPage('transcripts')} onStats={() => setPage('stats')} />}
      </div>
    </div>
  </div>;
}

const rootElement = document.getElementById('root');
if (!rootElement) throw new Error('The Voco renderer root is missing.');
createRoot(rootElement).render(<App />);
