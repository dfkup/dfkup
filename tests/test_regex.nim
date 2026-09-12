import std/[unittest, options]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem, lowlibs/libregex]

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
  let regexModule = newModule("regex", some"regex.dfkup")
  initRegex(script, regexModule)
  module.load(regexModule)
  script.stdpos = script.procs.high
  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = true
  gen.genScript(program, none(string))
  var vmInstance = newVm()
  let resultVal = vmInstance.interpret(script, mainChunk)
  if resultVal != nil and resultVal.typeId notin {tyNil}:
    result = $resultVal

suite "Regex":
  test "find with groups":
    check run("let m = find(\"hello42world\", \"([a-z]+)(\\\\d+)\")\nm[\"groups\"]") == "[\"hello\",\"42\"]"
    check run("let m = find(\"hello42world\", \"([a-z]+)(\\\\d+)\")\nm[\"matched\"]") == "true"
    check run("let m = find(\"hello42world\", \"([a-z]+)(\\\\d+)\")\nm[\"start\"]") == "0"
  test "match requires full match":
    check run("let m = match(\"42\", \"\\\\d+\")\nm[\"matched\"]") == "true"
    check run("let m = match(\"42hello\", \"\\\\d+\")\nm[\"matched\"]") == "false"
    check run("let m = match(\"hello\", \"\\\\d+\")\nm[\"matched\"]") == "false"
  test "findAll":
    check run("len(findAll(\"a1b22\", \"\\\\d+\"))") == "2"
    check run("len(findAll(\"abc\", \"\\\\d+\"))") == "0"
