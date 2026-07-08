# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/strutils

type
  TokenKind* = enum
    tkEof, tkIdentifier, tkInteger, tkFloat, tkString,
    tkPlus, tkMinus, tkAsterisk, tkDivide, tkMod, tkCaret,
    tkLC, tkRC, tkLP, tkRP, tkLB, tkRB,
    tkComma, tkDot, tkSemicolon, tkColon, tkScolon,
    tkAssign, tkEq, tkGt, tkLt, tkGte, tkLte,
    tkAndAnd, tkOrOr,
    tkIf, tkElse, tkWhile, tkFor, tkIn, tkFunc,
    tkReturn, tkVar, tkTrue, tkFalse, tkNil,
    tkComment, tkDoc, tkTernary, tkAmp, tkPipe,
    tkSqString, tkStringLiteral,
    tkNe, tkExc, tkId, tkBacktick, tkIdentVar, tkIdentVarSafe,
    tkBool, tkAt, tkCase, tkOf, tkElif, tkAnd, tkOr,
    tkType, tkLitObject, tkFn, tkIterator, tkMacro,
    tkBreakCmd, tkLet, tkConst, tkDiscardCmd, tkContinueCmd,
    tkEcho, tkYield, tkIs, tkIsNot, tkUnknown

  TokenTuple* = tuple
    kind: TokenKind
    value: string
    line: int
    col: int
    pos: int
    wsno: int

  Lexer* = object
    input: string
    pos*, line*, col*: int
    current*: char
    strbuf*: string

  DfkupLexerError* = object of CatchableError

proc newLexer*(input: string): Lexer =
  ## Create a new Lexer instance
  result.input = input
  result.pos = 0
  result.line = 1
  result.col = 0
  result.strbuf = ""
  if input.len > 0:
    result.current = input[0]
  else:
    result.current = '\0'

proc charAt(l: Lexer, idx: int): char {.inline.} =
  if idx < 0 or idx >= l.input.len: return '\0'
  l.input[idx]

proc getContext(l: Lexer, posOverride: int = -1): string =
  let rawPos = if posOverride >= 0: posOverride else: l.pos
  let atPos = max(0, min(rawPos, l.input.len))
  var lineStart = atPos
  while lineStart > 0 and l.charAt(lineStart - 1) != '\n':
    dec lineStart
  var lineEnd = atPos
  while lineEnd < l.input.len and l.charAt(lineEnd) notin {'\n', '\r'}:
    inc lineEnd
  var snippet: string
  if l.input.len > 0:
    snippet = l.input[lineStart ..< lineEnd]
  else:
    snippet = newStringOfCap(max(0, lineEnd - lineStart))
    for i in lineStart ..< lineEnd:
      snippet.add(l.charAt(i))
  let markerPos = max(0, min(snippet.len, atPos - lineStart))
  result = snippet & "\n" & " ".repeat(markerPos) & "^"

proc error*(l: var Lexer, msg: string) =
  let context = getContext(l)
  raise newException(DfkupLexerError, ("\n" & context & "\n" & "Error ($1:$2) " % [$l.line, $l.col]) & msg)

proc advance(lex: var Lexer) =
  if lex.pos < lex.input.len:
    if lex.current == '\n':
      inc lex.line
      lex.col = 0
    else:
      inc lex.col
    inc lex.pos
    if lex.pos < lex.input.len:
      lex.current = lex.input[lex.pos]
    else:
      lex.current = '\0'

proc peek(lex: Lexer, offset = 1): char =
  let idx = lex.pos + offset
  if idx < lex.input.len: lex.input[idx] else: '\0'

proc skipWhitespace(lex: var Lexer) =
  while lex.current in {' ', '\t', '\r'}:
    lex.advance()

proc peekToken(lex: Lexer, expectToken: string): bool =
  var pos = lex.pos
  while pos < lex.input.len and lex.input[pos] in {' ', '\t', '\r'}:
    inc pos
  for ch in expectToken:
    if pos >= lex.input.len or lex.input[pos] != ch:
      return false
    inc pos
  return true

proc initToken(lex: var Lexer, kind: static TokenKind,
                line, col, pos, wsno: int): TokenTuple =
  (kind, "", line, col, pos, wsno)

proc initToken(lex: var Lexer, kind: TokenKind,
                value: sink string, line, col, pos, wsno: int): TokenTuple =
  (kind, value, line, col, pos, wsno)

