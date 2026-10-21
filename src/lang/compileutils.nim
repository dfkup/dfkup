# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

## Host helper: parse and compile inline dfkup source into a live script.
##
## Used by `libsystem` for its inline iterators. The stdkups repo carries
## its own copy for the `llm` shard (which compiles coroutine helpers at
## init time); the two copies are intentionally independent so neither
## package depends on the other.

import std/options
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, value]
import ./parser

proc compileCode*(script: Script, module: Module, code: string) =
  ## Parse and compile inline dfkup source into the given script and module.
  var astProgram: Ast
  try:
    parseScript(astProgram, code)
  except DfkupParserError:
    return
  var gen = initCodeGen(script, module, script.mainChunk)
  gen.genScript(astProgram, none(string), emitHalt = false)
