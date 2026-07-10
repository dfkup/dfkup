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

  script.addProc(module, "contains", @[p("s", ttyString), p("sub", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].contains(args[1].stringVal[])))

  script.addProc(module, "startsWith", @[p("s", ttyString), p("prefix", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].startsWith(args[1].stringVal[])))

  script.addProc(module, "endsWith", @[p("s", ttyString), p("suffix", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].endsWith(args[1].stringVal[])))

  script.addProc(module, "find", @[p("s", ttyString), p("sub", ttyString),
      p("start", ttyInt, initValue(0.int64))], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].find(args[1].stringVal[], args[2].intVal.int).int64))

  script.addProc(module, "count", @[p("s", ttyString), p("sub", ttyString)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].count(args[1].stringVal[]).int64))

  script.addProc(module, "toLower", @[p("s", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].toLower()))

  script.addProc(module, "toUpper", @[p("s", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].toUpper()))

  script.addProc(module, "capitalize", @[p("s", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].capitalizeAscii()))

  script.addProc(module, "strip", @[p("s", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].strip()))

  script.addProc(module, "isEmptyOrWhitespace", @[p("s", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].isEmptyOrWhitespace()))

  script.addProc(module, "repeat", @[p("s", ttyString), p("n", ttyInt)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(strutils.repeat(args[0].stringVal[], args[1].intVal.int)))

  script.addProc(module, "replace", @[p("s", ttyString), p("from", ttyString), p("to", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].replace(args[1].stringVal[], args[2].stringVal[])))

  script.addProc(module, "indent", @[p("s", ttyString), p("n", ttyInt)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].indent(args[1].intVal.int)))

  script.addProc(module, "unindent", @[p("s", ttyString), p("n", ttyInt)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].unindent(args[1].intVal.int)))

  script.addProc(module, "align", @[p("s", ttyString), p("width", ttyInt)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].align(args[1].intVal.int)))

  script.addProc(module, "center", @[p("s", ttyString), p("width", ttyInt)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].center(args[1].intVal.int)))

  script.addProc(module, "delete", @[p("s", ttyString), p("first", ttyInt),
      p("last", ttyInt)], ttyString,
    proc (args: StackView, argc: int): Value =
      var s = args[0].stringVal[]
      s.delete(args[1].intVal.int .. args[2].intVal.int)
      result = initValue(s))

  script.addProc(module, "split", @[p("s", ttyString), p("sep", ttyString)], ttyJson,
    proc (args: StackView, argc: int): Value =
      let parts = args[0].stringVal[].split(args[1].stringVal[])
      var arr = newJArray()
      for p in parts:
        arr.add(newJString(p))
      result = initValue(arr))

  script.addProc(module, "join", @[p("parts", ttyJson), p("sep", ttyString)], ttyString,
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

  script.addProc(module, "join", @[p("s", ttyArray)], ttyString,
    proc (args: StackView, argc: int): Value =
      # joins an array of strings with ", "
      for vs in args[0].objectVal.fields:
        assert vs.refVal.typeId == tyString, "join() only works on arrays of strings"
      result = initvalue("")
      result.stringVal[] = args[0].objectVal.fields.mapIt(it.refVal.stringVal[]).join(", ")
  )

  script.addProc(module, "isAlphaAscii", @[p("s", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      let s = args[0].stringVal[]
      result = initValue(s.len == 1 and s[0].isAlphaAscii()))

  script.addProc(module, "isDigit", @[p("s", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      let s = args[0].stringVal[]
      result = initValue(s.len == 1 and s[0].isDigit()))

  script.addProc(module, "isAlphaNumeric", @[p("s", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      let s = args[0].stringVal[]
      result = initValue(s.len == 1 and s[0].isAlphaNumeric()))

  script.addProc(module, "isSpaceAscii", @[p("s", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      let s = args[0].stringVal[]
      result = initValue(s.len == 1 and s[0].isSpaceAscii()))

  script.addProc(module, "parseInt", @[p("s", ttyString)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(strutils.parseInt(args[0].stringVal[]).int64))

  script.addProc(module, "parseFloat", @[p("s", ttyString)], ttyFloat,
    proc (args: StackView, argc: int): Value =
      result = initValue(strutils.parseFloat(args[0].stringVal[])))

  script.addProc(module, "parseBool", @[p("s", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(strutils.parseBool(args[0].stringVal[])))
