import { z } from 'zod';

export const usageSchema = z.object({
  days: z.record(z.string().regex(/^\d{4}-\d{2}-\d{2}$/), z.object({
    words: z.number().int().nonnegative(),
    seconds: z.number().finite().nonnegative(),
    sessions: z.number().int().nonnegative(),
  })),
  dailyGoal: z.number().int().min(100).max(10000),
  typingWpm: z.number().int().min(10).max(200),
});
export type Usage = z.infer<typeof usageSchema>;
export const emptyUsage: Usage = { days: {}, dailyGoal: 500, typingWpm: 40 };

export function dateKey(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

export function shiftDay(date: Date, amount: number): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() + amount, 12);
}

export function usageSummary(usage: Usage, now = new Date()): { words: number; secondsSaved: number; streak: number; bestStreak: number; sessions: number } {
  const keys = Object.keys(usage.days).filter(key => (usage.days[key]?.words ?? 0) > 0).sort();
  let words = 0;
  let seconds = 0;
  let sessions = 0;
  let bestStreak = 0;
  let run = 0;
  let previous = '';
  for (const key of keys) {
    const day = usage.days[key];
    if (!day) continue;
    words += day.words;
    seconds += day.seconds;
    sessions += day.sessions;
    const date = new Date(`${key}T12:00:00`);
    run = dateKey(shiftDay(date, -1)) === previous ? run + 1 : 1;
    bestStreak = Math.max(bestStreak, run);
    previous = key;
  }
  let cursor = now;
  if (!(usage.days[dateKey(cursor)]?.words)) cursor = shiftDay(cursor, -1);
  let streak = 0;
  while ((usage.days[dateKey(cursor)]?.words ?? 0) > 0) {
    streak += 1;
    cursor = shiftDay(cursor, -1);
  }
  return { words, secondsSaved: Math.max(0, words / usage.typingWpm * 60 - seconds), streak, bestStreak, sessions };
}

export function savedTimeLabel(seconds: number): string {
  if (seconds < 60) return `${Math.floor(seconds)} sec`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)} min`;
  return `${Math.floor(seconds / 3600)} hr ${Math.floor(seconds % 3600 / 60)} min`;
}

export function sampleUsage(now = new Date()): Usage {
  const days: Usage['days'] = {};
  for (let offset = 20; offset >= 0; offset -= 1) {
    if (offset > 4 && offset % 4 === 0) continue;
    const words = 180 + (offset * 137 % 720);
    days[dateKey(shiftDay(now, -offset))] = { words, seconds: words / 2.5, sessions: 3 + offset % 5 };
  }
  return { ...emptyUsage, days };
}