proc nextToken*(lex: var Lexer): TokenTuple =
  var wsno = 0
  while true:
    while lex.current in {' ', '\t', '\r'}:
      inc wsno
      lex.advance()
    if lex.current == '\n' or lex.current == '\r':
      lex.advance()
      wsno = 0
      continue
    elif lex.current == '\r':
      if lex.peek() == '\n':
        lex.advance()
      inc lex.line
      lex.col = 0
      lex.advance()
      wsno = 0
      continue
    break

  let line = lex.line
  let col = lex.col
  let pos = lex.pos

  case lex.current
  of '\0':
    result = initToken(lex, tkEof, line, col, pos, wsno)
  of '+':
    lex.advance()
    result = initToken(lex, tkPlus, line, col, pos, wsno)
  of '-':
    if lex.peek() in {'0'..'9'}:
      lex.advance()
      lex.strbuf.setLen(0)
      lex.strbuf.add('-')
      var isFloat = false
      while lex.current in {'0'..'9', '_'}:
        if lex.current != '_':
          lex.strbuf.add(lex.current)
        lex.advance()
      let nextChar = lex.peek()
      if lex.current == '.' and nextChar in {'0'..'9'}:
        isFloat = true
        lex.strbuf.add('.')
        lex.advance()
        while lex.current in {'0'..'9', '_'}:
          if lex.current != '_':
            lex.strbuf.add(lex.current)
          lex.advance()
      if isFloat and (lex.current == 'e' or lex.current == 'E'):
        lex.strbuf.add(lex.current)
        lex.advance()
        if lex.current == '+' or lex.current == '-':
          lex.strbuf.add(lex.current)
          lex.advance()
        while lex.current in {'0'..'9', '_'}:
          if lex.current != '_':
            lex.strbuf.add(lex.current)
          lex.advance()
        result = initToken(lex, tkFloat, move lex.strbuf, line, col, pos, wsno)
      elif isFloat:
        result = initToken(lex, tkFloat, move lex.strbuf, line, col, pos, wsno)
      else:
        result = initToken(lex, tkInteger, move lex.strbuf, line, col, pos, wsno)
    else:
      lex.advance()
      result = initToken(lex, tkMinus, line, col, pos, wsno)
  of '*':
    lex.advance()
    result = initToken(lex, tkAsterisk, line, col, pos, wsno)
  of '/':
    if lex.peek() == '/':
      lex.advance()
      lex.advance()
      lex.strbuf.setLen(0)
      while lex.current != '\n' and lex.current != '\0':
        lex.strbuf.add(lex.current)
        lex.advance()
      result = initToken(lex, tkComment, move lex.strbuf, line, col, pos, wsno)
    elif lex.peek() == '*':
      lex.advance()
      lex.advance()
      lex.strbuf.setLen(0)
      var prev = '\0'
      while not (prev == '*' and lex.current == '/') and lex.current != '\0':
        if prev != '\0':
          lex.strbuf.add(prev)
        prev = lex.current
        lex.advance()
      if prev != '\0' and not (prev == '*' and lex.current == '/'):
        lex.strbuf.add(prev)
      if lex.current == '/':
        lex.advance()
      result = initToken(lex, tkDoc, move lex.strbuf, line, col, pos, wsno)
    else:
      lex.advance()
      result = initToken(lex, tkDivide, line, col, pos, wsno)
  of '%':
    lex.advance()
    result = initToken(lex, tkMod, line, col, pos, wsno)
  of '^':
    lex.advance()
    result = initToken(lex, tkCaret, line, col, pos, wsno)
  of '{':
    lex.advance()
    result = initToken(lex, tkLC, line, col, pos, wsno)
  of '}':
    lex.advance()
    result = initToken(lex, tkRC, line, col, pos, wsno)
  of '(':
    lex.advance()
    result = initToken(lex, tkLP, line, col, pos, wsno)
  of ')':
    lex.advance()
    result = initToken(lex, tkRP, line, col, pos, wsno)
  of '[':
    lex.advance()
    result = initToken(lex, tkLB, line, col, pos, wsno)
  of ']':
    lex.advance()
    result = initToken(lex, tkRB, line, col, pos, wsno)
  of '.':
    lex.advance()
    result = initToken(lex, tkDot, line, col, pos, wsno)
  of '#':
    lex.advance()
    result = initToken(lex, tkId, line, col, pos, wsno)
  of '?':
    lex.advance()
    result = initToken(lex, tkTernary, line, col, pos, wsno)
  of ':':
    lex.advance()
    result = initToken(lex, tkColon, line, col, pos, wsno)
  of ',':
    lex.advance()
    result = initToken(lex, tkComma, line, col, pos, wsno)
  of ';':
    lex.advance()
    result = initToken(lex, tkScolon, line, col, pos, wsno)
  of '$':
    lex.advance()
    case lex.current
    of IdentStartChars:
      lex.strbuf.setLen(0)
      lex.strbuf.add(lex.current)
      lex.advance()
      while lex.current in IdentChars + {'-'}:
        lex.strbuf.add(lex.current)
        lex.advance()
      result = initToken(lex, tkIdentVar, move lex.strbuf, line, col, pos, wsno)
    else: discard
  of '!':
    if lex.peek() == '=':
      lex.advance()
      lex.advance()
      result = initToken(lex, tkNe, "!=", line, col, pos, wsno)
    else:
      lex.advance()
      result = initToken(lex, tkExc, line, col, pos, wsno)
  of '=':
    if lex.peek() == '=':
      lex.advance()
      lex.advance()
      result = initToken(lex, tkEq, "==", line, col, pos, wsno)
    else:
      lex.advance()
      result = initToken(lex, tkAssign, line, col, pos, wsno)
  of '>':
    if lex.peek() == '=':
      lex.advance()
      lex.advance()
      result = initToken(lex, tkGte, ">=", line, col, pos, wsno)
    else:
      lex.advance()
      result = initToken(lex, tkGt, line, col, pos, wsno)
  of '<':
    if lex.peek() == '=':
      lex.advance()
      lex.advance()
      result = initToken(lex, tkLte, "<=", line, col, pos, wsno)
    else:
      lex.advance()
      result = initToken(lex, tkLt, line, col, pos, wsno)
  of '&':
    if lex.peek() == '&':
      lex.advance()
      lex.advance()
      result = initToken(lex, tkAndAnd, "&&", line, col, pos, wsno)
    else:
      lex.advance()
      result = initToken(lex, tkAmp, line, col, pos, wsno)
  of '|':
    if lex.peek() == '|':
      lex.advance()
      lex.advance()
      result = initToken(lex, tkOrOr, "||", line, col, pos, wsno)
    else:
      lex.advance()
      result = initToken(lex, tkPipe, line, col, pos, wsno)
  of '\'':
    lex.advance()
    lex.strbuf.setLen(0)
    while lex.current != '\'' and lex.current != '\0' and lex.current != '\n':
      lex.strbuf.add(lex.current)
      lex.advance()
    if lex.current == '\'':
      lex.advance()
    result = initToken(lex, tkSqString, move lex.strbuf, line, col, pos, wsno)
  of '"':
    if lex.peek() == '"' and lex.peek(2) == '"':
      lex.advance()
      lex.advance()
      lex.advance()
      lex.strbuf.setLen(0)
      while not (lex.current == '"' and lex.peek() == '"' and lex.peek(2) == '"') and lex.current != '\0':
        lex.strbuf.add(lex.current)
        lex.advance()
      if lex.current == '"' and lex.peek() == '"' and lex.peek(2) == '"':
        lex.advance()
        lex.advance()
        lex.advance()
      result = initToken(lex, tkString, move lex.strbuf, line, col, pos, wsno)
    else:
      lex.advance()
      lex.strbuf.setLen(0)
      while lex.current != '"' and lex.current != '\0' and lex.current != '\n':
        if lex.current == '\\':
          lex.advance()
          case lex.current
          of 'n': lex.strbuf.add('\n')
          of 'r': lex.strbuf.add('\r')
          of 't': lex.strbuf.add('\t')
          of '"': lex.strbuf.add('"')
          of '\\': lex.strbuf.add('\\')
          of '0': lex.strbuf.add('\0')
          else: lex.strbuf.add(lex.current)
          lex.advance()
        else:
          lex.strbuf.add(lex.current)
          lex.advance()
      if lex.current == '"':
        lex.advance()
      result = initToken(lex, tkString, move lex.strbuf, line, col, pos, wsno)
  of '`':
    lex.advance()
    lex.strbuf.setLen(0)
    while lex.current != '`' and lex.current != '\0' and lex.current != '\n':
      lex.strbuf.add(lex.current)
      lex.advance()
    if lex.current == '`':
      lex.advance()
    result = initToken(lex, tkBacktick, move lex.strbuf, line, col, pos, wsno)
  of '@':
    lex.advance()
    lex.strbuf.setLen(0)
    let
      savePos = lex.pos
      saveCol = lex.col
    while lex.current.isAlphaAscii():
      lex.strbuf.add(lex.current)
      lex.advance()
    if lex.strbuf.len > 0:
      lex.pos = savePos
      lex.col = saveCol
      if lex.pos < lex.input.len:
        lex.current = lex.input[lex.pos]
    result = initToken(lex, tkAt, line, col, pos, wsno)
  of '0'..'9':
    lex.strbuf.setLen(0)
    var isFloat = false
    while lex.current in {'0'..'9', '_'}:
      if lex.current != '_':
        lex.strbuf.add(lex.current)
      lex.advance()
    let nextChar = lex.peek()
    if lex.current == '.' and nextChar in {'0'..'9'}:
      isFloat = true
      lex.strbuf.add('.')
      lex.advance()
      while lex.current in {'0'..'9', '_'}:
        if lex.current != '_':
          lex.strbuf.add(lex.current)
        lex.advance()
    if isFloat and (lex.current == 'e' or lex.current == 'E'):
      lex.strbuf.add(lex.current)
      lex.advance()
      if lex.current == '+' or lex.current == '-':
        lex.strbuf.add(lex.current)
        lex.advance()
      while lex.current in {'0'..'9', '_'}:
        if lex.current != '_':
          lex.strbuf.add(lex.current)
        lex.advance()
      return initToken(lex, tkFloat, move lex.strbuf, line, col, pos, wsno)
    if isFloat:
      return initToken(lex, tkFloat, move lex.strbuf, line, col, pos, wsno)
    result = initToken(lex, tkInteger, move lex.strbuf, line, col, pos, wsno)
  else:
    if lex.current.isAlphaAscii() or lex.current in {'_', '-'}:
      lex.strbuf.setLen(0)
      while lex.current.isAlphaNumeric() or lex.current in {'_', '-'}:
        lex.strbuf.add(lex.current)
        lex.advance()
      case lex.strbuf
      of "true", "false":
        result = initToken(lex, tkBool, move lex.strbuf, line, col, pos, wsno)
      of "case":
        result = initToken(lex, tkCase, move lex.strbuf, line, col, pos, wsno)
      of "of":
        result = initToken(lex, tkOf, move lex.strbuf, line, col, pos, wsno)
      of "if":
        result = initToken(lex, tkIf, move lex.strbuf, line, col, pos, wsno)
      of "is":
        result = initToken(lex, tkIs, move lex.strbuf, line, col, pos, wsno)
      of "isnot":
        result = initToken(lex, tkIsNot, move lex.strbuf, line, col, pos, wsno)
      of "elif":
        result = initToken(lex, tkElif, move lex.strbuf, line, col, pos, wsno)
      of "else":
        result = initToken(lex, tkElse, move lex.strbuf, line, col, pos, wsno)
      of "and":
        result = initToken(lex, tkAnd, move lex.strbuf, line, col, pos, wsno)
      of "for":
        result = initToken(lex, tkFor, move lex.strbuf, line, col, pos, wsno)
      of "while":
        result = initToken(lex, tkWhile, move lex.strbuf, line, col, pos, wsno)
      of "in":
        result = initToken(lex, tkIn, move lex.strbuf, line, col, pos, wsno)
      of "or":
        result = initToken(lex, tkOr, move lex.strbuf, line, col, pos, wsno)
      of "type":
        result = initToken(lex, tkType, move lex.strbuf, line, col, pos, wsno)
      of "object":
        result = initToken(lex, tkLitObject, move lex.strbuf, line, col, pos, wsno)
      of "fn":
        result = initToken(lex, tkFn, move lex.strbuf, line, col, pos, wsno)
      of "func":
        result = initToken(lex, tkFunc, move lex.strbuf, line, col, pos, wsno)
      of "iterator":
        result = initToken(lex, tkIterator, move lex.strbuf, line, col, pos, wsno)
      of "macro":
        result = initToken(lex, tkMacro, move lex.strbuf, line, col, pos, wsno)
      of "break":
        result = initToken(lex, tkBreakCmd, move lex.strbuf, line, col, pos, wsno)
      of "var":
        result = initToken(lex, tkVar, move lex.strbuf, line, col, pos, wsno)
      of "let":
        result = initToken(lex, tkLet, move lex.strbuf, line, col, pos, wsno)
      of "const":
        result = initToken(lex, tkConst, move lex.strbuf, line, col, pos, wsno)
      of "return":
        result = initToken(lex, tkReturn, move lex.strbuf, line, col, pos, wsno)
      of "discard":
        result = initToken(lex, tkDiscardCmd, move lex.strbuf, line, col, pos, wsno)
      of "continue":
        result = initToken(lex, tkContinueCmd, move lex.strbuf, line, col, pos, wsno)
      of "echo":
        result = initToken(lex, tkEcho, move lex.strbuf, line, col, pos, wsno)
      of "yield":
        result = initToken(lex, tkYield, move lex.strbuf, line, col, pos, wsno)
      of "mod":
        result = initToken(lex, tkMod, move lex.strbuf, line, col, pos, wsno)
      of "nil":
        result = initToken(lex, tkNil, move lex.strbuf, line, col, pos, wsno)
      else:
        result = initToken(lex, tkIdentifier, move lex.strbuf, line, col, pos, wsno)
    else:
      result = initToken(lex, tkUnknown, $lex.current, line, col, pos, wsno)
      lex.advance()

proc getToken*(lex: var Lexer): TokenTuple =
  result = lex.nextToken()
