const { app, BrowserWindow, ipcMain } = require('electron');
const { mkdir, writeFile } = require('node:fs/promises');
const { resolve, join } = require('node:path');
const assert = require('node:assert/strict');

const output = resolve(process.argv[2] || '/tmp/voco-motion');
const renderer = resolve(__dirname, '../out/renderer/index.html');
let window;
const errors = [];
const evaluate = expression => window.webContents.executeJavaScript(expression, true);
const frame = () => evaluate('new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))');
const settle = () => evaluate('document.fonts.ready.then(() => new Promise(resolve => setTimeout(resolve, 500)))');
async function navigate(label) {
  await evaluate(`document.querySelector('button[aria-label=${JSON.stringify(label)}]').click()`);
  await frame();
}
async function capture(name) {
  await writeFile(join(output, `${name}.png`), (await window.webContents.capturePage()).toPNG());
}

app.whenReady().then(async () => {
  await mkdir(output, { recursive: true });
  window = new BrowserWindow({ width: 960, height: 720, show: false, webPreferences: { contextIsolation: true, backgroundThrottling: false } });
  window.webContents.on('console-message', (_event, details) => { if (details.level === 'error') errors.push(details.message); });
  await window.loadFile(renderer, { query: { preview: 'ready', page: 'home' } });
  await settle();
  await capture('home');
  assert.equal(await evaluate("CSS.supports('interpolate-size', 'allow-keywords')"), true, 'Electron does not support intrinsic disclosure animation');
  assert.equal(await evaluate("CSS.supports('appearance', 'base-select')"), true, 'Electron does not support native styled pickers');
  const ribbonFrame = await evaluate("document.querySelector('.voice-art pre').textContent");
  await settle();
  assert.equal(await evaluate("document.querySelector('.voice-art').dataset.motion"), 'running');
  assert.notEqual(await evaluate("document.querySelector('.voice-art pre').textContent"), ribbonFrame, 'ASCII artwork does not change glyph frames');
  await evaluate("document.querySelector('.voice-art').style.transform = 'translateY(-2000px)'");
  await settle();
  assert.equal(await evaluate("document.querySelector('.voice-art').dataset.motion"), 'paused', 'Offscreen artwork keeps running');
  const pausedRibbon = await evaluate("document.querySelector('.voice-art pre').textContent");
  await settle();
  assert.equal(await evaluate("document.querySelector('.voice-art pre').textContent"), pausedRibbon, 'Offscreen artwork changes glyph frames');
  await evaluate("document.querySelector('.voice-art').style.transform = ''");
  await settle();
  assert.equal(await evaluate("document.querySelector('.voice-art').dataset.motion"), 'running', 'Visible artwork did not resume');
  window.webContents.setBackgroundThrottling(true);
  window.showInactive();
  await settle();
  window.hide();
  await new Promise(resolve => setTimeout(resolve, 250));
  assert.equal(await evaluate('document.hidden'), true, 'Hidden native window reports a visible document');
  assert.equal(await evaluate("document.querySelector('.voice-art').dataset.motion"), 'paused', 'Hidden window keeps artwork running');
  const hiddenRibbon = await evaluate("document.querySelector('.voice-art pre').textContent");
  await new Promise(resolve => setTimeout(resolve, 250));
  assert.equal(await evaluate("document.querySelector('.voice-art pre').textContent"), hiddenRibbon, 'Hidden artwork changes glyph frames');
  window.webContents.setBackgroundThrottling(false);
  await settle();
  const transitions = [];
  for (const label of ['Transcripts', 'Settings', 'Stats', 'Home']) {
    await navigate(label);
    const during = await evaluate(`(() => {
      const pages = [...document.querySelectorAll('.page-transition')];
      return { filters: pages.map(page => getComputedStyle(page).filter),
        interactiveMains: [...document.querySelectorAll('main')].filter(main => !main.closest('[inert]')).length,
        maxOpacity: Math.max(...pages.map(page => Number(getComputedStyle(page).opacity))) };
    })()`);
    assert.ok(during.filters.every(filter => filter === 'none' || filter === 'blur(0px)'), `${label}: page text blurs during navigation`);
    assert.equal(during.interactiveMains, 1, `${label}: outgoing controls remain interactive`);
    assert.ok(during.maxOpacity > 0.2, `${label}: navigation leaves a blank frame`);
    await settle();
    assert.equal(await evaluate("document.querySelector('.nav-item[aria-current=page]').getAttribute('aria-label')"), label);
    assert.ok(await evaluate("document.activeElement?.matches('main h1')"), `${label}: focus did not reach the new heading`);
    await capture(label.toLowerCase());
    transitions.push({ page: label, ...during });
  }
  for (const label of ['Transcripts', 'Stats', 'Settings', 'Transcripts']) await navigate(label);
  await settle();
  assert.equal(await evaluate("document.querySelector('.nav-item[aria-current=page]').getAttribute('aria-label')"), 'Transcripts');
  assert.equal(await evaluate("document.querySelectorAll('.page-transition').length"), 1);
  assert.equal(await evaluate("document.activeElement.textContent"), 'Transcripts');
  await evaluate(`(() => { const input = document.querySelector('input[type=search]'); input.focus(); Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(input, 'meeting'); input.dispatchEvent(new Event('input', { bubbles: true })); })()`);
  await settle();
  assert.ok(await evaluate("document.activeElement.matches('input[type=search]')"), 'Filtering stole keyboard focus');
  assert.equal(await evaluate("document.querySelectorAll('.recent-transcript-row').length"), 1);
  await capture('filtered-transcripts');
  await navigate('Settings');
  await settle();
  for (const [label, target] of [['Models', 'model-heading'], ['Access', 'access-heading'], ['Dictation', 'dictation-heading'], ['Output', 'output-heading']]) {
    await evaluate(`[...document.querySelectorAll('[role=tab]')].find(tab => tab.textContent.trim() === '${label}').click()`);
    await settle();
    assert.equal(await evaluate("document.querySelector('[role=tab][aria-selected=true]').textContent.trim()"), label, `${label}: selected tab is wrong`);
    assert.equal(await evaluate("[...document.querySelectorAll('[role=tabpanel]')].filter(panel => !panel.hidden).length"), 1, `${label}: unrelated settings remain visible`);
    assert.ok(await evaluate(`(() => { const heading = document.getElementById('${target}'); const panel = heading.closest('[role=tabpanel]'); const tab = document.querySelector('[role=tab][aria-selected=true]'); return !panel.hidden && panel.getAttribute('aria-labelledby') === tab.id && document.getElementById(tab.getAttribute('aria-controls')) === panel; })()`), `${label}: panel is not linked to its tab`);
    assert.ok(await evaluate(`(() => { const r = document.getElementById('${target}').getBoundingClientRect(); const main = document.querySelector('.workspace-main').getBoundingClientRect(); return r.top >= main.top && r.bottom <= main.bottom; })()`), `${label}: section heading is not visible`);
    await capture(`settings-${label.toLowerCase()}`);
  }
  await evaluate("document.querySelector('[role=tab][aria-selected=true]').focus()");
  for (const [key, expected] of [['Right', 'Models'], ['End', 'Dictation'], ['Right', 'Output'], ['Left', 'Dictation'], ['Home', 'Output']]) {
    window.webContents.sendInputEvent({ type: 'keyDown', keyCode: key });
    window.webContents.sendInputEvent({ type: 'keyUp', keyCode: key });
    await frame();
    assert.equal(await evaluate("document.activeElement.textContent.trim()"), expected, `${key}: tab keyboard focus is wrong`);
    assert.equal(await evaluate("document.querySelector('[role=tab][aria-selected=true]').textContent.trim()"), expected, `${key}: selected panel did not follow focus`);
  }
  await evaluate("document.querySelector('#settings-tab-models').click()");
  await navigate('Home');
  await settle();
  await navigate('Settings');
  await settle();
  assert.equal(await evaluate("document.querySelector('[role=tab][aria-selected=true]').textContent.trim()"), 'Models', 'Settings forgot the selected tab after navigation');
  await evaluate("document.querySelector('#settings-tab-output').click()");
  await frame();
  async function key(keyCode) {
    window.webContents.sendInputEvent({ type: 'keyDown', keyCode });
    if (keyCode === 'Return' || keyCode === 'Space') window.webContents.sendInputEvent({ type: 'char', keyCode: keyCode === 'Return' ? '\r' : ' ' });
    window.webContents.sendInputEvent({ type: 'keyUp', keyCode });
    await frame();
  }
  async function disclosure(selector, reduced = false) {
    await evaluate(`document.querySelector('${selector} summary').focus()`);
    const closed = await evaluate(`document.querySelector('${selector}').getBoundingClientRect().height`);
    await key('Return');
    assert.equal(await evaluate(`document.querySelector('${selector}').open`), true, `${selector}: Enter did not open disclosure`);
    const opening = await evaluate(`document.querySelector('${selector}').getBoundingClientRect().height`);
    await settle();
    const opened = await evaluate(`document.querySelector('${selector}').getBoundingClientRect().height`);
    assert.ok(opened > closed + 10, `${selector}: content did not expand`);
    if (!reduced) assert.ok(opening < opened, `${selector}: opening jumps to its final height`);
    await key('Space');
    assert.equal(await evaluate(`document.querySelector('${selector}').open`), false, `${selector}: Space did not close disclosure`);
    const closing = await evaluate(`document.querySelector('${selector}').getBoundingClientRect().height`);
    if (!reduced) assert.ok(closing > closed, `${selector}: closing snaps shut`);
    await settle();
    assert.ok(Math.abs(await evaluate(`document.querySelector('${selector}').getBoundingClientRect().height`) - closed) < 1, `${selector}: closed content leaves a gap`);
    await key('Return');
    await key('Return');
    await key('Return');
    await settle();
    assert.equal(await evaluate(`document.querySelector('${selector}').open`), true, `${selector}: rapid reversal lost final intent`);
    assert.ok(Math.abs(await evaluate(`document.querySelector('${selector}').getBoundingClientRect().height`) - opened) < 1, `${selector}: reversal clips content`);
    await key('Return');
    await settle();
  }
  await disclosure('.output-details');
  await navigate('Stats');
  await settle();
  await disclosure('.progress-preferences');
  await evaluate("document.querySelector('.progress-preferences').open = true");
  await settle();
  await evaluate("document.querySelector('.preference-select').focus()");
  await key('Space');
  assert.equal(await evaluate("document.querySelector('.preference-select').matches(':open')"), true, 'Space did not open native picker');
  await settle();
  await capture('goal-dropdown');
  await key('End');
  await key('Return');
  await settle();
  assert.equal(await evaluate("document.querySelector('.preference-select').value"), '10000', 'Keyboard selection did not update goal');
  assert.equal(await evaluate("document.querySelector('.preference-select').matches(':open')"), false, 'Selection left native picker open');
  await key('Space');
  await key('Escape');
  assert.equal(await evaluate("document.querySelector('.preference-select').matches(':open')"), false, 'Escape did not dismiss native picker');
  assert.ok(await evaluate("document.activeElement.matches('.preference-select')"), 'Closing picker lost keyboard focus');
  await key('Space');
  window.webContents.sendInputEvent({ type: 'mouseDown', x: 20, y: 90, button: 'left', clickCount: 1 });
  window.webContents.sendInputEvent({ type: 'mouseUp', x: 20, y: 90, button: 'left', clickCount: 1 });
  await frame();
  assert.equal(await evaluate("document.querySelector('.preference-select').matches(':open')"), false, 'Outside click did not dismiss native picker');
  await evaluate("document.querySelector('.preference-select').focus(); document.querySelector('.progress-preferences').open = false");
  await frame();
  assert.ok(await evaluate("document.activeElement.matches('.progress-preferences summary')"), 'Programmatic close did not return focus to disclosure');
  await evaluate("document.querySelector('.preference-select').focus()");
  assert.equal(await evaluate("document.activeElement.matches('.preference-select')"), false, 'Closed disclosure controls remain focusable');
  window.webContents.debugger.attach('1.3');
  await window.webContents.debugger.sendCommand('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-reduced-motion', value: 'reduce' }] });
  await frame();
  await navigate('Home');
  await settle();
  assert.equal(await evaluate("document.querySelector('.voice-art').dataset.motion"), 'paused', 'Reduced motion leaves decorative animation running');
  const reducedRibbon = await evaluate("document.querySelector('.voice-art pre').textContent");
  await settle();
  assert.equal(await evaluate("document.querySelector('.voice-art pre').textContent"), reducedRibbon, 'Reduced motion still changes glyphs');
  await navigate('Settings');
  await settle();
  await disclosure('.output-details', true);
  await navigate('Transcripts');
  assert.equal(await evaluate("matchMedia('(prefers-reduced-motion: reduce)').matches"), true);
  assert.equal(await evaluate("document.querySelectorAll('.page-transition').length"), 1);
  const reduced = await evaluate("({ opacity: getComputedStyle(document.querySelector('.page-transition')).opacity, transform: getComputedStyle(document.querySelector('.page-transition')).transform, filter: getComputedStyle(document.querySelector('.page-transition')).filter })");
  assert.ok(Number(reduced.opacity) >= 0.7 && Number(reduced.opacity) <= 1, 'Reduced motion left the destination unreadable');
  assert.ok(reduced.transform === 'none' || reduced.transform === 'matrix(1, 0, 0, 1, 0, 0)');
  assert.ok(reduced.filter === 'none' || reduced.filter === 'blur(0px)');
  window.webContents.debugger.detach();
  let fixture = {
    userName: 'Alex', audioLevel: 0, audioWaveform: Array(11).fill(0),
    model: { kind: 'ready' }, selectedModel: 'moonshine', recommendedModel: 'parakeet',
    models: ['moonshine', 'parakeet', 'whisper'].map(id => ({ id, state: { kind: id === 'moonshine' ? 'ready' : 'missing' } })),
    permissions: { microphone: 'granted', accessibility: true, shortcut: true },
    session: { kind: 'idle' }, preferences: { keepLastTranscript: true, outputMode: 'fast' },
    lastTranscript: '', lastRawTranscript: '', polishNotice: '',
    polishing: { kind: 'unavailable', message: 'AI formatting unavailable in this test.' },
    usage: { days: {}, dailyGoal: 500, typingWpm: 40 },
  };
  const commands = [];
  ipcMain.handle('voco:get-state', () => fixture);
  ipcMain.handle('voco:get-navigation', () => null);
  ipcMain.handle('voco:command', (_event, command) => {
    commands.push(command);
    if (command.kind === 'setPreferences') {
      fixture = { ...fixture, preferences: command.preferences, ...(!command.preferences.keepLastTranscript ? { lastTranscript: '', lastRawTranscript: '' } : {}) };
      window.webContents.send('voco:state', fixture);
    }
  });
  const previewWindow = window;
  window = new BrowserWindow({ width: 960, height: 720, show: false, webPreferences: { contextIsolation: true, backgroundThrottling: false, preload: resolve(__dirname, '../out/preload/index.cjs') } });
  window.webContents.on('console-message', (_event, details) => { if (details.level === 'error') errors.push(details.message); });
  previewWindow.destroy();
  await window.loadFile(renderer, { query: { page: 'settings' } });
  await settle();
  assert.equal(await evaluate("Boolean(document.querySelector('.preview-notice'))"), false);
  await publish({ model: { kind: 'loading' }, models: fixture.models.map(model => model.id === fixture.selectedModel ? { ...model, state: { kind: 'loading' } } : model) });
  await settle();
  assert.equal(await evaluate("document.querySelector('.workspace-status [role=status]').textContent"), 'Loading speech model');
  assert.ok(await evaluate("Boolean(document.querySelector('.workspace-status .pill-loader'))"), 'Loading model is shown as ready');
  await publish({ model: { kind: 'ready' }, models: fixture.models.map(model => model.id === fixture.selectedModel ? { ...model, state: { kind: 'ready' } } : model) });
  await evaluate("document.querySelector('input[name=output-mode][value=balanced]').click()");
  await frame();
  assert.equal(commands.length, 1, 'Output preference command was delayed or repeated');
  assert.deepEqual(commands[0], { kind: 'setPreferences', preferences: { keepLastTranscript: true, outputMode: 'balanced' } });
  async function publish(patch) {
    fixture = { ...fixture, ...patch };
    window.webContents.send('voco:state', fixture);
    await frame();
  }
  await publish({ session: { kind: 'listening' }, audioLevel: 0.5, audioWaveform: Array(11).fill(0.1) });
  await settle();
  assert.equal(await evaluate("document.querySelector('.live-shortcut').textContent"), 'Press Esc to cancel');
  assert.equal(await evaluate("document.querySelector('.output-availability').textContent"), 'Finish or dismiss this dictation to change output settings.');
  await evaluate("window.__statusNode = document.querySelector('.workspace-status')");
  await publish({ audioLevel: 0.7, audioWaveform: Array(11).fill(0.2) });
  assert.equal(await evaluate("window.__statusNode === document.querySelector('.workspace-status')"), true, 'Audio frames remounted persistent status');
  await navigate('Transcripts');
  await settle();
  assert.equal(await evaluate("window.__statusNode === document.querySelector('.workspace-status')"), true, 'Navigation remounted persistent status');
  await publish({ audioLevel: 0, audioWaveform: Array(11).fill(0) });
  await settle();
  await settle();
  const silentWaveform = await evaluate("[...document.querySelectorAll('.workspace-status .waveform > span')].map(bar => getComputedStyle(bar).transform)");
  assert.equal(silentWaveform.length, 11, 'Listening status lost measured waveform bars');
  await frame();
  assert.deepEqual(await evaluate("[...document.querySelectorAll('.workspace-status .waveform > span')].map(bar => getComputedStyle(bar).transform)"), silentWaveform, 'Silence animates a synthetic waveform');
  await publish({ session: { kind: 'finishing' }, audioLevel: 0, audioWaveform: Array(11).fill(0) });
  await publish({ session: { kind: 'idle' }, lastTranscript: 'Words retained only for this session.' });
  await settle();
  assert.equal(await evaluate("document.querySelectorAll('.recent-transcript-row').length"), 1);
  await navigate('Settings');
  await settle();
  await evaluate("[...document.querySelectorAll('[role=tab]')].find(tab => tab.textContent.trim() === 'Dictation').click()");
  await frame();
  await evaluate("document.querySelector('button[role=switch]').click()");
  await frame();
  assert.equal(commands.length, 2, 'Retention preference command was delayed or repeated');
  await navigate('Transcripts');
  await settle();
  assert.equal(await evaluate("document.querySelectorAll('.recent-transcript-row').length"), 0);
  assert.ok(await evaluate("!document.body.innerText.includes('Words retained only for this session.')"), 'Turning off retention left transcript text visible');
  await evaluate("[...document.querySelectorAll('button')].find(button => button.textContent.trim() === 'Open Dictation settings').click()");
  await settle();
  assert.equal(await evaluate("document.querySelector('[role=tab][aria-selected=true]').textContent.trim()"), 'Dictation');
  assert.equal(await evaluate("document.querySelector('button[role=switch]').getAttribute('aria-checked')"), 'false');
  assert.equal(commands.length, 2, 'Opening preferences changed transcript retention');
  await navigate('Home');
  await settle();
  await evaluate("[...document.querySelectorAll('button')].find(button => button.textContent.trim() === 'Open Dictation settings').click()");
  await settle();
  assert.equal(await evaluate("document.querySelector('[role=tab][aria-selected=true]').textContent.trim()"), 'Dictation');
  await publish({ session: { kind: 'recovery', message: 'The destination changed.', text: 'Recover all of these words.' } });
  await settle();
  for (const label of ['Settings', 'Transcripts']) {
    await navigate(label);
    await settle();
    assert.ok(await evaluate("document.querySelector('.recovery-content').innerText.includes('Recover all of these words.')"), `${label}: recovery is inaccessible`);
  }
  assert.equal(await evaluate("document.querySelector('.live-shortcut').textContent"), 'Your transcript is ready to copy');
  await capture('native-recovery');
  await publish({ session: { kind: 'recovery', message: 'The helper stopped before transcription.', text: '' } });
  await settle();
  assert.equal(await evaluate("document.querySelector('.live-shortcut').textContent"), 'Review the error above to continue');
  assert.equal(await evaluate("document.querySelector('.recovery-actions button').disabled"), true);
  await publish({ session: { kind: 'idle' } });
  await navigate('Settings');
  await settle();
  await evaluate("[...document.querySelectorAll('[role=tab]')].find(tab => tab.textContent.trim() === 'Models').click()");
  await frame();
  await evaluate("document.querySelector('[data-model-id=parakeet] button').click()");
  await frame();
  assert.deepEqual(commands.at(-1), { kind: 'downloadModel', modelId: 'parakeet' }, 'Model download uses the wrong command');
  await publish({ models: fixture.models.map(model => model.id === 'parakeet' ? { ...model, state: { kind: 'downloading', progress: 0.42, file: 'parakeet-model' } } : model) });
  await settle();
  assert.equal(await evaluate("document.querySelector('[data-model-id=parakeet] progress').value"), 0.42);
  await evaluate("document.querySelector('button[aria-label=\"Cancel Parakeet download\"]').click()");
  await frame();
  assert.deepEqual(commands.at(-1), { kind: 'cancelDownload' }, 'Model cancellation uses the wrong command');
  await publish({ models: fixture.models.map(model => model.id === 'parakeet' ? { ...model, state: { kind: 'error', message: 'Download interrupted.' } } : model) });
  await settle();
  assert.ok(await evaluate("document.querySelector('[data-model-id=parakeet]').innerText.includes('Download interrupted.')"), 'Model error is hidden');
  await evaluate("document.querySelector('[data-model-id=parakeet] button').click()");
  await frame();
  assert.deepEqual(commands.at(-1), { kind: 'downloadModel', modelId: 'parakeet' }, 'Model retry uses the wrong command');
  await publish({ models: fixture.models.map(model => model.id === 'parakeet' ? { ...model, state: { kind: 'installed' } } : model) });
  await settle();
  await evaluate("document.querySelector('[data-model-id=parakeet] button').click()");
  await frame();
  assert.deepEqual(commands.at(-1), { kind: 'selectModel', modelId: 'parakeet' }, 'Installed model selection uses the wrong command');

  assert.deepEqual(errors, [], 'Renderer console errors');
  await writeFile(join(output, 'report.json'), JSON.stringify({ transitions, reduced, errors, ribbonLifecycle: 'passed', disclosures: 'passed', nativePickerKeyboard: 'passed', rapidNavigation: 'passed', searchFocus: 'passed', settingsSections: 'passed', immediateCommands: commands.length, persistentStatus: 'passed', retention: 'passed', recovery: 'passed' }, null, 2));
  process.stdout.write(`Verified ASCII lifecycle, disclosure reversal and focus, native picker keyboard, page continuity, and reduced motion. Evidence: ${output}\n`);
  app.quit();
}).catch(error => { process.stderr.write(`${error.stack}\n`); app.exit(1); });
