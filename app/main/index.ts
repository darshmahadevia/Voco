import { app, BrowserWindow, clipboard, ipcMain, Menu, nativeImage, screen, session, shell, Tray } from 'electron';
import { spawn } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';
import { NativeBridge } from './native-bridge';
import { commandSchema, type AppState, type Command } from '../shared/protocol';
import { initialState, isReady } from '../shared/state';

let settings: BrowserWindow | null = null;
let pill: BrowserWindow | null = null;
let tray: Tray | null = null;
let bridge: NativeBridge | null = null;
let state: AppState = initialState;
let quitting = false;
let nativeSeen = false;
const verificationArgument = process.argv.find((argument) => argument.startsWith('--verification-directory='));
const verificationDirectory = process.argv.includes('--verify-desktop') && verificationArgument
  ? verificationArgument.slice('--verification-directory='.length) : null;
const verificationModelArgument = process.argv.find((argument) => argument.startsWith('--verification-model-directory='));
const verificationModelDirectory = verificationDirectory && verificationModelArgument
  ? verificationModelArgument.slice('--verification-model-directory='.length) : null;
const verifyPermissionReturn = verificationDirectory !== null && process.argv.includes('--verify-permission-return');
type PermissionTarget = 'microphone' | 'accessibility';
let permissionReturn: PermissionTarget | null = null;
app.setName('Voco');
app.setPath('userData', verificationDirectory
  ? join(verificationDirectory, 'profile') : join(app.getPath('appData'), 'Voco'));

function loadWindow(window: BrowserWindow, route: 'settings' | 'pill'): void {
  window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  window.webContents.on('will-navigate', (event) => event.preventDefault());
  if (process.env.ELECTRON_RENDERER_URL) {
    void window.loadURL(`${process.env.ELECTRON_RENDERER_URL}/?view=${route}`);
  } else {
    void window.loadFile(join(__dirname, '../renderer/index.html'), { query: { view: route } });
  }
}

function showSettings(): void {
  if (!settings) {
    settings = new BrowserWindow({
      width: 1120, height: 780, minWidth: 820, minHeight: 640,
      show: false, title: 'Voco', titleBarStyle: 'hiddenInset', backgroundColor: '#080808',
      webPreferences: { preload: join(__dirname, '../preload/index.cjs'), contextIsolation: true, nodeIntegration: false, sandbox: true },
    });
    loadWindow(settings, 'settings');
    settings.on('close', (event) => {
      if (!quitting) {
        permissionReturn = null;
        event.preventDefault();
        settings?.hide();
      }
    });
    settings.once('ready-to-show', () => settings?.show());
  } else settings.show();
}

function focusSettings(): void {
  app.focus({ steal: true });
  showSettings();
  settings?.focus();
}

function permissionTarget(command: Command): PermissionTarget | null {
  switch (command.kind) {
    case 'requestMicrophone': return 'microphone';
    case 'requestAccessibility': return 'accessibility';
    case 'openPrivacy': return command.pane;
    default: return null;
  }
}

function permissionGranted(next: AppState, target: PermissionTarget): boolean {
  return target === 'microphone'
    ? next.permissions.microphone === 'granted'
    : next.permissions.accessibility;
}

function handleNativeFailure(message: string): void {
  permissionReturn = null;
  const transcript = state.session.kind === 'listening' || state.session.kind === 'recovery'
    ? state.session.text : state.lastTranscript;
  focusSettings();
  publish({ ...state, model: { kind: 'error', message, recovery: 'restart' }, session: { kind: 'recovery', message, text: transcript } });
}

async function verifyPermissionReturnFlow(window: BrowserWindow): Promise<Record<string, boolean>> {
  window.hide();
  publish({ ...state, permissions: { ...state.permissions, microphone: 'granted' } });
  const ordinaryGrantStayedClosed = !window.isVisible();
  publish({ ...state, permissions: { ...state.permissions, microphone: 'required' } });
  await window.webContents.executeJavaScript("window.voco.command({kind:'requestMicrophone'})");
  window.hide();
  publish({ ...state, permissions: { ...state.permissions, microphone: 'granted' } });
  const returnedOnGrant = window.isVisible();
  const focusedOnGrant = window.isFocused();
  window.hide();
  publish({ ...state });
  const repeatedSnapshotStayedClosed = !window.isVisible();
  await window.webContents.executeJavaScript("window.voco.command({kind:'requestAccessibility'})");
  await window.webContents.executeJavaScript('window.voco.closeSettings()');
  publish({ ...state, permissions: { ...state.permissions, accessibility: true } });
  const closeCanceledReturn = !window.isVisible();
  window.hide();
  handleNativeFailure('Verification failure.');
  return { ordinaryGrantStayedClosed, returnedOnGrant, focusedOnGrant, repeatedSnapshotStayedClosed,
    closeCanceledReturn, helperFailureRestoredSettings: window.isVisible() };
}

