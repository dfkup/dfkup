# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/[macros, strutils]
import pkg/vancode/interpreter/[errors, ast, sym]
import ./lexer
import ./staticeval

type
  Parser* = object
    lex: Lexer
    prev, curr, next: TokenTuple
    fwdDecl: seq[Node]

  DfkupParserError* = object of ValueError
    ln*, col*: int

const
  MathOperators = {tkPlus, tkMinus, tkAsterisk, tkDivide, tkMod}
  LogicalOperators = {tkAnd, tkAndAnd, tkOr, tkOrOr}
  ComparisonOperators = {tkEq, tkNe, tkGt, tkGte, tkLt, tkLte}
  Operators = ComparisonOperators + MathOperators + {tkAmp, tkAssign, tkCaret, tkIs, tkIsNot}
  Strings = {tkSqString, tkString, tkBacktick}
    # `tkBacktick` carries a raw string with no escape processing, which is what
    # the lexer already produces for `like this`. It was tokenised but not
    # parseable before, so every backtick string was a syntax error.
  Assignables = {tkBool, tkInteger, tkFloat, tkIdentifier, tkNil, tkIdentVar,
      tkDollar} + Strings
    # `tkDollar` is in the set so `echo $x` parses as a call rather than a
    # bare identifier followed by a separate statement.

  ThenPrecedence = 1
    ## Binding power of `then` in `await f() then g(x)`. Matches assignment,
    ## so the continuation is the loosest thing `await`'s operand can bind.

  DollarPrecedence = 26
    ## Binding power of the `$` prefix. Above every arithmetic operator but
    ## below `.` and `[`, so `$d["k"]` interpolates the element and `"x" & $f(1)`
    ## interpolates only the call's result.

  PostfixPrecedence = 40
    ## Binding power of the postfix operators `.` and `[`, and the floor for
    ## `await`'s operand. `await` binds a postfix chain (`f()`, `a.b`,
    ## `d["k"]`) and stops before every binary operator, so `await f() & "x"`
    ## is `(await f()) & "x"`. `then` is looser still, so `await f() then g()`
    ## leaves the continuation to the enclosing expression. The operand has to
    ## be a coroutine call or a coroutine value, so `await (a & b)` is not a
    ## way to group a compound expression.

proc error(tk: TokenTuple, msg: string) =
  raise (ref DfkupParserError)(
    ln: tk.line, col: tk.col,
    msg: msg
  )

proc skipNextComment(p: var Parser) =
  while true:
    case p.next.kind
    of tkComment:
      p.next = p.lex.getToken()
    else: break

template ruleGuard(body) =
  when declared(result):
    let
      ln = p.curr.line
      col = p.curr.col
  body
  when declared(result):
    if result != nil:
      result.ln = ln
      result.col = col

macro rule(pc) =
  if pc[6].kind != nnkEmpty:
    pc[6] = newCall("ruleGuard", newStmtList(pc[6]))
  pc

type
  PrefixFunction* = proc (p: var Parser, minPrec = 0): Node

macro prefixHandle(name: untyped, body: untyped) =
  name.newProc(
    [ident("Node"),
     nnkIdentDefs.newTree(ident"p", nnkVarTy.newTree(ident"Parser"), newEmptyNode()),
     nnkIdentDefs.newTree(ident"minPrec", ident"int", newLit(0))],
    body, pragmas = nnkPragma.newTree(ident"rule")
  )

proc walk(p: var Parser, offset = 1) =
  var i = 0
  while offset > i:
    inc i
    p.prev = p.curr
    p.curr = p.next
    p.next = p.lex.getToken()
    p.skipNextComment()

proc walkOpt(p: var Parser, kind: TokenKind) =
  if p.curr.kind == kind:
    walk(p)

proc walkOptSemiColon(p: var Parser) =
  if p.curr.kind == tkScolon:
    walk(p)

template expectWalk(k: TokenKind) =
  if likely(p.curr.kind == k):
    walk p
  else: return nil

template expectWalk(k: TokenKind, bdy) =
  if likely(p.curr.kind == k):
    walk p
    bdy
  else: return

proc skipComments(p: var Parser) =
  while p.curr.kind == tkComment:
    walk p

template caseNotNil(x: Node, body): untyped =
  if likely(x != nil):
    body
  else: return nil

template caseNotNil(x: Node, body, then): untyped =
  if likely(x != nil):
    body
  else: then

proc isInfix(p: var Parser): bool {.inline.} =
  p.curr.kind in Operators

proc isInfix(tk: TokenTuple): bool {.inline.} =
  tk.kind in Operators

proc `isnot`(tk: TokenTuple, kind: TokenKind): bool {.inline.} =
  tk.kind != kind

proc `is`(tk: TokenTuple, kind: TokenKind): bool {.inline.} =
  tk.kind == kind

