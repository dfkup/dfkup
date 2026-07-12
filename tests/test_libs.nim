import std/[unittest, options]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem, lowlibs/libjson]

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
  let jsonModule = newModule("json", some"json.dfkup")
  initJson(script, jsonModule)
  module.load(jsonModule)
  script.stdpos = script.procs.high
  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = true
  gen.genScript(program, none(string))
  var vmInstance = newVm()
  let resultVal = vmInstance.interpret(script, mainChunk)
  if resultVal != nil and resultVal.typeId notin {tyNil}:
    result = $resultVal

suite "Libraries - JSON":
  test "parse and dump":
    let r = run("let d = parseJson(\"{\\\"a\\\":1}\")\ndumpJson(d)")
    check r == "{\"a\":1}"
  test "get string field":
    let r = run("let d = parseJson(\"{\\\"n\\\":\\\"x\\\"}\")\nget(d, \"n\", \"\")")
    check r == "\"x\""
  test "get with default":
    let r = run("let d = parseJson(\"{}\")\nget(d, \"k\", \"fallback\")")
    check r == "\"fallback\""
  test "keys":
    let r = run("let d = parseJson(\"{\\\"a\\\":1,\\\"b\\\":2}\")\njoin(keys(d), \",\")")
    check r == "a,b"

suite "Libraries - OS":
  test "fileExists":
    check run("fileExists(\"tests/test_libs.nim\")") == "true"
    check run("fileExists(\"nonexistent\")") == "false"
  test "dirExists":
    check run("dirExists(\"tests\")") == "true"
  test "path operations":
    let r = run("joinPath(\"a\", \"b\")")
    check r == "a/b"
  test "getCurrentDir":
    let r = run("getCurrentDir()")
    check r.len > 0
  test "sleep":
    check run("sleep(1)") == ""
  test "getAppFilename":
    let r = run("getAppFilename()")
    check r.len > 0
  test "getFileSize":
    let r = run("getFileSize(\"tests/test_libs.nim\")")
    check r != "0"
