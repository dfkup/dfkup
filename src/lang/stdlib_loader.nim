# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

## Lazy stdlib loader.
##
## Every `std/<name>` module except `system`, `json` and `strings` can be
## built as `libdfkup_<name>.dylib` and is loaded on the first
## `import "std/<name>"`. Scripts that import nothing pay nothing. The
## three exceptions live in `lang/lowlibs` and are always linked into the
## host binary (CLI and node addon alike), so they never touch a dylib.
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

import std/[os, dynlib, options]
import pkg/vancode/interpreter/[chunk, sym, codegen]
import ./lowlibs/libjson as internalJson
import ./lowlibs/libstrings as internalStrings
import ./lowlibs/libsequtils as internalSequtils
import ./lowlibs/libregex as internalRegex

when defined(napibuild):
  import pkg/vancode/interpreter/value
  import ./lowlibs/liball as staticLibs

const dfkupStdlibAbiVersion* = 1'u32
  ## Bumped whenever the host <-> stdlib calling convention changes.

const dfkupStdlibNames* = ["json", "yaml", "strings", "sequtils",
  "http", "cli", "config", "regex", "browser", "toml", "uuid", "dotenv",
  "csv", "bson", "colors", "qr", "nanoid", "llm", "httpclient", "xml",
  "feed", "ical", "css", "svg", "markdown", "strongpwd", "twofa",
  "fswatch", "algos", "bench"]
  ## Every stdlib name `import "std/<name>"` resolves. `system`, `json`
  ## and `strings` are served from `lang/lowlibs` in-image; the rest
  ## load from dylib shards (CLI) or the static bundle (napibuild).

type
  StdlibLoadError* = object of CatchableError
  DfkupStdlibInitFn* = proc(script, sysmod: pointer,
    outModule: ptr pointer, outErr: ptr cstring): cint {.cdecl.}
  DfkupStdlibCleanupFn* = proc() {.cdecl.}
  DfkupStdlibSetVmFn* = proc(vm: pointer) {.cdecl.}
  DfkupStdlibAbiFn* = proc(): uint32 {.cdecl.}
  DfkupStdlibNimFn* = proc(): cstring {.cdecl.}
  DfkupStdlibSetRaiseFn* = proc(fn: pointer) {.cdecl.}
  DfkupConfigTakeFn* = proc(): pointer {.cdecl.}
  DfkupConfigClearFn* = proc() {.cdecl.}
  DfkupConfigFindFn* = proc(cfg: pointer, name: cstring): cstring {.cdecl.}
  DfkupConfigErrFn* = proc(): cstring {.cdecl.}

proc dfkupHostRaise*(msg: cstring) {.cdecl.} =
  ## Host error sink installed into every shard before its init. A shard
  ## foreign proc that raises is caught in-image by its guard wrapper and
  ## re-raised here, so the exception is host-native and catchable as
  ## usual (message intact). Raising directly from dylib code would miss
  ## every host handler — each image owns its handler chain — and kill
  ## the process.
  if msg != nil:
    raise newException(ValueError, $msg)
  else:
    raise newException(ValueError, "stdlib error")

var loadedStdlibLibs: seq[tuple[name: string, handle: LibHandle,
    cleanup: DfkupStdlibCleanupFn, setVm: DfkupStdlibSetVmFn]] = @[]

proc stdlibLibExt*(): string =
  ## Platform shard extension. Must match what `tools/build_shards.nim`
  ## in the stdkups repo emits (`.dylib` macOS, `.dll` Windows, `.so`
  ## elsewhere) so release archives bundle loadable shards per target.
  when defined(windows):
    ".dll"
  elif defined(macosx):
    ".dylib"
  else:
    ".so"

