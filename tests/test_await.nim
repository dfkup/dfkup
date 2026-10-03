import std/[unittest, options, strutils]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem]

proc exec(code: string): Value =
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
  result = vmInstance.interpret(script, mainChunk)

proc run(code: string): string =
  let v = exec(code)
  if v != nil and v.typeId notin {tyNil}: result = $v

proc messageOf(code: string): string =
  ## The compile-error message raised by `code`, or "" if it compiled.
  try:
    discard exec(code)
    ""
  except CatchableError as e:
    e.msg

# Resume `driver` to completion, concatenating every value it produces with a
# `|` separator so a test can assert on the whole sequence. Values are strings:
# dfkup's `$` is a display operator rather than a conversion, so an int cannot
# be turned into a string for `&`.
proc drain(prefix: string, driver: string): string =
  let code = prefix & "\nlet o = createCoro(" & driver & ")\n" & """
var acc = ""
while status(o) != "csCompleted":
  let v = resume(o)
  acc = acc & v & "|"
acc
"""
  run(code)

suite "Await":
  test "await returns the coroutine's return value":
    check drain("""
async func inner(): string =
  yield "7"
  yield "8"
  return "42"

async func outer(): string =
  let v = await inner()
  return v & "+100"
""", "outer") == "7|8|42+100|"

  test "await forwards intermediate yields to the awaiting coroutine":
    check drain("""
async func inner(): string =
  yield "1"
  yield "2"
  return "3"

async func outer(): string =
  return await inner()
""", "outer") == "1|2|3|"

  test "await passes arguments on the first resume":
    check drain("""
async func chat(p: string): string =
  yield "asking " & p
  return "re: " & p

async func outer(): string =
  return await chat("world")
""", "outer") == "asking world|re: world|"

  test "await on an existing coroutine value":
    check drain("""
async func inner(): string =
  yield "1"
  return "5"

async func outer(): string =
  let c = createCoro(inner)
  return await c
""", "outer") == "1|5|"

  test "nested coroutines restore the outer coroutine correctly":
    # Before the coroutine frame stack, resuming an inner coroutine from
    # inside an outer one clobbered the outer's saved state and the toplevel
    # continuation was silently dropped.
    check run("""
async func inner(): string =
  return "42"

async func outer(): string =
  let c = createCoro(inner)
  return resume(c)

let o = createCoro(outer)
let v = resume(o)
let s = status(o)
v & "/" & s
""") == "42/csCompleted"

  test "await composes across two coroutines":
    check drain("""
async func a(): string =
  yield "10"
  return "11"

async func b(): string =
  yield "20"
  return "21"

async func driver(): string =
  let ca = createCoro(a)
  let cb = createCoro(b)
  let x = await ca
  let y = await cb
  return x & y
""", "driver") == "10|20|1121|"

  test "await at toplevel drops intermediate yields":
    # There is no resumer to forward to outside a coroutine, so only the
    # awaited coroutine's return value survives.
    check run("""
async func inner(): int =
  yield 1
  yield 2
  return 99

await inner()
""") == "99"

suite "Async call errors":
  test "calling an async function directly points at await and dispatch":
    # A bare `compute()` used to report "'compute' is not a procedure", which
    # says nothing about what to do instead.
    check messageOf("""
async func compute(): int =
  return 42

fn bad(): int =
  return compute()
""").contains("is an async function") and
      messageOf("""
async func compute(): int =
  return 42

fn bad(): int =
  return compute()
""").contains("await compute(") and
      messageOf("""
async func compute(): int =
  return 42

fn bad(): int =
  return compute()
""").contains("dispatch(compute,")

  test "the error fires for a discarded call too":
    check messageOf("""
async func compute(): int =
  return 42

fn bad(): int =
  discard compute()
  return 0
""").contains("is an async function")

  test "await, dispatch and createCoro all still compile":
    # The coroutine branch in `callProc` must only fire for a direct call, so
    # the three sanctioned ways of naming an async func must stay error-free.
    # compute yields "a" then returns "b": await and dispatch both reach "b",
    # while createCoro leaves it unstarted so its first resume is still "a".
    check run("""
async func compute(): string =
  yield "a"
  return "b"

fn viaAwait(): string =
  return await compute()

fn viaDispatch(): string =
  let c = dispatch(compute)
  return resume(c)

fn viaCreateCoro(): string =
  let c = createCoro(compute)
  return resume(c)

let a = viaAwait()
let b = viaDispatch()
let c = viaCreateCoro()
a & "/" & b & "/" & c
""") == "b/b/a"

