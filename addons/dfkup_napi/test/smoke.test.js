'use strict';
const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const dfkup = require('../index.js');

describe('dfkup loader', () => {
  it('reports the loaded binary', () => {
    assert.match(dfkup.nativePair, /^(darwin|linux)-(arm64|x64)$/);
    assert.ok(fs.existsSync(dfkup.binaryPath));
  });

  it('exposes the package version', () => {
    const { version } = require('../package.json');
    assert.equal(dfkup.version, version);
  });
});

describe('dfkup run', () => {
  it('runs scripts and returns results', () => {
    assert.equal(dfkup.run('var x = 40 + 2\nx'), '42');
  });

  it('throws on invalid code', () => {
    assert.throws(() => dfkup.run('foo + 1'), Error);
  });

  it('loads statically-linked stdlibs with no shards present', () => {
    const out = dfkup.run('import "std/json"\nvar o = {"a": 40 + 2}\no.a');
    assert.equal(out, '42');
  });
});

describe('dfkup runFile', () => {
  it('runs example scripts touching several stdlibs', () => {
    // basics.dfkup is cwd-relative (like `dfkup run` from the repo
    // root): establish that cwd for the run, then restore.
    const root = path.join(__dirname, '..', '..', '..');
    const prev = process.cwd();
    process.chdir(root);
    try {
      assert.doesNotThrow(() => dfkup.runFile(path.join(root, 'examples', 'basics.dfkup')));
    } finally {
      process.chdir(prev);
    }
  });
});

describe('dfkup runConfig', () => {
  it('runs config files', () => {
    const conf = path.join(__dirname, '..', '..', '..', 'examples', 'config.kup');
    assert.equal(typeof dfkup.runConfig(conf), 'string');
  });
});

describe('dfkup ast', () => {
  it('returns parseable JSON', () => {
    const out = dfkup.ast('var x = 1\nx + 2');
    const parsed = JSON.parse(out);
    assert.ok(Array.isArray(parsed));
  });
});