import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const directory = await mkdtemp(join(tmpdir(), 'voco-desktop-check-'));
const electron = require('electron');
const executable = process.argv.slice(2).find((argument) => !argument.startsWith('--')) ?? electron;
const verifyPermissionReturn = process.argv.includes('--permission-return');
const modelDirectory = process.env.VOCO_VERIFY_MODEL_DIRECTORY;
const argumentsForApp = [
  ...(executable === electron ? ['.'] : []), '--verify-desktop', `--verification-directory=${directory}`,
  ...(verifyPermissionReturn ? ['--verify-permission-return'] : []),
  ...(modelDirectory ? [`--verification-model-directory=${modelDirectory}`] : []),
];
const environment = { ...process.env };
delete environment.ELECTRON_RUN_AS_NODE;
const child = spawn(executable, argumentsForApp, { stdio: 'inherit', env: environment });
const timeout = setTimeout(() => child.kill('SIGTERM'), 30_000);
const code = await new Promise((resolve) => child.once('exit', resolve));
clearTimeout(timeout);
try {
  if (code !== 0) throw new Error(`Desktop verification exited with ${code}`);
  const report = JSON.parse(await readFile(join(directory, 'report.json'), 'utf8'));
  if (report.title !== 'Voco' || report.preload !== true || report.preview !== false
    || report.helper !== true || report.windowCount !== 2 || report.background !== 'rgba(0, 0, 0, 0)'
    || (modelDirectory && report.model !== 'ready')) {
    throw new Error(`Invalid desktop verification report: ${JSON.stringify(report)}`);
  }
  if (verifyPermissionReturn && (!report.permissionReturn
    || report.permissionReturn.ordinaryGrantStayedClosed !== true
    || report.permissionReturn.returnedOnGrant !== true
    || report.permissionReturn.focusedOnGrant !== true
    || report.permissionReturn.repeatedSnapshotStayedClosed !== true
    || report.permissionReturn.closeCanceledReturn !== true
    || report.permissionReturn.helperFailureRestoredSettings !== true)) {
    throw new Error(`Permission return regression failed: ${JSON.stringify(report.permissionReturn)}`);
  }
  process.stdout.write(`Desktop runtime: PASS ${JSON.stringify(report)}\n`);
} finally { await rm(directory, { recursive: true, force: true }); }
