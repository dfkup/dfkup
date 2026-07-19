# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/[options, os, strformat, tables]

import ./lang/transformers
export transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import pkg/vancode/interpreter/jit/jit

import ./lang/[parser]
import ./lang/lowlibs/[libsystem, libstrings, libsequtils,
                  libhttp, libcli, libjson, libyaml, libregex,
                  libbrowser]

import pkg/openparser/json

type
  DfkupError* = object of CatchableError

proc exec*(code: string, sourcePath: string, allowExprResult, enableHotCodeDetection: bool): string =
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

  let systemModule = newModule("system", some"system.timl")
  initSystem(script, systemModule)
  module.load(systemModule)

  var stdlibs: StandardLibrary = newTable[string, ModuleLibrary]()

  stdlibs["json"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("json", some"json.dfkup")
    m.load(sysMod)
    initJson(scr, m)
    return m

  stdlibs["yaml"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("yaml", some"yaml.dfkup")
    m.load(sysMod)
    initYaml(scr, m)
    return m

  stdlibs["strings"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("strings", some"strings.dfkup")
    m.load(sysMod)
    initStrings(scr, m)
    return m

  stdlibs["sequtils"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("sequtils", some"sequtils.dfkup")
    m.load(sysMod)
    initSequtils(scr, m)
    return m

  stdlibs["http"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("http", some"http.dfkup")
    m.load(sysMod)
    initHttp(scr, m)
    return m

  stdlibs["cli"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("cli", some"cli.dfkup")
    m.load(sysMod)
    initCliLib(scr, m)
    return m

  stdlibs["regex"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("regex", some"regex.dfkup")
    m.load(sysMod)
    initRegex(scr, m)
    return m

  stdlibs["browser"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("browser", some"browser.dfkup")
    m.load(sysMod)
    initBrowser(scr, m)
    return m

  script.stdpos = script.procs.high

  var gen = initCompiler(script, module, mainChunk, stdlibs = stdlibs)
  gen.allowExprResult = allowExprResult
  try:
    gen.genScript(program, none(string))
  except CatchableError as e:
    raise newException(DfkupError, e.msg)

  var prefs = VMPreferences(enableHotCodeDetection : enableHotCodeDetection)
  var vmInstance = newVirtualMachine(prefs)
  when defined(vancodeJitDynasm):
    installJit(vmInstance)
  
  # Create a synthetic Proc for the main chunk so the JIT can compile it
  # var mainProc = Proc(
  #   name: "__main",
  #   kind: pkNative,
  #   chunk: mainChunk,
  #   procId: script.procs.len,
  #   paramCount: 0,
  #   hasResult: false,
  #   jitForeign: nil,
  #   jitCallCount: 0,
  #   jitCodePtr: nil,
  #   jitMaxLocal: 0,
  #   jitReturnBool: false,
  #   jitRecompiled: false
  # )
  # script.procs.add(mainProc)
  # script.mainProc = mainProc

  vmInstance.prewarmScriptOps(script)
  when defined(vancodeJitDynasm):
    detectRecursiveAndCompile(vmInstance, enableHotCodeDetection)
  try:
    let resultVal = vmInstance.interpret(script, mainChunk)
    if resultVal != nil and resultVal.typeId notin {tyNil}:
      result = $resultVal
  except CatchableError as e:
    raise newException(DfkupError, "runtime error: " & e.msg)

proc runScript*(code: string, sourcePath = "script.dfkup", enableHotCodeDetection: bool = true): string =
  ## Parse, compile, and execute a DFkup script from a string.
  result = exec(code, sourcePath, false, enableHotCodeDetection)

proc runFile*(path: string, enableHotCodeDetection: bool = true): string =
  ## Read a DFkup file, parse it, compile, and execute.
  result = exec(readFile(path), path, false, enableHotCodeDetection)

when isMainModule:
  #
  # The CLI application
  #
  import pkg/kapsis
  import pkg/kapsis/runtime
  import pkg/kapsis/interactive/prompts
  import ./lang/repl

  proc runCommand*(v: Values) =
    let filePath = $(v.get("script").getPath)
    try:
      let result = runFile(filePath, not v.has("--nojit"))
      if result.len > 0:
        echo result
    except DfkupError as e:
      display(span("error", fgRed), span(e.msg))
    except IOError as e:
      display(span("error", fgRed), span(e.msg))

  proc inlineCommand*(v: Values) =
    var code: string
    if v.has("code"):
      code = v.get("code").getStr
    elif paramCount() >= 1:
      for i in 1..paramCount():
        if code.len > 0: code.add(" ")
        code.add(paramStr(i))
    else:
      display(span("error", fgRed), span("Usage: dfkup inline <code>"))
      return
    try:
      let result = exec(code, "inline", allowExprResult = true, enableHotCodeDetection = false)
      if result.len > 0:
        echo result
    except DfkupError as e:
      display(span("error", fgRed), span(e.msg))

  proc replCommand*(v: Values) =
    runRepl()

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
  
    # todo, write to a file when `-o:some/path.ast` is provided
    if v.has("--dumptree") and v.get("--dumptree").getBool:
      for node in program.nodes:
        echo node.treeRepr
    else:
      echo toJson(program.nodes)

  initKapsis do:
    defaultCommand "run"
    commands:
      -- "Scripting"
      repl:
        ## Start an interactive REPL session
      run path(script), ?bool("--nojit"):
        ## Run a DFkup script file
      inline ?string(code):
        ## Execute DFkup code inline
      ast path(script), ?bool("--dumptree"):
        ## Generate AST from a DFkup script file
