import type { ModelId } from './protocol';

export const speechModels = [
  { id: 'moonshine', name: 'Moonshine', version: 'Medium Streaming', downloadSize: 'About 270 MB', description: 'English · native streaming' },
  { id: 'parakeet', name: 'Parakeet', version: 'TDT 0.6B v2', downloadSize: 'About 465 MB', description: 'English · punctuation and capitalization' },
  { id: 'whisper', name: 'Whisper', version: 'Large v3 Turbo', downloadSize: 'About 1.6 GB', description: 'English dictation · multilingual model' },
] satisfies { id: ModelId; name: string; version: string; downloadSize: string; description: string }[];