proc stdlibLibPath*(name: string): string =
  ## Filesystem path of the `libdfkup_<name>` shard, "" when absent.
  ## `~/.dfkup/libraries` is the package-manager-owned shared-library dir
  ## (`DFKUP_HOME` overrides the home); next to the binary is the dev
  ## fallback (the shard build script writes `bin/stdlib/` there).
  ## Release archives lay the shards flat next to the binary (the archive
  ## step cannot preserve directories), so the binary's own dir is also
  ## probed.
  let file = "libdfkup_" & name & stdlibLibExt()
  let home = getEnv("DFKUP_HOME", getHomeDir() / ".dfkup")
  result = home / "libraries" / file
  if fileExists(result):
    return result
  result = getAppDir() / "stdlib" / file
  if fileExists(result):
    return result
  result = getAppDir() / file
  if fileExists(result):
    return result
  return ""

proc hasStdlibLib*(name: string): bool =
  ## True when a dylib file exists for `name` (no loading attempted).
  ## Under napibuild the libs are statically linked, so every known name
  ## is available without probing the filesystem.
  when defined(napibuild):
    return name in dfkupStdlibNames
  else:
    return stdlibLibPath(name).len > 0

proc loadStdlibModule*(name: string, script: Script,
    sysmod: Module): Module =
  ## Build the populated Module for `std/<name>`. Raises StdlibLoadError.
  ##
  ## `json`, `strings`, `sequtils` and `regex` are owned by dfkup
  ## (`lang/lowlibs`) and always served in-image, in both CLI and addon
  ## builds: no dlopen, no ABI or Nim version checks (one compiler by
  ## construction), no retains or slot reservations (same heap), no
  ## raise-sink (native exceptions).
  ## Every other stdlib dlopens its `libdfkup_<name>.dylib` (CLI) or
  ## builds from the static bundle (napibuild, see `lowlibs/liball`).
  case name
  of "json", "strings", "sequtils", "regex":
    result = newModule(name, some(name & ".dfkup"))
    result.importModule(sysmod, "system")
    case name
    of "json": internalJson.initJson(script, result)
    of "strings": internalStrings.initStrings(script, result)
    of "sequtils": internalSequtils.initSequtils(script, result)
    else: internalRegex.initRegex(script, result)
    return result
  else:
    discard
  when defined(napibuild):
    result = newModule(name, some(name & ".dfkup"))
    result.importModule(sysmod, "system")
    case name
    of "yaml": staticLibs.initYaml(script, result)
    of "http": staticLibs.initHttp(script, result)
    of "cli": staticLibs.initCliLib(script, result)
    of "config": staticLibs.initConfig(script, result)
    of "browser": staticLibs.initBrowser(script, result)
    of "toml": staticLibs.initToml(script, result)
    of "uuid": staticLibs.initUuid(script, result)
    of "dotenv": staticLibs.initDotenv(script, result)
    of "csv": staticLibs.initCsv(script, result)
    of "bson": staticLibs.initBson(script, result)
    of "colors": staticLibs.initColors(script, result)
    of "qr": staticLibs.initQr(script, result)
    of "nanoid": staticLibs.initNanoId(script, result)
    of "llm": staticLibs.initLlm(script, result)
    of "httpclient": staticLibs.initHttpClient(script, result)
    of "xml": staticLibs.initXml(script, result)
    of "feed": staticLibs.initFeed(script, result)
    of "ical": staticLibs.initIcal(script, result)
    of "css": staticLibs.initCss(script, result)
    of "svg": staticLibs.initSvg(script, result)
    of "markdown": staticLibs.initMarkdown(script, result)
    of "strongpwd": staticLibs.initStrongpwd(script, result)
    of "twofa": staticLibs.initTwofa(script, result)
    of "fswatch": staticLibs.initFswatch(script, result)
    of "algos": staticLibs.initAlgos(script, result)
    of "bench": staticLibs.initBench(script, result)
    else:
      raise newException(StdlibLoadError,
        "std \"" & name & "\" is not available")
    return result
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
  # Install the host error sink before init: the guard wrappers that
  # init registers re-raise shard errors through it (see
  # `stdlib_plugin.tmpl`). Absent in pre-guard dylibs — those still
  # load, but a shard raise in them is fatal (rebuild stdlibs).
  let setRaise = cast[DfkupStdlibSetRaiseFn](
    lib.symAddr("dfkupStdlibSetRaise"))
  if setRaise != nil:
    setRaise(cast[pointer](dfkupHostRaise))
  # Pre-reserve proc slots from here. The init below registers one
  # foreign proc per capability via `script.procs.add` in *dylib* code;
  # a realloc there would free the host-heap payload with the dylib
  # allocator and corrupt both heaps. Reserving host-side keeps every
  # dylib-side append realloc-free.
  # 1024 covers the largest lib several times over; the slack is a few
  # KB per loaded stdlib in a run-once process. (add/pop rather than
  # setLen: shrinking never trims capacity, so the reservation holds.)
  let sc = cast[Script](script)
  for i in 1 .. 1024:
    sc.procs.add(nil)
  for i in 1 .. 1024:
    discard sc.procs.pop()
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
  when defined(napibuild):
    # Only `browser` has a hook; the rest are no-ops.
    staticLibs.closeAllBrowsers()
    return
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
  when defined(napibuild):
    # Only `http` re-enters the VM; the rest are no-ops.
    staticLibs.setHttpHostVm(vm)
    return
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

