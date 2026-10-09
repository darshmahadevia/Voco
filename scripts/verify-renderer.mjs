import { spawn } from 'node:child_process';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const directory = await mkdtemp(join(tmpdir(), 'voco-renderer-check-'));
const renderer = resolve('out/renderer/index.html');
const preload = join(directory, 'preload.cjs');
const fixture = join(directory, 'main.cjs');
await writeFile(preload, `
const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('voco', {
  getState: () => ipcRenderer.invoke('fixture:get-state'),
  subscribe: listener => {
    const receive = (_event, state) => listener(state);
    ipcRenderer.on('fixture:state', receive);
    return () => ipcRenderer.removeListener('fixture:state', receive);
  },
  command: command => ipcRenderer.invoke('fixture:command', command),
  closeSettings: async () => {},
});
`);
await writeFile(fixture, `
const { app, BrowserWindow, ipcMain } = require('electron');
const assert = require('node:assert/strict');
app.setPath('userData', ${JSON.stringify(join(directory, 'profile'))});
const ready = {
  audioLevel: 0, model: {kind: 'ready'},
  permissions: {microphone: 'granted', accessibility: true, shortcut: true},
  session: {kind: 'idle'}, preferences: {keepLastTranscript: true}, lastTranscript: '',
};
const missing = {...ready, model: {kind: 'missing'}, permissions: {microphone: 'required', accessibility: false, shortcut: false}};
let state = null;
let delayedRead = false;
let finishRead;
let readStarted = false;
let copiedText = '';
let rejectCopy = false;
ipcMain.handle('fixture:command', (_event, command) => {
  if (command.kind === 'copyLast') {
    if (rejectCopy) throw new Error('Clipboard is temporarily unavailable.');
    copiedText = state.lastTranscript;
  }
  if (command.kind === 'copyRecovery') {
    if (rejectCopy) throw new Error('Clipboard is temporarily unavailable.');
    copiedText = state.session.text;
  }
});
ipcMain.handle('fixture:get-state', () => {readStarted = true; return delayedRead ? new Promise(resolve => {finishRead = resolve;}) : state;});
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
app.whenReady().then(async () => {
  const window = new BrowserWindow({show: false, width: 1120, height: 780,
    webPreferences: {preload: ${JSON.stringify(preload)}, contextIsolation: true, sandbox: true}});
  const read = expression => window.webContents.executeJavaScript(expression);
  const publish = next => {state = next; window.webContents.send('fixture:state', next);};
  const wait = async expression => {
    const deadline = Date.now() + 3000;
    while (!(await read(expression))) {
      if (Date.now() > deadline) throw new Error('Timed out: ' + expression);
      await pause(25);
    }
  };
  const load = async (view = 'settings') => {
    readStarted = false;
    await window.loadFile(${JSON.stringify(renderer)}, {query: {view}});
    const deadline = Date.now() + 3000;
    while (!readStarted) {
      if (Date.now() > deadline) throw new Error('Renderer did not request its initial state');
      await pause(25);
    }
  };
  try {
    await load();
    await wait("document.querySelector('.startup-shell') !== null");
    assert.equal(await read("document.body.innerText.includes('A little setup.')"), false, 'unknown startup must not show onboarding');
    publish({...ready, model: {kind: 'loading'}});
    await wait("document.querySelector('#home-heading') !== null");
    assert.equal(await read("document.body.innerText.includes('Loading speech model')"), true);
    assert.equal(await read("document.body.innerText.includes('Finish setting up')"), false, 'model warmup is not missing setup');
    publish(ready);
    await wait("document.body.innerText.includes('Ready to dictate')");
    assert.equal(await read("document.querySelector('.transcript-panel').getBoundingClientRect().height > 0"), true, 'latest transcript stays visible');
    assert.equal(await read("document.querySelector('.dashboard details') === null"), true, 'latest transcript is not a disclosure');
    assert.equal(await read("document.querySelector('.dashboard button[aria-label=Settings]') === null && ![...document.querySelectorAll('.dashboard button')].some(button => button.textContent.trim() === 'Settings')"), true, 'Settings belongs in the sidebar');
    assert.equal(await read("document.querySelector('.copy-transcript-button').disabled"), true, 'empty transcript cannot be copied');
    await read("document.querySelector('.app-sidebar button[aria-label=Settings]').click()");
    await wait("document.querySelector('.settings-shell') !== null");
    await read("document.querySelector('.app-sidebar button[aria-label=Home]').click()");
    await wait("document.querySelector('#home-heading') !== null");
    publish({...ready, lastTranscript: 'Bring the meeting notes tomorrow.'});
    await wait("document.querySelector('.last-transcript').textContent === 'Bring the meeting notes tomorrow.'");
    const copyWidth = await read("document.querySelector('.copy-transcript-button').getBoundingClientRect().width");
    await read("document.querySelector('.copy-transcript-button').click()");
    await wait("document.querySelector('.copy-transcript-button').getAttribute('aria-label') === 'Copied'");
    assert.equal(await read("document.querySelector('.copy-transcript-button').getBoundingClientRect().width"), copyWidth, 'copy confirmation preserves button width');
    await read("document.fonts.ready.then(() => true)");
    assert.equal(await read("[...document.fonts].some(font => font.family === 'Pixelify Sans' && font.status === 'loaded')"), true, 'bundled Pixelify Sans loads successfully');
    assert.equal(copiedText, 'Bring the meeting notes tomorrow.', 'copy action receives the latest transcript');
    publish({...ready, lastTranscript: 'Send the revised draft.'});
    await wait("document.querySelector('.last-transcript').textContent === 'Send the revised draft.'");
    assert.equal(await read("document.querySelector('.copy-transcript-button').getAttribute('aria-label') === 'Copied'"), false, 'new transcript clears the old copy confirmation');
    rejectCopy = true;
    await read("document.querySelector('.copy-transcript-button').click()");
    await wait("document.querySelector('.transcript-panel [role=alert]') !== null");
    assert.equal(await read("document.querySelector('.copy-transcript-button').getAttribute('aria-label') === 'Copied'"), false, 'failed copy must not claim success');
    assert.equal(await read("document.querySelector('.last-transcript').textContent"), 'Send the revised draft.', 'failed copy retains the transcript');
    rejectCopy = false;
    await read("document.querySelector('.copy-transcript-button').click()");
    await wait("document.querySelector('.copy-transcript-button').getAttribute('aria-label') === 'Copied'");
    assert.equal(copiedText, 'Send the revised draft.', 'retry copies the current transcript');
    await wait("document.querySelector('.copy-transcript-button').getAttribute('aria-label') === 'Copy transcript'");
    publish({...ready, preferences: {keepLastTranscript: false}, lastTranscript: 'A private thought.'});
    await wait("document.querySelector('.copy-transcript-button').disabled");
    assert.equal(await read("document.querySelector('.transcript-panel').innerText.includes('A private thought.')"), false, 'disabled retention does not expose transcript text');
    publish({...ready, lastTranscript: 'A long thought. '.repeat(100)});
    await wait("document.querySelector('.last-transcript')?.textContent.length > 1000");
    await read("document.querySelector('.transcript-panel').dataset.fixturePersistence = 'present'; document.querySelector('.last-transcript').scrollTop = 100; document.querySelector('.copy-transcript-button').focus()");
    publish({...ready, lastTranscript: 'A long thought. '.repeat(100) + 'Still speaking.'});
    await wait("document.querySelector('.last-transcript').textContent.endsWith('Still speaking.')");
    assert.equal(await read("document.querySelector('.transcript-panel').dataset.fixturePersistence"), 'present', 'streaming updates keep the existing transcript panel');
    assert.equal(await read("document.querySelector('.last-transcript').scrollTop"), 100, 'streaming updates preserve transcript scroll position');
    assert.equal(await read("document.activeElement.matches('.copy-transcript-button')"), true, 'streaming updates preserve copy button focus');
    publish(ready);
    await wait("document.querySelector('.copy-transcript-button').disabled");
    for (const [width, height] of [[1120, 780], [820, 640], [390, 844], [320, 740]]) {
      window.setSize(width, height);
      await pause(100);
      const layout = await read("(() => { const heading = document.querySelector('#home-heading'); const range = document.createRange(); range.selectNodeContents(heading.querySelector('.headline-manrope')); const firstLine = range.getBoundingClientRect(); const secondLine = heading.querySelector('.headline-pixel').getBoundingClientRect(); const workspace = document.querySelector('.app-content').getBoundingClientRect(); return { firstSize: getComputedStyle(heading.querySelector('.headline-manrope')).fontSize, secondSize: getComputedStyle(heading.querySelector('.headline-pixel')).fontSize, pixelFamily: getComputedStyle(heading.querySelector('.headline-pixel')).fontFamily, width: innerWidth, workspaceCenter: workspace.left + workspace.width / 2, contentWidth: document.documentElement.scrollWidth, firstCenter: firstLine.left + firstLine.width / 2, secondCenter: secondLine.left + secondLine.width / 2, }; })()");
      assert.equal(layout.firstSize, layout.secondSize, 'headline lines must use equal font sizes at width ' + width);
      assert.equal(layout.pixelFamily.includes('Pixelify Sans'), true, 'accent line must use Pixelify Sans');
      assert.equal(layout.contentWidth <= layout.width, true, 'Home must fit its viewport at width ' + width);
      assert.equal(Math.abs(layout.firstCenter - layout.workspaceCenter) <= 2, true, 'first headline line must be centered at width ' + width);
      assert.equal(Math.abs(layout.secondCenter - layout.workspaceCenter) <= 2, true, 'pixel headline line must be centered at width ' + width);
    }
    window.setSize(1120, 780);
    publish(ready);
    await wait("document.body.innerText.includes('Ready to dictate')");
    await pause(100);
    const idleFirst = await read("[...document.querySelectorAll('.voice-core .waveform-energy')].map(bar => bar.getBoundingClientRect().height)");
    await pause(320);
    const idleSecond = await read("[...document.querySelectorAll('.voice-core .waveform-energy')].map(bar => bar.getBoundingClientRect().height)");
    assert.equal(idleFirst.some((height, index) => Math.abs(height - idleSecond[index]) > 1), true, 'idle waveform visibly moves inside the circle');
    assert.equal(await read("document.querySelector('.voice-caption').textContent.includes('Ready to dictate')"), true, 'idle motion does not imply listening');
    publish({...ready, permissions: {...ready.permissions, shortcut: false}});
    await wait("document.body.innerText.includes('Setup needed')");
    assert.equal(await read("document.querySelector('#home-heading') !== null"), true, 'runtime permission change must not restart onboarding');
    publish({...ready, session: {kind: 'recovery', message: 'Choose an editable field, or copy your words.', text: 'Keep these words safe. '.repeat(60)}});
    await wait("document.querySelector('.home-recovery') !== null");
    assert.equal(await read("document.querySelector('.voice-caption').textContent.includes('Ready to dictate')"), false, 'recovery must not claim readiness');
    assert.equal(await read("document.querySelector('.home-recovery .recovery-transcript').textContent.includes('Keep these words safe.')"), true, 'Home retains recovery words');
    assert.equal(await read("(() => { const text = document.querySelector('.home-recovery .recovery-transcript'); text.scrollTop = text.scrollHeight; return text.scrollTop > 0; })()"), true, 'long Home recovery can be read by scrolling');

    state = missing;
    await load();
    await wait("document.body.innerText.includes('A little setup.')");
    await read("document.querySelectorAll('.setup-steps button')[3].click()");
    await wait("document.querySelector('.practice-blocker button') !== null");
    assert.equal(await read("document.querySelector('#practice-text').disabled"), true, 'practice waits for a usable model and permissions');
    await read("document.querySelector('.practice-blocker button').click()");
    await wait("document.querySelector('.setup-steps button[aria-current=step]').textContent.includes('Speech model')");
    await read("document.querySelectorAll('.setup-steps button')[0].click()");
    publish(ready);
    await pause(100);
    assert.equal(await read("document.body.innerText.includes('A little setup.')"), true, 'first-time setup stays open until the user finishes');

    state = null;
    delayedRead = true;
    await load();
    await wait("document.querySelector('.startup-shell') !== null");
    publish(ready);
    await wait("document.querySelector('#home-heading') !== null");
    finishRead(null);
    await pause(100);
    assert.equal(await read("document.querySelector('#home-heading') !== null"), true, 'late initial read must not overwrite a newer state');
    delayedRead = false;

    const listening = {...ready, audioLevel: 0.65, session: {kind: 'listening', mode: 'hold', buffered: false, text: ''}};
    publish(listening);
    await wait("document.querySelector('.voice-core .waveform-active') !== null");
    await pause(400);
    const heights = () => read("[...document.querySelectorAll('.voice-core .waveform-energy')].map(bar => bar.getBoundingClientRect().height)");
    const first = await heights();
    await pause(250);
    const second = await heights();
    assert.equal(first.some((height, index) => Math.abs(height - second[index]) > 0.5), true, 'bars must animate with steady speech');
    publish({...listening, audioLevel: 0});
    await wait("document.querySelector('.voice-core .waveform-active') === null");
    await pause(600);
    assert.equal((await heights()).every(height => height <= 3.1), true, 'silent bars must settle to their baseline');

    state = listening;
    await load('pill');
    await wait("document.querySelector('.pill-status .waveform-active') !== null");
    assert.equal(await read("document.querySelector('.pill-title').textContent"), 'Listening…');
    window.webContents.debugger.attach('1.3');
    await window.webContents.debugger.sendCommand('Emulation.setEmulatedMedia', {features: [{name: 'prefers-reduced-motion', value: 'reduce'}]});
    assert.equal(await read("[...document.querySelectorAll('.waveform-energy')].every(bar => getComputedStyle(bar).animationName === 'none')"), true, 'reduced motion must stop the equalizer loop');
    window.webContents.debugger.detach();
    window.setSize(400, 220);
    const recoveryText = 'Bring the meeting notes tomorrow. '.repeat(30);
    publish({...ready, session: {kind: 'recovery', message: 'The target field is unavailable. Choose an editable field, or copy your words. '.repeat(5), text: recoveryText}});
    await wait("document.querySelector('.recovery-actions button') !== null");
    await pause(250);
    const actionsFit = () => read("(() => { const copy = document.querySelector('.recovery-actions button').getBoundingClientRect(); const dismiss = document.querySelector('.recovery-heading .button').getBoundingClientRect(); return copy.top >= 0 && copy.bottom <= innerHeight && dismiss.top >= 0 && dismiss.bottom <= innerHeight && document.documentElement.scrollWidth <= innerWidth; })()");
    assert.equal(await actionsFit(), true, 'recovery actions fit the native pill with a long message');
    rejectCopy = true;
    await read("document.querySelector('.recovery-actions button').click()");
    await wait("document.querySelector('.recovery-content [role=alert]') !== null");
    assert.equal(await actionsFit(), true, 'failed recovery copy keeps its actions reachable');
    rejectCopy = false;
    await read("document.querySelector('.recovery-actions button').click()");
    await wait("document.querySelector('.recovery-actions button').disabled === false");
    assert.equal(copiedText, recoveryText, 'recovery retry copies all words, including outside the excerpt');
    console.log('Renderer regression: PASS centered responsive layout, sidebar navigation, visible transcript, copy success/retry/reset/privacy, streaming focus/scroll, idle waveform, startup, model warmup, first-run routing, state race, live waveform, silence, pill, reduced motion');
    app.quit();
  } catch (error) {console.error(error); app.exit(1);}
});
`);
const environment = { ...process.env };
delete environment.ELECTRON_RUN_AS_NODE;
try {
  const child = spawn(require('electron'), [fixture], { stdio: 'inherit', env: environment });
  const timeout = setTimeout(() => child.kill('SIGTERM'), 30_000);
  const code = await new Promise((resolveExit) => child.once('exit', resolveExit));
  clearTimeout(timeout);
  if (code !== 0) throw new Error(`Renderer regression exited with ${code}`);
} finally {
  await rm(directory, { recursive: true, force: true });
}
