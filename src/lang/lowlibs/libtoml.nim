# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/[json, tables]
import pkg/openparser/toml
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

proc tomlToJson(n: TomlNode): JsonNode =
  if n == nil:
    return newJNull()
  case n.kind
  of tvkString: result = %(n.strVal)
  of tvkInteger: result = %(n.intVal)
  of tvkFloat: result = %(n.floatVal)
  of tvkBoolean: result = %(n.boolVal)
  of tvkDateTime: result = %(n.getValue())
  of tvkArray:
    result = newJArray()
    for item in n.arrayVal:
      result.add(tomlToJson(item))
  of tvkTable:
    result = newJObject()
    for k, v in n.tableVal:
      result[k] = tomlToJson(v)

proc getNode(v: Value): TomlNode =
  if v.typeId == tyNil:
    return nil
  cast[TomlNode](v.objectVal.foreign.data)

proc wrapNode(n: TomlNode): Value =
  if n == nil:
    result = Value(typeId: tyNil)
  else:
    result = initValue(tyPointer, n)
    result.objectVal.foreign.tag = "TOMLNode"

proc initToml*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  script.addProc(module, "parseToml", @[paramDef("s", ttyString)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapNode(parseTOML(args[0].stringVal[])))

  script.addProc(module, "get", @[paramDef("data", ttyPointer),
      paramDef("key", ttyString)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapNode(getNode(args[0]).get(args[1].stringVal[])))

  script.addProc(module, "getStr", @[paramDef("data", ttyPointer),
      paramDef("key", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(getNode(args[0]).get(args[1].stringVal[]).getStr()))

  script.addProc(module, "getInt", @[paramDef("data", ttyPointer),
      paramDef("key", ttyString)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(getNode(args[0]).get(args[1].stringVal[]).getInt()))

  script.addProc(module, "getFloat", @[paramDef("data", ttyPointer),
      paramDef("key", ttyString)], ttyFloat,
    proc (args: StackView, argc: int): Value =
      result = initValue(getNode(args[0]).get(args[1].stringVal[]).getFloat()))

  script.addProc(module, "getBool", @[paramDef("data", ttyPointer),
      paramDef("key", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(getNode(args[0]).get(args[1].stringVal[]).getBool()))

  script.addProc(module, "getArray", @[paramDef("data", ttyPointer),
      paramDef("key", ttyString)], ttyJson,
    proc (args: StackView, argc: int): Value =
      let n = getNode(args[0]).get(args[1].stringVal[])
      if n != nil and n.kind == tvkArray:
        result = initValue(tomlToJson(n))
      else:
        result = initValue(newJArray()))

  script.addProc(module, "hasKey", @[paramDef("data", ttyPointer),
      paramDef("key", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(getNode(args[0]).get(args[1].stringVal[]) != nil))

  script.addProc(module, "dumpToml", @[paramDef("data", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(dumpTOML(getNode(args[0]))))

  script.addProc(module, "toJson", @[paramDef("data", ttyPointer)], ttyJson,
    proc (args: StackView, argc: int): Value =
      result = initValue(tomlToJson(getNode(args[0]))))
