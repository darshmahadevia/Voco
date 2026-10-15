const { app, BrowserWindow } = require('electron');
const { readFileSync, writeFileSync } = require('node:fs');
const { resolve } = require('node:path');

app.whenReady().then(async () => {
  const directory = resolve(__dirname, '../Resources/Brand');
  const mark = readFileSync(resolve(directory, 'voco-mark.svg'), 'utf8');
  const appIcon = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <rect x="62" y="62" width="900" height="900" rx="200" fill="#171819"/>
  <svg x="205.4" y="278.4" width="613.2" height="467.2" viewBox="0 0 84 64">${mark}</svg>
</svg>\n`;
  writeFileSync(resolve(directory, 'voco-app.svg'), appIcon);

  const window = new BrowserWindow({ show: false, webPreferences: { sandbox: true } });
  try {
    await window.loadURL('data:text/html,<html></html>');
    const images = [
      ['voco-app.png', appIcon, 1024, 1024],
      ['voco-trayTemplate.png', mark.replace('#ff742f', '#000000'), 22, 22],
      ['voco-trayTemplate@2x.png', mark.replace('#ff742f', '#000000'), 44, 44],
    ];
    for (const [name, svg, width, height] of images) {
      const source = `data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}`;
      const png = await window.webContents.executeJavaScript(`(async () => {
        const image = new Image();
        image.src = ${JSON.stringify(source)};
        await image.decode();
        const canvas = document.createElement('canvas');
        canvas.width = ${width};
        canvas.height = ${height};
        canvas.getContext('2d').drawImage(image, 0, 0, canvas.width, canvas.height);
        return canvas.toDataURL('image/png').split(',')[1];
      })()`);
      writeFileSync(resolve(directory, name), Buffer.from(png, 'base64'));
      console.log(`Generated ${name} (${width} × ${height})`);
    }
  } finally {
    window.destroy();
  }
}).then(() => app.quit()).catch(error => {
  console.error(error);
  app.exit(1);
});
