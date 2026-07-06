# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/[strutils, sequtils, json]
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

proc initStrings*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  script.addProc(module, "contains", @[paramDef("s", ttyString), paramDef("sub", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].contains(args[1].stringVal[])))

  script.addProc(module, "startsWith", @[paramDef("s", ttyString), paramDef("prefix", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].startsWith(args[1].stringVal[])))

  script.addProc(module, "endsWith", @[paramDef("s", ttyString), paramDef("suffix", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].endsWith(args[1].stringVal[])))

  script.addProc(module, "find", @[paramDef("s", ttyString), paramDef("sub", ttyString),
      paramDef("start", ttyInt, initValue(0.int64))], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].find(args[1].stringVal[], args[2].intVal.int).int64))

  script.addProc(module, "count", @[paramDef("s", ttyString), paramDef("sub", ttyString)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].count(args[1].stringVal[]).int64))

  script.addProc(module, "toLower", @[paramDef("s", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].toLower()))

  script.addProc(module, "toUpper", @[paramDef("s", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].toUpper()))

  script.addProc(module, "capitalize", @[paramDef("s", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].capitalizeAscii()))

  script.addProc(module, "strip", @[paramDef("s", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].strip()))

  script.addProc(module, "isEmptyOrWhitespace", @[paramDef("s", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].isEmptyOrWhitespace()))

  script.addProc(module, "repeat", @[paramDef("s", ttyString), paramDef("n", ttyInt)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(strutils.repeat(args[0].stringVal[], args[1].intVal.int)))

  script.addProc(module, "replace", @[paramDef("s", ttyString), paramDef("from", ttyString),
      paramDef("to", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].replace(args[1].stringVal[], args[2].stringVal[])))

  script.addProc(module, "indent", @[paramDef("s", ttyString), paramDef("n", ttyInt)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].indent(args[1].intVal.int)))

  script.addProc(module, "unindent", @[paramDef("s", ttyString), paramDef("n", ttyInt)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].unindent(args[1].intVal.int)))

  script.addProc(module, "align", @[paramDef("s", ttyString), paramDef("width", ttyInt)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].align(args[1].intVal.int)))

  script.addProc(module, "center", @[paramDef("s", ttyString), paramDef("width", ttyInt)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].center(args[1].intVal.int)))

  script.addProc(module, "delete", @[paramDef("s", ttyString), paramDef("first", ttyInt),
      paramDef("last", ttyInt)], ttyString,
    proc (args: StackView, argc: int): Value =
      var s = args[0].stringVal[]
      s.delete(args[1].intVal.int, args[2].intVal.int)
      result = initValue(s))

  script.addProc(module, "split", @[paramDef("s", ttyString), paramDef("sep", ttyString)], ttyJson,
    proc (args: StackView, argc: int): Value =
      let parts = args[0].stringVal[].split(args[1].stringVal[])
      var arr = newJArray()
      for p in parts:
        arr.add(newJString(p))
      result = initValue(arr))

  script.addProc(module, "join", @[paramDef("parts", ttyJson), paramDef("sep", ttyString)], ttyString,
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

  script.addProc(module, "join", @[paramDef("s", ttyArray)], ttyString,
    proc (args: StackView, argc: int): Value =
      # joins an array of strings with ", "
      for v in args[0].objectVal.fields:
        assert v.typeId == tyString, "join() only works on arrays of strings"
      result = initvalue("")
      result.stringVal[] = args[0].objectVal.fields.mapIt(it.stringVal[]).join(", ")
  )

  script.addProc(module, "isAlphaAscii", @[paramDef("s", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      let s = args[0].stringVal[]
      result = initValue(s.len == 1 and s[0].isAlphaAscii()))

  script.addProc(module, "isDigit", @[paramDef("s", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      let s = args[0].stringVal[]
      result = initValue(s.len == 1 and s[0].isDigit()))

  script.addProc(module, "isAlphaNumeric", @[paramDef("s", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      let s = args[0].stringVal[]
      result = initValue(s.len == 1 and s[0].isAlphaNumeric()))

  script.addProc(module, "isSpaceAscii", @[paramDef("s", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      let s = args[0].stringVal[]
      result = initValue(s.len == 1 and s[0].isSpaceAscii()))

  script.addProc(module, "parseInt", @[paramDef("s", ttyString)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(strutils.parseInt(args[0].stringVal[]).int64))

  script.addProc(module, "parseFloat", @[paramDef("s", ttyString)], ttyFloat,
    proc (args: StackView, argc: int): Value =
      result = initValue(strutils.parseFloat(args[0].stringVal[])))

  script.addProc(module, "parseBool", @[paramDef("s", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(strutils.parseBool(args[0].stringVal[])))
