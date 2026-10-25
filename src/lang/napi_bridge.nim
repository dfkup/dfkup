## Node.js addon surface for dfkup (napibuild only).
##
## Included from `src/dfkup.nim` after the core `exec`/`runScript`/...
## declarations, so it lives in the same module and can call them directly.
## Denim is only imported under `napibuild`, so the library itself keeps
## zero denim dependency and zero overhead for normal builds.
##
## The stdlib is statically linked (see `lang/lowlibs/liball`): every
## `std/<name>` import resolves through `loadStdlibFactory`'s napibuild
## branch, no dylib shards involved.

import std/json except `%*`
import std/strutils

import denim

include ./lowlibs/liball

# `std/cmdline` reads the executable's argv through `{.importc.}`
# globals (`cmdCount`/`cmdLine`) that only a Nim `main` provides. A
# `--noMain` shared library defines no `main`, and denim links with
# `-undefined dynamic_lookup` (flat namespace → eager binding), so any
# stdlib transitively importing `std/cmdline` (e.g. `std/cli`) would
# make `dlopen` fail with `symbol not found in flat namespace`.
# Provide them here, napibuild-only: an addon has no CLI args, so
# `paramCount()` is 0 and `commandLineParams()` is empty. The CLI keeps
# its real `main`-provided symbols (this file never compiles there).
var cmdCount {.exportc.}: cint = 0
var cmdLine {.exportc.}: cstringArray = nil

const dfkupNapiVersion = block:
  ## Single source of truth: the package version in dfkup.nimble, read at
  ## compile time so the addon never drifts from the project release.
  var v = "0.0.0"
  for line in staticRead("../../dfkup.nimble").splitLines:
    let t = line.strip
    if t.startsWith("version"):
      v = t.split('"')[1]
      break
  v

init proc(module: nodeapi.Module) =
  proc run(code: string): string {.export_napi.} =
    ## Run a DFkup script from source and return its result. A trailing
    ## expression is the result (like the CLI `exec` command), so
    ## `run("40 + 2")` returns "42".
    return napiCreate exec(args.get("code").getStr, "inline",
      allowExprResult = true, enableHotCodeDetection = false)

  proc runFile(path: string): string {.export_napi.} =
    ## Run a DFkup script from a file.
    return napiCreate runFile(args.get("path").getStr)

  proc runConfig(path: string): string {.export_napi.} =
    ## Run a config.kup file at the given path.
    return napiCreate runConfigFile(args.get("path").getStr)

  proc runConfigCommand(path: string, command: string): string {.export_napi.} =
    ## Run one configured command from a config.kup file.
    return napiCreate runConfigFile(args.get("path").getStr,
      args.get("command").getStr)

  proc ast(code: string): string {.export_napi.} =
    ## Parse a DFkup script and return its AST as JSON.
    var program: Ast
    parseScript(program, args.get("code").getStr)
    return napiCreate toJson(program.nodes)

  module.register("version", dfkupNapiVersion)
