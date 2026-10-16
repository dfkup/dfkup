import std/[unittest, options]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem]
when defined(vancodeJitNim):
  import pkg/vancode/interpreter/jit/jit

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
  script.stdpos = script.procs.high
  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = true
  gen.genScript(program, none(string))
  var vmInstance = newVm()
  let resultVal = vmInstance.interpret(script, mainChunk)
  if resultVal != nil and resultVal.typeId notin {tyNil}:
    result = $resultVal

when defined(vancodeJitNim):
  proc runJit(code: string, procName = ""): tuple[output: string, jit: bool] =
    ## Same pipeline as run(), but with production JIT wiring
    ## (installJit + hot-code detection) so method compilation engages.
    ## Returns the script output plus whether procName got natively
    ## compiled (its self tail calls run as a loop back-edge then).
    var program: Ast
    parseScript(program, code)
    var
      mainChunk = newChunk("test")
      script = newScript(mainChunk)
      module = newModule("test", some"test.dfkup")
    let systemModule = newModule("system", some"system.dfkup")
    initSystem(script, systemModule)
    module.importModule(systemModule, "system")
    script.stdpos = script.procs.high
    var gen = initCodeGen(script, module, mainChunk)
    gen.allowExprResult = true
    gen.genScript(program, none(string))
    var vmInstance = newVirtualMachine(
      VMPreferences(enableHotCodeDetection: true))
    installJit(vmInstance)
    let resultVal = vmInstance.interpret(script, mainChunk)
    var output = ""
    if resultVal != nil and resultVal.typeId notin {tyNil}:
      output = $resultVal
    var engaged = false
    for p in script.procs:
      if p.name == procName and p.jitForeign != nil: engaged = true
    result = (output, engaged)

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
    check run("6 / 3") == "2"

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

when defined(vancodeJitNim):
  const tailRecSum = "fn tail_rec_sum(n, acc: int): int =\n" &
    "  if n == 0:\n" &
    "    return acc\n" &
    "  else:\n" &
    "    return tail_rec_sum(n - 1, acc + n)\n"

  suite "VM - tail recursion (JIT)":
    test "deep self tail call compiles to a native loop":
      let (output, jit) = runJit(tailRecSum & "\ntail_rec_sum(100000, 0)",
        "tail_rec_sum")
      check output == "5000050000"
      check jit
    test "million-deep tail recursion matches interpreted result":
      let (output, _) = runJit(tailRecSum & "\ntail_rec_sum(1000000, 0)",
        "tail_rec_sum")
      check output == "500000500000"
    test "non-tail self recursion still works (native self-call)":
      let (output, _) = runJit("fn fib(n: int): int =\n" &
        "  if n < 2:\n" &
        "    return n\n" &
        "  else:\n" &
        "    return fib(n - 1) + fib(n - 2)\n" &
        "\nfib(20)", "fib")
      check output == "6765"
