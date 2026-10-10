import { contextBridge, ipcRenderer } from 'electron';
import type { AppState, Command, NavigationPage, VocoApi } from '../shared/protocol';

const api: VocoApi = {
  getState: () => ipcRenderer.invoke('voco:get-state'),
  command: (command: Command) => ipcRenderer.invoke('voco:command', command),
  copyTranscript: (text) => ipcRenderer.invoke('voco:copy-transcript', text),
  closeSettings: () => ipcRenderer.invoke('voco:close-settings'),
  subscribeNavigation: (listener) => {
    let active = true;
    let received = false;
    const receive = (_event: Electron.IpcRendererEvent, page: NavigationPage): void => {
      received = true;
      listener(page);
    };
    ipcRenderer.on('voco:navigate', receive);
    void ipcRenderer.invoke('voco:get-navigation').then((page: NavigationPage | null) => {
      if (active && !received && page) listener(page);
    });
    return () => {
      active = false;
      ipcRenderer.removeListener('voco:navigate', receive);
    };
  },
  subscribe: (listener) => {
    const receive = (_event: Electron.IpcRendererEvent, state: AppState): void => listener(state);
    ipcRenderer.on('voco:state', receive);
    return () => ipcRenderer.removeListener('voco:state', receive);
  },
};
contextBridge.exposeInMainWorld('voco', api);
