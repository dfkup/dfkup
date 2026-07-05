# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/[os, strformat, options]
import pkg/openparser/json
import pkg/kapsis/[runtime, cli]
import pkg/kapsis/interactive/prompts
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]

import ../lang/[parser, libsystem]

proc execCommand*(v: Values) =
  ## Execute a DFkup script from file
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

  var
    mainChunk = newChunk(filePath)
    script = newScript(mainChunk)
    module = newModule(filePath.extractFilename, some(filePath))

  let systemModule = newModule("system", some"system.dfkup")
  initSystem(script, systemModule)
  module.load(systemModule)
  script.stdpos = script.procs.high

  try:
    var gen = initCodeGen(script, module, mainChunk)
    gen.genScript(program, none(string))
  except CatchableError as e:
    display(span("codegen error", fgRed), span(e.msg))
    return

  try:
    var vmInstance = newVm()
    let resultVal = vmInstance.interpret(script, mainChunk)
    if resultVal != nil and resultVal.typeId notin {tyNil}:
      echo $resultVal
  except CatchableError as e:
    display(span("runtime error", fgRed), span(e.msg))

proc astCommand*(v: Values) =
  ## Generate AST from a script file
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

  if v.has("--dumptree"):
    for node in program.nodes:
      echo node.treeRepr
  else:
    echo toJson(program.nodes)