import { contextBridge, ipcRenderer } from 'electron';
import type { AppState, Command, VocoApi } from '../shared/protocol';

const api: VocoApi = {
  getState: () => ipcRenderer.invoke('voco:get-state'),
  command: (command: Command) => ipcRenderer.invoke('voco:command', command),
  copyTranscript: (text) => ipcRenderer.invoke('voco:copy-transcript', text),
  closeSettings: () => ipcRenderer.invoke('voco:close-settings'),
  setWindowMode: (mode) => ipcRenderer.invoke('voco:set-window-mode', mode),
  subscribe: (listener) => {
    const receive = (_event: Electron.IpcRendererEvent, state: AppState): void => listener(state);
    ipcRenderer.on('voco:state', receive);
    return () => ipcRenderer.removeListener('voco:state', receive);
  },
};
contextBridge.exposeInMainWorld('voco', api);
