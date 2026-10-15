const { app, BrowserWindow } = require("electron");
const { readFile, writeFile, mkdtemp, rm } = require("node:fs/promises");
const { resolve, join } = require("node:path");
const { pathToFileURL } = require("node:url");
const { tmpdir } = require("node:os");

app
  .whenReady()
  .then(async () => {
    const temporary = await mkdtemp(join(tmpdir(), "voco-social-"));
    const assets = resolve(__dirname, "../public");
    const font = pathToFileURL(join(assets, "fonts/Manrope.ttf")).href;
    const screenshot = pathToFileURL(join(assets, "images/app-home.webp")).href;
    const mark = await readFile(join(assets, "images/voco-mark.svg"), "utf8");
    const html = `<!doctype html><html lang="en"><meta charset="utf-8"><title>Voco social image</title>
    <style>@font-face{font-family:Manrope;src:url('${font}')}*{box-sizing:border-box}body{margin:0;width:1200px;height:630px;overflow:hidden;background:#f6f4ee;color:#262720;font-family:Manrope,sans-serif}header{display:flex;align-items:center;justify-content:space-between;margin:42px 54px;color:#65665d;font-size:17px}.brand{display:flex;align-items:center;color:#262720;font-size:32px;font-weight:700}.brand svg{width:58px;height:42px;margin-right:8px}.brand span{color:#ff742f}h1{position:relative;z-index:2;font-size:88px;font-weight:500;line-height:1.08;letter-spacing:-.035em;margin:80px 0 0 54px}h1 span{color:#777e63}p{margin:32px 54px;font-size:20px;color:#65665d;line-height:1.6}.screen{position:absolute;width:660px;left:640px;top:190px;border-radius:14px;box-shadow:0 24px 55px #323c3033;transform:rotate(-7deg)}.foot{position:absolute;bottom:42px;left:54px;font-size:16px;color:#262720}</style>
    <header><div class="brand">${mark}voco<span>.</span></div><div>Local dictation for your Mac</div></header>
    <h1>Good ideas.<br><span>Less typing.</span></h1><p>Speak your mind.<br>Your words stay on your Mac.</p>
    <img class="screen" src="${screenshot}" alt="Voco dashboard"><div class="foot">Free to use. Offline after setup.</div></html>`;
    const source = join(temporary, "social.html");
    await writeFile(source, html);
    const window = new BrowserWindow({
      width: 1200,
      height: 630,
      useContentSize: true,
      show: false,
      webPreferences: {
        contextIsolation: true,
        nodeIntegration: false,
        backgroundThrottling: false,
      },
    });
    await window.loadFile(source);
    await window.webContents.executeJavaScript(
      "document.fonts.ready.then(() => Promise.all([...document.images].map(image => image.decode())))",
    );
    await writeFile(
      join(assets, "images/og-image.png"),
      (await window.webContents.capturePage())
        .resize({ width: 1200, height: 630 })
        .toPNG(),
    );
    window.destroy();
    await rm(temporary, { recursive: true });
    app.quit();
  })
  .catch((error) => {
    process.stderr.write(`${error.stack}\n`);
    app.exit(1);
  });