proc `in`(tk: TokenTuple, kind: set[TokenKind]): bool {.inline.} =
  tk.kind in kind

proc `notin`(tk: TokenTuple, kind: set[TokenKind]): bool {.inline.} =
  tk.kind notin kind

proc parseStmt(p: var Parser, minPrec = 0): Node
proc parsePrefix(p: var Parser, minPrec = 0): Node
proc parseExpression(p: var Parser, minPrec = 0): Node
proc parseIdent(p: var Parser, minPrec = 0): Node
proc parseCall(p: var Parser, minPrec = 0): Node
proc parseImport(p: var Parser, minPrec = 0): Node
proc parseGenericType(p: var Parser, lhs: Node): Node
proc parsePrefixPlus(p: var Parser, minPrec = 0): Node
proc parsePrefixNegate(p: var Parser, minPrec = 0): Node
proc parsePrefixNot(p: var Parser, minPrec = 0): Node
proc parseWhenSelected(p: var Parser): (seq[Node], TokenTuple)

prefixHandle parseBoolean:
  let v =
    try: parseBool(p.curr.value)
    except ValueError: return nil
  result = ast.newBoolLit(v)
  walk p

prefixHandle parseInteger:
  let v =
    try: parseInt(p.curr.value)
    except ValueError: return nil
  result = ast.newIntLit(v)
  walk p

prefixHandle parseFloat:
  let v =
    try: parseFloat(p.curr.value)
    except ValueError: return nil
  result = ast.newFloatLit(v)
  walk p

prefixHandle parseNil:
  result = ast.newNil()
  walk p

prefixHandle parseString:
  result = ast.newStringLit(p.curr.value)
  walk p

proc parseCommaList(p: var Parser, start, term: static TokenKind,
  results: var seq[Node], infixList: static bool = false,
  advanceToken: static bool = true): bool =
  when advanceToken == true:
    walk p
  if p.curr isnot term:
    while p.curr isnot tkEof:
      when infixList == true:
        if p.curr in {tkIdentifier, tkType} + Strings:
          let nodeKey: Node = p.createIdentNode()
          if p.curr.is tkColon:
            walk p
            let nodeVal: Node = p.parseExpression()
            if nodeVal == nil:
              return false
            let colonExpr = ast.newNode(nkColon)
            colonExpr.add([nodeKey, nodeVal])
            results.add(colonExpr)
          else:
            return false
        else:
          return false
      else:
        let lhs: Node = p.parseExpression()
        if lhs == nil:
          return false
        results.add(lhs)
      if p.curr is tkComma:
        walk p
      if p.curr is term:
        walk p; break
  else: walk p
  result = true

proc parseCommaIdentList(p: var Parser, start,
      term: static TokenKind, results: var seq[Node]): bool =
  walk p
  if p.curr isnot term:
    while p.curr isnot tkEof:
      let def: Node = p.parseIdentDefs()
      caseNotNil def:
        results.add(def)
      do: return false
      case p.curr.kind
      of tkComma, tkScolon:
        walk p
      of term:
        walk p; break
      else: return
  else: walk p
  result = true

proc parseBlock(p: var Parser, indentPos = 0,
            parseFnBlock: static bool = false): Node {.rule.} =
  var
    closingBlock: bool
    stmts = newSeq[Node](0)
  if p.curr is tkLC:
    closingBlock = true
    walk p
  elif p.curr is (
      when parseFnBlock == true: tkAssign
                            else: tkColon
      ): walk p
  var closed = not closingBlock
  while p.curr isnot tkEof:
    if closingBlock and p.curr is tkRC:
      walk p; closed = true; break
    elif not closingBlock and p.curr.col <= indentPos: break
    let subNode = p.parseStmt()
    if subNode != nil:
      if subNode.kind == nkStatic:
        # inline the selected `when` branch into the enclosing scope
        stmts.add(subNode.children)
      else:
        stmts.add(subNode)
    else:
      break
  # An indent-based block ends at the dedent (or at EOF, which is fine), but a
  # brace-based one has an explicit terminator. Without this check an
  # unterminated `{` swallowed every following statement, so a missing brace
  # surfaced as a confusing error far downstream -- or silently compiled.
  if not closed:
    raise (ref DfkupParserError)(
      ln: p.curr.line, col: p.curr.col,
      msg: "`}` is expected here"
    )
  result = ast.newTree(nkBlock, stmts)

prefixHandle parseForLoop:
  let tokenFor: TokenTuple = p.curr
  if p.next.kind in {tkIdentVar, tkIdentifier}:
    walk p
    var itemVar: Node
    if p.next is tkComma:
      itemVar = ast.newTree(nkBracket)
      itemVar.add(ast.newIdent(p.curr.value))
      walk p, 2
      itemVar.add(ast.newIdent(p.curr.value))
    else:
      itemVar = ast.newIdent(p.curr.value)
    walk p
    expectWalk(tkIn)
    let iterExpr: Node = p.parseExpression()
    caseNotNil iterExpr:
      let body: Node = p.parseBlock(tokenFor.col)
      caseNotNil body:
        result = ast.newTree(nkFor, itemVar, iterExpr, body)

