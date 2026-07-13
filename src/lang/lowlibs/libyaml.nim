import pkg/openparser/yaml
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

proc resolveNode(v: Value, key: string): YamlNode =
  if v.objectVal.foreign.tag == "YAMLObject":
    let obj = cast[YAMLObject](v.objectVal.foreign.data)
    result = obj.get(key)
  else:
    let node = cast[YamlNode](v.objectVal.foreign.data)
    result = node.get(key)

proc initYaml*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  script.addProc(module, "parseYaml", @[paramDef("s", ttyString)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = initValue(tyPointer, parseYAML(args[0].stringVal[]))
      result.objectVal.foreign.tag = "YAMLObject")

  script.addProc(module, "get", @[paramDef("data", ttyPointer), paramDef("key", ttyString)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      if args[0].objectVal.foreign.tag == "YAMLObject":
        let yamlObj = cast[YAMLObject](args[0].objectVal.foreign.data)
        result = initValue(tyPointer, yamlObj.get(args[1].stringVal[]))
      else:
        let node = cast[YamlNode](args[0].objectVal.foreign.data)
        result = initValue(tyPointer, node.get(args[1].stringVal[]))
      result.objectVal.foreign.tag = "YamlNode")

  script.addProc(module, "getStr", @[paramDef("data", ttyPointer), paramDef("key", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(resolveNode(args[0], args[1].stringVal[]).getStr()))

  script.addProc(module, "getInt", @[paramDef("data", ttyPointer), paramDef("key", ttyString)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(resolveNode(args[0], args[1].stringVal[]).getInt()))

  script.addProc(module, "getFloat", @[paramDef("data", ttyPointer), paramDef("key", ttyString)], ttyFloat,
    proc (args: StackView, argc: int): Value =
      result = initValue(resolveNode(args[0], args[1].stringVal[]).getFloat()))

  script.addProc(module, "getBool", @[paramDef("data", ttyPointer), paramDef("key", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(resolveNode(args[0], args[1].stringVal[]).getBool()))

  script.addProc(module, "toYaml", @[paramDef("data", ttyJson)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(dump(args[0].jsonVal)))
