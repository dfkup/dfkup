import std/[unittest, options]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem, lowlibs/libjson, lowlibs/libyaml]

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
  let yamlModule = newModule("yaml", some"yaml.dfkup")
  initYaml(script, yamlModule)
  module.load(yamlModule)
  script.stdpos = script.procs.high
  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = true
  gen.genScript(program, none(string))
  var vmInstance = newVm()
  let resultVal = vmInstance.interpret(script, mainChunk)
  if resultVal != nil and resultVal.typeId notin {tyNil}:
    result = $resultVal

suite "YAML":
  test "scalar getters":
    check run("let d = parseYaml(\"name: Ada\")\ngetStr(d, \"name\")") == "Ada"
    check run("let d = parseYaml(\"age: 36\")\ngetInt(d, \"age\")") == "36"
    check run("let d = parseYaml(\"admin: true\")\ngetBool(d, \"admin\")") == "true"
  test "nested dotted keys":
    check run("let d = parseYaml(\"nested:\\n  x: 1\")\ngetInt(d, \"nested.x\")") == "1"
    check run("let d = parseYaml(\"nested:\\n  x: 1\")\nlet s = get(d, \"nested\")\ngetInt(s, \"x\")") == "1"
  test "arrays":
    check run("let d = parseYaml(\"tags:\\n  - a\\n  - b\")\ngetArray(d, \"tags\")") == "[\"a\",\"b\"]"
    check run("let d = parseYaml(\"a: 1\")\ngetArray(d, \"missing\")") == "[]"
  test "hasKey and missing keys":
    check run("let d = parseYaml(\"a: 1\")\nhasKey(d, \"a\")") == "true"
    check run("let d = parseYaml(\"a: 1\")\nhasKey(d, \"b\")") == "false"
    check run("let d = parseYaml(\"a: 1\")\ngetStr(d, \"b\")") == ""
    check run("let d = parseYaml(\"a: 1\")\ngetInt(d, \"b\")") == "0"
  test "len":
    check run("let d = parseYaml(\"a: 1\\nb: 2\")\nlen(d)") == "2"
    check run("let d = parseYaml(\"tags:\\n  - a\\n  - b\")\nlet t = get(d, \"tags\")\nlen(t)") == "2"
  test "toYaml from json":
    check run("toYaml(parseJson(\"{\\\"a\\\": 1}\"))") == "a: 1"
  test "parse file":
    check run("let d = parseYamlFile(\"tests/fixtures/sample.yaml\")\ngetStr(d, \"name\")") == "Ada"
    check run("let d = parseYamlFile(\"tests/fixtures/sample.yaml\")\ngetInt(d, \"age\")") == "36"
