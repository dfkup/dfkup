# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import pkg/openparser/qr
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

proc initQr*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  script.addProc(module, "qrSvg", @[paramDef("text", ttyString),
      paramDef("scale", ttyInt, initValue(8'i64)),
      paramDef("border", ttyInt, initValue(4'i64))], ttyString,
    proc (args: StackView, argc: int): Value =
      let m = encodeQr(args[0].stringVal[])
      result = initValue(m.toSvg(scale = args[1].intVal.int,
        border = args[2].intVal.int)))

  script.addProc(module, "qrTerminal", @[paramDef("text", ttyString),
      paramDef("border", ttyInt, initValue(2'i64))], ttyString,
    proc (args: StackView, argc: int): Value =
      let m = encodeQr(args[0].stringVal[])
      result = initValue(m.toTerminal(border = args[1].intVal.int)))