suite "Then":
  test "then calls the continuation with the awaited result":
    check drain("""
fn shout(body: string): string =
  return body & "!"

async func inner(): string =
  return "hello"

async func outer(): string =
  return await inner() then shout()
""", "outer") == "hello!|"

  test "then still forwards intermediate yields":
    check drain("""
fn note(body: string): string =
  return body

async func inner(): string =
  yield "a"
  yield "b"
  return "c"

async func outer(): string =
  return await inner() then note()
""", "outer") == "a|b|c|"

  test "then with extra arguments":
    check drain("""
fn join(a: string, b: string, sep: string): string =
  return a & sep & b

async func inner(): string =
  return "left"

async func outer(): string =
  return await inner() then join("right", "-")
""", "outer") == "left-right|"

suite "Dispatch":
  test "dispatch starts the coroutine and yields to its first value":
    # `dispatch(f)` is `createCoro(f)` plus one resume, so the first `yield`
    # is consumed by the dispatch call itself.
    check run("""
async func counter(start: int): string =
  var i = start
  while i < start + 3:
    yield "v" & $i
    i = i + 1
  return "end"

let c = dispatch(counter, 10)
let s = status(c)
let a = resume(c)
let b = resume(c)
let done = resume(c)
s & "/" & a & "/" & b & "/" & done
""") == "csSuspended/v11/v12/end"

  test "dispatch binds arguments at dispatch time":
    # Unlike `createCoro(f)` + `resume(c, args)`, the arguments belong to
    # `dispatch`, so a later `resume` takes none. The first yield is consumed
    # by the dispatch, leaving only the return value to step to.
    check run("""
async func chat(p: string): string =
  yield "asked " & p
  return "re " & p

let c = dispatch(chat, "world")
let a = resume(c)
a & "/" & status(c)
""") == "re world/csCompleted"

  test "dispatch evaluates to the coroutine, so it can be stepped":
    check run("""
async func ticker(): string =
  yield "a"
  yield "b"
  return "c"

let c = dispatch(ticker)
var acc = ""
while status(c) != "csCompleted":
  acc = acc & resume(c) & "|"
acc
""") == "b|c|"

  test "dispatch on a coroutine with no yields runs it to completion":
    check run("""
async func oneShot(): string =
  return "only"

let c = dispatch(oneShot)
status(c)
""") == "csCompleted"

  test "dispatch of a zero-parameter coroutine needs no arguments":
    check run("""
async func greet(): string =
  yield "hi"
  return "bye"

let c = dispatch(greet)
# dispatch already consumed "hi", so the first resume is the return value
let v = resume(c)
let state = status(c)
state & "/" & v
""") == "csCompleted/bye"

  test "dispatch composes with await":
    # dispatch takes the first step, then `await` drives the rest and hands
    # back the return value.
    check run("""
async func work(n: int): string =
  yield "a"
  yield "b"
  return "n=" & $n

fn total(): string =
  let c = dispatch(work, 3)
  return await c

total()
""") == "n=3"

  test "await binds tighter than every binary operator":
    # `await f() & "x"` is `(await f()) & "x"`, so the concat applies to the
    # awaited result rather than being swallowed into the await operand.
    check run("""
async func steps(): string =
  yield "one"
  return "three"

fn shout(body: string): string =
  return "[" & body & "]"

fn concat(): string =
  return await steps() & "!"

fn twoAwaits(): string =
  return await steps() & await steps()

fn continued(): string =
  return await steps() then shout()

let a = concat()
let b = twoAwaits()
let c = continued()
a & "/" & b & "/" & c
""") == "three!/threethree/[three]"

  test "await binds tighter than arithmetic":
    check run("""
async func num(): int =
  yield 1
  return 5

fn plusOne(): int =
  return await num() + 1

$plusOne()
""") == "6"

  test "await is the concise form when only the result is wanted":
    # The pair the language actually pushes: `await f(args)` for the result,
    # `dispatch(f, args)` when the coroutine itself is wanted.
    check run("""
async func steps(): string =
  yield "one"
  yield "two"
  return "three"

fn run(): string =
  let v = await steps()
  return v & "!"

run()
""") == "three!"
