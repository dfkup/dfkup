import std/[unittest, options, os, strutils]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem, lowlibs/libfswatch]

proc run(code: string): string =
  var program: Ast
  parseScript(program, code)
  var
    mainChunk = newChunk("test")
    script = newScript(mainChunk)
    module = newModule("test", some"test.dfkup")
  let systemModule = newModule("system", some"system.dfkup")
  initSystem(script, systemModule)
  module.load(systemModule)
  let fsModule = newModule("fswatch", some"fswatch.dfkup")
  initFswatch(script, fsModule)
  module.load(fsModule)
  script.stdpos = script.procs.high
  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = true
  gen.genScript(program, none(string))
  var vmInstance = newVm()
  let resultVal = vmInstance.interpret(script, mainChunk)
  if resultVal != nil and resultVal.typeId notin {tyNil}:
    result = $resultVal

suite "FsWatch":
  test "watch invalid path fails":
    check run("watch(\"/tmp/dfkup-test-missing-xyz-123.txt\")") == "-1"
  test "watch path and unwatch":
    let path = getTempDir() / "dfkup-fswatch-test.txt"
    writeFile(path, "v1")
    let id = run("watch(\"" & path & "\")").parseInt()
    check id >= 1
    check run("watchPath(" & $id & ")") == path
    check run("unwatch(" & $id & ")") == "true"
    check run("unwatch(999999)") == "false"
  test "modify event delivered":
    let path = getTempDir() / "dfkup-fswatch-ev.txt"
    writeFile(path, "v1")
    let code = "let id = watch(\"" & path & "\")\nwriteFile(\"" & path & "\", \"v2\")\nlet evs = pollWatchers(500)\nlet ok = unwatch(id)\nevs"
    let evs = run(code)
    check evs.contains("\"modified\"")
    check evs.contains(path)
  test "quiet poll returns empty":
    let path = getTempDir() / "dfkup-fswatch-quiet.txt"
    writeFile(path, "v1")
    let code = "let id = watch(\"" & path & "\")\nlet evs = pollWatchers(50)\nlet ok = unwatch(id)\nevs"
    check run(code) == "[]"
