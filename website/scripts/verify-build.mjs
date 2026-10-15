import assert from 'node:assert/strict';
import { readFile, stat, readdir } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../dist/', import.meta.url));
const html = await readFile(join(root, 'index.html'), 'utf8');
const release = JSON.parse(await readFile(join(root, 'release.json'), 'utf8'));
assert.equal((html.match(/<h1\b/g) || []).length, 1, 'The page must have one main heading');
assert.ok(html.includes('https://getvoco.vercel.app'), 'Canonical production URL is missing');
assert.ok(!html.includes('github.com/darshmahadevia/Voco'), 'Private source repository linked publicly');
assert.ok(html.includes(release.downloadUrl), 'JavaScript-free download differs from release manifest');
assert.ok(html.includes(release.releaseUrl), 'JavaScript-free release notes differ from manifest');
assert.match(release.sha256, /^[a-f0-9]{64}$/, 'Installer checksum is invalid');
assert.ok(release.sizeBytes > 0, 'Installer size is invalid');
assert.equal(new URL(release.downloadUrl).protocol, 'https:');
const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]);
assert.equal(new Set(ids).size, ids.length, 'Duplicate HTML IDs');
for (const match of html.matchAll(/\bhref="#([^"]+)"/g)) {
  assert.ok(ids.includes(match[1]), `Broken section link #${match[1]}`);
}
const resources = new Set([...html.matchAll(/(?:src|href|content)="(\/[^"#?]+)"/g)].map(match => match[1]));
for (const resource of resources) {
  const path = resolve(root, `.${resource}`);
  assert.ok(path.startsWith(root), `Resource escapes dist: ${resource}`);
  assert.ok((await stat(path)).size > 0, `Empty resource: ${resource}`);
}
const files = await readdir(root, { recursive: true });
assert.ok(files.every(file => !/(?:^|\/)\.env|\.vercel|\.cjs$/.test(file)), 'Development files reached the deployment');
assert.ok(files.includes('images/og-image.png'), 'Social preview image is missing');
for (const page of ['home', 'settings', 'stats']) assert.ok(files.includes(`images/app-${page}.webp`), `Missing real ${page} screenshot`);
console.log(`Verified ${resources.size} local references, ${ids.length} unique IDs, section links, release metadata, real screenshots, and deployment contents.`);
