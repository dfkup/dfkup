import std/[unittest, options]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem, lowlibs/libuuid]

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
  let uuidModule = newModule("uuid", some"uuid.dfkup")
  initUuid(script, uuidModule)
  module.load(uuidModule)
  script.stdpos = script.procs.high
  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = true
  gen.genScript(program, none(string))
  var vmInstance = newVm()
  let resultVal = vmInstance.interpret(script, mainChunk)
  if resultVal != nil and resultVal.typeId notin {tyNil}:
    result = $resultVal

suite "UUID":
  test "v4 generates valid version 4":
    check run("isValidUuid(uuidV4())") == "true"
    check run("uuidVersion(uuidV4())") == "4"
  test "v7 generates valid version 7":
    check run("isValidUuid(uuidV7())") == "true"
    check run("uuidVersion(uuidV7())") == "7"
  test "invalid strings rejected":
    check run("isValidUuid(\"not-a-uuid\")") == "false"
  test "nil uuid detected":
    check run("isNilUuid(\"00000000-0000-0000-0000-000000000000\")") == "true"
    check run("isNilUuid(uuidV4())") == "false"
  test "parse normalizes":
    check run("isValidUuid(parseUuid(\"550E8400-E29B-41D4-A716-446655440000\"))") == "true"
