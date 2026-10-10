import { createRequire } from 'node:module';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { readFile, rm, symlink, lstat } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';

const require = createRequire(import.meta.url);
const { build, Platform, Arch } = require('electron-builder');
const output = join(homedir(), 'Library/Caches/Voco/Electron');
const target = process.argv[2] === 'dmg' ? 'dmg' : 'dir';
let identity = process.env.VOCO_CODESIGN_IDENTITY?.trim();
if (!identity) {
  try { identity = (await readFile(join(homedir(), 'Library/Application Support/Voco/signing-identity'), 'utf8')).trim(); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
}
const appBundle = join(output, 'mac-arm64/Voco.app');
try {
  if ((await lstat(appBundle)).isSymbolicLink()) await rm(appBundle);
} catch (error) { if (error.code !== 'ENOENT') throw error; }
await build({ targets: Platform.MAC.createTarget(target, Arch.arm64), config: {
  directories: { output }, mac: { identity: identity || '-', ...(identity === 'Voco Local Development' ? { timestamp: 'none' } : {}) }, forceCodeSigning: Boolean(identity && identity !== '-'),
} });
execFileSync('xattr', ['-cr', appBundle]);
execFileSync('codesign', ['--verify', '--deep', '--strict', appBundle]);
const entitlements = execFileSync('codesign', ['-d', '--entitlements', ':-',
  join(appBundle, 'Contents/Resources/native/VocoNative.app')], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
if (!/<key>com\.apple\.security\.device\.audio-input<\/key>\s*<true\/>/.test(entitlements)) {
  throw new Error('The signed native helper is missing microphone access.');
}
const link = join(process.cwd(), 'release');
await rm(link, { recursive: true, force: true });
await symlink(output, link);
process.stdout.write(`Built ${join(link, 'mac-arm64/Voco.app')}\n`);
