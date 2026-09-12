import std/[unittest, options, strutils]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem, lowlibs/libsvg]

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
  let svgModule = newModule("svg", some"svg.dfkup")
  initSvg(script, svgModule)
  module.load(svgModule)
  script.stdpos = script.procs.high
  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = true
  gen.genScript(program, none(string))
  var vmInstance = newVm()
  let resultVal = vmInstance.interpret(script, mainChunk)
  if resultVal != nil and resultVal.typeId notin {tyNil}:
    result = $resultVal

const svgDoc = "<svg xmlns=\\\"http://www.w3.org/2000/svg\\\" width=\\\"10\\\" height=\\\"10\\\"><rect x=\\\"1\\\" y=\\\"1\\\" width=\\\"8\\\" height=\\\"8\\\"/><circle cx=\\\"5\\\" cy=\\\"5\\\" r=\\\"2\\\"/></svg>"

suite "SVG":
  test "root tag and counts":
    check run("let d = parseSvg(\"" & svgDoc & "\")\nrootTag(d)") == "svg"
    check run("let d = parseSvg(\"" & svgDoc & "\")\nnodeCount(d)") == "3"
    check run("let d = parseSvg(\"" & svgDoc & "\")\ncountTag(d, \"rect\")") == "1"
    check run("let d = parseSvg(\"" & svgDoc & "\")\ncountTag(d, \"circle\")") == "1"
    check run("let d = parseSvg(\"" & svgDoc & "\")\ncountTag(d, \"path\")") == "0"
  test "serialize":
    let r = run("let d = parseSvg(\"" & svgDoc & "\")\ntoSvg(d)")
    check r.contains("<svg")
    check r.contains("<rect")
