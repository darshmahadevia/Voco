import vocoMark from '../../../Resources/Brand/voco-mark.svg';
import { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { AnimatePresence, motion, useReducedMotion, type Transition } from 'motion/react';
import {
  ArrowLeft,
  Home,
  Download,
  Globe,
  LockKeyhole,
  ArrowRight,
  Settings2,
  ShieldCheck,
  Check,
  Copy,
  ExternalLink,
  FolderOpen,
  Info,
  Keyboard,
  LoaderCircle,
  Mic,
  RotateCw,
  X,
} from 'lucide-react';
import {
  type AppState,
  type Command,
  type Preferences,
} from '../../shared/protocol';
import { initialState, isReady, isSetupComplete } from '../../shared/state';
import './styles.css';

type PreviewScenario = 'setup' | 'ready' | 'downloading' | 'recovery' | 'listening' | 'finishing' | 'silent';
type AppPage = 'auto' | 'home' | 'settings' | 'onboarding';
type NavigationPage = Exclude<AppPage, 'auto'>;

const query = new URLSearchParams(window.location.search);
const view = query.get('view') === 'pill' ? 'pill' : 'settings';
const previewScenario = parsePreviewScenario(query.get('preview'));
const preview = window.voco === undefined;
const previewState = createPreviewState(previewScenario);
document.documentElement.dataset.view = view;

const READINESS_CHECK = {
  type: 'spring',
  stiffness: 460,
  damping: 30,
  mass: 0.7,
} satisfies Transition;

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
    case 'silent':
      return value;
    default:
      return 'setup';
  }
}

