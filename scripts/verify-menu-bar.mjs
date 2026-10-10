import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdir, readFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import electron from 'electron';

const output = resolve(process.argv[2] ?? '/tmp/voco-menu-bar');
await mkdir(output, { recursive: true });
const environment = { ...process.env };
delete environment.ELECTRON_RUN_AS_NODE;
delete environment.ELECTRON_RENDERER_URL;
const child = spawn(electron, [
  resolve('.'), '--verify-desktop', '--verify-permission-return',
  `--verification-directory=${output}`,
], { env: environment, stdio: 'inherit' });
const timer = setTimeout(() => child.kill('SIGTERM'), 45_000);
try {
  const code = await new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('exit', (code, signal) => signal ? reject(new Error(`Desktop verification stopped: ${signal}`)) : resolve(code));
  });
  assert.equal(code, 0, 'Desktop verification failed');
} finally {
  clearTimeout(timer);
}
const report = JSON.parse(await readFile(join(output, 'report.json'), 'utf8'));
assert.equal(report.preload, true);
assert.equal(report.preview, false);
assert.equal(report.helper, true);
assert.equal(report.model, 'missing', 'The helper must report the isolated profile’s missing model');
assert.deepEqual(report.menuBar.startup, { dashboardHidden: true, pillHidden: true, dockHidden: true });
assert.deepEqual(report.menuBar.navigation, [
  { page: 'transcripts', visible: true, accelerator: 'CommandOrControl+2' },
  { page: 'settings', visible: true, accelerator: 'CommandOrControl+,' },
  { page: 'home', visible: true, accelerator: 'CommandOrControl+1' },
]);
assert.deepEqual(report.menuBar.shortcuts, [
  { page: 'transcripts', accelerator: 'CommandOrControl+2' },
  { page: 'settings', accelerator: 'CommandOrControl+,' },
  { page: 'home', accelerator: 'CommandOrControl+1' },
]);
for (const check of ['retainedBackgroundTranscript', 'closeHidesDashboard', 'relaunchStaysHidden', 'navigationDuringLoad', 'idleFailureStaysHidden']) {
  assert.equal(report.menuBar[check], true, check);
}
assert.deepEqual(report.layoutSizes, [[960, 720], [960, 720], [960, 720]]);
assert.deepEqual(report.windowConstraints, { minimum: [720, 520], maximum: [960, 720], maximizable: false, fullscreenable: false });
for (const [check, passed] of Object.entries(report.permissionReturn)) assert.equal(passed, true, check);
process.stdout.write(`Verified menu bar startup, navigation, shortcut registration, and permission recovery. Report: ${join(output, 'report.json')}\n`);
