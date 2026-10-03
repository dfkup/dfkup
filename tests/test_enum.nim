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
  ## The script's final value, rendered as a string.
  let v = exec(code)
  if v != nil and v.typeId notin {tyNil}: result = $v

proc failsWith(code, needle: string): bool =
  ## True when compiling `code` raises an error mentioning `needle`.
  try:
    discard exec(code)
    false
  except CatchableError as e:
    e.msg.contains(needle)

suite "Enum - declarations":
  test "a field with an explicit value":
    check run("""
      type Fruits = enum
        apple = "Apple"

      Fruits.apple
      """) == "Apple"

  test "a bare field stands for itself":
    check run("""
      type Fruits = enum
        strawberry

      Fruits.strawberry
      """) == "strawberry"

  test "every field of one enum is reachable":
    check run("""
      type Fruits = enum
        apple = "Apple"
        strawberry
        pear = "Pear, really"

      $Fruits.apple & "/" & $Fruits.strawberry & "/" & $Fruits.pear
      """) == "Apple/strawberry/Pear, really"

  test "an empty enum is allowed":
    check run("""
      type Empty = enum
      "ok"
      """) == "ok"

suite "Enum - qualified access":
  test "fields of two enums never collide":
    check run("""
      type Fruits = enum
        apple = "Apple"

      type BadFruits = enum
        apple

      $BadFruits.apple & "/" & $Fruits.apple
      """) == "apple/Apple"

  test "a bare field name is not in scope":
    check failsWith("""
      type Fruits = enum
        apple = "Apple"

      apple
      """, "undeclared identifier 'apple'")

  test "an unknown field is rejected":
    check failsWith("""
      type Fruits = enum
        apple = "Apple"

      Fruits.pear
      """, "does not exist")

  test "a duplicate field is rejected":
    check failsWith("""
      type Fruits = enum
        apple = "Apple"
        apple
      """, "already declared")

  test "a field value must be a string":
    check failsWith("""
      type Fruits = enum
        apple = 5
      """, "needs a string value")

suite "Enum - grouped declarations":
  test "several enums under one `type` keyword":
    check run("""
      type
        Fruits = enum
          apple = "Apple"
          strawberry
        Veg = enum
          carrot = "Carrot"

      $Fruits.apple & "/" & $Fruits.strawberry & "/" & $Veg.carrot
      """) == "Apple/strawberry/Carrot"

  test "an enum and an object under one `type` keyword":
    check run("""
      type
        Fruits = enum
          apple = "Apple"
        Box = object
          n: int

      Fruits.apple
      """) == "Apple"

suite "Enum - comparison":
  test "equal fields of one enum compare equal":
    check run("""
      type Fruits = enum
        apple = "Apple"
        strawberry

      Fruits.apple == Fruits.apple
      """) == "true"

  test "different fields of one enum do not compare equal":
    check run("""
      type Fruits = enum
        apple = "Apple"
        strawberry

      Fruits.apple == Fruits.strawberry
      """) == "false"

  test "different fields of one enum are not equal":
    check run("""
      type Fruits = enum
        apple = "Apple"
        strawberry

      Fruits.apple != Fruits.strawberry
      """) == "true"

  test "two enums sharing a field name are still distinct types":
    check failsWith("""
      type Fruits = enum
        apple = "Apple"

      type BadFruits = enum
        apple = "Apple"

      Fruits.apple == BadFruits.apple
      """, "type mismatch")

suite "Enum - type annotations":
  test "an enum works as a parameter type":
    check run("""
      type Fruits = enum
        apple = "Apple"
        strawberry

      func label(f: Fruits): string =
        if f == Fruits.apple: return "apple-ish"
        return "other"

      label(Fruits.apple)
      """) == "apple-ish"

  test "an enum works as a variable type":
    check run("""
      type Fruits = enum
        apple = "Apple"
        strawberry

      var f: Fruits = Fruits.strawberry
      f != Fruits.apple
      """) == "true"

  test "an enum value works as an if condition":
    check run("""
      type Fruits = enum
        apple = "Apple"
        strawberry

      let f = Fruits.strawberry
      if f == Fruits.apple: "apple" else: "not apple"
      """) == "not apple"

# Names follow VanCode's `lowerName` rule: the first letter is significant,
# everything after it is case-insensitive. So `Fruits.strawBERRY` resolves, but
# `Fruits.Apple` does not.
suite "Enum - name matching":
  test "field names ignore case after the first letter":
    check run("""
      type Fruits = enum
        apple = "Apple"
        strawberry

      $Fruits.apple & "/" & $Fruits.strawBERRY
      """) == "Apple/strawberry"

  test "a camelCase enum name is reachable":
    check run("""
      type BadFruits = enum
        apple

      BadFruits.apple
      """) == "apple"

  test "an enum name ignores case after the first letter":
    check run("""
      type BadFruits = enum
        apple

      BADFRUITS.apple
      """) == "apple"

  test "the first letter of a name is significant":
    check failsWith("""
      type Fruits = enum
        apple = "Apple"

      fruits.apple
      """, "undeclared identifier 'fruits'")

  test "the first letter of a field name is significant":
    check failsWith("""
      type Fruits = enum
        apple = "Apple"

      Fruits.Apple
      """, "does not exist")