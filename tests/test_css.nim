import std/[unittest, options]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem, lowlibs/libcss]

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
  let cssModule = newModule("css", some"css.dfkup")
  initCss(script, cssModule)
  module.load(cssModule)
  script.stdpos = script.procs.high
  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = true
  gen.genScript(program, none(string))
  var vmInstance = newVm()
  let resultVal = vmInstance.interpret(script, mainChunk)
  if resultVal != nil and resultVal.typeId notin {tyNil}:
    result = $resultVal

suite "CSS":
  test "rule count and selectors":
    check run("let s = parseCss(\"h1, h2 { color: red; } .x { margin: 0; }\")\nruleCount(s)") == "2"
    check run("let s = parseCss(\"h1, h2 { color: red; } .x { margin: 0; }\")\nselectors(s)") == "[\"h1, h2\",\".x\"]"
  test "validate clean sheet":
    check run("let s = parseCss(\"p { color: blue; margin: 10px; }\")\ncssValidate(s)") == "{\"total\":2,\"invalid\":0,\"valid\":true,\"errors\":[]}"
  test "validate flags bad values":
    check run("let s = parseCss(\"p { margin: red; display: bogus; color: blue; }\")\ncssValidate(s)") == "{\"total\":3,\"invalid\":2,\"valid\":false,\"errors\":[{\"selector\":\"p\",\"property\":\"margin\",\"value\":\"red\",\"message\":\"Value does not match property syntax\"},{\"selector\":\"p\",\"property\":\"display\",\"value\":\"bogus\",\"message\":\"Value does not match property syntax\"}]}"
  test "dump sheet":
    let r = run("let s = parseCss(\"h1 { color: red; }\")\ngetCss(s)")
    check r.len > 10
  test "parse file":
    check run("let s = parseCssFile(\"tests/fixtures/sample.css\")\nruleCount(s)") == "1"
