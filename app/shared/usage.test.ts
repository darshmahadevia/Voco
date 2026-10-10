import { expect, it } from 'vitest';
import { dateKey, emptyUsage, shiftDay, usageSummary, usageSchema } from './usage';

it('shows zero progress before the first dictation', () => {
  expect(usageSummary(emptyUsage, new Date(2026, 9, 9))).toEqual({ words: 0, secondsSaved: 0, streak: 0, bestStreak: 0, sessions: 0 });
});

it('keeps yesterday\'s streak alive and calculates savings from actual elapsed time', () => {
  const usage = { ...emptyUsage, days: {
    '2026-10-06': { words: 100, seconds: 30, sessions: 1 },
    '2026-10-07': { words: 200, seconds: 60, sessions: 2 },
    '2026-10-08': { words: 300, seconds: 90, sessions: 3 },
  } };
  expect(usageSummary(usage, new Date(2026, 9, 9))).toEqual({ words: 600, secondsSaved: 720, streak: 3, bestStreak: 3, sessions: 6 });
  expect(usageSummary(usage, new Date(2026, 9, 10)).streak).toBe(0);
  expect(usageSummary({ ...usage, typingWpm: 100 }, new Date(2026, 9, 9)).secondsSaved).toBe(180);
});

it('counts today once and finds the best run across year and leap-day boundaries', () => {
  const day = { words: 1, seconds: 10, sessions: 1 };
  const usage = { ...emptyUsage, days: { '2024-02-28': day, '2024-02-29': day, '2024-03-01': day, '2025-12-31': day, '2026-01-01': day } };
  expect(usageSummary(usage, new Date(2026, 0, 1))).toEqual({ words: 5, secondsSaved: 0, streak: 2, bestStreak: 3, sessions: 5 });
});

it('shifts local calendar days across DST without adding 24-hour milliseconds', () => {
  expect(dateKey(shiftDay(new Date(2026, 2, 8, 12), -1))).toBe('2026-03-07');
  expect(dateKey(shiftDay(new Date(2026, 10, 1, 12), 1))).toBe('2026-11-02');
});

it('rejects invalid persisted statistics and preferences at the protocol boundary', () => {
  expect(usageSchema.safeParse({ ...emptyUsage, dailyGoal: 0 }).success).toBe(false);
  expect(usageSchema.safeParse({ ...emptyUsage, days: { '2026-10-09': { words: -1, seconds: 0, sessions: 1 } } }).success).toBe(false);
});
