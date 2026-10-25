'use strict';
// Places the freshly built addon binary into the per-arch package slot:
//   addons/dfkup_napi/bin/<platform>-<arch>/dfkup.node
//
// Run from the repository root after `denim build` (see the `napi`
// nimble task, run via `clue task napi`). Native addons cannot be
// cross-compiled, so this runs on each target host (or CI runner) and the
// resulting files are packed together for publishing.
//
// The standard library is statically linked into the binary, so unlike
// the CLI release there are no shard files to place.

const fs = require('fs');
const os = require('os');
const path = require('path');

const PLATFORMS = {
  darwin: ['arm64', 'x64'],
  linux: ['arm64', 'x64'],
};

const repoRoot = path.resolve(__dirname, '..', '..', '..');
const src = path.join(repoRoot, 'bin', 'dfkup.node');

const plat = PLATFORMS[os.platform()] ? os.platform() : null;
if (plat === null || !PLATFORMS[plat].includes(os.arch())) {
  console.error(
    `dfkup-napi: unsupported host ${os.platform()}-${os.arch()}. ` +
      'Supported: ' +
      Object.entries(PLATFORMS)
        .map(([p, archs]) => archs.map((a) => `${p}-${a}`).join(', '))
        .join(', ')
  );
  process.exit(1);
}

if (!fs.existsSync(src)) {
  console.error(`dfkup-napi: ${src} not found. Run denim build first.`);
  process.exit(1);
}

const destDir = path.join(__dirname, '..', 'bin', `${plat}-${os.arch()}`);
fs.mkdirSync(destDir, { recursive: true });
fs.copyFileSync(src, path.join(destDir, 'dfkup.node'));
console.log(`dfkup-napi: placed binary for ${plat}-${os.arch()}`);
