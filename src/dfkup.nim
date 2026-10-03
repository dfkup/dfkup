# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/[options, os, osproc, strformat, tables]

import ./lang/transformers
export transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value, resolver]
import pkg/vancode/interpreter/jit/jit

import ./lang/[parser]
import ./lang/lowlibs/[libsystem, libstrings, libsequtils,
                  libhttp, libcli, libconfig, libjson, libyaml, libregex,
                  libbrowser, libtoml, libuuid, libdotenv,
                  libcsv, libbson, libcolors, libqr, libnanoid, libllm,
                  libhttpclient,
                  libxml, libfeed, libical, libcss, libsvg,
                  libmarkdown, libstrongpwd, libalgos, libtwofa,
                  libfswatch]

import pkg/openparser/json

type
  DfkupError* = object of CatchableError

proc parseDfkupFile(astProgram: var Ast, path: string,
                    resolver: FileResolver) =
  ## Parses an imported dfkup source file.
  ##
  ## vancode calls this for every non-stdlib `import`. Without it `genImport`
  ## dereferences a nil callback and the compiler segfaults on the first
  ## user-file import, so multi-file dfkup programs could not be compiled at
  ## all. Reading through the resolver keeps import resolution on the same
  ## path the file resolver already tracked.
  let code =
    try:
      resolver.readFile(path)
    except IOError as e:
      raise newException(DfkupError, "cannot read import: " & e.msg)
  try:
    parseScript(astProgram, code)
  except DfkupParserError as e:
    raise newException(DfkupError, &"{path}({e.ln},{e.col}): {e.msg}")
  astProgram.sourcePath = path

