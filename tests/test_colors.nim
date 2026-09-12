import std/[unittest, options]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem, lowlibs/libcolors]

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
  let colorsModule = newModule("colors", some"colors.dfkup")
  initColors(script, colorsModule)
  module.load(colorsModule)
  script.stdpos = script.procs.high
  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = true
  gen.genScript(program, none(string))
  var vmInstance = newVm()
  let resultVal = vmInstance.interpret(script, mainChunk)
  if resultVal != nil and resultVal.typeId notin {tyNil}:
    result = $resultVal

suite "Colors":
  test "named color to hex":
    check run("toHex(parseColor(\"rebeccapurple\"))") == "#663399"
  test "hex to name":
    check run("toName(parseColor(\"#ff0000\"))") == "red"
  test "format strings":
    check run("toRgb(parseColor(\"rebeccapurple\"))") == "rgb(102, 51, 153)"
    check run("toHsl(parseColor(\"rebeccapurple\"))") == "hsl(270, 50%, 40%)"
  test "channels":
    check run("red(parseColor(\"rebeccapurple\"))") == "102"
    check run("green(parseColor(\"rebeccapurple\"))") == "51"
    check run("blue(parseColor(\"rebeccapurple\"))") == "153"
    check run("alpha(parseColor(\"rebeccapurple\"))") == "1.0"
  test "validity":
    check run("isValidColor(\"hsl(120, 100%, 50%)\")") == "true"
    check run("isValidColor(\"nope-not-a-color\")") == "false"
