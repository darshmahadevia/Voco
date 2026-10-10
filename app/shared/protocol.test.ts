import { describe, expect, it } from 'vitest';
import { appStateSchema, commandSchema, nativeMessageSchema } from './protocol';
import { initialState, isReady } from './state';

describe('desktop protocol boundary', () => {
  it('allows dictation only after model, microphone, accessibility and monitor are ready', () => {
    expect(isReady(initialState)).toBe(false);
    const ready = { ...initialState, model: { kind: 'ready' }, models: initialState.models.map(entry => entry.id === 'moonshine' ? { ...entry, state: { kind: 'ready' } } : entry), permissions: { microphone: 'granted', accessibility: true, shortcut: true } };
    expect(isReady(appStateSchema.parse(ready))).toBe(true);
    expect(isReady(appStateSchema.parse({ ...ready, permissions: { ...ready.permissions, shortcut: false } }))).toBe(false);
    expect(isReady(appStateSchema.parse({ ...ready, model: { kind: 'loading' } }))).toBe(false);
  });

  it('rejects malformed download progress and unsafe preference inputs', () => {
    expect(nativeMessageSchema.safeParse({ type: 'state', state: { ...initialState, model: { kind: 'downloading', progress: 2, file: 'encoder' } } }).success).toBe(false);
    expect(commandSchema.safeParse({ kind: 'setPreferences', preferences: { keepLastTranscript: 'yes' } }).success).toBe(false);
    expect(commandSchema.parse({ kind: 'setPreferences', preferences: { keepLastTranscript: false } })).toEqual({ kind: 'setPreferences', preferences: { keepLastTranscript: false } });
    expect(appStateSchema.safeParse({ ...initialState, session: { kind: 'listening', mode: 'continuous', buffered: false, text: '' } }).success).toBe(false);
  });

  it('validates microphone levels before they reach the waveform', () => {
    expect(appStateSchema.parse({ ...initialState, audioLevel: 0.65 }).audioLevel).toBe(0.65);
    expect(appStateSchema.safeParse({ ...initialState, audioLevel: -0.1 }).success).toBe(false);
    expect(appStateSchema.safeParse({ ...initialState, audioLevel: 1.1 }).success).toBe(false);
    const audioWaveform = [0, 0.01, 0.02, 0.04, 0.1, 0.2, 0.4, 0.2, 0.1, 0.02, 0];
    expect(appStateSchema.parse({ ...initialState, audioWaveform }).audioWaveform).toEqual(audioWaveform);
    expect(appStateSchema.safeParse({ ...initialState, audioWaveform: [0.1] }).success).toBe(false);
    expect(appStateSchema.safeParse({ ...initialState, audioWaveform: audioWaveform.map(() => 1.1) }).success).toBe(false);
  });

  it('requires a known model for installation and switching', () => {
    expect(commandSchema.safeParse({ kind: 'downloadModel' }).success).toBe(false);
    expect(commandSchema.safeParse({ kind: 'selectModel', modelId: 'cloud' }).success).toBe(false);
    expect(commandSchema.parse({ kind: 'downloadModel', modelId: 'parakeet' })).toEqual({ kind: 'downloadModel', modelId: 'parakeet' });
    expect(commandSchema.parse({ kind: 'selectModel', modelId: 'whisper' })).toEqual({ kind: 'selectModel', modelId: 'whisper' });
  });

  it('keeps installed alternatives separate from the loaded model', () => {
    const state = appStateSchema.parse({
      ...initialState,
      selectedModel: 'parakeet',
      model: { kind: 'loading' },
      models: [
        { id: 'moonshine', state: { kind: 'installed' } },
        { id: 'parakeet', state: { kind: 'loading' } },
        { id: 'whisper', state: { kind: 'missing' } },
      ],
    });
    expect(isReady(state)).toBe(false);
    expect(appStateSchema.safeParse({ ...state, models: [state.models[0], state.models[0], state.models[2]] }).success).toBe(false);
    expect(appStateSchema.safeParse({ ...initialState, selectedModel: 'parakeet', model: { kind: 'ready' } }).success).toBe(false);
  });

  it('publishes capture status without provisional text or insertion modes', () => {
    expect(appStateSchema.parse({ ...initialState, session: { kind: 'listening', mode: 'hold' } }).session).toEqual({ kind: 'listening', mode: 'hold' });
    expect(appStateSchema.safeParse({ ...initialState, session: { kind: 'listening', mode: 'hold', buffered: false, text: 'Partial words' } }).success).toBe(false);
    expect(appStateSchema.parse({ ...initialState, session: { kind: 'recovery', message: 'The field changed.', text: 'Saved words.' } }).session).toEqual({ kind: 'recovery', message: 'The field changed.', text: 'Saved words.' });
    expect(nativeMessageSchema.safeParse({ type: 'state', state: { ...initialState, session: { kind: 'recovery', message: 'Missing text' } } }).success).toBe(false);
  });
});
