import std/[unittest, options, strutils]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem, lowlibs/libnanoid]

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
  let nanoModule = newModule("nanoid", some"nanoid.dfkup")
  nanoModule.importModule(systemModule, "system")
  initNanoId(script, nanoModule)
  module.load(nanoModule)
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

# dfkup has no try/except, so raising procs are checked from the outside
proc raises(code: string) =
  var threw = false
  try:
    discard interpret(code)
  except CatchableError:
    threw = true
  check threw

# every character of a generated id must come from the url-safe alphabet
proc isUrlSafe(id: string): bool =
  let alphabet = "useandom-26T198340PX75pxJACKVERYMINDBUSHWOLF_GQZbfghjklqvwyzrict"
  for c in id:
    if c notin alphabet:
      return false
  result = true

suite "Nano ID - generation":
  test "the default is 21 url-safe characters":
    let id = run("nanoid()")
    check id.len == 21
    check isUrlSafe(id)
  test "the size argument is honoured":
    for n in [1, 2, 8, 10, 32, 64, 100]:
      check run("nanoid(" & $n & ")").len == n
  test "output varies between calls":
    var seen: seq[string]
    for _ in 1 .. 100:
      let id = run("nanoid()")
      if id notin seen:
        seen.add id
    check seen.len > 95
  test "a non-positive size is rejected":
    raises("nanoid(0)")
    raises("nanoid(-1)")

suite "Nano ID - alphabets":
  test "the default alphabet is exposed and is url-safe":
    let alpha = run("nanoidAlphabet()")
    check alpha.len == 64
    check alpha == "useandom-26T198340PX75pxJACKVERYMINDBUSHWOLF_GQZbfghjklqvwyzrict"
  test "nanoidCustom draws only from the given alphabet":
    let id = run("nanoidCustom(\"abc\", 16)")
    check id.len == 16
    for c in id:
      check c in {'a', 'b', 'c'}
  test "nanoidCustom defaults to 21 characters":
    check run("nanoidCustom(\"ab\")").len == 21
  test "a narrow alphabet still covers every character":
    var seen: seq[char]
    for _ in 1 .. 40:
      for c in run("nanoidCustom(\"abc\", 4)"):
        if c notin seen:
          seen.add c
    check seen.len == 3
  test "a bad alphabet or size is rejected":
    raises("nanoidCustom(\"\", 5)")
    raises("nanoidCustom(\"a\", 5)")
    raises("nanoidCustom(\"abc\", 0)")

suite "Nano ID - non-secure variant":
  test "it produces valid ids":
    let id = run("nanoidNonSecure()")
    check id.len == 21
    check isUrlSafe(id)
  test "it honours the size argument":
    check run("nanoidNonSecure(8)").len == 8
  test "it draws from a custom alphabet too":
    let id = run("nanoidCustom(\"xyz\", 6)")
    for c in id:
      check c in {'x', 'y', 'z'}
