import { describe, expect, it } from 'vitest';
import { initialState } from '../../shared/state';
import { retainTranscripts } from './recent-transcripts';

describe('session transcript retention', () => {
  const first = { ...initialState, lastTranscript: 'First dictation.' };
  const entries = [{ id: 1, text: 'First dictation.', createdAt: 100 }];

  it('keeps dictations newest first', () => {
    expect(retainTranscripts({ entries, previous: first, next: { ...first, lastTranscript: 'Second dictation.' }, now: 200 })).toEqual([
      { id: 2, text: 'Second dictation.', createdAt: 200 }, ...entries,
    ]);
  });

  it('does not duplicate transcripts when status updates arrive', () => {
    expect(retainTranscripts({ entries, previous: first, next: { ...first, audioLevel: 0.4 }, now: 200 })).toBe(entries);
  });

  it('retains identical words from a separate completed dictation', () => {
    const next = { ...first, usage: { ...first.usage, days: { '2026-10-10': { words: 4, seconds: 2, sessions: 2 } } } };
    expect(retainTranscripts({ entries, previous: first, next, now: 200 })).toHaveLength(2);
  });

  it('keeps history when an empty dictation completes', () => {
    expect(retainTranscripts({ entries, previous: first, next: initialState, now: 200 })).toBe(entries);
  });

  it('clears all words when retention is turned off', () => {
    expect(retainTranscripts({ entries, previous: first, next: { ...first, preferences: { keepLastTranscript: false } }, now: 200 })).toEqual([]);
  });

  it('captures the initial transcript without saving an empty entry', () => {
    expect(retainTranscripts({ entries: [], previous: null, next: first, now: 100 })).toEqual(entries);
    expect(retainTranscripts({ entries: [], previous: null, next: initialState, now: 100 })).toEqual([]);
  });
});
