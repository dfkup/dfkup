import std/unittest
import ../src/lang/transformers
import pkg/vancode/interpreter/ast
import ../src/lang/parser
import ../src/lang/staticeval

proc parse(input: string): seq[Node] =
  var program: Ast
  parseScript(program, input)
  program.nodes

proc parseErrorMsg(input: string): string =
  ## The parser error message for `input`, or "" if it parsed cleanly.
  try:
    discard parse(input)
    ""
  except DfkupParserError as e:
    e.msg

suite "Parser - literals":
  test "integer":
    let nodes = parse("42")
    check nodes.len == 1
    check nodes[0].kind == nkInt
    check nodes[0].intVal == 42
  test "float":
    let nodes = parse("3.14")
    check nodes[0].kind == nkFloat
  test "string":
    let nodes = parse("\"hello\"")
    check nodes[0].kind == nkString
    check nodes[0].stringVal == "hello"
  test "boolean":
    let nodes = parse("true")
    check nodes[0].kind == nkBool
    check nodes[0].boolVal == true
  test "nil":
    let nodes = parse("nil")
    check nodes[0].kind == nkNil
  test "backtick string":
    let nodes = parse("`echo hello`")
    check nodes[0].kind == nkString
    check nodes[0].stringVal == "echo hello"
  test "backtick string as a call argument":
    let nodes = parse("execShell(`exit 0`)")
    check nodes[0].kind == nkCall
    check nodes[0][1].kind == nkString
    check nodes[0][1].stringVal == "exit 0"
  test "backtick string in an object literal":
    let nodes = parse("{cmd: `make all`}")
    check nodes[0].kind == nkObjectStorage
    check nodes[0][0][1].stringVal == "make all"

suite "Parser - when in expression position":
  test "selects the true branch":
    let nodes = parse("{name: when defined(\"posix\"): \"test\" else: \"x\"}")
    check nodes[0].kind == nkObjectStorage
    check nodes[0][0][1].kind == nkString
    check nodes[0][0][1].stringVal == (if PosixOS: "test" else: "x")
  test "selects the else branch on this host":
    let nodes = parse(
      "{name: when defined(\"nonexistent_flag\"): \"a\" else: \"fallback\"}")
    check nodes[0][0][1].stringVal == "fallback"
  test "works for getSystemInfo":
    let nodes = parse(
      "{cores: when getSystemInfo().cpuCores > 0: \"many\" else: \"none\"}")
    check nodes[0][0][1].kind == nkString
    check nodes[0][0][1].stringVal == "many"
  test "a multi-statement branch is rejected":
    # An indent block ends at the dedent, so the second line parses as its own
    # statement. Braces are what actually put two statements in one branch.
    check parseErrorMsg(
      "let x = when defined(\"posix\"): {1\n  2}") != ""
  test "an unknown static symbol is rejected":
    check parseErrorMsg(
      "{x: when notAThing: 1 else: 2}") != ""
  test "statement position still splices":
    let nodes = parse(
      "when defined(\"posix\"):\n  let x = 1\nelse:\n  let x = 2")
    check nodes.len == 1
    check nodes[0].kind == nkLet

suite "Parser - identifiers":
  test "identifier":
    let nodes = parse("foo")
    check nodes[0].kind == nkIdent
    check nodes[0].ident == "foo"

suite "Parser - expressions":
  test "binary operator":
    let nodes = parse("1 + 2")
    check nodes[0].kind == nkInfix
  test "comparison":
    let nodes = parse("x > 10")
    check nodes[0].kind == nkInfix
    check nodes[0][1].ident == "x"
    check nodes[0][0].ident == ">"
    check nodes[0][2].intVal == 10
  test "function call":
    let nodes = parse("echo(42)")
    check nodes[0].kind == nkCall
    check nodes[0][0].ident == "echo"
    check nodes[0][1].kind == nkInt

suite "Parser - variable declarations":
  test "var":
    let nodes = parse("var x = 42")
    check nodes[0].kind == nkVar
  test "let":
    let nodes = parse("let name = \"world\"")
    check nodes[0].kind == nkLet
  test "const":
    let nodes = parse("const max = 100")
    check nodes[0].kind == nkConst

