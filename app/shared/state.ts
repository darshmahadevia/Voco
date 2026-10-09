import type { AppState } from './protocol';

export const initialState: AppState = {
  audioLevel: 0,
  model: { kind: 'missing' },
  permissions: { microphone: 'required', accessibility: false, shortcut: false },
  session: { kind: 'idle' },
  preferences: { keepLastTranscript: true },
  lastTranscript: '',
};

export function isReady(state: AppState): boolean {
  return state.model.kind === 'ready' && isSetupComplete(state);
}

export function isSetupComplete(state: AppState): boolean {
  return (state.model.kind === 'ready' || state.model.kind === 'loading') && state.permissions.microphone === 'granted'
    && state.permissions.accessibility && state.permissions.shortcut;
}
