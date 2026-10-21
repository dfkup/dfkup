import std/[unittest, options]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem]
import pkg/stdkups/[libbench]

proc interpret(code: string): Value =
  var program: Ast
  parseScript(program, code)
  var
    mainChunk = newChunk("test")
    script = newScript(mainChunk)
    module = newModule("test", some"test.dfkup")
  let systemModule = newModule("system", some"system.dfkup")
  initSystem(script, systemModule)
  module.importModule(systemModule, "system")
  let benchModule = newModule("bench", some"bench.dfkup")
  benchModule.importModule(systemModule, "system")
  initBench(script, benchModule)
  module.load(benchModule)
  script.stdpos = script.procs.high
  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = true
  gen.genScript(program, none(string))
  var vmInstance = newVm()
  result = vmInstance.interpret(script, mainChunk)

proc run(code: string): string =
  let v = interpret(code)
  if v != nil and v.typeId notin {tyNil}:
    result = $v

suite "Bench - monotonic clock":
  test "monoNanos returns a positive integer":
    check run("let t = monoNanos()\nt > 0") == "true"
  test "the clock never runs backwards":
    check run("let a = monoNanos()\nlet b = monoNanos()\nb >= a") == "true"
  test "a busy loop advances the clock":
    check run("let t0 = monoNanos()\nvar i = 0\nwhile i < 100000:\n  i = i + 1\nlet t1 = monoNanos()\nt1 > t0") == "true"

suite "Bench - cpu clock":
  test "cpuTime returns a non-negative float":
    check run("let t = cpuTime()\nt >= 0.0") == "true"
  test "cpu time advances under load":
    check run("let t0 = cpuTime()\nvar i = 0\nwhile i < 200000:\n  i = i + 1\nlet t1 = cpuTime()\nt1 >= t0") == "true"

suite "Bench - elapsed helpers":
  test "elapsedMillis converts nanos to millis":
    check run("let ms = elapsedMillis(1000000, 2500000)\nms == 1.5") == "true"
  test "elapsedMillis handles a zero span":
    check run("let ms = elapsedMillis(7, 7)\nms == 0.0") == "true"
  test "elapsedSeconds converts nanos to seconds":
    check run("let s = elapsedSeconds(0, 3000000000)\ns == 3.0") == "true"
  test "a measured loop reports positive millis":
    check run("let t0 = monoNanos()\nvar i = 0\nwhile i < 200000:\n  i = i + 1\nlet ms = elapsedMillis(t0, monoNanos())\nms > 0.0") == "true"