prefixHandle parseWhileLoop:
  let tokenWhile: TokenTuple = p.curr
  walk p
  let whileExpr: Node = p.parseExpression()
  caseNotNil whileExpr:
    let whileBlock: Node = p.parseBlock(tokenWhile.col)
    caseNotNil whileBlock:
      result = ast.newTree(nkWhile, whileExpr, whileBlock)

prefixHandle parseIf:
  let tokenIf: TokenTuple = p.curr
  walk p
  let ifExpr: Node = p.parseExpression()
  caseNotNil ifExpr:
    var children = @[ifExpr]
    var braced = p.curr is tkLC
    let ifBlock: Node = p.parseBlock(tokenIf.col)
    caseNotNil ifBlock:
      children.add(ifBlock)
    # `elif`/`else` are allowed when:
    #   - the block is brace-delimited, OR
    #   - still on the same line (single-line `if: a else: b`), OR
    #   - indentation-based block at matching column
    while p.curr is tkElif and (braced or p.curr.line == tokenIf.line or p.curr.col == tokenIf.col):
      let tokenElif = p.curr
      walk p
      let elifExpr: Node = p.parseExpression()
      caseNotNil elifExpr:
        braced = p.curr is tkLC
        let elifBlock: Node = p.parseBlock(tokenIf.col)
        caseNotNil elifBlock:
          children.add(@[elifExpr, elifBlock])
    if p.curr is tkElse and (braced or p.curr.line == tokenIf.line or p.curr.col == tokenIf.col):
      walk p
      let elseBlock: Node = p.parseBlock(tokenIf.col)
      caseNotNil elseBlock:
        children.add(elseBlock)
    result = ast.newTree(nkIf, children)

proc parseWhenSelected(p: var Parser): (seq[Node], TokenTuple) =
  ## Parse a `when`/`elif`/`else` chain and return only the branch whose
  ## condition held at parse time.
  ##
  ## Written with explicit `if ... != nil` guards rather than `caseNotNil`,
  ## because that template yields `nil` on a miss, which does not typecheck as
  ## this tuple return.
  let tokenWhen: TokenTuple = p.curr
  walk p
  var selected = newSeq[Node](0)
  var matched = false
  var braced: bool
  let condExpr: Node = p.parseExpression()
  if condExpr != nil:
    braced = p.curr is tkLC
    let whenBlock: Node = p.parseBlock(tokenWhen.col)
    if whenBlock != nil:
      try:
        if evalStaticBool(condExpr):
          selected = whenBlock.children
          matched = true
      except StaticEvalError as e:
        raise (ref DfkupParserError)(ln: e.ln, col: e.col, msg: e.msg)
    while p.curr is tkElif and (braced or p.curr.line == tokenWhen.line or p.curr.col == tokenWhen.col):
      walk p
      let elifExpr: Node = p.parseExpression()
      if elifExpr != nil:
        braced = p.curr is tkLC
        let elifBlock: Node = p.parseBlock(tokenWhen.line)
        if elifBlock != nil and not matched:
          try:
            if evalStaticBool(elifExpr):
              selected = elifBlock.children
              matched = true
          except StaticEvalError as e:
            raise (ref DfkupParserError)(ln: e.ln, col: e.col, msg: e.msg)
    if p.curr is tkElse and (braced or p.curr.line == tokenWhen.line or p.curr.col == tokenWhen.col):
      walk p
      let elseBlock: Node = p.parseBlock(tokenWhen.line)
      if elseBlock != nil and not matched:
        selected = elseBlock.children
        matched = true
  result = (selected, tokenWhen)

prefixHandle parseWhen:
  ## Compile-time conditional, mirroring Nim's `when`. The condition is
  ## evaluated at parse time and only the selected branch is emitted,
  ## inlined into the enclosing scope (via an nkStatic marker node).
  # always return a node (never nil) so block/script loops don't stop;
  # parseBlock/parseScript splice nkStatic children into the statement list
  let (selected, _) = p.parseWhenSelected()
  result = ast.newTree(nkStatic, selected)

prefixHandle parseWhenExpr:
  ## `when` in expression position, where a single expression is required
  ## rather than a statement list. This is what makes an object field able to
  ## pick a value at parse time:
  ##   {name: when defined osx: "test" else: "x"}
  let (selected, tokenWhen) = p.parseWhenSelected()
  if selected.len != 1:
    p.curr.error("a `when` used as a value must have exactly one " &
      "expression in the branch it selects, got " & $selected.len)
  result = selected[0]

prefixHandle parseIdent:
  result = ast.newIdent(p.curr.value)
  walk p

