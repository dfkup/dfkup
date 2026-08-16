# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup
#
# Compile-time (parse-time) static evaluation used by the `when` construct.
#
# dfkup always exposes information about the machine it is compiled for,
# which can be accessed at parse time from within `when` conditions:
#   - `hostOS`     (string)  e.g. "macosx", "windows", "linux"
#   - `hostCPU`    (string)  e.g. "amd64", "arm64"
#   - `cpuEndian`  (string)  e.g. "littleEndian" / "bigEndian"
#   - `dfkupVersion`(string) the dfkup package version
# plus the `defined("symbol")` function over machine-derived flags.

import pkg/vancode/interpreter/ast

type
  StaticKind* = enum
    skBool, skInt, skFloat, skString, skNil

  StaticValue* = object
    case kind*: StaticKind
    of skBool:   boolVal*: bool
    of skInt:    intVal*: int64
    of skFloat:  floatVal*: float64
    of skString: strVal*: string
    of skNil:    discard

  StaticEvalError* = object of ValueError
    ln*, col*: int

# ------------------------------------------------------------------
# Compile-time machine info (of the dfkup host binary)
# ------------------------------------------------------------------
const HostOS* = hostOS
const HostCPU* = hostCPU
const HostEndian* = $cpuEndian
const DfkupVersion* = "0.1.0"

const PosixOS* = HostOS notin ["windows", "standalone"]

proc defined*(symbol: string): bool =
  ## Check whether a machine-derived compile-time flag is set.
  case symbol
  of "posix":                       PosixOS
  of "windows", "win":              HostOS == "windows"
  of "linux":                       HostOS == "linux"
  of "macosx", "macos", "darwin":   HostOS == "macosx"
  of "freebsd":                     HostOS == "freebsd"
  of "openbsd":                     HostOS == "openbsd"
  of "netbsd":                      HostOS == "netbsd"
  of "amd64", "x86_64":             HostCPU in ["amd64", "x86_64"]
  of "arm64", "aarch64":            HostCPU in ["arm64", "aarch64"]
  of "i386", "x86":                 HostCPU == "i386"
  of "arm":                         HostCPU == "arm"
  of "littleEndian":                HostEndian == "littleEndian"
  of "bigEndian":                   HostEndian == "bigEndian"
  else: false

proc isTrue*(v: StaticValue): bool =
  ## Interpret a static value as a boolean (for `when` conditions).
  case v.kind
  of skBool:   v.boolVal
  of skInt:    v.intVal != 0
  of skFloat:  v.floatVal != 0
  of skNil:    false
  of skString: v.strVal.len > 0

proc staticError(node: Node, msg: string) =
  raise (ref StaticEvalError)(ln: node.ln, col: node.col, msg: msg)

proc resolveIdent(name: string, node: Node): StaticValue =
  ## Resolve an identifier that is either a compile-time machine constant
  ## or a bare machine-derived define flag.
  case name
  of "hostOS":        result = StaticValue(kind: skString, strVal: HostOS)
  of "hostCPU":       result = StaticValue(kind: skString, strVal: HostCPU)
  of "cpuEndian":     result = StaticValue(kind: skString, strVal: HostEndian)
  of "dfkupVersion":  result = StaticValue(kind: skString, strVal: DfkupVersion)
  else:
    # bare define flag, e.g. `when windows:` / `when posix and arm64:`
    if defined(name):
      result = StaticValue(kind: skBool, boolVal: true)
    else:
      staticError(node, "cannot evaluate `" & name &
        "` at compile time: not a known compile-time symbol")

proc numValue(v: StaticValue, node: Node): float64 =
  case v.kind
  of skInt: result = v.intVal.float64
  of skFloat: result = v.floatVal
  of skBool: result = if v.boolVal: 1.0 else: 0.0
  else: staticError(node, "expected a number, got a static " & $v.kind)

proc staticEqual(l, r: StaticValue): bool =
  ## Value equality for static values.
  if l.kind != r.kind: return false
  case l.kind
  of skBool:   l.boolVal == r.boolVal
  of skInt:    l.intVal == r.intVal
  of skFloat:  l.floatVal == r.floatVal
  of skString: l.strVal == r.strVal
  of skNil:    true

proc cmpStatic(l, r: StaticValue, node: Node): int =
  ## Ordering comparison for static values (int/float/string).
  case l.kind
  of skInt:
    if r.kind != skInt:
      staticError(node, "cannot order mixed static number types")
    result = cmp(l.intVal, r.intVal)
  of skFloat:
    if r.kind != skFloat:
      staticError(node, "cannot order mixed static number types")
    result = cmp(l.floatVal, r.floatVal)
  of skString:
    if r.kind != skString:
      staticError(node, "cannot order a static string against a non-string")
    result = cmp(l.strVal, r.strVal)
  else:
    staticError(node, "cannot order static values of kind " & $l.kind)

