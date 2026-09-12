import std/[unittest, options]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem, lowlibs/libjson, lowlibs/libbson]

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
  let bsonModule = newModule("bson", some"bson.dfkup")
  initBson(script, bsonModule)
  module.load(bsonModule)
  script.stdpos = script.procs.high
  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = true
  gen.genScript(program, none(string))
  var vmInstance = newVm()
  let resultVal = vmInstance.interpret(script, mainChunk)
  if resultVal != nil and resultVal.typeId notin {tyNil}:
    result = $resultVal

suite "BSON":
  test "encode decode round trip":
    check run("let d = parseJson(\"{\\\"a\\\":1,\\\"b\\\":\\\"x\\\",\\\"c\\\":true}\")\ndecodeBson(encodeBson(d))") == "{\"a\":1,\"b\":\"x\",\"c\":true}"
  test "nested round trip":
    check run("let d = parseJson(\"{\\\"n\\\":{\\\"x\\\":[1,2]}}\")\ndecodeBson(encodeBson(d))") == "{\"n\":{\"x\":[1,2]}}"
