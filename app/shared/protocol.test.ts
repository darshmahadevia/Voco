import { describe, expect, it } from 'vitest';
import { appStateSchema, commandSchema, nativeMessageSchema } from './protocol';
import { initialState, isReady } from './state';

describe('desktop protocol boundary', () => {
  it('allows dictation only after model, microphone, accessibility and monitor are ready', () => {
    expect(isReady(initialState)).toBe(false);
    const ready = { ...initialState, model: { kind: 'ready' }, permissions: { microphone: 'granted', accessibility: true, shortcut: true } };
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
  });

  it('carries partial speech independently of transcript retention', () => {
    expect(appStateSchema.parse({ ...initialState, session: { kind: 'listening', mode: 'hold', buffered: true } }).session).toEqual({ kind: 'listening', mode: 'hold', buffered: true, text: '' });
    expect(appStateSchema.parse({ ...initialState, preferences: { ...initialState.preferences, keepLastTranscript: false }, session: { kind: 'listening', mode: 'hold', buffered: false, text: 'Partial words' } }).session).toEqual({ kind: 'listening', mode: 'hold', buffered: false, text: 'Partial words' });
    expect(appStateSchema.parse({ ...initialState, session: { kind: 'recovery', message: 'The field changed.', text: 'Saved words.' } }).session).toEqual({ kind: 'recovery', message: 'The field changed.', text: 'Saved words.' });
    expect(nativeMessageSchema.safeParse({ type: 'state', state: { ...initialState, session: { kind: 'recovery', message: 'Missing text' } } }).success).toBe(false);
  });
});
