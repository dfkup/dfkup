# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

proc initSystem*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  script.addProc(module, "echo", @[paramDef("x", ttyString)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      if likely(args[0].typeId == tyString):
        echo args[0].stringVal[]
      else:
        echo "<nil>"
    )

  script.addProc(module, "echo", @[paramDef("x", ttyInt)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      echo args[0].intVal)

  script.addProc(module, "echo", @[paramDef("x", ttyFloat)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      echo args[0].floatVal)

  script.addProc(module, "echo", @[paramDef("x", ttyBool)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      echo args[0].boolVal)

  script.addProc(module, "echo", @[paramDef("x", ttyNil)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      echo "nil")

  script.addProc(module, "&", @[paramDef("a", ttyString), paramDef("b", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[] & args[1].stringVal[]))
