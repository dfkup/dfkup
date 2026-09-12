import std/[unittest, options, strutils]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem, lowlibs/libxml]

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
  let xmlModule = newModule("xml", some"xml.dfkup")
  initXml(script, xmlModule)
  module.load(xmlModule)
  script.stdpos = script.procs.high
  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = true
  gen.genScript(program, none(string))
  var vmInstance = newVm()
  let resultVal = vmInstance.interpret(script, mainChunk)
  if resultVal != nil and resultVal.typeId notin {tyNil}:
    result = $resultVal

const doc = "<root lang=\\\"en\\\"><item id=\\\"1\\\">hello</item><item id=\\\"2\\\">world</item></root>"

suite "XML":
  test "tag and attributes":
    check run("let d = parseXml(\"" & doc & "\")\ntagName(d)") == "root"
    check run("let d = parseXml(\"" & doc & "\")\ngetAttr(d, \"lang\", \"?\")") == "en"
    check run("let d = parseXml(\"" & doc & "\")\ngetAttr(d, \"missing\", \"fb\")") == "fb"
  test "children navigation":
    check run("let d = parseXml(\"" & doc & "\")\nchildCount(d)") == "2"
    check run("let d = parseXml(\"" & doc & "\")\nlet f = child(d, 0)\ntagName(f)") == "item"
    check run("let d = parseXml(\"" & doc & "\")\nlet f = child(d, 1)\ngetAttr(f, \"id\", \"?\")") == "2"
    check run("let d = parseXml(\"" & doc & "\")\nlet f = findChild(d, \"item\")\ngetText(f)") == "hello"
  test "text content":
    check run("let d = parseXml(\"" & doc & "\")\ngetText(d)") == "helloworld"
  test "serialize":
    let r = run("let d = parseXml(\"" & doc & "\")\ngetXml(d)")
    check r.contains("<root")
    check r.contains("<item")
    check r.contains("hello")
  test "parse file":
    check run("let d = parseXmlFile(\"tests/fixtures/sample.xml\")\ntagName(d)") == "root"
    check run("let d = parseXmlFile(\"tests/fixtures/sample.xml\")\ngetText(d)") == "helloworld"
