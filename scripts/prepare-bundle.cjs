const { execFileSync } = require('node:child_process');
const { join } = require('node:path');

module.exports = async (context) => {
  if (context.electronPlatformName === 'darwin') {
    execFileSync('xattr', ['-cr', join(context.appOutDir, `${context.packager.appInfo.productFilename}.app`)]);
  }
};
