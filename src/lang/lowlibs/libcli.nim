# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/[cmdline, parseopt, json]
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

proc initCliLib*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  script.addProc(module, "paramCount", @[], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(paramCount().int64))

  script.addProc(module, "paramStr", @[paramDef("n", ttyInt)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(paramStr(args[0].intVal.int)))

  script.addProc(module, "commandLineArgs", @[], ttyJson,
    proc (args: StackView, argc: int): Value =
      var arr = newJArray()
      for i in 1..paramCount():
        arr.add(newJString(paramStr(i)))
      result = initValue(arr))

  script.addProc(module, "parseOpt", @[], ttyJson,
    proc (args: StackView, argc: int): Value =
      var p = initOptParser()
      var positional = newJArray()
      var options = newJObject()
      for kind, key, val in getopt(p):
        case kind
        of cmdEnd: break
        of cmdArgument:
          positional.add(newJString(key))
        of cmdLongOption:
          options[key] = newJString(val)
        of cmdShortOption:
          options[$key] = newJString(val)
      var resultObj = newJObject()
      resultObj["args"] = positional
      resultObj["opts"] = options
      result = initValue(resultObj))
