const { app, BrowserWindow, clipboard } = require('electron');
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
      calendarSquares: [...document.querySelectorAll('.heatmap-day, .heatmap-blank')].every(cell => { const rect = cell.getBoundingClientRect(); return Math.abs(rect.width - rect.height) < 0.1; }),
      calendarWidth: document.querySelector('.activity-scroll')?.clientWidth,
      calendarScrollWidth: document.querySelector('.activity-scroll')?.scrollWidth };
  })()`);
  assert.equal(layout.bodyWidth, layout.width, `${name}: page spills horizontally`);
  assert.equal(layout.bodyHeight, layout.height, `${name}: window spills vertically`);
  assert.ok(layout.mainScrollWidth <= layout.mainWidth + 1, `${name}: content spills horizontally`);
  assert.ok(layout.calendarSquares, `${name}: calendar cells are not square`);
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
  const clicked = await evaluate(`(() => { const button = [...document.querySelectorAll('button')].find(button => (button.getAttribute('aria-label') === ${JSON.stringify(label)} || button.textContent.trim() === ${JSON.stringify(label)})); if (!button || button.disabled) return false; button.click(); return true; })()`);
  assert.ok(clicked, `${label}: action unavailable`);
  await settle();
}
app.whenReady().then(async () => {
  await mkdir(output, { recursive: true });
  window = new BrowserWindow({ width: 960, height: 720, show: false, titleBarStyle: 'hiddenInset', webPreferences: { contextIsolation: true, nodeIntegration: false, backgroundThrottling: false } });
  window.webContents.on('console-message', (_event, details) => { if (details.level === 'error') errors.push(details.message); });
  for (const [width, height] of sizes) {
    window.setSize(width, height);
    const prefix = `${width}x${height}`;
    for (const page of ['home', 'transcripts', 'stats', 'settings']) {
      await load({ preview: 'ready', page });
      await capture(`${prefix}-${page}`);
      assert.ok(await evaluate("!document.body.textContent.includes('Local by design')"));
      if (page === 'home') {
        assert.equal(await evaluate("document.querySelectorAll('.activity-calendar, .daily-goal, .milestones').length"), 0);
        assert.ok(await evaluate("document.querySelector('.recent-transcript-row .copy-transcript-button').getBoundingClientRect().bottom <= document.querySelector('.live-footer').getBoundingClientRect().top"), `${prefix}: latest transcript action is below the viewport`);
        assert.ok(await evaluate("parseFloat(getComputedStyle(document.querySelector('#home-heading')).fontSize) >= 30"));
      }
      if (page === 'stats') assert.ok(await evaluate("Boolean(document.querySelector('.activity-calendar'))"));
      if (page === 'settings') {
        assert.deepEqual(await evaluate("[...document.querySelectorAll('input[name=output-mode]')].map(input => input.value)"), ['fast', 'balanced', 'accurate']);
        assert.equal(await evaluate("document.querySelector('input[name=output-mode]:checked').value"), 'fast');
        assert.ok(await evaluate("[...document.querySelectorAll('input[name=output-mode]')].every(input => input.disabled)"));
        assert.ok(await evaluate("![...document.querySelectorAll('button')].some(button => button.textContent.trim() === 'Done')"));
        await evaluate("document.querySelector('.workspace-main').scrollTo({ top: 10000 })");
        await capture(`${prefix}-settings-footer`);
      }
      assert.equal(await evaluate("document.querySelector('.workspace-status [role=status]').textContent"), 'Ready');
      assert.ok(await evaluate("(() => { const footer = document.querySelector('.live-footer').getBoundingClientRect(); return footer.top >= 0 && footer.bottom <= innerHeight; })()"), `${prefix}: live status is clipped`);
    }
    await load({ preview: 'ready', page: 'onboarding' });
    await capture(`${prefix}-welcome`);
    await click('Get started');
    await capture(`${prefix}-model`);
    assert.equal(await evaluate("document.querySelectorAll('.setup-workspace-model .model-row').length"), 3);
    assert.ok(await evaluate("(() => { const left = document.querySelector('.onboarding-copy').getBoundingClientRect(); const right = document.querySelector('.setup-workspace-model').getBoundingClientRect(); return left.right < right.left; })()"));
    await evaluate("document.querySelector('.setup-workspace-model .model-list').scrollTo({ top: 1000 })");
    await capture(`${prefix}-model-comparison`);
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
    assert.ok(await evaluate("!document.querySelector('#setup-hint')"));
    await capture(`${prefix}-blocked-model`);
    await load({ preview: 'downloading', page: 'onboarding' });
    await click('Get started');
    assert.equal(await evaluate("document.querySelector('.download-progress progress').value"), 0.42);
    assert.ok(await evaluate("Boolean(document.querySelector('button[aria-label=\"Cancel Moonshine download\"]'))"));
    await capture(`${prefix}-model-downloading`);
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
  await click('All stats');
  assert.ok(await evaluate("Boolean(document.querySelector('.stats-page .activity-calendar'))"));
  const originalDay = await evaluate("document.querySelector('.heatmap-day[tabindex=\"0\"]').dataset.date");
  await evaluate("document.querySelector('.heatmap-day[tabindex=\"0\"]').focus()");
  await window.webContents.sendInputEvent({ type: 'keyDown', keyCode: 'Left' });
  await settle();
  assert.notEqual(await evaluate("document.activeElement.dataset.date"), originalDay);
  assert.equal(await evaluate("document.activeElement.getAttribute('aria-pressed')"), 'true');
  await load({ preview: 'ready', page: 'transcripts' });
  window.show();
  app.focus({ steal: true });
  window.focus();
  await settle();
  const copyPoint = await evaluate("(() => { const rect = document.querySelector('.copy-transcript-button').getBoundingClientRect(); return { x: Math.round(rect.x + rect.width / 2), y: Math.round(rect.y + rect.height / 2) }; })()");
  window.webContents.sendInputEvent({ type: 'mouseDown', button: 'left', clickCount: 1, ...copyPoint });
  window.webContents.sendInputEvent({ type: 'mouseUp', button: 'left', clickCount: 1, ...copyPoint });
  await settle();
  assert.equal(await evaluate("document.querySelector('.copy-transcript-button').dataset.state"), 'copied');
  assert.equal(await clipboard.readText(), await evaluate("document.querySelector('.last-transcript').textContent"));
  window.hide();
  await load({ preview: 'ready', page: 'stats', progress: 'empty' });
  await evaluate("document.querySelector('.progress-preferences').open = true");
  await evaluate("(() => { const select = document.querySelector('.progress-preferences select'); select.value = '1000'; select.dispatchEvent(new Event('change', { bubbles: true })); })()");
  await settle();
  assert.match(await evaluate("document.querySelector('.goal-count').textContent"), /1,000/);
  const desktopWindow = window;
  window = new BrowserWindow({ width: 400, height: 220, show: false, frame: false, transparent: true, webPreferences: { contextIsolation: true, nodeIntegration: false, backgroundThrottling: false } });
  window.webContents.on('console-message', (_event, details) => { if (details.level === 'error') errors.push(details.message); });
  desktopWindow.destroy();
  for (const [scenario, title] of [['ready', 'Ready'], ['listening', 'Listening…'], ['silent', 'Listening…'], ['finishing', 'Transcribing…'], ['polishing', 'Polishing…'], ['recovery', 'Transcript needs attention']]) {
    await load({ preview: scenario, view: 'pill' });
    assert.equal(await evaluate("document.querySelector('.pill-title').textContent"), title);
    const bounds = await evaluate("(() => { const r = document.querySelector('.pill-card').getBoundingClientRect(); return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, width: innerWidth, height: innerHeight }; })()");
    assert.ok(bounds.left >= 0 && bounds.right <= bounds.width && bounds.top >= 0 && bounds.bottom <= bounds.height, `${scenario}: capsule is clipped`);
    if (scenario === 'finishing' || scenario === 'polishing') assert.ok(await evaluate("Boolean(document.querySelector('.pill-loader'))"));
    if (scenario === 'recovery') assert.ok(await evaluate("(() => { const r = document.querySelector('.recovery-actions').getBoundingClientRect(); return r.bottom <= innerHeight; })()"));
    await writeFile(join(output, `pill-${scenario}.png`), (await window.webContents.capturePage()).toPNG());
  }
  window.setContentSize(390, 844);
  await load({ preview: 'ready', page: 'home' });
  await capture('390x844-home');
  window.webContents.debugger.attach('1.3');
  await window.webContents.debugger.sendCommand('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-reduced-motion', value: 'reduce' }] });
  await load({ preview: 'listening', page: 'home' });
  assert.equal(await evaluate("matchMedia('(prefers-reduced-motion: reduce)').matches"), true);
  assert.equal(await evaluate("getComputedStyle(document.querySelector('.nav-item')).transitionDuration"), '0s');
  assert.ok(await evaluate("['none', 'blur(0px)'].includes(getComputedStyle(document.querySelector('.page-transition')).filter)"));
  window.webContents.debugger.detach();
  assert.deepEqual(errors, [], 'Renderer console errors');
  await writeFile(join(output, 'report.json'), JSON.stringify({ screenshots: report, errors, interactions: 'Onboarding, blocked continuation, transcript search, empty results, copy feedback, calendar keyboard navigation, and goal adjustment passed.' }, null, 2));
  process.stdout.write(`Verified ${report.length} layouts and onboarding/search interactions. Screenshots: ${output}\n`);
  app.quit();
}).catch(error => { process.stderr.write(`${error.stack}\n`); app.exit(1); });
