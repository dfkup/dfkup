# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

## Timing utilities for running benchmarks from scripts.
##
## Two clocks are exposed, matching their use in performance work:
## - `monoNanos` reads a monotonic nanosecond clock (`std/monotimes`).
##   It never jumps with wall-clock adjustments, so it is the right
##   clock for measuring elapsed time.
## - `cpuTime` reads process CPU seconds (`std/times`). It only
##   advances while this process runs, so it excludes time the OS
##   scheduled away (useful next to wall time to spot contention).
import std/[monotimes, times]
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib]

proc initBench*(script: Script, module: Module) =

  script.addProc(module, "monoNanos", @[], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(getMonoTime().ticks)
  )

  script.addProc(module, "cpuTime", @[], ttyFloat,
    proc (args: StackView, argc: int): Value =
      result = initValue(cpuTime())
  )

  script.addProc(module, "elapsedMillis", @[
      paramDef("startNs", ttyInt), paramDef("endNs", ttyInt)], ttyFloat,
    proc (args: StackView, argc: int): Value =
      result = initValue(
        (args[1].intVal - args[0].intVal).float64 / 1_000_000.0)
  )

  script.addProc(module, "elapsedSeconds", @[
      paramDef("startNs", ttyInt), paramDef("endNs", ttyInt)], ttyFloat,
    proc (args: StackView, argc: int): Value =
      result = initValue(
        (args[1].intVal - args[0].intVal).float64 / 1_000_000_000.0)
  )