proc configLibHandle*(): LibHandle =
  ## Handle of the loaded `config` dylib, or nil when not loaded yet.
  for entry in loadedStdlibLibs:
    if entry.name == "config":
      return entry.handle
  return nil

proc clearActiveConfig*() =
  ## Clear the `std/config` declaration retained by the config dylib.
  ## No-op when the dylib is not loaded yet (there is no state to clear);
  ## `runConfigFile` calls this both before (unloaded) and after (loaded).
  when defined(napibuild):
    staticLibs.clearActiveConfig()
    return
  let lib = configLibHandle()
  if lib == nil:
    return
  let fn = cast[DfkupConfigClearFn](lib.symAddr("dfkupConfigClearActive"))
  if fn == nil:
    raise newException(StdlibLoadError,
      "config dylib is missing dfkupConfigClearActive, rebuild stdlibs")
  fn()

proc takeActiveConfig*(): pointer =
  ## Peek at the retained config value as an opaque pointer. The dylib
  ## keeps its global reference alive (a raw pointer carries no ARC
  ## ownership); the caller releases via `clearActiveConfig`. Nil when
  ## no declaration ran.
  when defined(napibuild):
    let v = staticLibs.peekActiveConfig()
    if v == nil:
      return nil
    return cast[pointer](v)
  let lib = configLibHandle()
  if lib == nil:
    return nil
  let fn = cast[DfkupConfigTakeFn](lib.symAddr("dfkupConfigTakeActive"))
  if fn == nil:
    raise newException(StdlibLoadError,
      "config dylib is missing dfkupConfigTakeActive, rebuild stdlibs")
  return fn()

proc findConfigCommand*(cfg: pointer, name: string): string =
  ## Look up one command in a retained config value across the dylib
  ## boundary. Raises `ValueError` (like the static helper did) on
  ## unknown commands or malformed declarations.
  when defined(napibuild):
    return staticLibs.findConfigCommand(cast[Value](cfg), name)
  let lib = configLibHandle()
  if lib == nil:
    raise newException(StdlibLoadError,
      "std \"config\" is not installed (dylib not found)")
  let fn = cast[DfkupConfigFindFn](lib.symAddr("dfkupConfigFindCommand"))
  if fn == nil:
    raise newException(StdlibLoadError,
      "config dylib is missing dfkupConfigFindCommand, rebuild stdlibs")
  let res = fn(cfg, name.cstring)
  if res == nil:
    let errFn = cast[DfkupConfigErrFn](lib.symAddr("dfkupConfigTakeErr"))
    let msg = if errFn != nil and errFn() != nil: $errFn() else: "invalid config"
    raise newException(ValueError, msg)
  return $res