proc parseTypeName(p: var Parser): Node =
  ## Parse a type name: a bare `Veg` or a qualified `veggie.Veg` naming a type
  ## from an `import ... as veggie`.
  result = p.parseIdent()
  if p.curr is tkDot and p.next is tkIdentifier:
    walk p
    result = ast.newTree(nkDot, result, p.parseIdent())

prefixHandle parseIdentVar:
  result = ast.newIdent(p.curr.value)
  result.ln = p.curr.line
  result.col = p.curr.col
  walk p
  if p.curr is tkAssign:
    walk p
    let valNode: Node = p.parseExpression()
    caseNotNil valNode:
      result = ast.newInfix(ast.newIdent("="), result, valNode)

prefixHandle parseDollar:
  ## `$expr` renders `expr` as a string. It accepts any expression, so
  ## `$len(x)`, `$a.b` and `$f(1) + "!"` all work, not just `$name`.
  ## Lowers to a plain `toStr` call so ordinary call codegen handles it.
  let dollarPos = p.curr.line
  walk p
  # bind tighter than any infix operator but looser than `.` and `[`, so
  # `$d["k"]` interpolates the element and `"x" & $f(1)` interpolates only
  # the call's result
  let exprNode: Node = p.parseExpression(minPrec = DollarPrecedence)
  if exprNode == nil: return
  result = ast.newCall(ast.newIdent("toStr", dollarPos, p.curr.col), exprNode)

proc createIdentNode(p: var Parser): Node {.rule.} =
  result = ast.newIdent(p.curr.value)
  walk p

proc getVarIdent(p: var Parser, varIdent: bool): Node {.rule.} =
  result = p.createIdentNode()
  if varIdent:
    if p.curr is tkAsterisk:
      walk p
      return ast.newNode(nkPostfix).add([ast.newIdent("*"), result])

proc parseIdentDefs(p: var Parser): Node {.rule.} =
  result = newNode(nkIdentDefs)
  if p.curr.kind == tkIdentifier:
    let identNode = p.getVarIdent(true)
    var
      ty = newEmpty()
      val = newEmpty()
      vars: seq[Node]
    vars.add(identNode)
    while p.curr.kind != tkEof:
      case p.curr.kind
      of tkColon:
        walk p
        if p.curr is tkIdentifier:
          # `parseTypeName` also accepts `veggie.Veg`, the qualified form for a
          # type reached through `import ... as veggie`.
          ty = p.parseTypeName()
          if p.curr is tkLB:
            ty = p.parseGenericType(ty)
        elif p.curr is tkVar:
          ty = ast.newNode(nkVarTy)
          if p.next is tkIdentifier:
            ty.varType = ast.newIdent(p.next.value)
            walk p, 2
      of tkAssign:
        walk p
        val = p.parseExpression(minPrec = 0)
        break
      of tkComma:
        if ty.kind == nkEmpty and p.next is tkIdentifier:
          walk p
          vars.add(p.parseExpression())
        else: break
      else: break
    vars.add([ty, val])
    result.add(vars)

proc parseVarIdent(p: var Parser): Node {.rule.} =
  result = ast.newNode(nkIdentDefs)
  while true:
    let identNode = p.getVarIdent(true)
    var
      ty = newEmpty()
      val = newEmpty()
    if p.curr.kind == tkColon:
      walk p
      if p.curr.kind == tkIdentifier:
        ty = p.parseIdent()
        if p.curr.kind == tkLB:
          ty = p.parseGenericType(ty)
      else:
        p.curr.error("Expected type after ':'")
    if p.curr.kind == tkAssign:
      walk p
      val = p.parseExpression()
    result.add(ast.newTree(nkAssign, identNode, ty, val))
    if p.curr.kind == tkComma:
      if p.next.kind == tkIdentifier and p.next.col == identNode.col:
        walk p
      else: break
    else: break

prefixHandle parseVar:
  case p.curr.kind
  of tkVar:
    result = ast.newNode(nkVar)
  of tkLet:
    result = ast.newNode(nkLet)
  of tkConst:
    result = ast.newNode(nkConst)
  else: discard
  walk p
  result.add(p.parseVarIdent())

proc parseGenericType(p: var Parser, lhs: Node): Node =
  walk p
  let genericType = p.parseIdent()
  caseNotNil genericType:
    result = ast.newNode(nkIndex).add(lhs)
    result.add(genericType)
    if p.curr is tkLB:
      result = p.parseGenericType(result)
    expectWalk(tkRB)

