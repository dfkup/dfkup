# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import pkg/openparser/colors
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

type
  ColorBox = ref object
    c: Color

proc getColor(v: Value): Color =
  cast[ColorBox](v.objectVal.foreign.data).c

proc initColors*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  script.addProc(module, "parseColor", @[paramDef("s", ttyString)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = initValue(tyPointer, ColorBox(c: parseColor(args[0].stringVal[])))
      result.objectVal.foreign.tag = "Color")

  script.addProc(module, "isValidColor", @[paramDef("s", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      try:
        discard parseColor(args[0].stringVal[])
        result = initValue(true)
      except ParserColorError:
        result = initValue(false))

  script.addProc(module, "toHex", @[paramDef("c", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(getColor(args[0]).toHex()))

  script.addProc(module, "toRgb", @[paramDef("c", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(getColor(args[0]).toRgbString()))

  script.addProc(module, "toHsl", @[paramDef("c", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(getColor(args[0]).toHslString()))

  script.addProc(module, "toName", @[paramDef("c", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(getColor(args[0]).toName()))

  script.addProc(module, "red", @[paramDef("c", ttyPointer)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(getColor(args[0]).toRgb().r.int64))

  script.addProc(module, "green", @[paramDef("c", ttyPointer)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(getColor(args[0]).toRgb().g.int64))

  script.addProc(module, "blue", @[paramDef("c", ttyPointer)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(getColor(args[0]).toRgb().b.int64))

  script.addProc(module, "alpha", @[paramDef("c", ttyPointer)], ttyFloat,
    proc (args: StackView, argc: int): Value =
      result = initValue(getColor(args[0]).a))