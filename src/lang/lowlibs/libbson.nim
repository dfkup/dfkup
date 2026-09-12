# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import pkg/openparser/bson
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

proc bytesToString(b: seq[byte]): string =
  result = newString(b.len)
  if b.len > 0:
    copyMem(addr result[0], unsafeAddr b[0], b.len)

proc initBson*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  script.addProc(module, "encodeBson", @[paramDef("data", ttyJson)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(bytesToString(encodeBson(args[0].jsonVal))))

  script.addProc(module, "decodeBson", @[paramDef("s", ttyString)], ttyJson,
    proc (args: StackView, argc: int): Value =
      let s = args[0].stringVal[]
      result = initValue(decodeBson(toOpenArrayByte(s, 0, s.high))))