proc evalStatic*(node: Node): StaticValue {.gcsafe.} =
  ## Evaluate a constant expression at parse time.
  case node.kind
  of nkBool:
    result = StaticValue(kind: skBool, boolVal: node.boolVal)
  of nkInt:
    result = StaticValue(kind: skInt, intVal: node.intVal)
  of nkFloat:
    result = StaticValue(kind: skFloat, floatVal: node.floatVal)
  of nkString:
    result = StaticValue(kind: skString, strVal: node.stringVal)
  of nkNil:
    result = StaticValue(kind: skNil)
  of nkIdent:
    result = resolveIdent(node.ident, node)
  of nkPrefix:
    let rhs = evalStatic(node[1])
    case node[0].ident
    of "not", "!":
      result = StaticValue(kind: skBool, boolVal: not rhs.isTrue)
    of "-":
      result = StaticValue(kind: skFloat, floatVal: -rhs.numValue(node))
    else:
      staticError(node, "unsupported static prefix operator `" & node[0].ident & "`")
  of nkInfix:
    let op = node[0].ident
    # logical operators short-circuit
    if op in ["and", "or"]:
      let l = evalStatic(node[1])
      if op == "and":
        if not l.isTrue:
          return StaticValue(kind: skBool, boolVal: false)
        return StaticValue(kind: skBool, boolVal: evalStatic(node[2]).isTrue)
      else:
        if l.isTrue:
          return StaticValue(kind: skBool, boolVal: true)
        return StaticValue(kind: skBool, boolVal: evalStatic(node[2]).isTrue)
    let
      l = evalStatic(node[1])
      r = evalStatic(node[2])
    case op
    of "+", "-", "*", "/", "%":
      let isInt = l.kind == skInt and r.kind == skInt
      if isInt:
        let li = l.intVal
        let ri = r.intVal
        if op in ["/", "%"] and ri == 0:
          staticError(node, "division by zero in static expression")
        case op
        of "+": result = StaticValue(kind: skInt, intVal: li + ri)
        of "-": result = StaticValue(kind: skInt, intVal: li - ri)
        of "*": result = StaticValue(kind: skInt, intVal: li * ri)
        of "/": result = StaticValue(kind: skInt, intVal: li div ri)
        of "%": result = StaticValue(kind: skInt, intVal: li mod ri)
        else: discard
      else:
        let lf = l.numValue(node)
        let rf = r.numValue(node)
        let res =
          case op
          of "+": lf + rf
          of "-": lf - rf
          of "*": lf * rf
          of "/": lf / rf
          else: 0.0
        result = StaticValue(kind: skFloat, floatVal: res)
    of "==", "!=", "<", ">", "<=", ">=":
      var res: bool
      case op
      of "==": res = staticEqual(l, r)
      of "!=": res = not staticEqual(l, r)
      of "<":  res = cmpStatic(l, r, node) < 0
      of ">":  res = cmpStatic(l, r, node) > 0
      of "<=": res = cmpStatic(l, r, node) <= 0
      of ">=": res = cmpStatic(l, r, node) >= 0
      else: discard
      result = StaticValue(kind: skBool, boolVal: res)
    of "&":
      if l.kind == skString and r.kind == skString:
        result = StaticValue(kind: skString, strVal: l.strVal & r.strVal)
      else:
        staticError(node, "`&` in a static context requires two strings")
    else:
      staticError(node, "unsupported static infix operator `" & op & "`")
  of nkCall:
    if node[0].kind == nkIdent and node[0].ident == "defined":
      if node.len != 2:
        staticError(node, "`defined` expects exactly one argument")
      let arg = node[1]
      case arg.kind
      of nkString:
        result = StaticValue(kind: skBool, boolVal: defined(arg.stringVal))
      of nkIdent:
        result = StaticValue(kind: skBool, boolVal: defined(arg.ident))
      else:
        staticError(node, "`defined` expects a string literal or symbol name")
    else:
      staticError(node, "cannot call `" & $node[0].ident &
        "` at compile time")
  else:
    staticError(node, "expression cannot be evaluated at compile time " &
      "(node kind: " & $node.kind & ")")

proc evalStaticBool*(node: Node): bool =
  ## Evaluate a `when` condition to a boolean.
  let v = evalStatic(node)
  case v.kind
  of skBool: result = v.boolVal
  else:
    staticError(node, "`when` condition must evaluate to a boolean, got a static " & $v.kind)
