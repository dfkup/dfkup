import std/[unittest, options, strutils]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem, lowlibs/libjson, lowlibs/libstrongpwd]

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
  let pwdModule = newModule("strongpwd", some"strongpwd.dfkup")
  initStrongpwd(script, pwdModule)
  module.load(pwdModule)
  script.stdpos = script.procs.high
  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = true
  gen.genScript(program, none(string))
  var vmInstance = newVm()
  let resultVal = vmInstance.interpret(script, mainChunk)
  if resultVal != nil and resultVal.typeId notin {tyNil}:
    result = $resultVal

suite "Strongpwd":
  test "weak passwords":
    check run("pwdStrength(\"password\")") == "Weak"
    check run("pwdStrength(\"abc\")") == "Weak"
    check run("checkPassword(\"password\")") == "{\"strength\":\"Weak\",\"score\":1.125,\"reason\":\"TooPredictable\"}"
  test "strong passphrase":
    check run("pwdStrength(\"Xk9#mQ2$vL7@nR4!\")") == "Strong"
  test "score ordering":
    let weak = run("pwdScore(\"password\")").parseFloat()
    let strong = run("pwdScore(\"Xk9#mQ2$vL7@nR4!\")").parseFloat()
    check strong > weak
  test "custom word list":
    check run("checkPasswordWithWords(\"miller99!\", parseJson(\"[\\\"miller\\\"]\"))") == "{\"strength\":\"Medium\",\"score\":2.952777862548828,\"reason\":\"NotEnoughVariety\"}"
  test "prepared dictionary":
    check run("let d = newPwdDict(parseJson(\"[\\\"miller\\\"]\"))\ncheckPasswordWithDict(\"miller99!\", d)") == "{\"strength\":\"Medium\",\"score\":2.952777862548828,\"reason\":\"NotEnoughVariety\"}"
    check run("let d = newPwdDict(parseJson(\"[]\"))\ncheckPasswordWithDict(\"Xk9#mQ2$vL7@nR4!\", d)") == "{\"strength\":\"Strong\",\"score\":6.0,\"reason\":\"GoodComplexity\"}"