proc parseFunctionHead(p: var Parser, isAnon: bool;
                name, genericParams, formalParams: var Node) =
  if not isAnon:
    name = ast.newIdent(p.curr.value)
    walk p
    if p.curr is tkAsterisk:
      walk p
      name = ast.newNode(nkPostfix).add([ast.newIdent("*"), name])
  else:
    name = ast.newEmpty()
  if p.curr is tkLB:
    genericParams = ast.newNode(nkGenericParams)
    var params: seq[Node]
    if p.parseCommaIdentList(tkLB, tkRB, params):
      genericParams.add(params)
  else:
    genericParams = ast.newEmpty()
  formalParams = newTree(nkFormalParams, newEmpty())
  if p.curr is tkLP:
    var params: seq[Node]
    if p.parseCommaIdentList(tkLP, tkRP, params):
      formalParams.add(params)
  # A return type may be a bare name or a qualified name from an aliased import,
  # as in `f(v: veggie.Veg): veggie.Veg`. `tkDot` is absent from the guard
  # because a qualified name is the one case the bare `parseIdent` cannot read.
  if p.curr is tkColon and p.next in {tkIdentifier, tkLitObject}:
    walk p
    formalParams[0] = p.parseTypeName()

prefixHandle parseFunction:
  let fnpos = p.curr.col
  walk p
  var name, genericParams, formalParams: Node
  let isAnon = p.curr.kind != tkIdentifier
  parseFunctionHead(p, isAnon, name, genericParams, formalParams)
  if p.curr in {tkAssign, tkLC}:
    let fnBlock: Node = p.parseBlock(fnpos, parseFnBlock = true)
    caseNotNil fnBlock:
      result = ast.newTree(nkProc, name, genericParams, formalParams, fnBlock)
  else:
    # forward declaration: function head without body
    result = ast.newTree(nkProc, name, genericParams, formalParams, ast.newEmpty())
    p.fwdDecl.add(result)

prefixHandle parseIterator:
  let tokenIterator = p.curr.col
  walk p
  var name, genericParams, formalParams: Node
  parseFunctionHead(p, isAnon = false, name, genericParams, formalParams)
  if p.curr in {tkAssign, tkLC}:
    let fnBlock: Node = p.parseBlock(tokenIterator, parseFnBlock = true)
    caseNotNil fnBlock:
      result = ast.newTree(nkIterator, name, genericParams, formalParams, fnBlock)

prefixHandle parseCoroutine:
  let coroPos = p.curr.col
  walk p  # skip 'async'
  if p.curr.kind notin {tkFunc, tkFn}:
    p.curr.error("expected 'func' or 'fn' after 'async'")
  walk p  # skip 'func'/'fn'
  var name, genericParams, formalParams: Node
  parseFunctionHead(p, isAnon = false, name, genericParams, formalParams)
  if p.curr in {tkAssign, tkLC}:
    let fnBlock: Node = p.parseBlock(coroPos, parseFnBlock = true)
    caseNotNil fnBlock:
      result = ast.newTree(nkCoroutine, name, genericParams, formalParams, fnBlock)

prefixHandle parseCall:
  let fnName = ast.newIdent(p.curr.value, p.curr.line, p.curr.col)
  result = ast.newCall(fnName)
  var expectRP: bool
  walk p
  if p.curr.kind == tkLP:
    expectRP = true
    walk p
  if p.curr isnot tkRP:
    while true:
      if p.curr.kind == tkIdentVar and p.next.kind == tkAssign:
        let name = ast.newIdent(p.curr.value)
        walk p
        walk p
        let value = p.parseExpression()
        let namedArg = ast.newTree(nkColon, name, value)
        result.add(namedArg)
      else:
        if p.next.kind == tkColon:
          discard p.parseCommaList(tkLP, tkRP, result.children,
                                 infixList = true, advanceToken = false)
          break
        else:
          let arg = p.parseExpression()
          caseNotNil arg:
            result.add(arg)
      case p.curr.kind
      of tkComma:
        walk p
      of tkRP:
        if expectRP:
          walk p
        break
      of tkEof:
        break
      else: break
  else: walk p

prefixHandle parseArray:
  result = ast.newTree(nkArray)
  discard p.parseCommaList(tkLB, tkRB, result.children)
  p.walkOpt(tkScolon)

prefixHandle parseObjectStorage:
  result = ast.newTree(nkObjectStorage)
  discard p.parseCommaList(tkLC, tkRC, result.children, infixList = true)

prefixHandle parseParExpr:
  walk p
  result = p.parseExpression()
  expectWalk(tkRP)

prefixHandle parseBreak:
  result = ast.newTree(nkBreak)
  walk p
  p.walkOpt(tkScolon)

prefixHandle parseDiscard:
  result = ast.newTree(nkDiscard)
  walk p
  if p.curr.line == p.prev.line:
    let exprNode = p.parseExpression()
    caseNotNil exprNode:
      result.add(exprNode)
  p.walkOpt(tkScolon)

prefixHandle parseReturn:
  result = ast.newTree(nkReturn)
  walk p
  if p.curr.line == p.prev.line:
    let exprNode: Node = p.parseExpression()
    caseNotNil exprNode:
      result.add(exprNode)
      p.walkOpt(tkScolon)

