# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/[json, memfiles, os, tempfiles]
import pkg/openparser/csv
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

proc collectCsv(mf: MemFile, options: CsvOptions): JsonNode =
  var rows = newJArray()
  parseCsv(mf, proc(fields: openArray[CsvFieldSlice], row: int): bool =
    var arr = newJArray()
    for f in fields:
      arr.add(%(f.toString()))
    rows.add(arr)
    true, options)
  result = rows

proc parseCsvString(s: string, delimiter: char): JsonNode =
  if s.len == 0:
    return newJArray()
  let (tmpFile, tmpPath) = createTempFile("dfkup_csv_", ".tmp")
  try:
    tmpFile.write(s)
    tmpFile.close()
    var mf = memfiles.open(tmpPath, mode = fmRead)
    defer: mf.close()
    var options = defaultCsvOptions()
    options.delimiter = delimiter
    result = collectCsv(mf, options)
  finally:
    removeFile(tmpPath)

proc initCsv*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  script.addProc(module, "parseCsv", @[paramDef("s", ttyString),
      paramDef("delimiter", ttyString, initValue(","))], ttyJson,
    proc (args: StackView, argc: int): Value =
      let d = args[1].stringVal[]
      let delim = if d.len > 0: d[0] else: ','
      result = initValue(parseCsvString(args[0].stringVal[], delim)))

  script.addProc(module, "parseCsvFile", @[paramDef("path", ttyString),
      paramDef("delimiter", ttyString, initValue(","))], ttyJson,
    proc (args: StackView, argc: int): Value =
      let d = args[1].stringVal[]
      var options = defaultCsvOptions()
      options.delimiter = if d.len > 0: d[0] else: ','
      var mf = memfiles.open(args[0].stringVal[], mode = fmRead)
      defer: mf.close()
      result = initValue(collectCsv(mf, options)))
