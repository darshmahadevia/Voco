import type { AppState } from './protocol';
import { emptyUsage } from './usage';

export const initialState: AppState = {
  userName: '',
  audioLevel: 0,
  audioWaveform: Array.from({ length: 11 }, () => 0),
  model: { kind: 'missing' },
  selectedModel: 'moonshine',
  recommendedModel: 'parakeet',
  models: [
    { id: 'moonshine', state: { kind: 'missing' } },
    { id: 'parakeet', state: { kind: 'missing' } },
    { id: 'whisper', state: { kind: 'missing' } },
  ],
  permissions: { microphone: 'required', accessibility: false, shortcut: false },
  session: { kind: 'idle' },
  preferences: { keepLastTranscript: true, outputMode: 'fast' },
  lastTranscript: '',
  lastRawTranscript: '',
  polishNotice: '',
  polishing: { kind: 'unavailable', message: 'Local AI cleanup availability is not known yet.' },
  usage: emptyUsage,
};

export function isReady(state: AppState): boolean {
  return state.model.kind === 'ready' && isSetupComplete(state);
}

export function isSetupComplete(state: AppState): boolean {
  return (state.model.kind === 'ready' || state.model.kind === 'loading') && state.permissions.microphone === 'granted'
    && state.permissions.accessibility && state.permissions.shortcut;
}

export function nativeFailureState(state: AppState, message: string): AppState {
  return {
    ...state,
    model: { kind: 'error', message, recovery: 'restart' },
    session: state.session.kind === 'idle'
      ? { kind: 'idle' }
      : { kind: 'recovery', message, text: state.session.kind === 'recovery' ? state.session.text : '' },
  };
}
