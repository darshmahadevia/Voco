import { expect, it } from 'vitest';
import { initialState, nativeFailureState } from './state';
import type { AppState } from './protocol';

it.each([
  { kind: 'starting' },
  { kind: 'listening', mode: 'hold' },
  { kind: 'finishing' },
] satisfies AppState['session'][])('does not offer a previous transcript after a helper failure during $kind', (session) => {
  const failed = nativeFailureState({ ...initialState, lastTranscript: 'Previous dictation.', session }, 'Connection lost.');
  expect(failed.session).toEqual({ kind: 'recovery', message: 'Connection lost.', text: '' });
  expect(failed.lastTranscript).toBe('Previous dictation.');
  expect(failed.model).toEqual({ kind: 'error', message: 'Connection lost.', recovery: 'restart' });
});

it('preserves text already recovered from the interrupted session', () => {
  const failed = nativeFailureState({
    ...initialState,
    lastTranscript: 'Previous dictation.',
    session: { kind: 'recovery', message: 'Insertion failed.', text: 'Current dictation.' },
  }, 'Connection lost.');
  expect(failed.session).toEqual({ kind: 'recovery', message: 'Connection lost.', text: 'Current dictation.' });
});

it('keeps an idle session idle when the helper fails', () => {
  expect(nativeFailureState(initialState, 'Connection lost.').session).toEqual({ kind: 'idle' });
});
