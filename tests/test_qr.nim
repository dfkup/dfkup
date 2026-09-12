import std/[unittest, options, strutils]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem, lowlibs/libqr]

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
  let qrModule = newModule("qr", some"qr.dfkup")
  initQr(script, qrModule)
  module.load(qrModule)
  script.stdpos = script.procs.high
  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = true
  gen.genScript(program, none(string))
  var vmInstance = newVm()
  let resultVal = vmInstance.interpret(script, mainChunk)
  if resultVal != nil and resultVal.typeId notin {tyNil}:
    result = $resultVal

suite "QR":
  test "svg output":
    let r = run("qrSvg(\"hello\", 4, 2)")
    check r.contains("<svg")
    check r.contains("<path")
  test "terminal output":
    let r = run("qrTerminal(\"hi\", 1)")
    check r.len > 10
