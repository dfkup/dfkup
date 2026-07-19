import std/[tables, strformat, options, strutils]
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ./parser
import ./lowlibs/[libsystem, libjson, libyaml, libstrings, libsequtils, libhttp, libcli, libregex, libbrowser]

proc newStdlibs*(script: Script, systemModule: Module): StandardLibrary =
  result = newTable[string, ModuleLibrary]()
  result["json"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("json", some"json.dfkup")
    m.load(sysMod)
    initJson(scr, m)
    return m
  result["yaml"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("yaml", some"yaml.dfkup")
    m.load(sysMod)
    initYaml(scr, m)
    return m
  result["strings"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("strings", some"strings.dfkup")
    m.load(sysMod)
    initStrings(scr, m)
    return m
  result["sequtils"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("sequtils", some"sequtils.dfkup")
    m.load(sysMod)
    initSequtils(scr, m)
    return m
  result["http"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("http", some"http.dfkup")
    m.load(sysMod)
    initHttp(scr, m)
    return m
  result["cli"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("cli", some"cli.dfkup")
    m.load(sysMod)
    initCliLib(scr, m)
    return m
  result["regex"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("regex", some"regex.dfkup")
    m.load(sysMod)
    initRegex(scr, m)
    return m

  result["browser"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("browser", some"browser.dfkup")
    m.load(sysMod)
    initBrowser(scr, m)
    return m

type ReplSession* = object
  script*: Script
  module*: Module
  systemModule*: Module
  stdlibs*: StandardLibrary
  vm*: Vm

proc initReplSession*(): ReplSession =
  result.script = newScript(newChunk("repl"))
  result.module = newModule("repl", some"repl.dfkup")
  result.systemModule = newModule("system", some"system.dfkup")
  initSystem(result.script, result.systemModule)
  result.module.load(result.systemModule)
  result.stdlibs = newStdlibs(result.script, result.systemModule)
  result.script.stdpos = result.script.procs.high
  result.vm = newVirtualMachine(VMPreferences())

proc evalRepl*(session: var ReplSession, code: string): string =
  var program: Ast
  try:
    parseScript(program, code)
  except DfkupParserError as e:
    return "parse error: " & e.msg
  var chunk = newChunk("repl")
  var gen = initCompiler(session.script, session.module, chunk, stdlibs = session.stdlibs)
  gen.allowExprResult = true
  try:
    gen.genScript(program, none(string))
  except CatchableError as e:
    return "compile error: " & e.msg
  try:
    let r = session.vm.interpret(session.script, chunk)
    if r.typeId notin {tyNil}:
      result = $r
  except CatchableError as e:
    result = "runtime error: " & e.msg

proc runRepl*() =
  var session = initReplSession()
  echo &"DFkup REPL"
  echo &"Type 'exit' to quit"
  var buffer = ""
  var failCount = 0
  while true:
    try:
      let prompt = if buffer.len == 0: "dfkup> " else: "dfkup.. "
      stdout.write(prompt)
      stdout.flushFile()
      let line = stdin.readLine()
      if line == "exit" or line == "exit()":
        break
      buffer.add(line)
      buffer.add("\n")
      let result = evalRepl(session, buffer)
      if result.startsWith("parse error:"):
        inc failCount
        if failCount < 4:
          continue
      else:
        failCount = 0
      if result.len > 0:
        echo result
      buffer.setLen(0)
    except IOError:
      break
    except EOFError:
      break