prefixHandle parseYield:
  result = ast.newTree(nkYield)
  walk p
  let exprNode: Node = p.parseExpression()
  caseNotNil exprNode:
    result.add(exprNode)
    p.walkOpt(tkScolon)

prefixHandle parseAwait:
  result = ast.newTree(nkAwait)
  walk p
  # `await` binds as tightly as a postfix operator, so its operand is just a
  # primary plus any `.` / `[` chain. Every binary operator, including the
  # `then` continuation, is left to the enclosing expression -- that is what
  # makes `await f() & "x"` mean `(await f()) & "x"` and lets `then` attach to
  # the whole `await` rather than to its operand.
  let exprNode: Node = p.parseExpression(minPrec = PostfixPrecedence)
  caseNotNil exprNode:
    result.add(exprNode)

prefixHandle parseEcho:
  result = ast.newTree(nkCall)
  result.add(ast.newIdent("echo"))
  walk p
  let exprNode: Node = p.parseExpression()
  caseNotNil exprNode:
    result.add(exprNode)
    p.walkOpt(tkScolon)

prefixHandle parseAssert:
  result = ast.newTree(nkCall)
  result.add(ast.newIdent("assert"))
  walk p
  let exprNode: Node = p.parseExpression()
  caseNotNil exprNode:
    result.add(exprNode)
    p.walkOpt(tkScolon)

prefixHandle parseImport:
  if p.curr.value == "import":
    walk p  # consume import
    if p.curr.kind in Strings:
      result = ast.newNode(nkImport)
      result.add(ast.newStringLit(p.curr.value))
      walk p  # consume string literal
      # `import "x" as alias` binds the module under a name, which is how a
      # type that exists in two imported files is referred to unambiguously:
      # `alias.Veg`.
      if p.curr.value == "as":
        walk p  # consume 'as'
        if p.curr.kind == tkIdentifier:
          result.add(ast.newIdent(p.curr.value))
          walk p  # consume the alias
        else:
          p.curr.error("expected an identifier after 'as'")
  elif p.curr.value == "include":
    walk p  # consume include
    if p.curr.kind in Strings:
      result = ast.newNode(nkInclude)
      result.add(ast.newStringLit(p.curr.value))
      walk p  # consume string literal

prefixHandle parseDocComment:
  result = ast.newNode(nkDocComment)
  result.comment = p.curr.value
  walk p

proc parseEnumBody(p: var Parser, typeIdent: Node, typeDefCol: int): Node =
  ## Parse the indented field list of `type Name = enum`.
  ##
  ## A field is either a bare `name`, which stands for itself, or
  ## `name = "value"`, which carries an explicit value:
  ##
  ##   type Fruits = enum
  ##     apple = "Apple"
  ##     strawberry
  ##
  ## Fields are collected as `nkEnumField` nodes and hang off the enum's
  ## `enumFields`; the enum's own identifier stays on `enumName` so
  ## `Fruits.apple` can be resolved to just this enum's fields later.
  result = ast.newNode(nkEnumDef)
  result.ln = typeIdent.ln
  result.col = typeIdent.col
  result.enumName = typeIdent
  var seen: seq[string]
  while p.curr.kind != tkEof:
    if p.curr.kind == tkIdentifier and p.curr.col > typeDefCol:
      let
        fieldName = p.curr.value
        fieldLn = p.curr.line
        fieldCol = p.curr.col
      # Duplicate detection uses the canonical form, so `apple` and `APPLE`
      # collide the same way they will once codegen normalizes field names.
      if lowerName(fieldName) in seen:
        p.curr.error(ErrDuplicateEnumField % [fieldName, typeIdent.ident])
      seen.add(lowerName(fieldName))
      walk p
      # `field = "value"` gives an explicit value; a bare `field` is its own
      # value, which is what Nim does too.
      var value = fieldName
      if p.curr.kind == tkAssign:
        walk p
        if p.curr.kind notin Strings:
          p.curr.error(ErrEnumFieldValue % fieldName)
        value = p.curr.value
        walk p
      var field = ast.newNode(nkEnumField)
      # line/column are kept on the node itself so errors and `ast --dumptree`
      # point at the field as written.
      field.ln = fieldLn
      field.col = fieldCol
      field.fieldName = fieldName
      field.fieldValue = value
      result.enumFields.add(field)
    else: break

