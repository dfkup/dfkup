# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

## `dfkup` for wasm32 — string-in/string-out bridge for the browser
## playground (no Emscripten; pure wasm via the WASI SDK + a JS shim).
##
## Only the image-linked lowlibs (`system`, `json`, `strings`, `sequtils`,
## `regex`) are available: every other `std/*` module loads from a dylib
## shard on native targets, and there is no `dlopen` in the browser.
## Filesystem, shell, environment and process builtins are compiled out of
## `system` under `-d:wasm` (see `lang/lowlibs/libsystem`), `echo` output
## is captured into `wasmEchoBuf`, and scripts run on the VM only
## (the DynASM JIT emits native machine code and stays off).
##
## Memory protocol (linear memory is exported by the module):
## - host writes input bytes via `dfkupAlloc`, then calls an API proc,
## - the call returns 0 on success (result bytes in the shared buffer)
##   or 1 on error (message bytes in the shared buffer),
## - host reads `dfkupResultLen` bytes at `dfkupResultPtr` and copies out.

import std/[tables, options, strutils]
import ./transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value,
  resolver, manager, policy]
import pkg/openparser/json

import ./parser
import ./lowlibs/libsystem
import ./lowlibs/libjson as internalJson
import ./lowlibs/libstrings as internalStrings
import ./lowlibs/libsequtils as internalSequtils
import ./lowlibs/libregex as internalRegex

const DfkupWasmVersion* = "0.1.0"
  ## Mirrors the `versionStr` in the CLI block of `src/dfkup.nim`.
  ## Keep the two in sync on every version bump.

var wasmResult {.global.}: string

proc copyFromHost(p: pointer, len: int): string =
  ## Copy `len` bytes from wasm linear memory into a Nim string.
  result = newString(len)
  if len > 0:
    copyMem(addr result[0], p, len)

proc takeError(msg: string): cint =
  wasmResult = msg
  1

proc takeOk(output: string): cint =
  wasmResult = output
  0

proc wasmStdlibFactory(name: string): ModuleLibrary =
  ## Serve the five image-linked lowlibs; anything else is unavailable
  ## (no dylib loading in the browser playground, so factory is nil and
  ## vancode reports the import error itself).
  case name
  of "json", "strings", "sequtils", "regex":
    var cached: Module = nil
    var done = false
    result = proc(scr: Script, sysMod: Module): Module =
      if not done:
        cached = newModule(name, some(name & ".dfkup"))
        cached.importModule(sysMod, "system")
        case name
        of "json": internalJson.initJson(scr, cached)
        of "strings": internalStrings.initStrings(scr, cached)
        of "sequtils": internalSequtils.initSequtils(scr, cached)
        else: internalRegex.initRegex(scr, cached)
        done = true
      return cached
  else:
    result = nil

proc wasmParseFile(astProgram: var Ast, path: string,
    resolver: FileResolver) =
  ## File imports cannot resolve without a filesystem: fail loudly
  ## instead of dereferencing the nil callback and segfaulting.
  raise newException(CatchableError,
    "file imports are unavailable in the wasm build: " & path)

proc runSource(code: string): string =
  ## Parse, compile and interpret one script; `echo` output and a trailing
  ## expression value are joined into the returned string.
  var program: Ast
  try:
    parseScript(program, code)
  except DfkupParserError as e:
    raise newException(CatchableError, "parse error: " & e.msg)
  var
    mainChunk = newChunk("playground")
    script = newScript(mainChunk)
    module = newModule("playground", some("playground"))
  let systemModule = newModule("system", some("system.dfkup"))
  initSystem(script, systemModule)
  module.importModule(systemModule, "system")
  wasmEchoBuf = ""
  var stdlibs: StandardLibrary = newTable[string, ModuleLibrary]()
  var manager = newModuleManager()
  var gen = initCompiler(script, module, mainChunk, manager = manager,
    stdlibs = stdlibs, parserCallback = wasmParseFile,
    stdlibLoader = wasmStdlibFactory)
  gen.allowExprResult = true
  try:
    gen.genScript(program, none(string))
  except CatchableError as e:
    raise newException(CatchableError, e.msg)
  script.stdpos = script.procs.high
  var prefs = VMPreferences(enableHotCodeDetection: false)
  var vmInstance = newVirtualMachine(prefs)
  vmInstance.prewarmScriptOps(script)
  try:
    let resultVal = vmInstance.interpret(script, mainChunk)
    result = wasmEchoBuf.strip(leading = false, trailing = true)
    if resultVal != nil and resultVal.typeId notin {tyNil}:
      if result.len > 0:
        result.add("\n")
      result.add($resultVal)
  except CatchableError as e:
    raise newException(CatchableError, "runtime error: " & e.msg)

proc dfkupAlloc*(size: csize_t): pointer {.exportc.} =
  ## Allocate `size` bytes for host-provided input. Host writes input
  ## bytes into the returned pointer before calling an API proc.
  if size == 0:
    return nil
  alloc(size)

proc dfkupFree*(p: pointer) {.exportc.} =
  ## Release a pointer previously returned by `dfkupAlloc`.
  if p != nil:
    dealloc(p)

proc dfkupResultPtr*(): pointer {.exportc.} =
  ## Pointer to the first byte of the last result (or error message).
  if wasmResult.len == 0:
    nil
  else:
    unsafeAddr wasmResult[0]

proc dfkupResultLen*(): cint {.exportc.} =
  ## Length in bytes of the last result (or error message).
  wasmResult.len.cint

proc dfkupRun*(srcPtr: pointer, srcLen: cint): cint {.exportc.} =
  ## Execute a dfkup script. Returns 0 with `echo` output + trailing
  ## expression value in the result buffer, 1 with the error message.
  try:
    takeOk(runSource(copyFromHost(srcPtr, srcLen.int)))
  except CatchableError as e:
    takeError(e.msg)
  except Exception as e:
    takeError(e.msg)

proc dfkupAst*(srcPtr: pointer, srcLen: cint): cint {.exportc.} =
  ## Parse a dfkup script and return its AST as JSON.
  try:
    var program: Ast
    try:
      parseScript(program, copyFromHost(srcPtr, srcLen.int))
    except DfkupParserError as e:
      raise newException(CatchableError, "parse error: " & e.msg)
    takeOk(toJson(program.nodes))
  except CatchableError as e:
    takeError(e.msg)
  except Exception as e:
    takeError(e.msg)

proc dfkupVersion*(): cint {.exportc.} =
  ## Report the engine version through the shared result buffer.
  takeOk(DfkupWasmVersion)