function createPreviewState(scenario: PreviewScenario): AppState {
  const ready = {
    ...initialState,
    model: { kind: 'ready' },
    permissions: { microphone: 'granted', accessibility: true, shortcut: true },
  } satisfies AppState;

  switch (scenario) {
    case 'ready':
      return ready;
    case 'downloading':
      return {
        ...initialState,
        model: { kind: 'downloading', progress: 0.42, file: 'encoder.bin' },
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
    case 'silent':
      return { ...ready, session: { kind: 'listening', mode: 'hold', buffered: false, text: '' } };
    case 'listening':
      return {
        ...ready,
        session: { kind: 'listening', mode: 'hold', buffered: true, text: 'The quick brown fox' },
        audioLevel: 0.65,
      };
    case 'setup':
      return initialState;
  }
}

function useAppState(): { state: AppState | null; error: string } {
  const [state, setState] = useState<AppState | null>(preview ? previewState : null);
  const [error, setError] = useState('');

  useEffect(() => {
    const api = window.voco;
    if (!api) return;

    let active = true;
    let eventCount = 0;
    const unsubscribe = api.subscribe((nextState) => {
      eventCount += 1;
      setState(nextState);
      setError('');
    });
    const eventCountAtRead = eventCount;
    void api.getState().then((nextState) => {
      if (active && eventCount === eventCountAtRead) setState(nextState);
    }).catch((caught: unknown) => {
      if (!active || eventCount !== eventCountAtRead) return;
      setError(caught instanceof Error ? caught.message : 'Voco could not read its current state.');
    });

    return () => {
      active = false;
      unsubscribe();
    };
  }, []);

  return { state, error };
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
  const navigationPages: NavigationPage[] = showSetup ? ['home', 'settings', 'onboarding'] : ['home', 'settings'];
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
    <div className="sidebar-privacy"><LockKeyhole size={14} aria-hidden="true" /><span>Local by design</span></div>
  </aside>;
}

function ActionError({ message }: { message: string }): React.JSX.Element | null {
  if (!message) return null;
  return <p className="action-error" role="alert">{message}</p>;
}

function SettingsView({ state, loadError }: { state: AppState; loadError: string }): React.JSX.Element {
  const { run, pending, error } = useCommands();
  const reducedMotion = useReducedMotion();
  const [closeError, setCloseError] = useState('');
  const ready = isReady(state);
  const canCopyLast = state.preferences.keepLastTranscript && state.lastTranscript.length > 0;

  async function closeSettings(): Promise<void> {
    if (!window.voco || !ready) return;
    try {
      await window.voco.closeSettings();
    } catch (caught: unknown) {
      setCloseError(caught instanceof Error ? caught.message : 'Voco could not close this window.');
    }
  }

  return (
    <main className="settings-shell">
      <header className="settings-header">
        <div><h1>Settings</h1><p className="intro-copy">Model, permissions, and dictation.</p></div>
      </header>

      <section className="settings-section" aria-labelledby="model-heading">
        <h2 className="section-heading" id="model-heading">Speech model</h2>
        <div className="model-row">
          <div className="model-copy">
            <p className="row-title">Moonshine Medium Streaming</p>
            <p className="row-description">English · downloads once, then works offline</p>
            <ModelStatus model={state.model} />
          </div>
          <ModelAction model={state.model} pending={pending} run={run} />
        </div>
        {state.model.kind === 'downloading' && (
          <div className="download-progress">
            <progress value={state.model.progress} max={1} aria-label="Speech model download progress" />
            <span>{Math.round(state.model.progress * 100)}%</span>
          </div>
        )}
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
        <SettingRow title="Dictation shortcut" description="Hold Fn / Globe to dictate, then release to finish.">
          <kbd>Fn / Globe</kbd>
        </SettingRow>
        <SettingRow title="Keep last transcript" description="Keep your latest words in memory until you quit.">
          <button
            className="switch"
            type="button"
            role="switch"
            aria-checked={state.preferences.keepLastTranscript}
            aria-label="Keep last transcript"
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

      <ActionError message={error || closeError || loadError} />
      {ready && (
        <footer className="settings-footer">
          <span className="ready-label">
            <motion.span
              className="ready-check"
              aria-hidden="true"
              initial={reducedMotion ? false : { scale: 0.6, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              transition={reducedMotion ? { duration: 0 } : READINESS_CHECK}
            >
              <Check size={13} strokeWidth={2.8} />
            </motion.span>
            Ready to dictate
          </span>
          <Button disabled={preview} onClick={() => void closeSettings()}>Done</Button>
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

function ModelStatus({ model }: { model: AppState['model'] }): React.JSX.Element {
  switch (model.kind) {
    case 'missing':
      return <p className="model-status">Not downloaded</p>;
    case 'downloading':
      return <p className="model-status">Downloading speech model…</p>;
    case 'loading':
      return <p className="model-status"><LoaderCircle className="spin" size={13} aria-hidden="true" /> Loading model…</p>;
    case 'ready':
      return <p className="model-status status-good">Downloaded and ready</p>;
    case 'error':
      return <p className="model-status status-error">{model.message}</p>;
  }
}

function ModelAction({
  model,
  pending,
  run,
}: {
  model: AppState['model'];
  pending: Command['kind'] | null;
  run: (command: Command) => Promise<void>;
}): React.JSX.Element | null {
  if (model.kind === 'ready' || model.kind === 'loading') return null;
  if (model.kind === 'downloading') {
    return <Button kind="secondary" disabled={preview || pending !== null} onClick={() => void run({ kind: 'cancelDownload' })}>Cancel</Button>;
  }

  if (model.kind === 'error' && model.recovery === 'restart') {
    return <Button disabled={preview || pending !== null} onClick={() => void run({ kind: 'restart' })}>Restart Voco</Button>;
  }

  const isRetry = model.kind === 'error';
  return (
    <Button disabled={preview || pending !== null} onClick={() => void run({ kind: 'downloadModel' })}>
      {pending === 'downloadModel' ? 'Starting…' : isRetry ? 'Try again' : 'Download speech model'}
    </Button>
  );
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

function Waveform({ level, large = false, active = false }: { level: number; large?: boolean; active?: boolean }): React.JSX.Element {
  const reducedMotion = useReducedMotion();
  const energy = Math.sqrt(level);
  return <span className={`waveform ${large ? 'waveform-large' : ''} ${active && level > 0.015 ? 'waveform-active' : ''}`} aria-hidden="true">
    {WAVE_PROFILE.map((height, index) => <motion.span
      key={index}
      initial={false}
      animate={{ scaleY: (3 + energy * height * (large ? 49 : 22)) / (large ? 52 : 25) }}
      transition={reducedMotion ? { duration: 0 } : { type: 'spring', stiffness: 500, damping: 32, mass: 0.35 }}
    ><span className="waveform-energy" style={{ animationDelay: `${-index * 83}ms`, animationDuration: `${680 + (index % 4) * 115}ms` }} /></motion.span>)}
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
    case 'recovery': title = 'Words saved'; break;
  }
  const processing = session.kind === 'starting' || session.kind === 'finishing';
  return <div className="pill-status" role="status" aria-live="polite">
    {processing ? <LoaderCircle className="spin pill-loader" size={18} aria-hidden="true" /> : <Waveform level={session.kind === 'listening' ? state.audioLevel : 0} active={session.kind === 'listening'} />}
    <p className="pill-title">{title}</p>
  </div>;
}

function HomeView({ state, loadError, onSetup }: { state: AppState; loadError: string; onSetup: () => void }): React.JSX.Element {
  const ready = isReady(state);
  const setupComplete = isSetupComplete(state);
  const { run, pending, error } = useCommands();
  const listening = state.session.kind === 'listening';
  let status: string;
  switch (state.session.kind) {
    case 'listening': status = 'Listening'; break;
    case 'starting': status = 'Starting'; break;
    case 'finishing': status = 'Transcribing'; break;
    case 'recovery': status = 'Transcript needs attention'; break;
    case 'idle': status = ready ? 'Ready to dictate' : setupComplete ? 'Loading speech model' : 'Setup needed'; break;
  }
  const hasLastTranscript = state.preferences.keepLastTranscript && state.lastTranscript.length > 0;
  return <main className="dashboard">
    <section className="home-hero" aria-labelledby="home-heading">
      <div className={`voice-stage ${listening ? 'voice-stage-active' : ''}`}>
        <div className="voice-orbit" aria-hidden="true"><div className="voice-core"><Waveform level={listening ? state.audioLevel : 0.62} large active={listening} /></div></div>
        <span className="voice-caption" role="status" aria-live="polite">
          <span className={`status-dot ${listening ? 'status-dot-listening' : ready && state.session.kind !== 'recovery' ? 'status-dot-ready' : ''}`} />
          {status}
        </span>
      </div>
      <h1 id="home-heading"><span className="headline-manrope">Less typing.</span><span className="headline-pixel">More You.</span></h1>
      <p className="hero-description">Hold Fn / Globe to dictate into a text field.</p>
      {setupComplete ? <div className="hero-shortcut"><kbd>Fn <Globe size={16} /></kbd><span>Hold to speak. Release to finish.</span></div> : <button className="button button-primary setup-button" type="button" onClick={onSetup}>Finish setting up <ArrowRight size={16} /></button>}
    </section>
    {state.session.kind === 'recovery' && <div className="home-recovery"><RecoveryContent session={state.session} preview={preview} pending={pending} run={run} error={error || loadError} /></div>}
    <TranscriptPanel
      text={hasLastTranscript ? state.lastTranscript : ''}
      enabled={state.preferences.keepLastTranscript}
    />
    {state.session.kind !== 'recovery' && <ActionError message={error || loadError} />}
    <footer className="dashboard-footer"><ShieldCheck size={13} aria-hidden="true" /> Offline after setup. No account needed.</footer>
  </main>;
}

type TranscriptCopyState =
  | { kind: 'idle' }
  | { kind: 'copying'; text: string }
  | { kind: 'copied'; text: string }
  | { kind: 'error'; text: string; message: string };

function TranscriptPanel({ text, enabled }: { text: string; enabled: boolean }): React.JSX.Element {
  const status = text ? 'Available this session' : enabled ? 'Nothing yet' : 'Off in Settings';
  return <section className="transcript-panel" aria-labelledby="transcript-panel-heading">
    <div className="transcript-panel-header">
      <div className="transcript-heading-copy">
        <h2 id="transcript-panel-heading">Last transcript</h2>
        <span className="transcript-panel-status">{status}</span>
      </div>
      <CopyTranscriptButton text={text} disabled={!enabled || text.length === 0} />
    </div>
    <div className={`transcript-body${text ? ' has-transcript' : ''}`}>
      {text ? <p className="last-transcript">{text}</p> : <p className="transcript-empty-copy">{enabled ? 'Your latest dictation will appear here until you quit.' : 'Turn on Keep last transcript in Settings to see it here.'}</p>}
    </div>
  </section>;
}

function CopyTranscriptButton({ text, disabled }: { text: string; disabled: boolean }): React.JSX.Element {
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
      if (window.voco) {
        await window.voco.command({ kind: 'copyLast' });
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
    try { const saved = localStorage.getItem('voco.setup.step.v1'); return saved === 'model' || saved === 'access' || saved === 'practice' ? saved : 'welcome'; } catch { return 'welcome'; }
  });
  function setStep(next: SetupStep): void {
    updateStep(next);
    if (!preview) { try { localStorage.setItem('voco.setup.step.v1', next); } catch { return; } }
  }
  const { run, pending, error } = useCommands();
  const modelReady = state.model.kind === 'ready';
  const accessReady = state.permissions.microphone === 'granted' && state.permissions.accessibility && state.permissions.shortcut;
  let modelBlockerMessage: string | null;
  switch (state.model.kind) {
    case 'missing': modelBlockerMessage = 'Download the speech model before trying dictation.'; break;
    case 'downloading': modelBlockerMessage = 'The speech model is downloading. Wait for it to finish before trying dictation.'; break;
    case 'loading': modelBlockerMessage = 'The speech model is loading. Wait for it to finish before trying dictation.'; break;
    case 'error': modelBlockerMessage = 'The speech model needs attention. Go to the model step to try again or restart Voco.'; break;
    case 'ready': modelBlockerMessage = null; break;
  }
  const practiceBlocker = modelBlockerMessage
    ? { step: 'model', message: modelBlockerMessage, action: 'Go to speech model' } satisfies { step: SetupStep; message: string; action: string }
    : !accessReady
      ? { step: 'access', message: 'Allow microphone and keyboard access before trying dictation.', action: 'Go to app permissions' } satisfies { step: SetupStep; message: string; action: string }
      : null;
  const stepIndex = SETUP_STEPS.findIndex(item => item.id === step);
  const headings = { welcome: 'A little setup.\nA lot less typing.', model: 'Give your voice\na place to land.', access: 'A few permissions.\nYou are in control.', practice: 'Meet your new\nway to write.' };
  return <main className="onboarding">
    <header className="page-heading"><h1>Set up Voco</h1><button className="text-link" onClick={onDone}>Explore the app <ArrowRight size={14} /></button></header>
    <nav className="setup-steps" aria-label="Setup progress">{SETUP_STEPS.map((item, index) => <button key={item.id} onClick={() => setStep(item.id)} aria-current={step === item.id ? 'step' : undefined}><span>{(item.id === 'model' ? modelReady : item.id === 'access' ? accessReady : item.id === 'welcome' && step !== 'welcome') ? <Check size={14} /> : index + 1}</span>{item.title}</button>)}</nav>
    <div className="onboarding-layout">
      <div className="onboarding-copy"><h2>{headings[step].split('\n').map((line, index) => <span key={line} className={index ? 'serif-line' : ''}>{line}</span>)}</h2><p>{step === 'welcome' ? 'Voco turns your voice into text, right where you are working. Dictation runs on your Mac, without an account.' : step === 'model' ? 'Download the English speech model once. After that, your dictation works entirely offline.' : step === 'access' ? 'Voco needs to hear you and write into your apps. macOS asks for your approval for each permission.' : 'Click the field and hold Fn / Globe to speak. Release to finish.'}</p><span className="onboarding-privacy"><ShieldCheck size={17} /> Audio and transcripts are never saved to disk.</span></div>
      <div className="setup-workspace">
        {step === 'welcome' && <><div className="welcome-wave"><Waveform level={0.8} large /></div><h3>Your voice, wherever you write.</h3><p>Emails, notes, messages. Keep your attention on what you want to say.</p><div className="welcome-shortcut"><kbd>fn <Globe size={16} /></kbd><span>One key. Your own words.</span></div><Button onClick={() => setStep('model')}>Get started <ArrowRight size={16} /></Button></>}
        {step === 'model' && <><Download size={28} className="setup-symbol" /><h3>English speech model</h3><p>Moonshine Medium Streaming</p><ModelStatus model={state.model} />{state.model.kind === 'downloading' && <div className="download-progress"><progress value={state.model.progress} max={1} aria-label="Speech model download progress" /><span>{Math.round(state.model.progress * 100)}%</span></div>}<ModelAction model={state.model} pending={pending} run={run} /><p className="setup-note">Keep Voco open while the model downloads. You can cancel and try again.</p><Button kind={modelReady ? 'primary' : 'secondary'} disabled={!modelReady} onClick={() => setStep('access')}>Continue <ArrowRight size={15} /></Button></>}
        {step === 'access' && <><h3>Allow access</h3><PermissionRow icon={<Mic size={18} />} title="Microphone" description="To hear your words." status={microphoneStatus(state.permissions.microphone)} statusKind={state.permissions.microphone === 'granted' ? 'good' : 'neutral'}>{state.permissions.microphone !== 'granted' && <Button disabled={preview || pending !== null} onClick={() => void run(state.permissions.microphone === 'denied' ? { kind: 'openPrivacy', pane: 'microphone' } : { kind: 'requestMicrophone' })}>{state.permissions.microphone === 'denied' ? 'Open Settings' : 'Allow'}</Button>}</PermissionRow><PermissionRow icon={<Keyboard size={18} />} title="Keyboard access" description="To use your shortcut and insert text." status={keyboardStatus(state)} statusKind={accessReady ? 'good' : 'neutral'}>{!state.permissions.accessibility ? <Button disabled={preview || pending !== null} onClick={() => void run({ kind: 'requestAccessibility' })}>Allow</Button> : !state.permissions.shortcut ? <Button disabled={preview || pending !== null} onClick={() => void run({ kind: 'restart' })}>Restart Voco</Button> : null}</PermissionRow>{!state.permissions.accessibility && <div className="access-help"><p>Enable Voco in System Settings → Privacy &amp; Security → Accessibility. If it is missing, add the app shown in Finder.</p><Button kind="quiet" disabled={preview || pending !== null} onClick={() => void run({ kind: 'showApp' })}><FolderOpen size={14} /> Show app in Finder</Button><Button kind="quiet" disabled={preview || pending !== null} onClick={() => void run({ kind: 'refresh' })}><RotateCw size={14} /> Check again</Button></div>}<Button disabled={!accessReady || !modelReady} onClick={() => setStep('practice')}>Try dictation <ArrowRight size={15} /></Button></>}
        {step === 'practice' && <>{practiceBlocker && <div className="practice-blocker" role="status"><p>{practiceBlocker.message}</p><Button kind="secondary" onClick={() => setStep(practiceBlocker.step)}>{practiceBlocker.action} <ArrowRight size={15} /></Button></div>}<div className="practice-heading"><kbd>fn <Globe size={16} /></kbd><span>Hold to speak, release to finish</span></div><label className="visually-hidden" htmlFor="practice-text">Try your first dictation</label><textarea id="practice-text" placeholder="Click here and say something…" disabled={!isReady(state)} /><p className="setup-note">{preview ? 'Dictation is available in the desktop app.' : 'Try: “My best ideas start with a conversation.”'}</p><details className="practice-help"><summary>Set up your Fn / Globe key</summary><p>In macOS System Settings → Keyboard, set “Press Globe key to” to “Do Nothing”. Turn off any Apple Dictation shortcut that uses the same key.</p></details><Button disabled={!isReady(state)} onClick={onDone}>Open Voco <ArrowRight size={15} /></Button></>}
        <ActionError message={error || loadError} />
      </div>
    </div>
    {step !== 'welcome' && <button className="text-link onboarding-back" onClick={() => setStep(SETUP_STEPS[Math.max(0, stepIndex - 1)]?.id ?? 'welcome')}><ArrowLeft size={15} /> Back</button>}
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

function App(): React.JSX.Element {
  const { state, error } = useAppState();
  const [page, setPage] = useState<AppPage>(() => query.get('page') === 'settings' ? 'settings' : query.get('page') === 'onboarding' ? 'onboarding' : query.get('page') === 'home' ? 'home' : 'auto');
  const [setupSeen, setSetupSeen] = useState(() => { try { return localStorage.getItem('voco.setup.v1') === 'seen'; } catch { return false; } });
  useEffect(() => {
    if (state && page === 'auto') setPage(setupSeen || isSetupComplete(state) ? 'home' : 'onboarding');
  }, [state, page, setupSeen]);
  if (!state) return view === 'pill' ? <main className="pill-shell" /> : <StartupView error={error} />;
  if (view === 'pill') return <PillView state={state} loadError={error} />;
  const currentPage: NavigationPage = page === 'auto' ? setupSeen || isSetupComplete(state) ? 'home' : 'onboarding' : page;
  function finishSetup(): void {
    try { localStorage.setItem('voco.setup.v1', 'seen'); } catch { /* Setup remains accessible without local storage. */ }
    setSetupSeen(true);
    setPage('home');
  }
  return <div className="desktop-shell">
    <AppSidebar
      currentPage={currentPage}
      showSetup={!isSetupComplete(state) || currentPage === 'onboarding'}
      onNavigate={setPage}
    />
    <div className="app-content">
      <div className="titlebar window-drag" aria-hidden="true" />
      <div className="workspace-main">
        <PreviewNotice />
        {currentPage === 'settings' ? <SettingsView state={state} loadError={error} /> : currentPage === 'onboarding' ? <OnboardingView state={state} loadError={error} onDone={finishSetup} /> : <HomeView state={state} loadError={error} onSetup={() => setPage('onboarding')} />}
      </div>
    </div>
  </div>;
}

const rootElement = document.getElementById('root');
if (!rootElement) throw new Error('The Voco renderer root is missing.');
createRoot(rootElement).render(<App />);
