import std/[unittest, options]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem, lowlibs/libdotenv]

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
  let dotenvModule = newModule("dotenv", some"dotenv.dfkup")
  initDotenv(script, dotenvModule)
  module.load(dotenvModule)
  script.stdpos = script.procs.high
  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = true
  gen.genScript(program, none(string))
  var vmInstance = newVm()
  let resultVal = vmInstance.interpret(script, mainChunk)
  if resultVal != nil and resultVal.typeId notin {tyNil}:
    result = $resultVal

suite "Dotenv":
  test "parseEnv to object":
    check run("parseEnv(\"HOST=localhost\\nPORT=8080\")") == "{\"HOST\":\"localhost\",\"PORT\":\"8080\"}"
  test "parseEnv skips comments and export":
    check run("parseEnv(\"# c\\nexport DEBUG=true\\nEMPTY=\")") == "{\"DEBUG\":\"true\",\"EMPTY\":\"\"}"
  test "live env round trip":
    check run("envSet(\"DFKUP_TEST_DOTENV\", \"42\")\nenvGet(\"DFKUP_TEST_DOTENV\", \"\")") == "42"
    check run("envSet(\"DFKUP_TEST_DOTENV\", \"42\")\nenvHas(\"DFKUP_TEST_DOTENV\")") == "true"
    check run("envSet(\"DFKUP_TEST_DOTENV\", \"42\")\nenvDel(\"DFKUP_TEST_DOTENV\")\nenvHas(\"DFKUP_TEST_DOTENV\")") == "false"
    check run("envGet(\"DFKUP_TEST_MISSING_XYZ\", \"fallback\")") == "fallback"
