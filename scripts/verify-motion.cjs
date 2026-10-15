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
    await evaluate(`document.querySelector('.settings-index a[href="#${target}"]').click()`);
    await settle();
    assert.equal(await evaluate('document.activeElement.id'), target, `${label}: section focus is missing`);
    assert.equal(await evaluate("document.querySelector('.settings-index a[aria-current=location]').textContent"), label, `${label}: section indicator is wrong. ${JSON.stringify(await evaluate("({ active:document.activeElement.id, top:document.querySelector('.workspace-main').getBoundingClientRect().top, bottom:document.querySelector('.workspace-main').getBoundingClientRect().bottom, scroll:document.querySelector('.workspace-main').scrollTop, headings:[...document.querySelectorAll('.settings-section h2')].map(e=>({id:e.id,top:e.getBoundingClientRect().top,bottom:e.getBoundingClientRect().bottom})) })"))}`);
    assert.ok(await evaluate(`(() => { const r = document.getElementById('${target}').getBoundingClientRect(); const main = document.querySelector('.workspace-main').getBoundingClientRect(); return r.top >= main.top && r.bottom <= main.bottom; })()`), `${label}: section heading is not visible`);
  }
  window.webContents.debugger.attach('1.3');
  await window.webContents.debugger.sendCommand('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-reduced-motion', value: 'reduce' }] });
  await frame();
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
  await evaluate("document.querySelector('button[role=switch]').click()");
  await frame();
  assert.equal(commands.length, 2, 'Retention preference command was delayed or repeated');
  await navigate('Transcripts');
  await settle();
  assert.equal(await evaluate("document.querySelectorAll('.recent-transcript-row').length"), 0);
  assert.ok(await evaluate("!document.body.innerText.includes('Words retained only for this session.')"), 'Turning off retention left transcript text visible');
  await publish({ session: { kind: 'recovery', message: 'The destination changed.', text: 'Recover all of these words.' } });
  await settle();
  for (const label of ['Settings', 'Transcripts']) {
    await navigate(label);
    await settle();
    assert.ok(await evaluate("document.querySelector('.recovery-content').innerText.includes('Recover all of these words.')"), `${label}: recovery is inaccessible`);
  }
  await capture('native-recovery');
  assert.deepEqual(errors, [], 'Renderer console errors');
  await writeFile(join(output, 'report.json'), JSON.stringify({ transitions, reduced, errors, rapidNavigation: 'passed', searchFocus: 'passed', settingsSections: 'passed', immediateCommands: commands.length, persistentStatus: 'passed', retention: 'passed', recovery: 'passed' }, null, 2));
  process.stdout.write(`Verified page continuity, rapid navigation, search focus, and reduced motion. Evidence: ${output}\n`);
  app.quit();
}).catch(error => { process.stderr.write(`${error.stack}\n`); app.exit(1); });
