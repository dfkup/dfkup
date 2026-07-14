import std/json
import pkg/openparser/regex
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

proc matchToJson(m: MatchResult, input: string): JsonNode =
  result = newJObject()
  result["matched"] = %(m.matched)
  result["start"] = %(m.start)
  result["stop"] = %(m.stop)
  var groups = newJArray()
  for i in 1 .. m.groupCount():
    groups.add(%(m.group(i).str(input)))
  result["groups"] = groups
  result["groupCount"] = %(m.groupCount())

proc initRegex*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  script.addProc(module, "match", @[paramDef("input", ttyString), paramDef("pattern", ttyString)], ttyJson,
    proc (args: StackView, argc: int): Value =
      let input = args[0].stringVal[]
      result = initValue(matchToJson(match(args[1].stringVal[], input), input)))

  script.addProc(module, "find", @[paramDef("input", ttyString), paramDef("pattern", ttyString)], ttyJson,
    proc (args: StackView, argc: int): Value =
      let input = args[0].stringVal[]
      result = initValue(matchToJson(find(args[1].stringVal[], input), input)))

  script.addProc(module, "findAll", @[paramDef("input", ttyString), paramDef("pattern", ttyString)], ttyJson,
    proc (args: StackView, argc: int): Value =
      let input = args[0].stringVal[]
      let matches = findAll(args[1].stringVal[], input)
      var arr = newJArray()
      for m in matches:
        arr.add(matchToJson(m, input))
      result = initValue(arr))
