# DFkup browser playground (wasm, no backend)

Runs dfkup scripts directly in the browser using `build/dfkup.wasm`.
No server, no Node.js involved at runtime — the page talks to the wasm
module through `bindings/wasm/dfkup.wasm.js`.

## Build

Requires Nim 2.4.0 and wasi-sdk 34
(`~/.local/share/wasi-sdk/wasi-sdk-34.0-x86_64-macos`, or set `$WASI_SDK`):

```
clue task wasm          # produces build/dfkup.wasm + stages examples/wasm/
```

The task copies `dfkup.wasm` and the `dfkup.wasm.js` glue next to this
page, so the example is self-contained: serve this directory and open
the page.

## Run

```
cd examples/wasm
python3 -m http.server 8000
# open http://localhost:8000/
```

Edit the script on the left — the output re-runs automatically.
`Run` executes the script (`echo` output plus the trailing expression
value); `Show AST` dumps the parsed AST as JSON.

## How it works

- `bindings/wasm/dfkup.wasm.js` (universal module: Node.js `require` or
  browser `<script>`) instantiates the module with a minimal WASI shim
  and exposes `run`, `ast` and `version`.
- The wasm API is string-in/string-out over linear memory: the host
  copies source in with `dfkupAlloc`, calls `dfkupRun` / `dfkupAst`,
  then reads the output (or the error message) from `dfkupResultPtr` /
  `dfkupResultLen`.
- Only the image-linked lowlibs (`system`, `json`, `strings`,
  `sequtils`, `regex`) exist in the wasm build. Filesystem, shell,
  environment and process builtins are compiled out for security, and
  every other `std/*` module reports an unavailable import (no `dlopen`
  in the browser). Scripts run on the VM only — the JIT stays off.
