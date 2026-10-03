import std/[unittest, options, os, strutils]
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
  module.importModule(systemModule, "system")
  let jsonModule = newModule("json", some"json.dfkup")
  jsonModule.importModule(systemModule, "system")
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
    check r == joinPath("a", "b")
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

suite "Libraries - getSystemInfo":
  test "osName field":
    check run("let i = getSystemInfo()\ni.osName") == hostOS
  test "arch field":
    check run("let i = getSystemInfo()\ni.arch") == hostCPU
  test "cpuCores is positive":
    check parseInt(run("let i = getSystemInfo()\ni.cpuCores")) > 0
  test "cpuEndian field":
    check run("let i = getSystemInfo()\ni.cpuEndian") == $cpuEndian
  test "totalMemory is positive":
    check parseInt(run("let i = getSystemInfo()\ni.totalMemory")) > 0
  test "executablePath is non-empty":
    check run("let i = getSystemInfo()\ni.executablePath").len > 3
  test "two calls agree":
    check run("let i = getSystemInfo()\ni.cpuCores") ==
      run("let j = getSystemInfo()\nj.cpuCores")
  test "the whole object dumps as an object":
    check run("getSystemInfo()").startsWith("{")

suite "Libraries - execShell":
  test "true on success":
    check run("execShell(\"exit 0\")") == "true"
  test "false on failure":
    check run("execShell(\"exit 3\")") == "false"
  test "out returns output and exit code":
    check run("execShellOut(\"echo hi\")") ==
      "{\"output\":\"hi\\n\",\"exitCode\":0}"
  test "out reports a non-zero exit code":
    check run("execShellOut(\"exit 7\")") == "{\"output\":\"\",\"exitCode\":7}"
  test "shell metacharacters are interpreted":
    check run("execShell(\"exit $((2 + 3))\")") == "false"