prefixHandle parseTypeDef:
  result = ast.newTree(nkTypeDef)
  result.ln = p.curr.line
  result.col = p.curr.col
  walk p
  # A `type` block may declare more than one type, one per indented line:
  #
  #   type
  #     Fruits = enum
  #       apple
  #     BadFruits = enum
  #       apple
  #
  # so declarations are collected in a loop instead of one ident per keyword.
  # `declCol` is the column of the first declaration; anything further right
  # than that is a body, anything equal is the next declaration.
  let declCol = p.curr.col
  while p.curr.kind == tkIdentifier and p.curr.col == declCol:
    var typeIdent = ast.newIdent(p.curr.value)
    typeIdent.ln = p.curr.line
    typeIdent.col = p.curr.col
    walk p
    # `type Veg* = enum` marks the type as exported, matching `func f*()`.
    # Without this a type declared in an imported file is invisible there.
    if p.curr is tkAsterisk:
      # wrap as a postfix marker, the same shape `newProc` reads for `f*()`
      typeIdent = ast.newNode(nkPostfix).add([ast.newIdent("*"), typeIdent])
      walk p
    let typeDefCol =
      if result.ln == typeIdent.ln: result.col
      else: typeIdent.col
    if p.curr is tkLB:
      typeIdent = p.parseGenericType(typeIdent)
    expectWalk(tkAssign)
    case p.curr.kind
    of tkLitObject:
      walk p
      var objectDef = newNode(nkObject)
      var fieldDefs = newNode(nkRecFields)
      while p.curr.kind != tkEof:
        if p.curr.kind == tkIdentifier and p.curr.col > typeDefCol:
          let fieldDef: Node = p.parseIdentDefs()
          caseNotNil fieldDef:
            fieldDefs.add(fieldDef)
        else: break
      objectDef.add(typeIdent)
      objectDef.add(fieldDefs)
      result.add(objectDef)
    of tkEnum:
      walk p
      result.add(p.parseEnumBody(typeIdent, typeDefCol))
    else: break

proc getPrefixFn(p: var Parser, minPrec: int): PrefixFunction =
  result =
    case p.curr.kind
    of tkBool: parseBoolean
    of tkInteger: parseInteger
    of tkFloat: parseFloat
    of tkNil: parseNil
    of Strings: parseString
    of tkIdentVar: parseIdentVar
    of tkDollar: parseDollar
    of tkIf: parseIf
    of tkIdentifier:
      if p.next is tkLP and p.next.line == p.curr.line:
        parseCall
      elif p.next.kind in Assignables and (p.next.line == p.curr.line or p.next.col > p.curr.col):
        parseCall
      else:
        parseIdent
    of tkFor: parseForLoop
    of tkWhile: parseWhileLoop
    of tkReturn: parseReturn
    of tkBreakCmd: parseBreak
    of tkDiscardCmd: parseDiscard
    of tkFunc, tkFn: parseFunction
    of tkIterator: parseIterator
    of tkCoroutine: parseCoroutine
    of tkWhen: parseWhenExpr
    of tkLP: parseParExpr
    of tkLB: parseArray
    of tkLC: parseObjectStorage
    of tkYield: parseYield
    of tkAwait: parseAwait
    of tkEcho: parseEcho
    of tkAssert: parseAssert
    of tkVar, tkLet, tkConst: parseVar
    of tkDoc: parseDocComment
    of tkType: parseTypeDef
    of tkPlus: parsePrefixPlus
    of tkMinus: parsePrefixNegate
    of tkNot, tkExc: parsePrefixNot
    of tkImport, tkInclude: parseImport
    else: nil

prefixHandle parsePrefixPlus:
  walk p
  result = p.parseExpression(minPrec)

prefixHandle parsePrefixNegate:
  walk p
  let expr = p.parseExpression(10)
  result = ast.newInfix(ast.newIdent("-"), ast.newIntLit(0), expr)

prefixHandle parsePrefixNot:
  walk p
  let expr = p.parseExpression(9)
  result = ast.newTree(nkPrefix, ast.newIdent("not"), expr)

prefixHandle parsePrefix:
  let parseFn = p.getPrefixFn(minPrec)
  if parseFn != nil:
    return parseFn(p)

proc getPrecedence(op: string): int {.inline.} =
  case op
  of "+", "-": 10
  of "*", "/", "%": 20
  of ".": 45
  of "[": 40
  of "==", "!=", ">", "<", ">=", "<=": 5
  of "and", "&&": 3
  of "or", "||": 2
  of "&": 6
  of "^": 25
  of "then": ThenPrecedence
  of "=": 1
  else: 0

proc isInfix(kind: TokenKind, minPrec = 0): (bool, int, string) {.inline.} =
  var opStr: string
  case kind
  of tkPlus: opStr = "+"
  of tkMinus: opStr = "-"
  of tkAsterisk: opStr = "*"
  of tkDivide: opStr = "/"
  of tkMod: opStr = "%"
  of tkCaret: opStr = "^"
  of tkGt: opStr = ">"
  of tkGte: opStr = ">="
  of tkLt: opStr = "<"
  of tkLte: opStr = "<="
  of tkEq: opStr = "=="
  of tkNe: opStr = "!="
  of tkAmp: opStr = "&"
  of tkAssign: opStr = "="
  of tkDot: opStr = "."
  of tkLB: opStr = "["
  of tkAnd: opStr = "and"
  of tkAndAnd: opStr = "&&"
  of tkOr: opStr = "or"
  of tkOrOr: opStr = "||"
  of tkIs: opStr = "is"
  of tkIsNot: opStr = "isnot"
  of tkThen: opStr = "then"
  else: return (false, 0, "")
  let prec = getPrecedence(opStr)
  result = (prec > minPrec, prec, opStr)

