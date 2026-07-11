# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/json
import pkg/openparser/json as opjson
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

proc initJson*(script: Script, module: Module) =
  ## This is a low-level procedure for initializing JSON module
  module.initSystemTypes()
  script.initSystemOps(module)

  script.addProc(module, "parseJson", @[paramDef("s", ttyString)], ttyJson,
    proc (args: StackView, argc: int): Value =
      result = initValue(fromJson(args[0].stringVal[])))

  script.addProc(module, "dumpJson", @[paramDef("v", ttyJson)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(opjson.toJson(args[0].jsonVal)))

  script.addProc(module, "toJson", @[paramDef("v", ttyAny)], ttyJson,
    proc (args: StackView, argc: int): Value =
      let v = args[0]
      case v.typeId
      of tyNil:
        result = initValue(newJNull())
      of tyBool:
        result = initValue(newJBool(v.boolVal))
      of tyInt:
        result = initValue(newJInt(v.intVal))
      of tyFloat:
        result = initValue(newJFloat(v.floatVal))
      of tyString:
        result = initValue(newJString(v.stringVal[]))
      of tyJsonStorage:
        result = v
      of tyArrayObject:
        var arr = newJArray()
        for vs in v.objectVal.fields:
          let elem = vs.toValue
          case elem.typeId
          of tyNil: arr.add(newJNull())
          of tyBool: arr.add(newJBool(elem.boolVal))
          of tyInt: arr.add(newJInt(elem.intVal))
          of tyFloat: arr.add(newJFloat(elem.floatVal))
          of tyString: arr.add(newJString(elem.stringVal[]))
          of tyJsonStorage: arr.add(elem.jsonVal)
          else: arr.add(newJString($elem))
        result = initValue(arr)
      of tyPointer:
        # convert pointer to string representation
        result = initValue(newJString($v))
      of tyProc:
        result = initValue(newJString("proc<" & $v.procVal.procId & ":" & v.procVal.procScript & ">"))
      else:
        result = initValue(newJString($v)))

  script.addProc(module, "pretty", @[paramDef("v", ttyJson)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(json.pretty(args[0].jsonVal)))

  script.addProc(module, "keys", @[paramDef("obj", ttyJson)], ttyJson,
    proc (args: StackView, argc: int): Value =
      if args[0].jsonVal.kind == JObject:
        var arr = newJArray()
        for k, _ in args[0].jsonVal.pairs:
          arr.add(newJString(k))
        result = initValue(arr)
      else:
        result = initValue(newJArray()))

  script.addProc(module, "values", @[paramDef("obj", ttyJson)], ttyJson,
    proc (args: StackView, argc: int): Value =
      if args[0].jsonVal.kind == JObject:
        var arr = newJArray()
        for _, v in args[0].jsonVal.pairs:
          arr.add(v)
        result = initValue(arr)
      else:
        result = initValue(newJArray()))

  script.addProc(module, "join", @[paramDef("arr", ttyJson), paramDef("sep", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue("")
      let sep = args[1].stringVal[]
      let joiner = proc(v: JsonNode): string =
        case v.kind
        of JString: v.getStr()
        of JInt: $v.getInt()
        of JFloat: $v.getFloat()
        of JBool: $v.getBool()
        of JNull: "null"
        else: ""
      for i, v in args[0].jsonVal.elems:
        result.stringVal[] = result.stringVal[] & joiner(v)
        if i < args[0].jsonVal.elems.len - 1:
          result.stringVal[] = result.stringVal[] & sep)

  script.addProc(module, "get", @[paramDef("obj", ttyJson),
      paramDef("key", ttyString),
      paramDef("default", ttyJson, initValue(newJNull()))], ttyJson,
    proc (args: StackView, argc: int): Value =
      if args[0].jsonVal.kind == JObject and args[0].jsonVal.hasKey(args[1].stringVal[]):
        result = initValue(args[0].jsonVal[args[1].stringVal[]])
      else:
        result = args[2])

  script.addProc(module, "get", @[paramDef("obj", ttyJson),
      paramDef("key", ttyString),
      paramDef("default", ttyString)], ttyJson,
    proc (args: StackView, argc: int): Value =
      if args[0].jsonVal.kind == JObject and args[0].jsonVal.hasKey(args[1].stringVal[]):
        result = initValue(args[0].jsonVal[args[1].stringVal[]])
      else:
        result = initValue(newJString(args[2].stringVal[])))
