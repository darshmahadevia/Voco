import { z } from 'zod';
import { emptyUsage, usageSchema } from './usage';

export const preferencesSchema = z.object({
  keepLastTranscript: z.boolean(),
});
export type Preferences = z.infer<typeof preferencesSchema>;

export const modelIdSchema = z.enum(['moonshine', 'parakeet', 'whisper']);
export type ModelId = z.infer<typeof modelIdSchema>;

export const modelSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('missing') }),
  z.object({ kind: z.literal('installed') }),
  z.object({ kind: z.literal('downloading'), progress: z.number().min(0).max(1), file: z.string() }),
  z.object({ kind: z.literal('loading') }),
  z.object({ kind: z.literal('ready') }),
  z.object({ kind: z.literal('error'), message: z.string(), recovery: z.literal('restart').optional() }),
]);
export const sessionSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('idle') }),
  z.object({ kind: z.literal('starting') }),
  z.object({ kind: z.literal('listening'), mode: z.literal('hold') }).strict(),
  z.object({ kind: z.literal('finishing') }),
  z.object({ kind: z.literal('recovery'), message: z.string(), text: z.string() }),
]);
export const appStateSchema = z.object({
  userName: z.string().default(''),
  audioLevel: z.number().min(0).max(1).default(0),
  audioWaveform: z.array(z.number().min(0).max(1)).length(11).default(() => Array.from({ length: 11 }, () => 0)),
  model: modelSchema,
  selectedModel: modelIdSchema,
  recommendedModel: modelIdSchema.nullable(),
  models: z.array(z.object({ id: modelIdSchema, state: modelSchema })).length(3)
    .refine(entries => new Set(entries.map(entry => entry.id)).size === 3, 'Each speech model must occur once.'),
  permissions: z.object({
    microphone: z.enum(['required', 'denied', 'granted']),
    accessibility: z.boolean(),
    shortcut: z.boolean(),
  }),
  session: sessionSchema,
  preferences: preferencesSchema,
  lastTranscript: z.string(),
  usage: usageSchema.default(() => ({ ...emptyUsage, days: {} })),
}).refine(state => state.model.kind !== 'ready'
  || state.models.find(entry => entry.id === state.selectedModel)?.state.kind === 'ready',
  'A ready engine must belong to the selected, ready model.');
export type AppState = z.infer<typeof appStateSchema>;
export type Session = AppState['session'];

export const commandSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('downloadModel'), modelId: modelIdSchema }),
  z.object({ kind: z.literal('selectModel'), modelId: modelIdSchema }),
  z.object({ kind: z.literal('cancelDownload') }),
  z.object({ kind: z.literal('requestMicrophone') }),
  z.object({ kind: z.literal('requestAccessibility') }),
  z.object({ kind: z.literal('openPrivacy'), pane: z.enum(['microphone', 'accessibility']) }),
  z.object({ kind: z.literal('setPreferences'), preferences: preferencesSchema }),
  z.object({ kind: z.literal('setUsagePreferences'), dailyGoal: usageSchema.shape.dailyGoal, typingWpm: usageSchema.shape.typingWpm }),
  z.object({ kind: z.literal('stop') }),
  z.object({ kind: z.literal('cancel') }),
  z.object({ kind: z.literal('copyRecovery') }),
  z.object({ kind: z.literal('copyLast') }),
  z.object({ kind: z.literal('refresh') }),
  z.object({ kind: z.literal('restart') }),
  z.object({ kind: z.literal('showApp') }),
]);
export type Command = z.infer<typeof commandSchema>;

export const windowModeSchema = z.enum(['onboarding', 'workspace']);
export type WindowMode = z.infer<typeof windowModeSchema>;

export const navigationPageSchema = z.enum(['home', 'transcripts', 'stats', 'settings', 'onboarding']);
export type NavigationPage = z.infer<typeof navigationPageSchema>;

export const nativeMessageSchema = z.discriminatedUnion('type', [
  z.object({ type: z.literal('state'), state: appStateSchema }),
  z.object({ type: z.literal('reply'), id: z.string(), ok: z.boolean(), error: z.string().optional() }),
  z.object({ type: z.literal('showSettings') }),
]);
export type NativeMessage = z.infer<typeof nativeMessageSchema>;

export interface VocoApi {
  getState(): Promise<AppState | null>;
  command(command: Command): Promise<void>;
  copyTranscript(text: string): Promise<void>;
  subscribe(listener: (state: AppState) => void): () => void;
  subscribeNavigation(listener: (page: NavigationPage) => void): () => void;
  closeSettings(): Promise<void>;
  setWindowMode(mode: WindowMode): Promise<void>;
}

