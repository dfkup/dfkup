# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import pkg/openparser/uuid
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

proc initUuid*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  script.addProc(module, "uuidV4", returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      result = initValue($newUuidV4()))

  script.addProc(module, "uuidV7", returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      result = initValue($newUuidV7()))

  script.addProc(module, "parseUuid", @[paramDef("s", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue($parseUuid(args[0].stringVal[])))

  script.addProc(module, "isValidUuid", @[paramDef("s", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(isValidUuid(args[0].stringVal[])))

  script.addProc(module, "uuidVersion", @[paramDef("s", ttyString)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(parseUuid(args[0].stringVal[]).version().int64))

  script.addProc(module, "isNilUuid", @[paramDef("s", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(parseUuid(args[0].stringVal[]).isNil()))