function createPill(): void {
  pill = new BrowserWindow({
    width: 400, height: 220, show: false, frame: false, transparent: true,
    focusable: false, resizable: false, movable: false, hasShadow: false, skipTaskbar: true,
    webPreferences: { preload: join(__dirname, '../preload/index.cjs'), contextIsolation: true, nodeIntegration: false, sandbox: true },
  });
  pill.setAlwaysOnTop(true, 'floating');
  pill.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  loadWindow(pill, 'pill');
}

function publish(next: AppState): void {
  nativeSeen = true;
  state = next;
  if (permissionReturn && permissionGranted(next, permissionReturn)) {
    permissionReturn = null;
    focusSettings();
  }
  settings?.webContents.send('voco:state', state);
  pill?.webContents.send('voco:state', state);
  if (state.session.kind === 'idle') pill?.hide();
  else if (pill) {
    pill.setFocusable(state.session.kind === 'recovery');
    if (!pill.isVisible()) {
      const display = screen.getDisplayNearestPoint(screen.getCursorScreenPoint());
      const { x, y, width, height } = display.workArea;
      pill.setPosition(Math.round(x + (width - 400) / 2), y + height - 230);
    }
    pill.setIgnoreMouseEvents(state.session.kind !== 'recovery', { forward: true });
    pill.showInactive();
  }
  updateMenu();
}

function updateMenu(): void {
  tray?.setToolTip(isReady(state) ? 'Voco · Ready to dictate' : 'Voco · Finish setup');
  tray?.setContextMenu(Menu.buildFromTemplate([
    { label: isReady(state) ? 'Ready to dictate' : 'Finish setup', enabled: false },
    { type: 'separator' },
    { label: 'Settings…', click: showSettings },
    { label: 'Copy last transcript', enabled: state.lastTranscript.length > 0, click: () => clipboard.writeText(state.lastTranscript) },
    { type: 'separator' },
    { label: 'Quit Voco', click: () => app.quit() },
  ]));
}

