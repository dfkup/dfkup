import std/unittest
import ../src/lang/lexer

suite "Lexer basics":
  test "tokenize symbols":
    let input = "+ - * / % ( ) { } [ ] , . ; :"
    var lex = newLexer(input)
    var tokens: seq[string]
    while true:
      let tok = lex.nextToken()
      if tok.kind == tkEof:
        break
      tokens.add $tok.kind
    check tokens == @["tkPlus", "tkMinus", "tkAsterisk", "tkDivide", "tkMod",
                    "tkLP", "tkRP", "tkLC", "tkRC", "tkLB", "tkRB",
                    "tkComma", "tkDot", "tkScolon", "tkColon"]