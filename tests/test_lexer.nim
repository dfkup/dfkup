import std/unittest
import ../src/lang/lexer

proc tokens(input: string): seq[string] =
  var lex = newLexer(input)
  while true:
    let tok = lex.nextToken()
    if tok.kind == tkEof:
      break
    result.add $tok.kind

proc tokenValues(input: string): seq[string] =
  var lex = newLexer(input)
  while true:
    let tok = lex.nextToken()
    if tok.kind == tkEof:
      break
    result.add tok.value

suite "Lexer - operators":
  test "arithmetic operators":
    check tokens("+ - * / % ^") == @["tkPlus", "tkMinus", "tkAsterisk", "tkDivide", "tkMod", "tkCaret"]
  test "comparison operators":
    check tokens("== != < > <= >=") == @["tkEq", "tkNe", "tkLt", "tkGt", "tkLte", "tkGte"]
  test "logical operators":
    check tokens("&& || and or") == @["tkAndAnd", "tkOrOr", "tkAnd", "tkOr"]
  test "assignment":
    check tokens("=") == @["tkAssign"]
  test "ampersand and pipe":
    check tokens("& |") == @["tkAmp", "tkPipe"]

suite "Lexer - delimiters":
  test "parentheses":
    check tokens("( )") == @["tkLP", "tkRP"]
  test "braces":
    check tokens("{ }") == @["tkLC", "tkRC"]
  test "brackets":
    check tokens("[ ]") == @["tkLB", "tkRB"]
  test "punctuation":
    check tokens(", . ; : ?") == @["tkComma", "tkDot", "tkScolon", "tkColon", "tkTernary"]

suite "Lexer - literals":
  test "integer":
    check tokens("42 0 1_000") == @["tkInteger", "tkInteger", "tkInteger"]
    check tokenValues("42 0 1_000") == @["42", "0", "1000"]
  test "float":
    check tokens("3.14 2.0") == @["tkFloat", "tkFloat"]
    check tokenValues("3.14 2.0") == @["3.14", "2.0"]
  test "negative numbers":
    check tokens("-42") == @["tkInteger"]
    check tokenValues("-42") == @["-42"]
    check tokens("- 5") == @["tkMinus", "tkInteger"]
    check tokens("5 - 3") == @["tkInteger", "tkMinus", "tkInteger"]
  test "string double-quoted":
    check tokens("\"hello\"") == @["tkString"]
    check tokenValues("\"hello\"") == @["hello"]
  test "string single-quoted":
    check tokens("'hello'") == @["tkSqString"]
    check tokenValues("'hello'") == @["hello"]
  test "backtick":
    check tokens("`cmd`") == @["tkBacktick"]
    check tokenValues("`cmd`") == @["cmd"]
  test "boolean":
    check tokens("true false") == @["tkBool", "tkBool"]
    check tokenValues("true false") == @["true", "false"]
  test "nil":
    check tokens("nil") == @["tkNil"]

suite "Lexer - identifiers and keywords":
  test "identifiers":
    check tokens("foo bar_baz") == @["tkIdentifier", "tkIdentifier"]
  test "keywords":
    check tokens("if elif else for while in and or") ==
      @["tkIf", "tkElif", "tkElse", "tkFor", "tkWhile", "tkIn", "tkAnd", "tkOr"]
  test "declaration keywords":
    check tokens("var let const fn func return") ==
      @["tkVar", "tkLet", "tkConst", "tkFn", "tkFunc", "tkReturn"]
  test "control flow keywords":
    check tokens("break continue discard yield echo type object iterator nil") ==
      @["tkBreakCmd", "tkContinueCmd", "tkDiscardCmd", "tkYield", "tkEcho", "tkType", "tkLitObject", "tkIterator", "tkNil"]
  test "case and of":
    check tokens("case of") == @["tkCase", "tkOf"]

suite "Lexer - special tokens":
  test "variable interpolation":
    check tokens("$foo $bar_baz") == @["tkIdentVar", "tkIdentVar"]
    check tokenValues("$foo") == @["foo"]
  test "hash":
    check tokens("#") == @["tkId"]
  test "at":
    check tokens("@") == @["tkAt"]
  test "exclamation":
    check tokens("! !=") == @["tkExc", "tkNe"]

suite "Lexer - comments":
  test "line comment":
    check tokens("// this is a comment") == @["tkComment"]
  test "block comment":
    check tokens("/* doc */") == @["tkDoc"]

suite "Lexer - string escapes":
  test "escaped chars":
    check tokenValues("\"\\n\\t\\r\\\\\\\"\"") == @["\n\t\r\\\""]
