import std/unittest
import ../src/lang/transformers
import pkg/vancode/interpreter/ast
import ../src/lang/parser

proc parse(input: string): seq[Node] =
  var program: Ast
  parseScript(program, input)
  program.nodes

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

suite "Parser - data structures":
  test "array":
    let nodes = parse("[1, 2, 3]")
    check nodes[0].kind == nkArray
  test "object storage":
    let nodes = parse("{a: 1, b: 2}")
    check nodes[0].kind == nkObjectStorage
