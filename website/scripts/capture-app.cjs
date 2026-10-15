const { app, BrowserWindow } = require('electron');
const { mkdir, writeFile, rm } = require('node:fs/promises');
const { execFileSync } = require('node:child_process');
const { resolve, join } = require('node:path');
const assert = require('node:assert/strict');

const output = resolve(__dirname, '../public/images');
const renderer = resolve(__dirname, '../../out/renderer/index.html');

app.whenReady().then(async () => {
  await mkdir(output, { recursive: true });
  const window = new BrowserWindow({
    width: 1100, height: 780, useContentSize: true, show: false,
    webPreferences: { contextIsolation: true, nodeIntegration: false, backgroundThrottling: false },
  });
  for (const page of ['home', 'settings', 'stats']) {
    await window.loadFile(renderer, { query: { preview: 'ready', page } });
    await window.webContents.executeJavaScript('document.fonts.ready.then(() => new Promise(resolve => setTimeout(resolve, 600)))');
    const heading = await window.webContents.executeJavaScript("document.querySelector('h1')?.textContent");
    assert.ok(heading, `${page}: app did not render`);
    const png = join(output, `app-${page}.png`);
    await writeFile(png, (await window.webContents.capturePage()).toPNG());
    execFileSync('cwebp', ['-quiet', '-q', '92', png, '-o', join(output, `app-${page}.webp`)]);
    await rm(png);
    process.stdout.write(`Captured ${page}: ${heading}\n`);
  }
  window.destroy();
  app.quit();
}).catch(error => { process.stderr.write(`${error.stack}\n`); app.exit(1); });
