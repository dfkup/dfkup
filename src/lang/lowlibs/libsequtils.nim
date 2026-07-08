# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/algorithm
import pkg/vancode/interpreter/[chunk, sym, value]
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

template makeArrayIntTy(module: Module): Sym =
  let t = module.sym("array").clone
  t.arrayTy = module.sym("int")
  t

proc initSequtils*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  script.addProc(module, "isEmpty", @[paramDef("data", ttyArray)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].objectVal.fields.len == 0)
  )

  script.addProc(module, "contains", @[paramDef("data", ttyArray), paramDef("val", ttyInt)], ttyBool,
    proc (args: StackView, argc: int): Value =
      let needle = args[1]
      for vs in args[0].objectVal.fields:
        if valueEq(vs.toValue, needle):
          return initValue(true)
      result = initValue(false)
  )

  script.addProc(module, "count", @[paramDef("data", ttyArray), paramDef("val", ttyInt)], ttyInt,
    proc (args: StackView, argc: int): Value =
      var c = 0
      let needle = args[1]
      for vs in args[0].objectVal.fields:
        if valueEq(vs.toValue, needle):
          inc c
      result = initValue(c.int64)
  )

  script.addProc(module, "indexOf", @[paramDef("data", ttyArray), paramDef("val", ttyInt)], ttyInt,
    proc (args: StackView, argc: int): Value =
      let needle = args[1]
      for i, vs in args[0].objectVal.fields:
        if valueEq(vs.toValue, needle):
          return initValue(i.int64)
      result = initValue((-1).int64)
  )

  script.addProc(module, "first", @[paramDef("data", ttyArray)], ttyInt,
    proc (args: StackView, argc: int): Value =
      if args[0].objectVal.fields.len > 0:
        result = args[0].objectVal.fields[0].toValue
      else:
        result = initValue(0.int64)
  )

  script.addProc(module, "last", @[paramDef("data", ttyArray)], ttyInt,
    proc (args: StackView, argc: int): Value =
      let f = args[0].objectVal.fields
      if f.len > 0:
        result = f[^1].toValue
      else:
        result = initValue(0.int64)
  )

  script.addProc(module, "min", @[paramDef("data", ttyArray)], ttyInt,
    proc (args: StackView, argc: int): Value =
      let f = args[0].objectVal.fields
      if f.len == 0:
        return initValue(0.int64)
      result = f[0].toValue
      for i in 1..<f.len:
        let vi = f[i].toValue
        if valueLess(vi, result):
          result = vi
  )

  script.addProc(module, "max", @[paramDef("data", ttyArray)], ttyInt,
    proc (args: StackView, argc: int): Value =
      let f = args[0].objectVal.fields
      if f.len == 0:
        return initValue(0.int64)
      result = f[0].toValue
      for i in 1..<f.len:
        let vi = f[i].toValue
        if valueLess(result, vi):
          result = vi
  )

  let arrIntTy = makeArrayIntTy(module)

  script.addProc(module, "distinct", @[paramDef("data", ttyArray)], ttyArray,
    proc (args: StackView, argc: int): Value =
      var seen: seq[Value]
      for vs in args[0].objectVal.fields:
        let v = vs.toValue
        var dup = false
        for s in seen:
          if valueEq(s, v):
            dup = true
            break
        if not dup:
          seen.add(v)
      result = initArray(seen.len)
      for i, v in seen:
        result.objectVal.fields[i] = v.toStorage
    , returnTySym = arrIntTy
  )

  script.addProc(module, "concat", @[paramDef("a", ttyArray), paramDef("b", ttyArray)], ttyArray,
    proc (args: StackView, argc: int): Value =
      let a = args[0].objectVal.fields
      let b = args[1].objectVal.fields
      result = initArray(a.len + b.len)
      for i, vs in a:
        result.objectVal.fields[i] = vs
      for i, vs in b:
        result.objectVal.fields[a.len + i] = vs
    , returnTySym = arrIntTy
  )

  script.addProc(module, "reverse", @[paramDef("data", ttyArray)], ttyArray,
    proc (args: StackView, argc: int): Value =
      let f = args[0].objectVal.fields
      result = initArray(f.len)
      for i, vs in f:
        result.objectVal.fields[^ (i + 1)] = vs
    , returnTySym = arrIntTy
  )

  script.addProc(module, "flatten", @[paramDef("data", ttyArray)], ttyArray,
    proc (args: StackView, argc: int): Value =
      var flat: seq[Value]
      for vs in args[0].objectVal.fields:
        let v = vs.toValue
        if v.typeId == tyArrayObject:
          for elem in v.objectVal.fields:
            flat.add(elem.toValue)
        else:
          flat.add(v)
      result = initArray(flat.len)
      for i, v in flat:
        result.objectVal.fields[i] = v.toStorage
    , returnTySym = arrIntTy
  )

  script.addProc(module, "sort", @[paramDef("data", ttyArray)], ttyArray,
    proc (args: StackView, argc: int): Value =
      var f: seq[Value]
      for vs in args[0].objectVal.fields:
        f.add(vs.toValue)
      f.sort(proc(a, b: Value): int =
        if valueEq(a, b): return 0
        if valueLess(a, b): return -1
        return 1
      )
      result = initArray(f.len)
      for i, v in f:
        result.objectVal.fields[i] = v.toStorage
    , returnTySym = arrIntTy
  )

  script.addProc(module, "add", @[paramDef("s", ttyArray), paramDef("item", ttyAny)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      args[0].objectVal.fields.add(args[1].toStorage)
  )
