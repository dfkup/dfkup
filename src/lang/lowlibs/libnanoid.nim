# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import pkg/openparser/nanoid
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

type
  NanoIdBindError* = object of ValueError

proc initNanoId*(script: Script, module: Module) =

  script.addProc(module, "nanoidAlphabet", @[], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(urlAlphabet))

  script.addProc(module, "nanoid", @[
      paramDef("size", ttyInt, initValue(defaultSize))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(nanoid(args[0].intVal.int)))

  script.addProc(module, "nanoidNonSecure", @[
      paramDef("size", ttyInt, initValue(defaultSize))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(nanoidNonSecure(args[0].intVal.int)))

  script.addProc(module, "nanoidCustom", @[
      paramDef("alphabet", ttyString),
      paramDef("size", ttyInt, initValue(defaultSize))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(customAlphabet(args[0].stringVal[],
        args[1].intVal.int)))
