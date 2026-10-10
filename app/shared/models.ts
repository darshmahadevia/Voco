import type { ModelId } from './protocol';

export const speechModels = [
  { id: 'moonshine', name: 'Moonshine', version: 'Medium Streaming', description: 'English · native streaming · about 270 MB to download' },
  { id: 'parakeet', name: 'Parakeet', version: 'TDT 0.6B v2', description: 'English · punctuation and capitalization · about 465 MB to download' },
  { id: 'whisper', name: 'Whisper', version: 'Large v3 Turbo', description: 'English dictation · multilingual model · about 1.6 GB to download' },
] satisfies { id: ModelId; name: string; version: string; description: string }[];
