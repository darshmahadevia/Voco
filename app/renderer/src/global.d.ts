import type { VocoApi } from '../../shared/protocol';

declare global {
  interface Window {
    voco?: VocoApi;
  }
}

export {};
