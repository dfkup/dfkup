# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/[options, os, osproc, strformat, tables]

import ./lang/transformers
export transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value,
  resolver, manager]
import pkg/vancode/interpreter/jit/jit

import ./lang/[parser]
import ./lang/stdlib_loader
import ./pkg/pkgman
import ./lang/lowlibs/libsystem
## NB: only `libsystem` is statically linked. Every other stdlib
## (`json`, `yaml`, `strings`, `sequtils`, `http`, `cli`, `config`,
## `regex`, `browser`, `toml`, `uuid`, `dotenv`, `csv`, `bson`,
## `colors`, `qr`, `nanoid`, `llm`, `httpclient`, `xml`, `feed`,
## `ical`, `css`, `svg`, `markdown`, `strongpwd`, `twofa`, `fswatch`,
## `algos`, `bench`) resolves at runtime through `stdlibLoader`
## (dylib shards built by stdkups `tools/build_shards.py`, invoked from
## the GitHub workflows); importing them here
## would statically link their dependency chains into every `dfkup`
## process — notably `powpow/net/tls` (`-lssl -lcrypto`), which dyld
## then loads and initializes on every startup, even for `echo 1`.

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

  # Every stdlib except `system` loads from a shard dylib via
  # `stdlibLoader` (see `src/lang/stdlib_loader.nim`). Scripts that
  # import nothing pay nothing; the table above stays empty and only
  # fills with vancode's own cache entries as dylibs load.

  if autoloadConfig:
    # `conf` mode makes `config({...})` available without an explicit
    # `import "std/config"`. Ordinary scripts still resolve `config` only
    # through that import. The dylib loads here, before compilation.
    module.importModule(loadStdlibModule("config", script, systemModule),
      "config")

  script.stdpos = script.procs.high

  # `pkg/<name>` imports resolve from the ~/.dfkup home through vancode's
  # manager hook (no vancode changes needed): develop checkouts win,
  # otherwise the latest installed version. Unresolvable specs get
  # ErrImportError from vancode.
  var manager = newModuleManager()
  let pkgCfg = newDfkupPkgConfig(ensureSource = false)
  # `ensurePkgSource` (home-dir IO) runs only when a `pkg/` import
  # actually needs resolving — plain `run` scripts never pay it.
  var pkgSourceEnsured = false
  manager.pkgResolver = some(
    proc(spec: string): Option[string] {.closure.} =
      if not pkgSourceEnsured:
        pkgCfg.ensurePkgSource()
        pkgSourceEnsured = true
      pkgCfg.resolvePkgImport(spec))
  var gen = initCompiler(script, module, mainChunk, manager = manager,
                         stdlibs = stdlibs,
                         parserCallback = parseDfkupFile,
                         stdlibLoader = loadStdlibFactory)
  gen.allowExprResult = allowExprResult
  try:
    gen.genScript(program, none(string))
  except CatchableError as e:
    raise newException(DfkupError, e.msg)
  # Retain compiler state when a stdlib dylib was loaded: tearing down
  # objects adopted across the dylib boundary faults (host dispose of a
  # dylib-owned graph member with a nil runtime-type pointer). Retaining
  # is safe for a run-once CLI (the OS reclaims everything at exit) and
  # a no-op for runs without dylib imports. See plans/stdlib-dylibs.md.
  if stdlibDynlibLoaded():
    GC_ref(gen)

  var prefs = VMPreferences(enableHotCodeDetection : enableHotCodeDetection)
  var vmInstance = newVirtualMachine(prefs)
  when defined(vancodeJitNim):
    installJit(vmInstance)
  # Hand the VM to dylibs that re-enter it (libhttp server callbacks).
  # Factories load at compile time above, before any VM exists.
  setStdlibVms(cast[pointer](vmInstance))
  
  vmInstance.prewarmScriptOps(script)
  when defined(vancodeJitNim):
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
    # `browser` is a dylib now; its cleanup hook runs via cleanupStdlibs.
    cleanupStdlibs()

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
  import std/[parseopt, strutils]

  const versionStr = "0.1.0"

  const
    ansiReset = "\e[0m"
    ansiBoldWhite = "\e[1;37m"
    ansiGrey = "\e[90m"
    ansiRed = "\e[31m"

  proc useColor(): bool =
    getEnv("NO_COLOR") == "" and getEnv("TERM") != "dumb"

  proc paint(s, code: string): string =
    if useColor():
      code & s & ansiReset
    else:
      s

  proc label(s: string): string =
    paint(s, ansiBoldWhite)

  proc grey(s: string): string =
    paint(s, ansiGrey)

  proc errPrefix(): string =
    paint("error:", ansiRed)

  proc printHelp() =
    echo grey("A tiny scripting language. Enjoyable, easy to learn and work with so you don't f*ck up")
    echo grey("  (c) OpenPeeps | LGPL-3.0-or-later License")
    echo grey("  Build Version: " & versionStr)
    echo ""
    echo "usage: dfkup <command> [args] [options]"
    echo ""
    echo label("Scripting")
    echo "  run <script>            " & grey("run a .dfkup/.kup script")
    echo "          --nojit         " & grey("disable the JIT compiler")
    echo "  exec <code>             " & grey("execute dfkup code inline")
    echo "  conf [command]          " & grey("run a config.kup, optionally executing one configured command")
    echo ""
    echo label("Packages")
    echo "  pkg install <spec>      " & grey("install a package by name, git URL (--url=... pins a source URL)")
    echo "  pkg remove <name> [ver] " & grey("uninstall a package (one version, or all)")
    echo "  pkg update [name]       " & grey("update one package, or all when omitted")
    echo "  pkg list                " & grey("list installed packages")
    echo "  pkg develop <path>      " & grey("editable install from a local directory")
    echo "  pkg prune               " & grey("remove orphaned packages")
    echo "  pkg refresh             " & grey("re-download registry data")
    echo ""
    echo label("Codegen & Debugging")
    echo "  ast <script>            " & grey("generate AST from a DFkup script file")
    echo "          --dumptree      " & grey("print the AST as a tree instead of JSON")
    echo ""
    echo "  -h, --help              " & grey("show this help")
    echo "  --version               " & grey("show version")

  proc runScriptFile(filePath: string, nojit: bool): int =
    ## Execute dfkup from a file
    try:
      let result = runFile(filePath, not nojit)
      if result.len > 0:
        echo result
    except DfkupError as e:
      echo errPrefix() & " " & e.msg
      return 1
    except IOError as e:
      echo errPrefix() & " " & e.msg
      return 1
    return 0

  proc execCode(code: string): int =
    ## Execute inline dfkup script
    try:
      let result = exec(code, "inline", allowExprResult = true, enableHotCodeDetection = false)
      if result.len > 0:
        echo result
    except DfkupError as e:
      echo errPrefix() & " " & e.msg
      return 1
    return 0

  proc printAst(filePath: string, dumpTree: bool): int =
    ## Parse and print the AST representation of a dfkup source
    if not fileExists(filePath):
      echo errPrefix() & " file not found: " & filePath
      return 1
    let code = readFile(filePath)
    var program: Ast
    try:
      parseScript(program, code)
    except DfkupParserError as e:
      echo errPrefix() & " " & &"{filePath}({e.ln},{e.col}): {e.msg}"
      return 1

    # todo, write to a file when `-o:some/path.ast` is provided
    if dumpTree:
      for node in program.nodes:
        echo node.treeRepr
    else:
      echo toJson(program.nodes)
    return 0

  proc runConf(command: string): int =
    ## Run a config file, optionally executing one configured command.
    let filePath = getCurrentDir() / "config.kup"
    if not filePath.fileExists():
      echo errPrefix() & " No config.kup file at the current path"
      return 1
    try:
      let result = runConfigFile(filePath, command)
      if result.len > 0:
        echo result
    except DfkupError as e:
      echo errPrefix() & " " & e.msg
      return 1
    except IOError as e:
      echo errPrefix() & " " & e.msg
      return 1
    return 0

  proc printPkgHelp() =
    echo "usage: dfkup pkg <install|remove|update|list|develop|prune|refresh> [args]"
    echo ""
    echo "  install <spec> [--url=...]  " & grey("install by registry name, git URL, or name + source URL")
    echo "  remove <name> [version]     " & grey("uninstall one version, or all versions")
    echo "  update [name]               " & grey("update one package, or all")
    echo "  list                        " & grey("list installed packages")
    echo "  develop <path>              " & grey("editable install from a local directory")
    echo "  prune                       " & grey("remove orphaned packages")
    echo "  refresh                     " & grey("re-download registry data")

  proc runPkg(args: seq[string], pkgUrl: string): int =
    ## Package management on the ~/.dfkup home (DFKUP_HOME overrides).
    if args.len == 0:
      printPkgHelp()
      return 1
    let cfg = newDfkupPkgConfig()
    case args[0]
    of "install":
      if args.len < 2:
        echo errPrefix() & " package name or URL is required"
        printPkgHelp()
        return 1
      if args.len > 2:
        echo errPrefix() & " only one package allowed"
        return 1
      try:
        if cfg.pkgInstall(args[1], url = pkgUrl):
          return 0
      except CatchableError as e:
        echo errPrefix() & " " & e.msg
      return 1
    of "remove", "uninstall":
      if args.len < 2:
        echo errPrefix() & " package name is required"
        printPkgHelp()
        return 1
      if args.len > 3:
        echo errPrefix() & " usage: dfkup pkg remove <name> [version]"
        return 1
      let version = if args.len > 2: args[2] else: ""
      try:
        if cfg.pkgRemove(args[1], version):
          return 0
      except CatchableError as e:
        echo errPrefix() & " " & e.msg
      return 1
    of "update":
      if args.len > 2:
        echo errPrefix() & " usage: dfkup pkg update [name]"
        return 1
      let name = if args.len > 1: args[1] else: ""
      try:
        if cfg.pkgUpdate(name):
          return 0
      except CatchableError as e:
        echo errPrefix() & " " & e.msg
      return 1
    of "list":
      try:
        cfg.pkgList()
        return 0
      except CatchableError as e:
        echo errPrefix() & " " & e.msg
      return 1
    of "develop":
      if args.len != 2:
        echo errPrefix() & " directory is required (usage: dfkup pkg develop <path>)"
        return 1
      try:
        if cfg.pkgDevelop(args[1]):
          return 0
      except CatchableError as e:
        echo errPrefix() & " " & e.msg
      return 1
    of "prune":
      try:
        cfg.pkgPrune()
        return 0
      except CatchableError as e:
        echo errPrefix() & " " & e.msg
      return 1
    of "refresh":
      try:
        if cfg.refreshAllSources():
          return 0
      except CatchableError as e:
        echo errPrefix() & " " & e.msg
      return 1
    else:
      echo errPrefix() & " unknown pkg command `" & args[0] & "`"
      printPkgHelp()
      return 1

  proc main(): int =
    var command = ""
    var positionals: seq[string] = @[]
    var nojit = false
    var dumptree = false
    var showHelp = false
    var showVersion = false
    var pkgUrl = ""
    var p = initOptParser(commandLineParams())
    for kind, key, val in p.getopt():
      case kind
      of cmdArgument:
        if command == "":
          command = key
        else:
          positionals.add(key)
      of cmdLongOption, cmdShortOption:
        case key
        of "help", "h":
          showHelp = true
        of "version":
          showVersion = true
        of "nojit":
          nojit = val notin ["false", "0"]
        of "dumptree":
          dumptree = val notin ["false", "0"]
        of "url":
          pkgUrl = val
        else:
          echo errPrefix() & " unknown option --" & key
          printHelp()
          return 1
      of cmdEnd:
        discard
    if showVersion:
      echo versionStr
      return 0
    if showHelp:
      printHelp()
      return 0
    if command == "":
      printHelp()
      return 0
    case command
    of "run":
      # run a .dfkup/.kup script file
      if positionals.len == 0:
        echo errPrefix() & " script is required"
        printHelp()
        return 1
      if positionals.len > 1:
        echo errPrefix() & " only one script allowed"
        printHelp()
        return 1
      return runScriptFile(positionals[0], nojit)
    of "exec":
      # execute dfkup code inline
      let code = positionals.join(" ")
      if code.len == 0:
        echo errPrefix() & " code is required (usage: dfkup exec <code>)"
        printHelp()
        return 1
      return execCode(code)
    of "ast":
      # generate AST from a DFkup script file
      if positionals.len == 0:
        echo errPrefix() & " script is required"
        printHelp()
        return 1
      if positionals.len > 1:
        echo errPrefix() & " only one script allowed"
        printHelp()
        return 1
      return printAst(positionals[0], dumptree)
    of "conf":
      # run a config.kup, optionally executing one configured command
      let confCommand = positionals.join(" ")
      return runConf(confCommand)
    of "pkg":
      # package management on the ~/.dfkup home
      return runPkg(positionals, pkgUrl)
    else:
      # default command: a bare script path runs like `run <script>`
      if positionals.len == 0 and fileExists(command):
        return runScriptFile(command, nojit)
      echo errPrefix() & " unknown command `" & command & "`"
      printHelp()
      return 1

  quit(main())