proc parseThen(p: var Parser, awaited: Node): Node =
  ## Parses the continuation after `then` in `await coroExpr then proc(args)`.
  ## The continuation is a direct call to a named proc; the awaited result is
  ## passed as its first argument.
  if p.curr.kind != tkIdentifier:
    p.curr.error("expected a proc name after 'then'")
  let callee = ast.newIdent(p.curr.value, p.curr.line, p.curr.col)
  var call = ast.newCall(callee)
  if p.next.kind == tkLP and p.next.line == p.curr.line:
    walk p  # consume the proc name
    walk p  # consume '('
    # the awaited value becomes the first argument
    call.add(awaited)
    if p.curr.kind != tkRP:
      while true:
        let arg = p.parseExpression()
        caseNotNil arg:
          call.add(arg)
        if p.curr.kind != tkComma:
          break
        walk p
    expectWalk(tkRP)
  else:
    call.add(awaited)
  ast.newTree(nkThen, awaited, call)

proc parseExpression(p: var Parser, minPrec = 0): Node =
  var lhs = p.parsePrefix(minPrec)
  caseNotNil lhs:
    while true:
      var opStr: string
      var prec: int
      var isBracket = false
      var isDot = false
      case p.curr.kind
      of Operators, LogicalOperators:
        let inf = p.curr.kind.isInfix(minPrec)
        if not inf[0]: break
        opStr = inf[2]
        prec = inf[1]
      of tkDot:
        opStr = "."
        prec = getPrecedence(".")
        isDot = true
      of tkLB:
        opStr = "["
        prec = getPrecedence("[")
        isBracket = true
      of tkThen:
        opStr = "then"
        prec = getPrecedence("then")
      else: break
      if prec < minPrec: break
      walk p
      if opStr == "then":
        # `await coroExpr then proc(args)`: a sequential continuation.
        lhs = p.parseThen(lhs)
        continue
      if isBracket:
        let indexNode = p.parseExpression()
        expectWalk tkRB
        lhs = ast.newNode(nkBracket).add([lhs, indexNode])
      elif isDot:
        if p.curr is tkDot and p.curr.wsno == 0:
          walk p
          let rhs = p.parseExpression(minPrec = prec + 1)
          caseNotNil rhs:
            return ast.newCall(ast.newIdent("range"), lhs, rhs)
        let rhs = p.parseExpression(minPrec = prec + 1)
        lhs = ast.newTree(nkDot, lhs, rhs)
      else:
        let rhs = p.parseExpression(minPrec = prec)
        lhs = ast.newInfix(ast.newIdent(opStr), lhs, rhs)
    result = lhs

prefixHandle parseStmt:
  let prefixFn: PrefixFunction =
    case p.curr.kind
    of tkIdentifier:
      if p.next.line == p.curr.line and p.next is tkLP:
        parseCall
      elif p.next.kind in Assignables and (p.next.line == p.curr.line or p.next.col > p.curr.col):
        parseCall
      else:
        parseExpression
    of tkVar, tkLet, tkConst: parseVar
    of tkIf: parseIf
    of tkWhen: parseWhen
    of tkWhile: parseWhileLoop
    of tkFor: parseForLoop
    of tkFunc, tkFn: parseFunction
    of tkIterator: parseIterator
    of tkEcho: parseEcho
    of tkAssert: parseAssert
    of tkReturn: parseReturn
    of tkBreakCmd: parseBreak
    of tkDiscardCmd: parseDiscard
    of tkDoc: parseDocComment
    of tkType: parseTypeDef
    of tkImport, tkInclude: parseImport
    else: parseExpression
  if prefixFn != nil:
    return prefixFn(p)

proc parseScript*(astProgram: var Ast, code: string) =
  var p = Parser(lex: newLexer(code))
  p.curr = p.lex.getToken()
  p.next = p.lex.getToken()
  p.skipComments()
  astProgram = Ast()
  while p.curr.kind != tkEof:
    let node: Node = p.parseStmt()
    caseNotNil node:
      if node.kind == nkStatic:
        # inline the selected `when` branch into the top-level scope
        astProgram.nodes.add(node.children)
      else:
        astProgram.nodes.add(node)
    do:
      p.curr.error(ErrUnexpectedToken % $p.curr.kind)
  astProgram.forwardDecl = p.fwdDecl
