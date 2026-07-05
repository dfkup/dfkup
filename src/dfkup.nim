# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/[options, os, strformat]
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import pkg/vancode/interpreter/jit/jit
import ./lang/[parser, lowlibs/libsystem, lowlibs/libjson]

type
  DfkupError* = object of CatchableError

proc exec*(code: string, sourcePath: string, allowExprResult: bool): string =
  ## Core execution: parse, compile, run a DFkup script.
  var program: Ast
  try:
    parseScript(program, code)
  except DfkupParserError as e:
    raise newException(DfkupError, &"{sourcePath}({e.ln},{e.col}): {e.msg}")

  var
    mainChunk = newChunk(sourcePath)
    script = newScript(mainChunk)
    module = newModule(sourcePath.extractFilename, some(sourcePath))

  let systemModule = newModule("system", some"system.dfkup")
  initSystem(script, systemModule)
  module.load(systemModule)

  let jsonModule = newModule("json", some"json.dfkup")
  initJson(script, jsonModule)
  module.load(jsonModule)

  script.stdpos = script.procs.high

  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = allowExprResult
  try:
    gen.genScript(program, none(string))
  except CatchableError as e:
    raise newException(DfkupError, "codegen error: " & e.msg)

  var prefs = VMPreferences(enableHotCodeDetection: true, hotProcThreshold: 2)
  var vmInstance = newVirtualMachine(prefs)
  when defined(vancodeJit):
    installJit(vmInstance)
  try:
    let resultVal = vmInstance.interpret(script, mainChunk)
    if resultVal != nil and resultVal.typeId notin {tyNil}:
      result = $resultVal
  except CatchableError as e:
    raise newException(DfkupError, "runtime error: " & e.msg)

proc runScript*(code: string, sourcePath = "script.dfkup"): string =
  ## Parse, compile, and execute a DFkup script from a string.
  result = exec(code, sourcePath, false)

proc runFile*(path: string): string =
  ## Read a DFkup file, parse it, compile, and execute.
  result = exec(readFile(path), path, false)

when isMainModule:
  import pkg/kapsis
  import pkg/kapsis/runtime
  import pkg/kapsis/interactive/prompts

  proc runCommand*(v: Values) =
    let filePath = $(v.get("script").getPath)
    try:
      let result = runFile(filePath)
      if result.len > 0:
        echo result
    except DfkupError as e:
      display(span("error", fgRed), span(e.msg))
    except IOError as e:
      display(span("error", fgRed), span(e.msg))

  proc astCommand*(v: Values) =
    let filePath = $(v.get("script").getPath)
    if not fileExists(filePath):
      display(span("error", fgRed), span(&"file not found: {filePath}"))
      return
    let code = readFile(filePath)
    var program: Ast
    try:
      parseScript(program, code)
    except DfkupParserError as e:
      display(span("error", fgRed), span(&"{filePath}({e.ln},{e.col}): {e.msg}"))
      return
    for node in program.nodes:
      echo node.treeRepr

  initKapsis do:
    commands:
      -- "Scripting"
      run path(script):
        ## Run a DFkup script file
      ast path(script), ?bool("--dumptree"):
        ## Generate AST from a DFkup script file
