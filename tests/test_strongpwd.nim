import std/[unittest, options, strutils]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem]
import pkg/stdkups/[libjson, libstrongpwd]

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
  let pwdModule = newModule("strongpwd", some"strongpwd.dfkup")
  pwdModule.importModule(systemModule, "system")
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
    # blackpaper >= 0.2.0 fuzzy-matches the password against the custom
    # words: "miller99!" contains "miller", so it is Weak/SimilarToCommon
    # (upstream contract: leet+suffix variants of a listed word never
    # reach Strong). The Medium/NotEnoughVariety verdict below was the
    # pre-0.2.0 scoring, which ignored the similarity.
    check run("checkPasswordWithWords(\"miller99!\", parseJson(\"[\\\"miller\\\"]\"))") == "{\"strength\":\"Weak\",\"score\":0.0,\"reason\":\"SimilarToCommon\"}"
  test "prepared dictionary":
    check run("let d = newPwdDict(parseJson(\"[\\\"miller\\\"]\"))\ncheckPasswordWithDict(\"miller99!\", d)") == "{\"strength\":\"Weak\",\"score\":0.0,\"reason\":\"SimilarToCommon\"}"
    check run("let d = newPwdDict(parseJson(\"[]\"))\ncheckPasswordWithDict(\"Xk9#mQ2$vL7@nR4!\", d)") == "{\"strength\":\"Strong\",\"score\":6.0,\"reason\":\"GoodComplexity\"}"