if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on('second-instance', showSettings);
  app.on('activate', showSettings);
  app.on('window-all-closed', () => {});
  app.on('before-quit', () => { quitting = true; bridge?.stop(); });
  void app.whenReady().then(() => {
    const helperExecutable = app.isPackaged
      ? join(process.resourcesPath, 'native/VocoNative.app/Contents/MacOS/VocoNative')
      : join(app.getAppPath(), 'native/build/VocoNative.app/Contents/MacOS/VocoNative');
    const modelDirectory = verificationModelDirectory ?? join(app.getPath('userData'), 'models/moonshine-medium-streaming-en');
    const liveInsertionIndex = process.argv.indexOf('--verify-live-insertion');
    const expectedEditorText = liveInsertionIndex >= 0 ? process.argv[liveInsertionIndex + 1] : undefined;
    const nativeVerificationArguments = process.argv.includes('--verify-microphone')
      ? ['--verify-microphone', '5', '--verification-output', join(verificationDirectory ?? '', 'microphone.json')]
      : expectedEditorText !== undefined
        ? ['--verify-live-insertion', expectedEditorText]
        : process.argv.includes('--verify-empty-rich-editor') ? ['--verify-empty-rich-editor'] : null;
    if (verificationDirectory && nativeVerificationArguments) {
      const fixtureIndex = process.argv.indexOf('--audio-fixture');
      const audioFixture = fixtureIndex >= 0 ? process.argv[fixtureIndex + 1] : undefined;
      if (audioFixture) {
        nativeVerificationArguments.push('--audio-fixture', audioFixture);
      }
      const child = spawn(helperExecutable, [...nativeVerificationArguments, '--model-directory', modelDirectory], { stdio: 'inherit' });
      child.once('error', (error) => { process.stderr.write(`${error.message}\n`); app.exit(1); });
      child.once('exit', (code) => app.exit(code ?? 1));
      return;
    }
    app.dock?.hide();
    session.defaultSession.setPermissionRequestHandler((_contents, _permission, callback) => callback(false));
    session.defaultSession.setPermissionCheckHandler(() => false);
    const brandDirectory = app.isPackaged
      ? join(process.resourcesPath, 'brand') : resolve('Resources/Brand');
    const icon = nativeImage.createFromPath(join(brandDirectory, 'voco-trayTemplate.png'));
    icon.setTemplateImage(true);
    tray = new Tray(icon);
    tray.on('click', showSettings);
    updateMenu();
    createPill();
    showSettings();
    bridge = new NativeBridge({
      executable: helperExecutable,
      modelDirectory,
      onState: publish,
      onShowSettings: showSettings,
      onFailure: handleNativeFailure,
    });
    bridge.start();
    function trusted(event: Electron.IpcMainInvokeEvent): void {
      const sender = event.sender;
      if (sender !== settings?.webContents && sender !== pill?.webContents) throw new Error('Unknown window.');
      if (event.senderFrame !== sender.mainFrame) throw new Error('Unknown frame.');
    }
    ipcMain.handle('voco:get-state', (event) => { trusted(event); return nativeSeen ? state : null; });
    ipcMain.handle('voco:command', async (event, value: unknown) => {
      trusted(event);
      const command = commandSchema.parse(value);
      if (command.kind === 'restart') { app.relaunch(); app.quit(); return; }
      if (command.kind === 'showApp') {
        shell.showItemInFolder(resolve(dirname(app.getPath('exe')), '..', '..'));
        return;
      }
      if (!bridge?.isRunning) {
        if (command.kind === 'copyLast') { clipboard.writeText(state.lastTranscript); return; }
        if (command.kind === 'cancel' || command.kind === 'copyRecovery') {
          if (command.kind === 'copyRecovery' && state.session.kind === 'recovery' && state.session.text) {
            clipboard.writeText(state.session.text);
          }
          publish({ ...state, session: { kind: 'idle' } });
          return;
        }
        throw new Error('The native service is unavailable. Restart Voco.');
      }
      const requestedPermission = permissionTarget(command);
      if (requestedPermission) permissionReturn = requestedPermission;
      if (verifyPermissionReturn && requestedPermission) return;
      try { await bridge.command(command); }
      catch (error) {
        if (permissionReturn === requestedPermission) permissionReturn = null;
        throw error;
      }
    });
    ipcMain.handle('voco:close-settings', (event) => { trusted(event); permissionReturn = null; settings?.hide(); });
    screen.on('display-metrics-changed', () => { if (state.session.kind !== 'idle') { pill?.hide(); publish(state); } });
    if (verificationDirectory) {
      const directory = verificationDirectory;
      const verify = async (): Promise<void> => {
        await mkdir(directory, { recursive: true });
        const deadline = Date.now() + 20_000;
        while ((!nativeSeen || settings?.webContents.isLoading() || pill?.webContents.isLoading()
          || (verificationModelDirectory && state.model.kind !== 'ready' && state.model.kind !== 'error')) && Date.now() < deadline) {
          await new Promise((resolve) => setTimeout(resolve, 50));
        }
        if (!settings || !pill || !nativeSeen) throw new Error('The desktop or native helper did not load.');
        await bridge?.command({ kind: 'refresh' });
        const permissionReturnReport = verifyPermissionReturn ? await verifyPermissionReturnFlow(settings) : undefined;
        if (verifyPermissionReturn) await bridge?.command({ kind: 'refresh' });
        const renderer = await settings.webContents.executeJavaScript(`({title:document.title,preload:typeof window.voco?.command==='function',preview:document.body.innerText.includes('Interface preview')})`);
        const background = await pill.webContents.executeJavaScript('getComputedStyle(document.body).backgroundColor');
        const capture = await settings.webContents.capturePage();
        await writeFile(join(directory, 'settings.png'), capture.toPNG());
        await writeFile(join(directory, 'report.json'), JSON.stringify({ ...renderer, background, helper: nativeSeen, model: state.model.kind, permissions: state.permissions, windowCount: BrowserWindow.getAllWindows().length, permissionReturn: permissionReturnReport }));
      };
      void verify().then(() => app.quit()).catch((error: unknown) => { process.stderr.write(`${error instanceof Error ? error.message : 'Desktop verification failed'}\n`); app.exit(1); });
    }
  });
}
