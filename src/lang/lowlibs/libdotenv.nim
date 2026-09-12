# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/json
import pkg/openparser/dotenv as opdotenv
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

proc initDotenv*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  script.addProc(module, "parseEnv", @[paramDef("s", ttyString)], ttyJson,
    proc (args: StackView, argc: int): Value =
      var obj = newJObject()
      for e in opdotenv.parseEnv(args[0].stringVal[]):
        obj[e.key] = %(e.value)
      result = initValue(obj))

  script.addProc(module, "envGet", @[paramDef("key", ttyString),
      paramDef("default", ttyString, initValue(""))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(opdotenv.get(args[0].stringVal[], args[1].stringVal[])))

  script.addProc(module, "envSet",
    params = @[paramDef("key", ttyString), paramDef("value", ttyString)],
    returnTy = ttyVoid, impl =
    proc (args: StackView, argc: int): Value =
      opdotenv.set(args[0].stringVal[], args[1].stringVal[]))

  script.addProc(module, "envHas", @[paramDef("key", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(opdotenv.has(args[0].stringVal[])))

  script.addProc(module, "envDel",
    params = @[paramDef("key", ttyString)],
    returnTy = ttyVoid, impl =
    proc (args: StackView, argc: int): Value =
      opdotenv.del(args[0].stringVal[]))
