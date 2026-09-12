import std/[unittest, options, strutils]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem, lowlibs/libtwofa]

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
  let twofaModule = newModule("twofa", some"twofa.dfkup")
  initTwofa(script, twofaModule)
  module.load(twofaModule)
  script.stdpos = script.procs.high
  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = true
  gen.genScript(program, none(string))
  var vmInstance = newVm()
  let resultVal = vmInstance.interpret(script, mainChunk)
  if resultVal != nil and resultVal.typeId notin {tyNil}:
    result = $resultVal

suite "TwoFA":
  test "totp at fixed timestamp":
    check run("let t = newTotp(\"JBSWY3DPEHPK3PXP\")\ntotpAt(t, 1234567890)") == "742275"
  test "totp verify round trip":
    check run("let t = newTotp(\"JBSWY3DPEHPK3PXP\")\ntotpVerify(t, totpAt(t, 1234567890), 1234567890)") == "true"
    check run("let t = newTotp(\"JBSWY3DPEHPK3PXP\")\ntotpVerify(t, \"000000\", 1234567890)") == "false"
  test "totp uri and qr":
    check run("let t = newTotp(\"JBSWY3DPEHPK3PXP\", \"MyApp\", \"alice\")\ntotpUri(t)").startsWith("otpauth://totp/")
    let svg = run("let t = newTotp(\"JBSWY3DPEHPK3PXP\")\ntotpQrSvg(t)")
    check svg.contains("<svg")
  test "hotp vectors":
    check run("var h = newHotp(\"JBSWY3DPEHPK3PXP\")\nhotpAt(h, 0)") == "282760"
    check run("var h = newHotp(\"JBSWY3DPEHPK3PXP\")\nhotpNext(h)") == "282760"
    check run("var h = newHotp(\"JBSWY3DPEHPK3PXP\")\nhotpVerify(h, \"282760\", 0)") == "true"
    check run("var h = newHotp(\"JBSWY3DPEHPK3PXP\")\nhotpVerify(h, \"000000\", 0)") == "false"
    check run("var h = newHotp(\"JBSWY3DPEHPK3PXP\")\nhotpUri(h)").startsWith("otpauth://hotp/")
  test "secret generation":
    check run("len(genSecret())") == "32"
    check run("let s = genSecret()\nlet t = newTotp(s)\nlen(totpNow(t))") == "6"
  test "uri helpers":
    check run("genTotpUri(\"JBSWY3DPEHPK3PXP\", \"alice\", \"MyApp\")").startsWith("otpauth://totp/")
    check run("genHotpUri(\"JBSWY3DPEHPK3PXP\", \"alice\", \"MyApp\")").startsWith("otpauth://hotp/")
