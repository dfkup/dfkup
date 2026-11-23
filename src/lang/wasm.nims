import std/[strutils, os]
--mm:arc

when defined(wasm):
  # Browser playground: wasm32 via the WASI SDK clang (no Emscripten).
  # `--os:linux` (not standalone) so the full system — notably exception
  # handling — is available; all OS imports resolve against wasi-libc and
  # are satisfied by the JS WASI shim at instantiation. The engine itself
  # never touches the filesystem, network or clocks on this path
  # (see the `when not defined(wasm)` guards in `lowlibs/libsystem`).
  # Set $WASI_SDK to override the default SDK location.
  switch("cpu", "wasm32")
  switch("os", "linux")
  switch("cc", "clang")
  const wasiSdk = getEnv("WASI_SDK",
    expandTilde("~/.local/share/wasi-sdk/wasi-sdk-34.0-x86_64-macos"))
  const wasiSysroot = wasiSdk / "share/wasi-sysroot"
  switch("clang.exe", wasiSdk / "bin/clang")
  switch("clang.linkerexe", wasiSdk / "bin/clang")
  switch("passC", "--sysroot=" & wasiSysroot &
    " -D_WASI_EMULATED_MMAN -D_WASI_EMULATED_SIGNAL")
  switch("passL", "--sysroot=" & wasiSysroot &
    " -lwasi-emulated-mman -lwasi-emulated-signal" &
    " -nostartfiles -Wl,--no-entry -Wl,--gc-sections" &
    " -Wl,--export=NimMain -Wl,--export=__wasm_call_ctors" &
    " -Wl,--export=dfkupAlloc -Wl,--export=dfkupFree" &
    " -Wl,--export=dfkupResultPtr -Wl,--export=dfkupResultLen" &
    " -Wl,--export=dfkupRun -Wl,--export=dfkupAst" &
    " -Wl,--export=dfkupVersion")
  switch("define", "openparserNoMmap")
  --threads:off
  --deepcopy:on
  --define:useMalloc
  --define:release
