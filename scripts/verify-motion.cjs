const { app, BrowserWindow } = require('electron');
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
  window.webContents.debugger.attach('1.3');
  await window.webContents.debugger.sendCommand('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-reduced-motion', value: 'reduce' }] });
  await navigate('Settings');
  await settle();
  assert.equal(await evaluate("matchMedia('(prefers-reduced-motion: reduce)').matches"), true);
  assert.equal(await evaluate("document.querySelectorAll('.page-transition').length"), 1);
  const reduced = await evaluate("({ opacity: getComputedStyle(document.querySelector('.page-transition')).opacity, transform: getComputedStyle(document.querySelector('.page-transition')).transform, filter: getComputedStyle(document.querySelector('.page-transition')).filter })");
  assert.equal(reduced.opacity, '1');
  assert.ok(reduced.transform === 'none' || reduced.transform === 'matrix(1, 0, 0, 1, 0, 0)');
  assert.ok(reduced.filter === 'none' || reduced.filter === 'blur(0px)');
  window.webContents.debugger.detach();
  assert.deepEqual(errors, [], 'Renderer console errors');
  await writeFile(join(output, 'report.json'), JSON.stringify({ transitions, reduced, errors, rapidNavigation: 'passed', searchFocus: 'passed' }, null, 2));
  process.stdout.write(`Verified page continuity, rapid navigation, search focus, and reduced motion. Evidence: ${output}\n`);
  app.quit();
}).catch(error => { process.stderr.write(`${error.stack}\n`); app.exit(1); });