proc exec*(code: string, sourcePath: string, allowExprResult, enableHotCodeDetection: bool,
    autoloadConfig = false): string =
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
  module.importModule(systemModule, "system")

  var stdlibs: StandardLibrary = newTable[string, ModuleLibrary]()

  stdlibs["json"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("json", some"json.dfkup")
    m.importModule(sysMod, "system")
    initJson(scr, m)
    return m

  stdlibs["yaml"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("yaml", some"yaml.dfkup")
    m.importModule(sysMod, "system")
    initYaml(scr, m)
    return m

  stdlibs["strings"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("strings", some"strings.dfkup")
    m.importModule(sysMod, "system")
    initStrings(scr, m)
    return m

  stdlibs["sequtils"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("sequtils", some"sequtils.dfkup")
    m.importModule(sysMod, "system")
    initSequtils(scr, m)
    return m

  stdlibs["http"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("http", some"http.dfkup")
    m.importModule(sysMod, "system")
    initHttp(scr, m)
    return m

  stdlibs["cli"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("cli", some"cli.dfkup")
    m.importModule(sysMod, "system")
    initCliLib(scr, m)
    return m

  stdlibs["config"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("config", some"config.dfkup")
    m.importModule(sysMod, "system")
    initConfig(scr, m)
    return m

  stdlibs["regex"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("regex", some"regex.dfkup")
    m.importModule(sysMod, "system")
    initRegex(scr, m)
    return m

  stdlibs["browser"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("browser", some"browser.dfkup")
    m.importModule(sysMod, "system")
    initBrowser(scr, m)
    return m

  stdlibs["toml"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("toml", some"toml.dfkup")
    m.importModule(sysMod, "system")
    initToml(scr, m)
    return m

  stdlibs["uuid"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("uuid", some"uuid.dfkup")
    m.importModule(sysMod, "system")
    initUuid(scr, m)
    return m

  stdlibs["dotenv"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("dotenv", some"dotenv.dfkup")
    m.importModule(sysMod, "system")
    initDotenv(scr, m)
    return m

  stdlibs["csv"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("csv", some"csv.dfkup")
    m.importModule(sysMod, "system")
    initCsv(scr, m)
    return m

  stdlibs["bson"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("bson", some"bson.dfkup")
    m.importModule(sysMod, "system")
    initBson(scr, m)
    return m

  stdlibs["colors"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("colors", some"colors.dfkup")
    m.importModule(sysMod, "system")
    initColors(scr, m)
    return m

  stdlibs["qr"] = proc(scr: Script, sysMod: Module): Module =
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

  stdlibs["xml"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("xml", some"xml.dfkup")
    m.importModule(sysMod, "system")
    initXml(scr, m)
    return m

  stdlibs["feed"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("feed", some"feed.dfkup")
    m.importModule(sysMod, "system")
    initFeed(scr, m)
    return m

  stdlibs["ical"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("ical", some"ical.dfkup")
    m.importModule(sysMod, "system")
    initIcal(scr, m)
    return m

  stdlibs["css"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("css", some"css.dfkup")
    m.importModule(sysMod, "system")
    initCss(scr, m)
    return m

  stdlibs["svg"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("svg", some"svg.dfkup")
    m.importModule(sysMod, "system")
    initSvg(scr, m)
    return m

  stdlibs["markdown"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("markdown", some"markdown.dfkup")
    m.importModule(sysMod, "system")
    initMarkdown(scr, m)
    return m

  stdlibs["strongpwd"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("strongpwd", some"strongpwd.dfkup")
    m.importModule(sysMod, "system")
    initStrongpwd(scr, m)
    return m

  # stdlibs["algos"] = proc(scr: Script, sysMod: Module): Module =
  #   let m = newModule("algos", some"algos.dfkup")
  #   m.importModule(sysMod, "system")
  #   initAlgos(scr, m)
  #   return m

  stdlibs["twofa"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("twofa", some"twofa.dfkup")
    m.importModule(sysMod, "system")
    initTwofa(scr, m)
    return m

  stdlibs["fswatch"] = proc(scr: Script, sysMod: Module): Module =
    let m = newModule("fswatch", some"fswatch.dfkup")
    m.importModule(sysMod, "system")
    initFswatch(scr, m)
    return m

  if autoloadConfig:
    # `conf` mode makes `config({...})` available without an explicit
    # `import "std/config"`. Ordinary scripts still resolve `config` only
    # through that import.
    module.importModule(stdlibs["config"](script, systemModule), "config")

  script.stdpos = script.procs.high

  var gen = initCompiler(script, module, mainChunk, stdlibs = stdlibs,
                         parserCallback = parseDfkupFile)
  gen.allowExprResult = allowExprResult
  try:
    gen.genScript(program, none(string))
  except CatchableError as e:
    raise newException(DfkupError, e.msg)

  var prefs = VMPreferences(enableHotCodeDetection : enableHotCodeDetection)
  var vmInstance = newVirtualMachine(prefs)
  when defined(vancodeJitDynasm):
    installJit(vmInstance)
  
  vmInstance.prewarmScriptOps(script)
  when defined(vancodeJitDynasm):
    detectRecursiveAndCompile(vmInstance, enableHotCodeDetection)
  try:
    let resultVal = vmInstance.interpret(script, mainChunk)
    if resultVal != nil and resultVal.typeId notin {tyNil}:
      result = $resultVal
  except CatchableError as e:
    raise newException(DfkupError, "runtime error: " & e.msg)
  finally:
    # a script that aborts, errors, or is interrupted never reaches its own
    # `close(browser)`, and a browser handle's destructor only unrefs. Without
    # this a failed run leaves headless Chrome processes behind.
    closeAllBrowsers()

proc runScript*(code: string, sourcePath = "script.dfkup", enableHotCodeDetection: bool = true): string =
  ## Parse, compile, and execute a DFkup script from a string.
  result = exec(code, sourcePath, false, enableHotCodeDetection)

proc runFile*(path: string, enableHotCodeDetection: bool = true): string =
  ## Read a DFkup file, parse it, compile, and execute.
  result = exec(readFile(path), path, false, enableHotCodeDetection)

proc runConfigFile*(path: string, command = "",
    enableHotCodeDetection: bool = true): string =
  ## Run a config file with `std/config` loaded automatically.
  ##
  ## Without `command`, this behaves like `runFile` for a config source. With
  ## `command`, it executes the matching string from the config's `commands`
  ## object through the system shell and returns the captured output.
  clearActiveConfig()
  try:
    result = exec(readFile(path), path, false, enableHotCodeDetection,
      autoloadConfig = true)
    if command.len == 0:
      return result
    let cfg = takeActiveConfig()
    if cfg == nil:
      raise newException(DfkupError, path & ": no config declaration found")
    let commandText =
      try:
        findConfigCommand(cfg, command)
      except ValueError as e:
        raise newException(DfkupError, path & ": " & e.msg)
    let shellResult = osproc.execCmdEx(commandText,
      options = {poEvalCommand, poUsePath, poStdErrToStdOut})
    if shellResult.exitCode != 0:
      raise newException(DfkupError, path & ": command '" & command &
        "' failed with exit code " & $shellResult.exitCode & "\n" &
        shellResult.output)
    result = shellResult.output
  finally:
    clearActiveConfig()

when isMainModule:
  #
  # The CLI application
  #
  import pkg/kapsis
  import pkg/kapsis/runtime
  import pkg/kapsis/interactive/prompts

  proc runCommand*(v: Values) =
    ## Execute dfkup from a file
    let filePath = $(v.get("script").getPath)
    try:
      let result = runFile(filePath, not v.has("--nojit"))
      if result.len > 0:
        echo result
    except DfkupError as e:
      display(span("error", fgRed), span(e.msg))
    except IOError as e:
      display(span("error", fgRed), span(e.msg))

  proc execCommand*(v: Values) =
    ## Execute inline dfkup script 
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

  # proc replCommand*(v: Values) =
  #   ## Command for entering in a REPL Session
  #   runRepl()

  proc astCommand*(v: Values) =
    ## Command for parsing and generating the AST
    ## representation of a dfkup source
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

  proc confCommand*(v: Values) =
    ## Run a config file, optionally executing one configured command.
    let filePath = getCurrentDir() / "config.kup"
    if not filePath.fileExists():
      displayError("No config.kup file at the current path", quitProcess = true)
    let command =
      if v.has("command"): v.get("command").getStr
      else: ""
    try:
      let result = runConfigFile(filePath, command)
      if result.len > 0:
        echo result
    except DfkupError as e:
      displayError(e.msg)
    except IOError as e:
      displayError(e.msg)

  initKapsis do:
    defaultCommand: "run"
    commands:
      -- "Scripting"
      run path(script), ?bool("--nojit"):
        ## run a .dfkup/.kup script
      exec ?string(code):
        ## execute dfkup code inline
      conf ?string(command):
        ## run a config.kup, optionally executing one configured command
      -- "Codegen & Debugging"
      ast path("script"), ?bool("--dumptree"):
        ## generate AST from a DFkup script file