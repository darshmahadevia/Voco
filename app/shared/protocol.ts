import { z } from 'zod';

export const preferencesSchema = z.object({
  keepLastTranscript: z.boolean(),
});
export type Preferences = z.infer<typeof preferencesSchema>;

export const modelSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('missing') }),
  z.object({ kind: z.literal('downloading'), progress: z.number().min(0).max(1), file: z.string() }),
  z.object({ kind: z.literal('loading') }),
  z.object({ kind: z.literal('ready') }),
  z.object({ kind: z.literal('error'), message: z.string(), recovery: z.literal('restart').optional() }),
]);
export const sessionSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('idle') }),
  z.object({ kind: z.literal('starting') }),
  z.object({ kind: z.literal('listening'), mode: z.literal('hold'), buffered: z.boolean(), text: z.string().default('') }),
  z.object({ kind: z.literal('finishing') }),
  z.object({ kind: z.literal('recovery'), message: z.string(), text: z.string() }),
]);
export const appStateSchema = z.object({
  audioLevel: z.number().min(0).max(1).default(0),
  model: modelSchema,
  permissions: z.object({
    microphone: z.enum(['required', 'denied', 'granted']),
    accessibility: z.boolean(),
    shortcut: z.boolean(),
  }),
  session: sessionSchema,
  preferences: preferencesSchema,
  lastTranscript: z.string(),
});
export type AppState = z.infer<typeof appStateSchema>;
export type Session = AppState['session'];

export const commandSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('downloadModel') }),
  z.object({ kind: z.literal('cancelDownload') }),
  z.object({ kind: z.literal('requestMicrophone') }),
  z.object({ kind: z.literal('requestAccessibility') }),
  z.object({ kind: z.literal('openPrivacy'), pane: z.enum(['microphone', 'accessibility']) }),
  z.object({ kind: z.literal('setPreferences'), preferences: preferencesSchema }),
  z.object({ kind: z.literal('stop') }),
  z.object({ kind: z.literal('cancel') }),
  z.object({ kind: z.literal('copyRecovery') }),
  z.object({ kind: z.literal('copyLast') }),
  z.object({ kind: z.literal('refresh') }),
  z.object({ kind: z.literal('restart') }),
  z.object({ kind: z.literal('showApp') }),
]);
export type Command = z.infer<typeof commandSchema>;

export const nativeMessageSchema = z.discriminatedUnion('type', [
  z.object({ type: z.literal('state'), state: appStateSchema }),
  z.object({ type: z.literal('reply'), id: z.string(), ok: z.boolean(), error: z.string().optional() }),
  z.object({ type: z.literal('showSettings') }),
]);
export type NativeMessage = z.infer<typeof nativeMessageSchema>;

export interface VocoApi {
  getState(): Promise<AppState | null>;
  command(command: Command): Promise<void>;
  subscribe(listener: (state: AppState) => void): () => void;
  closeSettings(): Promise<void>;
}

