// DFkup — browser/Node.js glue for build/dfkup.wasm (wasm32, no backend).
//
// The module is `--os:linux` + WASI libc with all OS imports satisfied by
// this minimal shim. The engine itself never touches the filesystem,
// network or clocks on the wasm path; the shims only exist so the module
// instantiates and libc startup succeeds.
//
// Universal module: `require('./dfkup.wasm.js')` in Node.js, or
// `<script src="dfkup.wasm.js">` + `DfkupWasm.loadDfkupUrl(url)` in the browser.

(function (global, factory) {
  'use strict';
  if (typeof module === 'object' && typeof module.exports === 'object') {
    module.exports = factory();
  } else {
    global.DfkupWasm = factory();
  }
}(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  const ERRNO_SUCCESS = 0;
  const ERRNO_BADF = 8;

  function makeWasi(getBuffer) {
    const view = () => new DataView(getBuffer());
    const u8 = () => new Uint8Array(getBuffer());

    const iovsSize = (iovs, iovsLen) => {
      let total = 0;
      for (let i = 0; i < iovsLen; i++) {
        total += view().getUint32(iovs + i * 8 + 4, true);
      }
      return total;
    };

    return {
      // Wall clock for wasi-libc internals. The engine never asks for time;
      // Date.now keeps libc init paths honest.
      clock_time_get: (clockId, precision, outPtr) => {
        const ns = BigInt(Date.now()) * 1000000n;
        view().setBigUint64(outPtr, ns, true);
        return ERRNO_SUCCESS;
      },
      fd_write: (fd, iovs, iovsLen, nwrittenPtr) => {
        // Discard guest stdout/stderr (`echo` output travels through the
        // wasmEchoBuf capture into the result buffer instead).
        view().setUint32(nwrittenPtr, iovsSize(iovs, iovsLen), true);
        return ERRNO_SUCCESS;
      },
      fd_read: () => ERRNO_BADF,
      fd_close: () => ERRNO_SUCCESS,
      fd_seek: () => ERRNO_BADF,
      fd_pread: () => ERRNO_BADF,
      fd_fdstat_get: () => ERRNO_BADF,
      fd_fdstat_set_flags: () => ERRNO_BADF,
      fd_filestat_get: () => ERRNO_BADF,
      // No preopened directories in the playground.
      fd_prestat_get: () => ERRNO_BADF,
      fd_prestat_dir_name: () => ERRNO_BADF,
      path_open: () => ERRNO_BADF,
      // Real randomness via the host CSPRNG
      // (globalThis.crypto exists in browsers and modern Node.js).
      random_get: (ptr, len) => {
        const out = u8().subarray(ptr, ptr + len);
        globalThis.crypto.getRandomValues(out);
        return ERRNO_SUCCESS;
      },
      proc_exit: (code) => { throw new Error('dfkup.wasm proc_exit(' + code + ')'); },
    };
  }

  async function instantiate(bytes) {
    const mod = new WebAssembly.Module(bytes);
    let memory = null;
    const wasi = makeWasi(() => memory.buffer);
    // Proxy: tolerate any extra WASI import by failing closed (BADF),
    // so future SDK additions don't break the shim.
    const imports = new Proxy(wasi, {
      get: (t, p) => (p in t ? t[p] : () => ERRNO_BADF),
    });
    const instance = new WebAssembly.Instance(mod, {
      wasi_snapshot_preview1: imports,
    });
    memory = instance.exports.memory;
    // Run libc constructors, then Nim's runtime init (idempotent).
    if (instance.exports.__wasm_call_ctors) instance.exports.__wasm_call_ctors();
    instance.exports.NimMain();

    const enc = new TextEncoder();
    const dec = new TextDecoder();

    function writeStr(s) {
      const encoded = enc.encode(s);
      const ptr = instance.exports.dfkupAlloc(encoded.length);
      new Uint8Array(memory.buffer).set(encoded, ptr);
      return [ptr, encoded.length];
    }
    function readResult() {
      const ptr = instance.exports.dfkupResultPtr();
      const len = instance.exports.dfkupResultLen();
      if (!ptr || !len) return '';
      return dec.decode(new Uint8Array(memory.buffer).slice(ptr, ptr + len));
    }
    function call(fn, ...strings) {
      const args = [];
      try {
        for (const s of strings) {
          const [ptr, len] = writeStr(s);
          args.push(ptr, len);
        }
        const code = fn(...args);
        const out = readResult();
        return { code, out };
      } finally {
        for (let i = 0; i < args.length; i += 2) instance.exports.dfkupFree(args[i]);
      }
    }

    return {
      instance,
      version: () => call(instance.exports.dfkupVersion),
      run: (src) => call(instance.exports.dfkupRun, src),
      ast: (src) => call(instance.exports.dfkupAst, src),
    };
  }

  // Node.js: load from a file path.
  async function loadDfkup(wasmPath) {
    if (wasmPath === undefined) {
      const path = require('path');
      // bindings/wasm/dfkup.wasm.js -> repo/build/dfkup.wasm
      wasmPath = path.join(__dirname, '..', '..', 'build', 'dfkup.wasm');
    }
    const fs = require('fs');
    return instantiate(fs.readFileSync(wasmPath));
  }

  // Browser: load from a URL.
  async function loadDfkupUrl(url) {
    const res = await fetch(url);
    if (!res.ok) throw new Error('Failed to fetch ' + url + ': ' + res.status);
    return instantiate(await res.arrayBuffer());
  }

  const api = { instantiate, loadDfkup, loadDfkupUrl };

  // Node.js self-test: `node dfkup.wasm.js`.
  if (typeof require === 'function' && typeof module !== 'undefined' &&
      require.main === module) {
    (async () => {
      const dfkup = await loadDfkup();
      console.log('version:', JSON.stringify(dfkup.version()));
      console.log('run:', JSON.stringify(
        dfkup.run('echo "Hello, " & "WASM!"\n40 + 2')));
      console.log('ast:', JSON.stringify(dfkup.ast('echo 1').out.slice(0, 80)));
      console.log('error:', JSON.stringify(dfkup.run('echo undefinedThing')));
    })().catch((e) => { console.error(e); process.exit(1); });
  }

  return api;
}));
