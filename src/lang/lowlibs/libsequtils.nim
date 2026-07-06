# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/algorithm
import pkg/vancode/interpreter/[ast, chunk, sym, value, codegen]
import pkg/vancode/interpreter/stdlib/[syslib]

proc valueEq(a, b: Value): bool =
  if a == nil and b == nil: return true
  if a == nil or b == nil: return false
  if a.typeId != b.typeId: return false
  case a.typeId
  of tyBool:   result = a.boolVal == b.boolVal
  of tyInt:    result = a.intVal == b.intVal
  of tyFloat:  result = a.floatVal == b.floatVal
  of tyString: result = a.stringVal[] == b.stringVal[]
  else:        result = false

proc valueLess(a, b: Value): bool =
  if a.typeId != b.typeId: return a.typeId < b.typeId
  case a.typeId
  of tyInt:    result = a.intVal < b.intVal
  of tyFloat:  result = a.floatVal < b.floatVal
  of tyString: result = a.stringVal[] < b.stringVal[]
  else:        result = false

proc initSequtils*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  # isEmpty
  block:
    let arrTy = module.sym("array")
    let boolTy = module.sym("bool")
    var nodeParams: seq[ProcParam]
    nodeParams.add((ast.newIdent("data"), arrTy, nil, false, false))
    let (sym, theProc) = script.newProc(
      ast.newIdent("isEmpty"), impl = nil, nodeParams,
      boolTy, pkForeign, exported = true)
    theProc.foreign = proc (args: StackView, argc: int): Value =
      result = initValue(args[0].objectVal.fields.len == 0)
    discard module.addCallable(sym, sym.name)
    script.procs.add(theProc)

  # contains
  block:
    let arrTy = module.sym("array")
    let boolTy = module.sym("bool")
    let intTy = module.sym("int")
    var nodeParams: seq[ProcParam]
    nodeParams.add((ast.newIdent("data"), arrTy, nil, false, false))
    nodeParams.add((ast.newIdent("val"), intTy, nil, false, false))
    let (sym, theProc) = script.newProc(
      ast.newIdent("contains"), impl = nil, nodeParams,
      boolTy, pkForeign, exported = true)
    theProc.foreign = proc (args: StackView, argc: int): Value =
      let needle = args[1]
      for v in args[0].objectVal.fields:
        if valueEq(v, needle):
          return initValue(true)
      result = initValue(false)
    discard module.addCallable(sym, sym.name)
    script.procs.add(theProc)

  # count
  block:
    let arrTy = module.sym("array")
    let intTy = module.sym("int")
    var nodeParams: seq[ProcParam]
    nodeParams.add((ast.newIdent("data"), arrTy, nil, false, false))
    nodeParams.add((ast.newIdent("val"), intTy, nil, false, false))
    let (sym, theProc) = script.newProc(
      ast.newIdent("count"), impl = nil, nodeParams,
      intTy, pkForeign, exported = true)
    theProc.foreign = proc (args: StackView, argc: int): Value =
      var c = 0
      let needle = args[1]
      for v in args[0].objectVal.fields:
        if valueEq(v, needle):
          inc c
      result = initValue(c.int64)
    discard module.addCallable(sym, sym.name)
    script.procs.add(theProc)

  # indexOf
  block:
    let arrTy = module.sym("array")
    let intTy = module.sym("int")
    var nodeParams: seq[ProcParam]
    nodeParams.add((ast.newIdent("data"), arrTy, nil, false, false))
    nodeParams.add((ast.newIdent("val"), intTy, nil, false, false))
    let (sym, theProc) = script.newProc(
      ast.newIdent("indexOf"), impl = nil, nodeParams,
      intTy, pkForeign, exported = true)
    theProc.foreign = proc (args: StackView, argc: int): Value =
      let needle = args[1]
      for i, v in args[0].objectVal.fields:
        if valueEq(v, needle):
          return initValue(i.int64)
      result = initValue(-1.int64)
    discard module.addCallable(sym, sym.name)
    script.procs.add(theProc)

  # first
  block:
    let arrTy = module.sym("array")
    let intTy = module.sym("int")
    var nodeParams: seq[ProcParam]
    nodeParams.add((ast.newIdent("data"), arrTy, nil, false, false))
    let (sym, theProc) = script.newProc(
      ast.newIdent("first"), impl = nil, nodeParams,
      intTy, pkForeign, exported = true)
    theProc.foreign = proc (args: StackView, argc: int): Value =
      if args[0].objectVal.fields.len > 0:
        result = args[0].objectVal.fields[0]
      else:
        result = initValue(0.int64)
    discard module.addCallable(sym, sym.name)
    script.procs.add(theProc)

  # last
  block:
    let arrTy = module.sym("array")
    let intTy = module.sym("int")
    var nodeParams: seq[ProcParam]
    nodeParams.add((ast.newIdent("data"), arrTy, nil, false, false))
    let (sym, theProc) = script.newProc(
      ast.newIdent("last"), impl = nil, nodeParams,
      intTy, pkForeign, exported = true)
    theProc.foreign = proc (args: StackView, argc: int): Value =
      let f = args[0].objectVal.fields
      if f.len > 0:
        result = f[^1]
      else:
        result = initValue(0.int64)
    discard module.addCallable(sym, sym.name)
    script.procs.add(theProc)

  # min
  block:
    let arrTy = module.sym("array")
    let intTy = module.sym("int")
    var nodeParams: seq[ProcParam]
    nodeParams.add((ast.newIdent("data"), arrTy, nil, false, false))
    let (sym, theProc) = script.newProc(
      ast.newIdent("min"), impl = nil, nodeParams,
      intTy, pkForeign, exported = true)
    theProc.foreign = proc (args: StackView, argc: int): Value =
      let f = args[0].objectVal.fields
      if f.len == 0:
        return initValue(0.int64)
      result = f[0]
      for i in 1..<f.len:
        if valueLess(f[i], result):
          result = f[i]
    discard module.addCallable(sym, sym.name)
    script.procs.add(theProc)

  # max
  block:
    let arrTy = module.sym("array")
    let intTy = module.sym("int")
    var nodeParams: seq[ProcParam]
    nodeParams.add((ast.newIdent("data"), arrTy, nil, false, false))
    let (sym, theProc) = script.newProc(
      ast.newIdent("max"), impl = nil, nodeParams,
      intTy, pkForeign, exported = true)
    theProc.foreign = proc (args: StackView, argc: int): Value =
      let f = args[0].objectVal.fields
      if f.len == 0:
        return initValue(0.int64)
      result = f[0]
      for i in 1..<f.len:
        if valueLess(result, f[i]):
          result = f[i]
    discard module.addCallable(sym, sym.name)
    script.procs.add(theProc)

  template makeArrayIntTy: Sym =
    let t = module.sym("array").clone
    t.arrayTy = module.sym("int")
    t

  # distinct
  block:
    let arrTy = module.sym("array")
    let retTy = makeArrayIntTy()
    var nodeParams: seq[ProcParam]
    nodeParams.add((ast.newIdent("data"), arrTy, nil, false, false))
    let (sym, theProc) = script.newProc(
      ast.newIdent("distinct"), impl = nil, nodeParams,
      retTy, pkForeign, exported = true)
    theProc.foreign = proc (args: StackView, argc: int): Value =
      var seen: seq[Value]
      for v in args[0].objectVal.fields:
        var dup = false
        for s in seen:
          if valueEq(s, v):
            dup = true
            break
        if not dup:
          seen.add(v)
      result = initArray(seen.len)
      for i, v in seen:
        result.objectVal.fields[i] = v
    discard module.addCallable(sym, sym.name)
    script.procs.add(theProc)

  # concat
  block:
    let arrTy = module.sym("array")
    let retTy = makeArrayIntTy()
    var nodeParams: seq[ProcParam]
    nodeParams.add((ast.newIdent("a"), arrTy, nil, false, false))
    nodeParams.add((ast.newIdent("b"), arrTy, nil, false, false))
    let (sym, theProc) = script.newProc(
      ast.newIdent("concat"), impl = nil, nodeParams,
      retTy, pkForeign, exported = true)
    theProc.foreign = proc (args: StackView, argc: int): Value =
      let a = args[0].objectVal.fields
      let b = args[1].objectVal.fields
      result = initArray(a.len + b.len)
      for i, v in a:
        result.objectVal.fields[i] = v
      for i, v in b:
        result.objectVal.fields[a.len + i] = v
    discard module.addCallable(sym, sym.name)
    script.procs.add(theProc)

  # reverse
  block:
    let arrTy = module.sym("array")
    let retTy = makeArrayIntTy()
    var nodeParams: seq[ProcParam]
    nodeParams.add((ast.newIdent("data"), arrTy, nil, false, false))
    let (sym, theProc) = script.newProc(
      ast.newIdent("reverse"), impl = nil, nodeParams,
      retTy, pkForeign, exported = true)
    theProc.foreign = proc (args: StackView, argc: int): Value =
      let f = args[0].objectVal.fields
      result = initArray(f.len)
      for i, v in f:
        result.objectVal.fields[^ (i + 1)] = v
    discard module.addCallable(sym, sym.name)
    script.procs.add(theProc)

  # flatten
  block:
    let arrTy = module.sym("array")
    let retTy = makeArrayIntTy()
    var nodeParams: seq[ProcParam]
    nodeParams.add((ast.newIdent("data"), arrTy, nil, false, false))
    let (sym, theProc) = script.newProc(
      ast.newIdent("flatten"), impl = nil, nodeParams,
      retTy, pkForeign, exported = true)
    theProc.foreign = proc (args: StackView, argc: int): Value =
      var flat: seq[Value]
      for v in args[0].objectVal.fields:
        if v.typeId == tyArrayObject:
          for elem in v.objectVal.fields:
            flat.add(elem)
        else:
          flat.add(v)
      result = initArray(flat.len)
      for i, v in flat:
        result.objectVal.fields[i] = v
    discard module.addCallable(sym, sym.name)
    script.procs.add(theProc)

  # join (array overload)
  # block:
  #   let arrTy = module.sym("array")
  #   let stringTy = module.sym("string")
  #   var nodeParams: seq[ProcParam]
  #   nodeParams.add((ast.newIdent("data"), arrTy, nil, false, false))
  #   nodeParams.add((ast.newIdent("sep"), stringTy, nil, false, false))
  #   let (sym, theProc) = script.newProc(
  #     ast.newIdent("join"), impl = nil, nodeParams,
  #     stringTy, pkForeign, exported = true)
  #   theProc.foreign = proc (args: StackView, argc: int): Value =
  #     result = initValue("")
  #     let sep = args[1].stringVal[]
  #     for i, v in args[0].objectVal.fields:
  #       if i > 0:
  #         result.stringVal[] = result.stringVal[] & sep
  #       case v.typeId
  #       of tyInt:    result.stringVal[] = result.stringVal[] & $v.intVal
  #       of tyFloat:  result.stringVal[] = result.stringVal[] & $v.floatVal
  #       of tyString: result.stringVal[] = result.stringVal[] & v.stringVal[]
  #       of tyBool:   result.stringVal[] = result.stringVal[] & $v.boolVal
  #       else:        result.stringVal[] = result.stringVal[] & "<unknown>"
  #   discard module.addCallable(sym, sym.name)
  #   script.procs.add(theProc)

  # sort
  block:
    let arrTy = module.sym("array")
    let retTy = makeArrayIntTy()
    var nodeParams: seq[ProcParam]
    nodeParams.add((ast.newIdent("data"), arrTy, nil, false, false))
    let (sym, theProc) = script.newProc(
      ast.newIdent("sort"), impl = nil, nodeParams,
      retTy, pkForeign, exported = true)
    theProc.foreign = proc (args: StackView, argc: int): Value =
      var f = args[0].objectVal.fields
      f.sort(proc(a, b: Value): int =
        if valueEq(a, b): return 0
        if valueLess(a, b): return -1
        return 1
      )
      result = initArray(f.len)
      for i, v in f:
        result.objectVal.fields[i] = v
    discard module.addCallable(sym, sym.name)
    script.procs.add(theProc)
