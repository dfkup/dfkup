# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

## Lazy stdlib dylib loader.
##
## Every `std/<name>` module (except `system`, which is always linked)
## can be built as `libdfkup_<name>.dylib` and is loaded on the first
## `import "std/<name>"`. Scripts that import nothing pay nothing.
##
## Dylib entry points mirror pluginkit's low-level conventions
## (C ABI, no plugin DSL):
## - `dfkupStdlibAbi(): uint32` must equal `dfkupStdlibAbiVersion`
## - `dfkupStdlibNim(): cstring` must equal the host `NimVersion`
## - `dfkupStdlibInit(script, sysmod, outModule, outErr): cint`
## - optional `dfkupStdlibCleanup()` run from `cleanupStdlibs`
## - optional `dfkupStdlibSetVm(vm)` giving the dylib the host VM (libhttp:
##   server callbacks re-enter the VM through the JIT bridge, whose
##   `jitGlobalVm` lives per-image; the ABI version is unchanged since
##   every addition is nil-tolerant)
##
## Handles are never unloaded; the CLI runs once per process.

import std/[os, dynlib]
import pkg/vancode/interpreter/[chunk, sym, codegen]

const dfkupStdlibAbiVersion* = 1'u32
  ## Bumped whenever the host <-> stdlib calling convention changes.

const dfkupStdlibNames* = ["json", "yaml", "strings", "sequtils",
  "http", "cli", "regex", "browser", "toml", "uuid", "dotenv", "csv",
  "bson", "colors", "qr", "nanoid", "llm", "httpclient", "xml", "feed",
  "ical", "css", "svg", "markdown", "strongpwd", "twofa", "fswatch",
  "algos"]
  ## Every stdlib available as a dylib. `system` and `config` stay
  ## statically linked in the core binary.

type
  StdlibLoadError* = object of CatchableError
  DfkupStdlibInitFn* = proc(script, sysmod: pointer,
    outModule: ptr pointer, outErr: ptr cstring): cint {.cdecl.}
  DfkupStdlibCleanupFn* = proc() {.cdecl.}
  DfkupStdlibSetVmFn* = proc(vm: pointer) {.cdecl.}
  DfkupStdlibAbiFn* = proc(): uint32 {.cdecl.}
  DfkupStdlibNimFn* = proc(): cstring {.cdecl.}

var loadedStdlibLibs: seq[tuple[name: string, handle: LibHandle,
    cleanup: DfkupStdlibCleanupFn, setVm: DfkupStdlibSetVmFn]] = @[]

proc stdlibLibPath*(name: string): string =
  ## Filesystem path of `libdfkup_<name>.dylib`, "" when absent.
  ## `~/.dfkup/libraries` is the package-manager-owned shared-library dir
  ## (`DFKUP_HOME` overrides the home); next to the binary is the dev
  ## fallback (`clue task stdlibs` builds there).
  let file = "libdfkup_" & name & ".dylib"
  let home = getEnv("DFKUP_HOME", getHomeDir() / ".dfkup")
  result = home / "libraries" / file
  if fileExists(result):
    return result
  result = getAppDir() / "stdlib" / file
  if fileExists(result):
    return result
  return ""

proc hasStdlibLib*(name: string): bool =
  ## True when a dylib file exists for `name` (no loading attempted).
  stdlibLibPath(name).len > 0

proc loadStdlibModule*(name: string, script: Script,
    sysmod: Module): Module =
  ## dlopen `libdfkup_<name>.dylib`, verify ABI + Nim version, run its
  ## init and return the populated Module. Raises StdlibLoadError.
  let path = stdlibLibPath(name)
  if path.len == 0:
    raise newException(StdlibLoadError, "std \"" & name &
      "\" is not installed (dylib not found)")
  let lib =
    try:
      loadLib(path)
    except CatchableError:
      nil
  if lib == nil:
    raise newException(StdlibLoadError,
      "cannot load stdlib dylib: " & path)
  let abiFn = cast[DfkupStdlibAbiFn](lib.symAddr("dfkupStdlibAbi"))
  if abiFn == nil or abiFn() != dfkupStdlibAbiVersion:
    unloadLib(lib)
    raise newException(StdlibLoadError,
      "stdlib ABI mismatch, rebuild stdlibs: " & path)
  let nimFn = cast[DfkupStdlibNimFn](lib.symAddr("dfkupStdlibNim"))
  if nimFn == nil or $nimFn() != NimVersion:
    unloadLib(lib)
    raise newException(StdlibLoadError, "stdlib built with another Nim " &
      "version, rebuild stdlibs: " & path & " (need " & NimVersion & ")")
  let initFn = cast[DfkupStdlibInitFn](lib.symAddr("dfkupStdlibInit"))
  if initFn == nil:
    unloadLib(lib)
    raise newException(StdlibLoadError,
      "missing dfkupStdlibInit symbol: " & path)
  var outMod: pointer = nil
  var outErr: cstring = nil
  if initFn(cast[pointer](script), cast[pointer](sysmod),
      addr outMod, addr outErr) != 0 or outMod == nil:
    let msg = if outErr != nil: $outErr else: "init failed"
    unloadLib(lib)
    raise newException(StdlibLoadError,
      "stdlib init failed (" & name & "): " & msg)
  let cleanup = cast[DfkupStdlibCleanupFn](
    lib.symAddr("dfkupStdlibCleanup"))
  let setVm = cast[DfkupStdlibSetVmFn](
    lib.symAddr("dfkupStdlibSetVm"))
  loadedStdlibLibs.add((name, lib, cleanup, setVm))
  return cast[Module](outMod)

proc loadStdlibFactory*(name: string): ModuleLibrary =
  ## Vancode `StdlibLoader` entry: nil when `name` is not a known dfkup
  ## stdlib (vancode reports ErrImportError); otherwise a caching factory
  ## that loads on first use. Load/init failures raise StdlibLoadError,
  ## which vancode reports with file/line context.
  if name notin dfkupStdlibNames:
    return nil
  var cached: Module = nil
  var done = false
  result = proc(scr: Script, sysMod: Module): Module =
    if not done:
      cached = loadStdlibModule(name, scr, sysMod)
      done = true
    return cached

proc cleanupStdlibs*() =
  ## Run optional per-stdlib cleanup hooks (e.g. reap headless browsers).
  ## Never unloads: the CLI runs once per process.
  for entry in loadedStdlibLibs:
    if entry.cleanup != nil:
      try:
        entry.cleanup()
      except CatchableError:
        discard

proc setStdlibVms*(vm: pointer) =
  ## Push the host VM into every loaded dylib that asked for it
  ## (`dfkupStdlibSetVm` export). Runs once the VM exists, before
  ## interpret: stdlib factories load at compile time, when no VM
  ## exists yet, so the handoff cannot happen in `loadStdlibModule`.
  for entry in loadedStdlibLibs:
    if entry.setVm != nil:
      try:
        entry.setVm(vm)
      except CatchableError:
        discard

proc stdlibDynlibLoaded*(): bool =
  ## True once any stdlib dylib was initialized this process. The host
  ## uses it to decide whether compiler state must be retained (below).
  loadedStdlibLibs.len > 0
