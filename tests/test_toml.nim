import std/[unittest, options]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem, lowlibs/libtoml]

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
  let tomlModule = newModule("toml", some"toml.dfkup")
  initToml(script, tomlModule)
  module.load(tomlModule)
  script.stdpos = script.procs.high
  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = true
  gen.genScript(program, none(string))
  var vmInstance = newVm()
  let resultVal = vmInstance.interpret(script, mainChunk)
  if resultVal != nil and resultVal.typeId notin {tyNil}:
    result = $resultVal

suite "TOML":
  test "scalar getters":
    check run("let d = parseToml(\"title = \\\"hi\\\"\")\ngetStr(d, \"title\")") == "hi"
    check run("let d = parseToml(\"age = 30\")\ngetInt(d, \"age\")") == "30"
    check run("let d = parseToml(\"admin = true\")\ngetBool(d, \"admin\")") == "true"
    check run("let d = parseToml(\"pi = 3.14\")\ngetFloat(d, \"pi\")") == "3.14"
  test "nested dotted keys":
    check run("let d = parseToml(\"[owner]\\nname = \\\"Tom\\\"\")\ngetStr(d, \"owner.name\")") == "Tom"
  test "arrays":
    check run("let d = parseToml(\"[owner]\\nports = [8000, 8001]\")\ngetArray(d, \"owner.ports\")") == "[8000,8001]"
    check run("let d = parseToml(\"a = 1\")\ngetArray(d, \"missing\")") == "[]"
  test "hasKey and missing keys":
    check run("let d = parseToml(\"a = 1\")\nhasKey(d, \"a\")") == "true"
    check run("let d = parseToml(\"a = 1\")\nhasKey(d, \"b\")") == "false"
    check run("let d = parseToml(\"a = 1\")\ngetStr(d, \"b\")") == ""
    check run("let d = parseToml(\"a = 1\")\ngetInt(d, \"b\")") == "0"
  test "toJson bridge":
    check run("let d = parseToml(\"title = \\\"hi\\\"\\nage = 30\")\ntoJson(d)") == "{\"title\":\"hi\",\"age\":30}"
  test "getToml round trip":
    check run("let d = parseToml(\"title = \\\"hi\\\"\")\ngetToml(d)") == "title = \"hi\"\n"
  test "parse file":
    check run("let d = parseTomlFile(\"tests/fixtures/sample.toml\")\ngetStr(d, \"title\")") == "hi"
    check run("let d = parseTomlFile(\"tests/fixtures/sample.toml\")\ngetInt(d, \"age\")") == "30"
