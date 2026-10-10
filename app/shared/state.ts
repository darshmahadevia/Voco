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
  preferences: { keepLastTranscript: true },
  lastTranscript: '',
  usage: emptyUsage,
};

export function isReady(state: AppState): boolean {
  return state.model.kind === 'ready' && isSetupComplete(state);
}

export function isSetupComplete(state: AppState): boolean {
  return (state.model.kind === 'ready' || state.model.kind === 'loading') && state.permissions.microphone === 'granted'
    && state.permissions.accessibility && state.permissions.shortcut;
}