suite "Parser - control flow":
  test "if":
    let nodes = parse("if true: 1")
    check nodes[0].kind == nkIf
  test "if-else":
    let nodes = parse("if true: 1 else: 2")
    check nodes[0].kind == nkIf
    check nodes[0].len == 3
  test "if-elif-else":
    let nodes = parse("if a: 1 elif b: 2 else: 3")
    check nodes[0].kind == nkIf
  test "while":
    let nodes = parse("while x > 0: x = x - 1")
    check nodes[0].kind == nkWhile
  test "for":
    let nodes = parse("for x in items: echo x")
    check nodes[0].kind == nkFor

suite "Parser - when (compile-time)":
  test "true condition inlines selected branch":
    let nodes = parse("when true: var x = 10")
    check nodes.len == 1
    check nodes[0].kind == nkVar
  test "false condition emits nothing (no else)":
    let nodes = parse("when false: echo 1")
    check nodes.len == 0
  test "false condition selects else branch":
    let nodes = parse("when false: echo 1 else: echo 2")
    check nodes.len == 1
    check nodes[0].kind == nkCall
    check nodes[0][0].ident == "echo"
    check nodes[0][1].intVal == 2
  test "elif chain selects matching branch":
    let nodes = parse("when 1 == 2: echo 1 elif 2 == 2: echo 2 else: echo 3")
    check nodes.len == 1
    check nodes[0].kind == nkCall
    check nodes[0][1].intVal == 2
  test "constant arithmetic condition":
    let nodes = parse("when 2 + 2 == 4: let a = 5")
    check nodes.len == 1
    check nodes[0].kind == nkLet
  test "non-static condition raises parser error":
    expect DfkupParserError:
      discard parse("when someVar == 1: echo 1")

suite "Parser - statements":
  test "echo":
    let nodes = parse("echo 42")
    check nodes[0].kind == nkCall
    check nodes[0][0].ident == "echo"
  test "return":
    let nodes = parse("return 42")
    check nodes[0].kind == nkReturn
  test "break":
    let nodes = parse("break")
    check nodes[0].kind == nkBreak
  test "yield":
    let nodes = parse("yield x")
    check nodes[0].kind == nkYield

suite "Parser - functions":
  test "function definition":
    let nodes = parse("fn add(a, b) = a + b")
    check nodes[0].kind == nkProc

suite "Parser - brace blocks":
  # A brace-based block has an explicit terminator. An unterminated `{` used to
  # swallow every following statement, so a missing brace surfaced as a
  # confusing error far downstream -- or silently compiled when nothing
  # followed the block.
  test "unterminated function body is rejected":
    check parseErrorMsg("""
fn f(): int {
  var i = 0
  return i
""") == "`}` is expected here"

  test "unterminated body does not swallow following statements":
    # The `echo` on the last line belongs to the script, not to `f`.
    check parseErrorMsg("""
fn f(): int {
  return 1

echo f()
""") == "`}` is expected here"

  test "unterminated if body is rejected":
    check parseErrorMsg("""
fn f(): int {
  if true {
    return 1
  return 2
}
""") == "`}` is expected here"

  test "unterminated while body is rejected":
    check parseErrorMsg("""
fn f(): int {
  var i = 0
  while i < 3 {
    i = i + 1
  return i
}
""") == "`}` is expected here"

  test "unterminated nested block is rejected":
    check parseErrorMsg("""
async func counterB(): int {
  var i = 10
  while i < 13 {
    yield i
    i = i + 1
  return -1
""") == "`}` is expected here"

  test "closed brace bodies still parse":
    let nodes = parse("""
fn f(n: int): string {
  if n > 1 {
    return "big"
  }
  return "small"
}
""")
    check nodes[0].kind == nkProc

  test "brace bodies agree with indent bodies":
    let braced = parse("""
fn f(n: int): int {
  var t = 0
  for i in 0..n {
    while t < i {
      t = t + 1
    }
  }
  return t
}
""")
    let indented = parse("""
fn f(n: int): int =
  var t = 0
  for i in 0..n:
    while t < i:
      t = t + 1
  return t
""")
    check braced.len == indented.len
    check braced[0].kind == nkProc
    check indented[0].kind == nkProc

  test "indent-based blocks need no closing brace":
    # The dedent is the terminator, so reaching EOF is not an error.
    let nodes = parse("""
fn f(n: int): int =
  var t = 0
  for i in 0..n:
    t = t + i
  return t
""")
    check nodes[0].kind == nkProc

suite "Parser - data structures":
  test "array":
    let nodes = parse("[1, 2, 3]")
    check nodes[0].kind == nkArray
  test "object storage":
    let nodes = parse("{a: 1, b: 2}")
    check nodes[0].kind == nkObjectStorage
