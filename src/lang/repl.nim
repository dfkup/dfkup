import std/[tables, strformat, options, strutils]
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ./parser
import ./lowlibs/[libsystem, libjson, libyaml, libstrings, libsequtils, libhttp, libcli, libconfig, libregex, libbrowser,
  libtoml, libuuid, libdotenv, libcsv, libbson, libcolors, libqr, libxml, libfeed, libical, libcss, libsvg,
  libmarkdown, libstrongpwd, libalgos, libtwofa, libfswatch, libnanoid, libllm, libhttpclient]

proc newStdlibs*(script: Script, systemModule: Module): StandardLibrary =
  result = newTable[string, ModuleLibrary]()
  result["json"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("json", some"json.dfkup")
    m.importModule(sysMod, "system")
    initJson(scr, m)
    return m
  result["yaml"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("yaml", some"yaml.dfkup")
    m.importModule(sysMod, "system")
    initYaml(scr, m)
    return m
  result["strings"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("strings", some"strings.dfkup")
    m.importModule(sysMod, "system")
    initStrings(scr, m)
    return m
  result["sequtils"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("sequtils", some"sequtils.dfkup")
    m.importModule(sysMod, "system")
    initSequtils(scr, m)
    return m
  result["http"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("http", some"http.dfkup")
    m.importModule(sysMod, "system")
    initHttp(scr, m)
    return m
  result["cli"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("cli", some"cli.dfkup")
    m.importModule(sysMod, "system")
    initCliLib(scr, m)
    return m
  result["config"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("config", some"config.dfkup")
    m.importModule(sysMod, "system")
    initConfig(scr, m)
    return m
  result["regex"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("regex", some"regex.dfkup")
    m.importModule(sysMod, "system")
    initRegex(scr, m)
    return m

  result["browser"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("browser", some"browser.dfkup")
    m.importModule(sysMod, "system")
    initBrowser(scr, m)
    return m

  result["toml"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("toml", some"toml.dfkup")
    m.importModule(sysMod, "system")
    initToml(scr, m)
    return m
  result["uuid"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("uuid", some"uuid.dfkup")
    m.importModule(sysMod, "system")
    initUuid(scr, m)
    return m
  result["dotenv"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("dotenv", some"dotenv.dfkup")
    m.importModule(sysMod, "system")
    initDotenv(scr, m)
    return m
  result["csv"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("csv", some"csv.dfkup")
    m.importModule(sysMod, "system")
    initCsv(scr, m)
    return m
  result["bson"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("bson", some"bson.dfkup")
    m.importModule(sysMod, "system")
    initBson(scr, m)
    return m
  result["colors"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("colors", some"colors.dfkup")
    m.importModule(sysMod, "system")
    initColors(scr, m)
    return m
  result["qr"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("qr", some"qr.dfkup")
    m.importModule(sysMod, "system")
    initQr(scr, m)
    return m

  stdlibs["nanoid"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("nanoid", some"nanoid.dfkup")
    m.importModule(sysMod, "system")
    initNanoId(scr, m)
    return m

  stdlibs["llm"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("llm", some"llm.dfkup")
    m.importModule(sysMod, "system")
    initLlm(scr, m)
    return m

  stdlibs["httpclient"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("httpclient", some"httpclient.dfkup")
    m.importModule(sysMod, "system")
    initHttpClient(scr, m)
    return m
  result["xml"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("xml", some"xml.dfkup")
    m.importModule(sysMod, "system")
    initXml(scr, m)
    return m
  result["feed"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("feed", some"feed.dfkup")
    m.importModule(sysMod, "system")
    initFeed(scr, m)
    return m
  result["ical"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("ical", some"ical.dfkup")
    m.importModule(sysMod, "system")
    initIcal(scr, m)
    return m
  result["css"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("css", some"css.dfkup")
    m.importModule(sysMod, "system")
    initCss(scr, m)
    return m
  result["svg"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("svg", some"svg.dfkup")
    m.importModule(sysMod, "system")
    initSvg(scr, m)
    return m
  result["markdown"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("markdown", some"markdown.dfkup")
    m.importModule(sysMod, "system")
    initMarkdown(scr, m)
    return m
  result["strongpwd"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("strongpwd", some"strongpwd.dfkup")
    m.importModule(sysMod, "system")
    initStrongpwd(scr, m)
    return m
  result["algos"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("algos", some"algos.dfkup")
    m.importModule(sysMod, "system")
    initAlgos(scr, m)
    return m
  result["twofa"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("twofa", some"twofa.dfkup")
    m.importModule(sysMod, "system")
    initTwofa(scr, m)
    return m
  result["fswatch"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("fswatch", some"fswatch.dfkup")
    m.importModule(sysMod, "system")
    initFswatch(scr, m)
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
    return "parse error: (" & $e.ln & "," & $e.col & "): " & e.msg
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