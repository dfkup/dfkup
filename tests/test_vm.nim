import std/[unittest, options]
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem]

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
  script.stdpos = script.procs.high
  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = true
  gen.genScript(program, none(string))
  var vmInstance = newVm()
  let resultVal = vmInstance.interpret(script, mainChunk)
  if resultVal != nil and resultVal.typeId notin {tyNil}:
    result = $resultVal

suite "VM - literals":
  test "integer expression":
    check run("42") == "42"
  test "string expression":
    check run("\"hello\"") == "hello"
  test "boolean expression":
    check run("true") == "true"
  test "nil expression":
    check run("nil") == ""

suite "VM - echo":
  test "echo string":
    check run("echo \"hello\"") == ""
  test "echo int":
    check run("echo 42") == ""

suite "VM - variables":
  test "var declaration":
    check run("var x = 10") == ""
  test "let declaration":
    check run("let x = 10") == ""

suite "VM - arithmetic":
  test "addition":
    check run("1 + 2") == "3"
  test "subtraction":
    check run("5 - 3") == "2"
  test "multiplication":
    check run("3 * 4") == "12"
  test "division":
    check run("6 / 3") == "2.0"

suite "VM - comparison":
  test "equality":
    check run("1 == 1") == "true"
    check run("1 == 2") == "false"
  test "less than":
    check run("1 < 2") == "true"
    check run("2 < 1") == "false"

suite "VM - logical":
  test "and":
    check run("true and true") == "true"
    check run("true and false") == "false"
  test "or":
    check run("true or false") == "true"
    check run("false or false") == "false"

suite "VM - string concat":
  test "concat":
    check run("\"hello \" & \"world\"") == "hello world"

suite "VM - blocks":
  test "block expressions":
    check run("if true: 42") == "42"
  test "if-else":
    check run("if false: 1 else: 2") == "2"
  test "while loop body type":
    check run("var x = 0\nwhile x < 3:\n  x = x + 1") == ""
