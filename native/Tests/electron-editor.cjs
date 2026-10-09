const { app, BrowserWindow } = require('electron');
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const { mkdtemp, readFile, rm } = require('node:fs/promises');
const { join, resolve } = require('node:path');
const { tmpdir } = require('node:os');
const assert = require('node:assert/strict');
const run = promisify(execFile);

app.whenReady().then(async () => {
  const logs = await mkdtemp(join(tmpdir(), 'voco-electron-editor-'));
  const window = new BrowserWindow({ width: 960, height: 760, webPreferences: { contextIsolation: true, nodeIntegration: false } });
  app.setAccessibilitySupportEnabled(true);
  try {
    await window.loadFile(join(__dirname, 'editors.html'));
    for (const field of ['input', 'textarea', '[contenteditable]']) {
      for (const selected of [false, true]) {
        await window.webContents.executeJavaScript(`(() => {
          const field = document.querySelector(${JSON.stringify(field)});
          if ('value' in field) field.value = 'Before selected after';
          else field.textContent = 'Before selected after';
          field.focus();
          const start = ${selected ? 7 : 15};
          const end = 15;
          if ('setSelectionRange' in field) field.setSelectionRange(start, end);
          else {
            const range = document.createRange();
            range.setStart(field.firstChild, start); range.setEnd(field.firstChild, end);
            getSelection().removeAllRanges(); getSelection().addRange(range);
          }
          window.vocoEditorEvents.length = 0;
        })()`);
        app.focus({ steal: true });
        window.focus();
        const output = join(logs, 'output.log');
        const errors = join(logs, 'error.log');
        const speechArguments = field === 'textarea' && selected && process.env.VOCO_VERIFY_AUDIO_FIXTURE
          ? ['--audio-fixture', process.env.VOCO_VERIFY_AUDIO_FIXTURE, '--model-directory', process.env.VOCO_VERIFY_MODEL_DIRECTORY] : [];
        await run('open', ['-W', '-g', '-n', resolve(__dirname, '../build/VocoNative.app'), '--stdout', output, '--stderr', errors,
          '--args', '--verify-live-insertion', 'Before selected after', ...speechArguments], { timeout: 20000 });
        const transcript = await readFile(output, 'utf8');
        if (!transcript.includes('Live insertion checks: PASS')) {
          const diagnostic = await window.webContents.executeJavaScript(`JSON.stringify({fields:[...document.querySelectorAll('input,textarea,[contenteditable]')].map(field=>({value:field.value??field.textContent,start:field.selectionStart,end:field.selectionEnd})),events:window.vocoEditorEvents,keys:window.vocoKeys})`);
          throw new Error(`${transcript}${await readFile(errors, 'utf8')}\nEditor state: ${diagnostic}`);
        }
        const result = await window.webContents.executeJavaScript(`(() => {
          const field = document.querySelector(${JSON.stringify(field)});
          const events = (window.vocoEditorEvents ?? []).filter(event => event.field === field.getAttribute('aria-label'));
          return { value: field.value ?? field.textContent, lastInput: events.at(-1)?.value, inputCount: events.length };
        })()`);
        assert.ok(result.inputCount >= 6, 'The editor must receive input events for live revisions');
        assert.equal(result.lastInput, result.value, 'The application state must match the final editor value');
        if (speechArguments.length > 0 && process.env.VOCO_VERIFY_EXPECTED_TRANSCRIPT) {
          assert.ok(result.value.includes(process.env.VOCO_VERIFY_EXPECTED_TRANSCRIPT), 'The expected speech must appear exactly in the editor');
          assert.match(transcript, /Verified Moonshine stream: [1-9][0-9]* partial revisions/);
        }
        process.stdout.write(`PASS Electron ${field}, selected=${selected}, input events=${result.inputCount}, speech=${speechArguments.length > 0}\n`);
      }
    }
    for (const emptyRich of [true, false]) {
      await window.webContents.executeJavaScript(`(() => {
        const field = document.querySelector(${JSON.stringify(emptyRich ? '[aria-label="Empty rich editor"]' : 'textarea')});
        if (${emptyRich}) {
          field.innerHTML = '<p><br></p>';
          field.focus();
          const range = document.createRange(); range.setStart(field.firstChild, 0); range.collapse(true);
          getSelection().removeAllRanges(); getSelection().addRange(range);
        } else { field.value = '\\n'; field.focus(); field.setSelectionRange(0, 0); }
      })()`);
      app.focus({ steal: true }); window.focus();
      const output = join(logs, emptyRich ? 'empty-rich.log' : 'literal-newline.log');
      const errors = join(logs, 'error.log');
      await run('open', ['-W', '-g', '-n', resolve(__dirname, '../build/VocoNative.app'), '--stdout', output, '--stderr', errors,
        '--args', ...(emptyRich ? ['--verify-empty-rich-editor'] : ['--verify-live-insertion', '\n'])], { timeout: 20000 });
      const transcript = await readFile(output, 'utf8');
      assert.ok(transcript.includes(emptyRich ? 'Empty rich editor checks: PASS' : 'Live insertion checks: PASS'),
        transcript + await readFile(errors, 'utf8'));
      if (emptyRich) {
        assert.equal(await window.webContents.executeJavaScript(`document.querySelector('[aria-label="Empty rich editor"]').textContent`), 'Goodbye again.');
      }
      process.stdout.write(`PASS Electron ${emptyRich ? 'empty rich-text placeholder lifecycle' : 'literal textarea newline preserved'}\n`);
    }
  } catch (error) {
    process.stderr.write(`${error.stack}\n`);
    app.exit(1);
    return;
  } finally { await rm(logs, { recursive: true, force: true }); }
  app.exit(0);
});
