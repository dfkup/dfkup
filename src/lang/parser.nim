# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/[macros, strutils]
import pkg/vancode/interpreter/[errors, ast]
import ./lexer

type
  Parser* = object
    lex: Lexer
    prev, curr, next: TokenTuple

  DfkupParserError* = object of ValueError
    ln*, col*: int

const
  MathOperators = {tkPlus, tkMinus, tkAsterisk, tkDivide, tkMod}
  LogicalOperators = {tkAnd, tkAndAnd, tkOr, tkOrOr}
  ComparisonOperators = {tkEq, tkNe, tkGt, tkGte, tkLt, tkLte}
  Operators = ComparisonOperators + MathOperators + {tkAmp, tkAssign, tkCaret}
  Strings = {tkSqString, tkString}
  Assignables = {tkBool, tkInteger, tkFloat, tkIdentifier, tkNil, tkIdentVar} + Strings

proc error(tk: TokenTuple, msg: string) =
  raise (ref DfkupParserError)(
    ln: tk.line, col: tk.col,
    msg: ErrorFmt % ["", $tk.line, $tk.col, msg]
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
proc parseGenericType(p: var Parser, lhs: Node): Node

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
  while p.curr isnot tkEof:
    if closingBlock and p.curr is tkRC:
      walk p; break
    elif not closingBlock and p.curr.col <= indentPos: break
    let subNode = p.parseStmt()
    if subNode != nil:
      stmts.add(subNode)
    else:
      break
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
    let ifBlock: Node = p.parseBlock(tokenIf.col)
    caseNotNil ifBlock:
      children.add(ifBlock)
    while p.curr is tkElif:
      let tokenElif = p.curr
      walk p
      let elifExpr: Node = p.parseExpression()
      caseNotNil elifExpr:
        let elifBlock: Node = p.parseBlock(tokenIf.col)
        caseNotNil elifBlock:
          children.add(@[elifExpr, elifBlock])
    if p.curr is tkElse:
      walk p
      let elseBlock: Node = p.parseBlock(tokenIf.col)
      caseNotNil elseBlock:
        children.add(elseBlock)
    result = ast.newTree(nkIf, children)

prefixHandle parseIdent:
  result = ast.newIdent(p.curr.value)
  walk p

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
          ty = p.parseIdent()
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
  if p.curr is tkColon and p.next in {tkIdentifier, tkLitObject}:
    walk p
    formalParams[0] = p.parseIdent()

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

prefixHandle parseIterator:
  let tokenIterator = p.curr.col
  walk p
  var name, genericParams, formalParams: Node
  parseFunctionHead(p, isAnon = false, name, genericParams, formalParams)
  if p.curr in {tkAssign, tkLC}:
    let fnBlock: Node = p.parseBlock(tokenIterator, parseFnBlock = true)
    caseNotNil fnBlock:
      result = ast.newTree(nkIterator, name, genericParams, formalParams, fnBlock)

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

prefixHandle parseEcho:
  result = ast.newTree(nkCall)
  result.add(ast.newIdent("echo"))
  walk p
  let exprNode: Node = p.parseExpression()
  caseNotNil exprNode:
    result.add(exprNode)
    p.walkOpt(tkScolon)

prefixHandle parseDocComment:
  result = ast.newNode(nkDocComment)
  result.comment = p.curr.value
  walk p

prefixHandle parseTypeDef:
  result = ast.newTree(nkTypeDef)
  result.ln = p.curr.line
  result.col = p.curr.col
  walk p
  var typeIdent = ast.newIdent(p.curr.value)
  typeIdent.ln = p.curr.line
  typeIdent.col = p.curr.col
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
  else: discard

proc getPrefixFn(p: var Parser, minPrec: int): PrefixFunction =
  result =
    case p.curr.kind
    of tkBool: parseBoolean
    of tkInteger: parseInteger
    of tkFloat: parseFloat
    of tkNil: parseNil
    of Strings: parseString
    of tkIdentVar: parseIdentVar
    of tkIf: parseIf
    of tkIdentifier:
      if p.next is tkLP and p.next.line == p.curr.line:
        parseCall
      else:
        parseIdent
    of tkFor: parseForLoop
    of tkWhile: parseWhileLoop
    of tkReturn: parseReturn
    of tkBreakCmd: parseBreak
    of tkFunc, tkFn: parseFunction
    of tkIterator: parseIterator
    of tkLP: parseParExpr
    of tkLB: parseArray
    of tkLC: parseObjectStorage
    of tkYield: parseYield
    of tkEcho: parseEcho
    of tkVar, tkLet, tkConst: parseVar
    of tkDoc: parseDocComment
    of tkType: parseTypeDef
    else: nil

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
  else: return (false, 0, "")
  let prec = getPrecedence(opStr)
  result = (prec > minPrec, prec, opStr)

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
      else: break
      if prec < minPrec: break
      walk p
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
      else:
        parseExpression
    of tkVar, tkLet, tkConst: parseVar
    of tkIf: parseIf
    of tkWhile: parseWhileLoop
    of tkFor: parseForLoop
    of tkFunc, tkFn: parseFunction
    of tkIterator: parseIterator
    of tkEcho: parseEcho
    of tkReturn: parseReturn
    of tkBreakCmd: parseBreak
    of tkDoc: parseDocComment
    of tkType: parseTypeDef
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
      astProgram.nodes.add(node)
    do:
      p.curr.error(ErrUnexpectedToken % $p.curr.kind)
