const { app, BrowserWindow } = require('electron');
const { mkdir, writeFile } = require('node:fs/promises');
const { resolve, join } = require('node:path');
const assert = require('node:assert/strict');

const output = resolve(process.argv[2] || '/tmp/voco-compact-ui');
const renderer = resolve(__dirname, '../out/renderer/index.html');
const sizes = [[720, 520], [820, 620], [960, 720]];
const report = [];
const errors = [];
let window;
const evaluate = async expression => {
  let timer;
  try {
    return await Promise.race([window.webContents.executeJavaScript(expression, true), new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(`Renderer check timed out: ${expression.slice(0, 120)}`)), 10000); })]);
  } finally { clearTimeout(timer); }
};
const settle = () => evaluate('document.fonts.ready.then(() => new Promise(resolve => setTimeout(resolve, 300)))');
async function capture(name) {
  await settle();
  const layout = await evaluate(`(() => {
    const main = document.querySelector('.workspace-main');
    const setup = document.querySelector('.onboarding-layout');
    const button = document.querySelector('.setup-arrow-next');
    const rect = button?.getBoundingClientRect();
    return { width: innerWidth, height: innerHeight,
      bodyWidth: document.body.scrollWidth, bodyHeight: document.body.scrollHeight,
      mainWidth: main.clientWidth, mainScrollWidth: main.scrollWidth,
      setupWidth: setup?.clientWidth, setupScrollWidth: setup?.scrollWidth,
      nextVisible: !rect || (rect.top >= 0 && rect.bottom <= innerHeight),
      calendarWidth: document.querySelector('.activity-scroll')?.clientWidth,
      calendarScrollWidth: document.querySelector('.activity-scroll')?.scrollWidth };
  })()`);
  assert.equal(layout.bodyWidth, layout.width, `${name}: page spills horizontally`);
  assert.equal(layout.bodyHeight, layout.height, `${name}: window spills vertically`);
  assert.ok(layout.mainScrollWidth <= layout.mainWidth + 1, `${name}: content spills horizontally`);
  assert.ok(layout.nextVisible, `${name}: setup action is clipped`);
  if (layout.setupWidth) assert.ok(layout.setupScrollWidth <= layout.setupWidth + 1, `${name}: setup spills horizontally`);
  if (layout.calendarWidth) assert.ok(layout.calendarScrollWidth <= layout.calendarWidth + 1, `${name}: calendar spills horizontally`);
  await writeFile(join(output, `${name}.png`), (await window.webContents.capturePage()).toPNG());
  report.push({ name, ...layout });
}
async function load(query) {
  await window.loadFile(renderer, { query });
  await settle();
}
async function click(label) {
  const clicked = await evaluate(`(() => { const button = [...document.querySelectorAll('button')].find(button => button.getAttribute('aria-label') === ${JSON.stringify(label)}); if (!button || button.disabled) return false; button.click(); return true; })()`);
  assert.ok(clicked, `${label}: action unavailable`);
  await settle();
}
app.whenReady().then(async () => {
  await mkdir(output, { recursive: true });
  window = new BrowserWindow({ width: 820, height: 620, show: false, titleBarStyle: 'hiddenInset', webPreferences: { contextIsolation: true, nodeIntegration: false, backgroundThrottling: false } });
  window.webContents.on('console-message', (_event, details) => { if (details.level === 'error') errors.push(details.message); });
  for (const [width, height] of sizes) {
    window.setSize(width, height);
    const prefix = `${width}x${height}`;
    for (const page of ['home', 'transcripts', 'stats', 'settings']) {
      await load({ preview: 'ready', page });
      await capture(`${prefix}-${page}`);
    }
    await load({ preview: 'ready', page: 'onboarding' });
    await capture(`${prefix}-welcome`);
    await click('Get started');
    await capture(`${prefix}-model`);
    await evaluate("document.querySelector('.setup-model-options').open = true");
    await capture(`${prefix}-model-expanded`);
    await click('Continue');
    await capture(`${prefix}-access`);
    await click('Try dictation');
    await capture(`${prefix}-practice`);
    await evaluate("document.querySelector('.practice-help').open = true");
    await capture(`${prefix}-practice-help`);
    await click('Open Voco');
    assert.ok(await evaluate("Boolean(document.querySelector('.dashboard'))"));
    await load({ preview: 'setup' });
    await click('Get started');
    assert.ok(await evaluate("document.querySelector('.setup-arrow-next').disabled"));
    assert.match(await evaluate("document.querySelector('#setup-hint').textContent"), /Download a model/);
    await capture(`${prefix}-blocked-model`);
    await load({ preview: 'recovery', page: 'home' });
    await capture(`${prefix}-recovery`);
    await load({ preview: 'ready', page: 'transcripts', progress: 'empty' });
    await capture(`${prefix}-empty-transcripts`);
  }
  await load({ preview: 'ready', page: 'transcripts' });
  assert.equal(await evaluate("document.querySelectorAll('.recent-transcript-row').length"), 4);
  await evaluate(`(() => { const input = document.querySelector('input[type=search]'); Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(input, 'meeting'); input.dispatchEvent(new Event('input', { bubbles: true })); })()`);
  await settle();
  assert.equal(await evaluate("document.querySelectorAll('.recent-transcript-row').length"), 1);
  await evaluate(`(() => { const input = document.querySelector('input[type=search]'); Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(input, 'no matching words'); input.dispatchEvent(new Event('input', { bubbles: true })); })()`);
  await settle();
  assert.match(await evaluate("document.querySelector('.transcript-search-empty').textContent"), /No transcripts match/);
  await load({ preview: 'ready', page: 'home' });
  const originalDay = await evaluate("document.querySelector('.heatmap-day[tabindex=\"0\"]').dataset.date");
  await evaluate("document.querySelector('.heatmap-day[tabindex=\"0\"]').focus()");
  await window.webContents.sendInputEvent({ type: 'keyDown', keyCode: 'Left' });
  await settle();
  assert.notEqual(await evaluate("document.activeElement.dataset.date"), originalDay);
  assert.equal(await evaluate("document.activeElement.getAttribute('aria-pressed')"), 'true');
  await load({ preview: 'ready', page: 'transcripts' });
  window.show();
  window.focus();
  await settle();
  await click('Copy transcript');
  await settle();
  assert.equal(await evaluate("document.querySelector('.copy-transcript-button').dataset.state"), 'copied');
  window.hide();
  await load({ preview: 'ready', page: 'stats', progress: 'empty' });
  await evaluate("document.querySelector('.progress-preferences').open = true");
  await evaluate("(() => { const select = document.querySelector('.progress-preferences select'); select.value = '1000'; select.dispatchEvent(new Event('change', { bubbles: true })); })()");
  await settle();
  assert.match(await evaluate("document.querySelector('.goal-count').textContent"), /1,000/);
  assert.deepEqual(errors, [], 'Renderer console errors');
  await writeFile(join(output, 'report.json'), JSON.stringify({ screenshots: report, errors, interactions: 'Onboarding, blocked continuation, transcript search, empty results, copy feedback, calendar keyboard navigation, and goal adjustment passed.' }, null, 2));
  process.stdout.write(`Verified ${report.length} layouts and onboarding/search interactions. Screenshots: ${output}\n`);
  app.quit();
}).catch(error => { process.stderr.write(`${error.stack}\n`); app.exit(1); });
