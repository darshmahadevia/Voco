const assert = require('node:assert/strict');
const { readFileSync, readdirSync } = require('node:fs');
const { homedir } = require('node:os');
const { join, resolve } = require('node:path');
const { execFileSync } = require('node:child_process');
const asar = require('@electron/asar');

const bundle = process.argv[2] ?? join(homedir(), 'Applications/Voco.app');
const archive = join(bundle, 'Contents/Resources/app.asar');
const project = resolve(__dirname, '..');
const html = readFileSync(join(project, 'out/renderer/index.html'), 'utf8');
const assets = [...html.matchAll(/(?:src|href)="\.\/(assets\/[^" ]+)"/g)].map((match) => match[1]);
assert.ok(assets.length > 0, 'the current renderer includes built assets');
for (const file of ['out/main/index.js', 'out/preload/index.cjs', 'out/renderer/index.html', ...assets.map((asset) => `out/renderer/${asset}`)]) {
  assert.ok(asar.extractFile(archive, file).equals(readFileSync(join(project, file))), `${bundle}: ${file} differs from the latest build`);
}
const installedHelper = join(bundle, 'Contents/Resources/native/VocoNative.app/Contents/MacOS/VocoNative');
const builtHelper = join(project, 'native/build/VocoNative.app/Contents/MacOS/VocoNative');
function nativeBuildId(path) {
  const output = execFileSync('xcrun', ['dwarfdump', '--uuid', path], { encoding: 'utf8' });
  const id = output.match(/UUID: ([0-9A-F-]+) \(arm64\)/)?.[1];
  assert.ok(id, `${path}: missing native build UUID`);
  return id;
}
assert.equal(nativeBuildId(installedHelper), nativeBuildId(builtHelper), `${bundle}: native helper differs from the latest build`);
const iconName = execFileSync('plutil', ['-extract', 'CFBundleIconFile', 'raw', join(bundle, 'Contents/Info.plist')], { encoding: 'utf8' }).trim();
const installedIcon = iconName.endsWith('.icns') ? iconName : `${iconName}.icns`;
const brandFiles = readdirSync(join(project, 'Resources/Brand'));
const resourcePairs = [
  ...brandFiles.map((file) => [`Resources/Brand/${file}`, `Contents/Resources/brand/${file}`]),
  ['Resources/Voco.icns', `Contents/Resources/${installedIcon}`],
  ['Resources/Voco.icns', 'Contents/Resources/native/VocoNative.app/Contents/Resources/Voco.icns'],
];
for (const [source, installed] of resourcePairs) {
  assert.ok(readFileSync(join(bundle, installed)).equals(readFileSync(join(project, source))), `${bundle}: ${installed} differs from the current brand assets`);
}
console.log(`PASS latest installed Voco: ${bundle}`);
