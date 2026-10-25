'use strict';
// Main entry for the dfkup native addon.
//
// This package ships prebuilt `.node` binaries per platform/arch under
// `bin/<platform>-<arch>/dfkup.node` (populated by `npm run build` on
// each host — native addons cannot be cross-compiled). At load time the
// binary matching `process.platform`/`process.arch` is selected.
//
// A repository checkout fallback (`../../bin/dfkup.node`, produced by
// running `clue task napi` at the repo root) keeps the developer flow
// working without packing binaries.
//
// The standard library is statically linked into the binary, so there
// are no runtime shard files to ship or locate.

const fs = require('fs');
const path = require('path');

const SUPPORTED = {
  darwin: ['arm64', 'x64'],
  linux: ['arm64', 'x64'],
};

function candidates() {
  const pair = `${process.platform}-${process.arch}`;
  const list = [];
  list.push(path.join(__dirname, 'bin', pair, 'dfkup.node'));
  // Developer fallback: repo-root build output (not shipped in the
  // published tarball, see package.json `files`).
  list.push(path.join(__dirname, '..', '..', 'bin', 'dfkup.node'));
  return { list, pair };
}

let loaded = null;
let loadedFrom = null;
const { list, pair } = candidates();

for (const p of list) {
  if (fs.existsSync(p)) {
    loadedFrom = p;
    loaded = require(p);
    break;
  }
}

if (loaded === null) {
  const supported = Object.entries(SUPPORTED)
    .map(([plat, archs]) => archs.map((a) => `${plat}-${a}`).join(', '))
    .join(', ');
  throw new Error(
    `dfkup-napi: no prebuilt binary for ${pair} and no dev fallback found. Tried:\n` +
      list.join('\n') +
      `\nSupported: ${supported}.\n` +
      'Build it with `npm run build` on the target host ' +
      '(requires Nim, denim and cmake-js).'
  );
}

module.exports = loaded;
module.exports.binaryPath = loadedFrom;
module.exports.nativePair = pair;