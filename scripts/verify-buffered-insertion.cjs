const { app, BrowserWindow, clipboard } = require('electron');
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const { mkdtemp, readFile, rm, mkdir } = require('node:fs/promises');
const { homedir, tmpdir } = require('node:os');
const { join } = require('node:path');
const assert = require('node:assert/strict');
const run = promisify(execFile);
const desktop = process.env.VOCO_VERIFY_DESKTOP_APP || join(homedir(), 'Applications/Voco.app');
const model = process.env.VOCO_VERIFY_MODEL_DIRECTORY || join(homedir(), 'Library/Application Support/Voco/models/moonshine-medium-streaming-en');

async function clipboardSnapshot() {
  return Promise.all((await clipboard.read()).map(async item => Promise.all(item.types.map(async type => {
    const value = await item.getType(type);
    return [type, value instanceof Blob ? Buffer.from(await value.arrayBuffer()).toString('base64') : value];
  }))));
}
app.on('window-all-closed', () => {});
app.whenReady().then(async () => {
  const logs = await mkdtemp(join(tmpdir(), 'voco-buffered-editor-'));
  const window = new BrowserWindow({ width: 800, height: 620 });
  app.setAccessibilitySupportEnabled(true);
  try {
    const page = join(logs, 'editor.html');
    await require('node:fs/promises').writeFile(page, `<h1>Voco disposable buffered insertion check</h1>
      <input aria-label="Plain input"><textarea aria-label="Textarea"></textarea>
      <div contenteditable="true" role="textbox" aria-label="Rich text"></div>
      <style>input,textarea,div {display:block; padding:20px; margin:20px; width:80%; border:1px solid gray}</style>
      <script>window.inputEvents=[];document.addEventListener('input', e=>inputEvents.push(e.target.value ?? e.target.textContent));</script>`);
    await window.loadFile(page);
    async function check({ field, selected = false, empty = false, limited = false, speech = false }) {
      const label = `${field}-${selected}-${empty}-${limited}-${speech}`;
      await mkdir(join(logs, label));
      await window.webContents.executeJavaScript(`(() => {
        const field=document.querySelector(${JSON.stringify(field)});
        document.querySelector('input').removeAttribute('maxlength');
        const value=${JSON.stringify(empty ? '' : 'Before selected after')};
        if ('value' in field) field.value=value;
        else field.innerHTML=${empty ? "'<p><br></p>'" : 'value'};
        if (${limited}) field.maxLength=4;
        field.focus();
        const start=${empty ? 0 : selected ? 7 : 15}, end=${empty ? 0 : 15};
        if ('setSelectionRange' in field) field.setSelectionRange(start,end);
        else { const range=document.createRange();range.setStart(field.firstChild,start);range.setEnd(field.firstChild,end);getSelection().removeAllRanges();getSelection().addRange(range); }
        window.inputEvents=[];
      })()`);
      app.focus({ steal: true }); window.focus();
      const savedClipboard = await clipboardSnapshot();
      const output = join(logs, `${label}.log`), errors = join(logs, `${label}-error.log`);
      const words = limited ? 'Keep the whole transcript.' : selected || empty ? 'spoken words 🍦' : ' spoken words 🍦';
      await run('open', ['-W', '-g', '-n', desktop, '--stdout', output, '--stderr', errors, '--args',
        '--verify-desktop', `--verification-directory=${join(logs, label)}`, `--verification-model-directory=${model}`,
        '--verify-buffered-insertion', words,
        ...(speech ? ['--audio-fixture', process.env.VOCO_VERIFY_AUDIO_FIXTURE] : [])], { timeout: 30000 });
      const report = await readFile(output, 'utf8'), diagnostic = await readFile(errors, 'utf8');
      const result = await window.webContents.executeJavaScript(`(() => {
        const field=document.querySelector(${JSON.stringify(field)});
        return {value:(field.value ?? field.textContent).replaceAll('\u00a0',' '), events:window.inputEvents.map(value=>value.replaceAll('\u00a0',' '))};
      })()`);
      if (limited) {
        assert.equal(result.value, 'Keep');
        assert.ok(!report.includes('Buffered insertion checks: PASS') && diagnostic.includes('Text could not be inserted'), 'A truncated paste must report failure');
      } else {
        assert.ok(report.includes('Buffered insertion checks: PASS'), report + diagnostic);
        const inserted = speech ? process.env.VOCO_VERIFY_EXPECTED_TRANSCRIPT : words;
        assert.ok(inserted, 'Set the literal expected audio transcript');
        const expected = empty ? inserted : selected ? `Before ${inserted} after` : `Before selected${inserted} after`;
        assert.equal(result.value, expected);
        assert.deepEqual(result.events, [expected], 'The editor must receive the complete transcript once');
      }
      assert.ok(JSON.stringify(await clipboardSnapshot()) === JSON.stringify(savedClipboard), 'Clipboard contents must be restored');
      process.stdout.write(`PASS buffered ${label}, exact editor text, input event, clipboard\n`);
    }
    for (const field of ['input', 'textarea', '[contenteditable]']) {
      for (const selected of [false, true]) await check({ field, selected });
    }
    await check({ field: '[contenteditable]', empty: true });
    await check({ field: 'input', empty: true, limited: true });
    if (process.env.VOCO_VERIFY_AUDIO_FIXTURE) await check({ field: 'textarea', selected: true, speech: true });
  } finally { window.destroy(); await rm(logs, { recursive: true, force: true }); }
  app.quit();
}).catch(error => { process.stderr.write(`${error.stack}\n`); app.exit(1); });
