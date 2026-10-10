import type { AppState } from '../../shared/protocol';

export type RecentTranscript = { id: number; text: string; createdAt: number };

export function retainTranscripts({ entries, previous, next, now }: {
  entries: RecentTranscript[];
  previous: AppState | null;
  next: AppState;
  now: number;
}): RecentTranscript[] {
  if (!next.preferences.keepLastTranscript) return [];
  if (!next.lastTranscript) return entries;
  const sessionCount = (state: AppState): number => Object.values(state.usage?.days ?? {}).reduce((total, day) => total + day.sessions, 0);
  const completed = previous !== null && sessionCount(next) > sessionCount(previous);
  if (previous?.lastTranscript === next.lastTranscript && !completed) return entries;
  return [{ id: (entries[0]?.id ?? 0) + 1, text: next.lastTranscript, createdAt: now }, ...entries];
}
