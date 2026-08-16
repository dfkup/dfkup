import std/unittest
import pkg/vancode/interpreter/ast
import ../src/lang/staticeval

proc b(v: bool): Node = ast.newBoolLit(v)
proc i(v: int64): Node = ast.newIntLit(v)
proc s(v: string): Node = ast.newStringLit(v)
proc infix(op: string, l, r: Node): Node = ast.newInfix(ast.newIdent(op), l, r)
proc notExpr(e: Node): Node = ast.newTree(nkPrefix, ast.newIdent("not"), e)
proc call(name: string, args: varargs[Node]): Node =
  var c = ast.newCall(ast.newIdent(name))
  for a in args: c.add(a)
  c

proc evalB(node: Node): bool = evalStaticBool(node)

suite "Static - literals":
  test "bool literal":
    check evalB(b(true)) == true
    check evalB(b(false)) == false
  test "int literal":
    check evalB(infix("==", i(42), i(42))) == true
  test "string literal":
    check evalB(infix("==", s("a"), s("a"))) == true
  test "int truthiness in bool context errors":
    expect StaticEvalError:
      discard evalStaticBool(i(1))

suite "Static - arithmetic":
  test "addition":
    check evalB(infix("==", infix("+", i(2), i(3)), i(5)))
  test "subtraction":
    check evalB(infix("==", infix("-", i(10), i(4)), i(6)))
  test "multiplication":
    check evalB(infix("==", infix("*", i(6), i(7)), i(42)))
  test "division":
    check evalB(infix("==", infix("/", i(9), i(3)), i(3)))
  test "modulo":
    check evalB(infix("==", infix("%", i(10), i(3)), i(1)))

suite "Static - comparison":
  test "greater than":
    check evalB(infix(">", i(5), i(3)))
  test "less than or equal":
    check evalB(infix("<=", i(3), i(3)))
  test "not equal":
    check evalB(infix("!=", i(3), i(4)))
  test "string ordering":
    check evalB(infix("<", s("a"), s("b")))

suite "Static - logical":
  test "and":
    check evalB(infix("and", b(true), b(true)))
    check evalB(infix("and", b(false), b(true))) == false
  test "or":
    check evalB(infix("or", b(false), b(true)))
    check evalB(infix("or", b(false), b(false))) == false
  test "not":
    check evalB(notExpr(b(false))) == true
    check evalB(notExpr(b(true))) == false
  test "not of comparison":
    check evalB(notExpr(infix("==", i(1), i(2)))) == true

suite "Static - defined":
  test "posix flag matches host":
    check staticeval.defined("posix") == (hostOS != "windows")
  test "unknown flag is false":
    check staticeval.defined("nonexistent_flag") == false
  test "known os flag":
    check staticeval.defined(hostOS) == true

suite "Static - machine info":
  test "hostOS resolves":
    let v = evalStatic(ast.newIdent("hostOS"))
    check v.kind == skString
    check v.strVal == hostOS
  test "hostCPU resolves":
    let v = evalStatic(ast.newIdent("hostCPU"))
    check v.kind == skString
    check v.strVal == hostCPU
  test "cpuEndian resolves":
    let v = evalStatic(ast.newIdent("cpuEndian"))
    check v.kind == skString
    check v.strVal == $cpuEndian
  test "bare define flag as bool":
    let v = evalStatic(ast.newIdent(hostOS))
    check v.kind == skBool
    check v.boolVal == true

suite "Static - errors":
  test "unknown compile-time symbol":
    expect StaticEvalError:
      discard evalStatic(ast.newIdent("someRuntimeVar"))
  test "unsupported operator":
    expect StaticEvalError:
      discard evalStatic(infix("^", i(2), i(3)))
  test "defined with wrong arg count":
    expect StaticEvalError:
      discard evalStatic(call("defined"))
