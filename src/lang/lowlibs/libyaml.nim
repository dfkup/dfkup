import std/[json, tables]
import pkg/openparser/yaml
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

proc yamlToJson(n: YamlNode): JsonNode =
  if n == nil:
    return newJNull()
  case n.kind
  of yamlNull: result = newJNull()
  of yamlBoolean: result = %(n.boolValue)
  of yamlInteger: result = %(n.intValue)
  of yamlFloat: result = %(n.floatValue)
  of yamlString: result = %(n.strValue)
  of yamlObject:
    result = newJObject()
    for k, v in n.objValue:
      result[k] = yamlToJson(v)
  of yamlArray:
    result = newJArray()
    for item in n.arrValue:
      result.add(yamlToJson(item))

proc safeObjGet(obj: YAMLObject, key: string): YamlNode =
  if '.' notin key:
    if obj.hasKey(key): obj[key] else: nil
  else:
    let dotIdx = key.find('.')
    let head = key[0 ..< dotIdx]
    let tail = key[dotIdx+1 .. ^1]
    if not obj.hasKey(head):
      return nil
    let next = obj[head]
    if next == nil:
      return nil
    next.get(tail)

proc resolveNode(v: Value, key: string): YamlNode =
  if v.typeId == tyNil:
    return nil
  if v.objectVal.foreign.tag == "YAMLObject":
    result = safeObjGet(cast[YAMLObject](v.objectVal.foreign.data), key)
  else:
    let node = cast[YamlNode](v.objectVal.foreign.data)
    if node == nil:
      result = nil
    else:
      result = node.get(key)

proc wrapNode(n: YamlNode, tag: string): Value =
  if n == nil:
    result = Value(typeId: tyNil)
  else:
    result = initValue(tyPointer, n)
    result.objectVal.foreign.tag = tag

proc initYaml*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  script.addProc(module, "parseYaml", @[paramDef("s", ttyString)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = initValue(tyPointer, parseYAML(args[0].stringVal[]))
      result.objectVal.foreign.tag = "YAMLObject")

  script.addProc(module, "parseYamlFile", @[paramDef("path", ttyString)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = initValue(tyPointer, parseYAML(readFile(args[0].stringVal[])))
      result.objectVal.foreign.tag = "YAMLObject")

  script.addProc(module, "get", @[paramDef("data", ttyPointer), paramDef("key", ttyString)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapNode(resolveNode(args[0], args[1].stringVal[]), "YamlNode"))

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

  script.addProc(module, "getArray", @[paramDef("data", ttyPointer), paramDef("key", ttyString)], ttyJson,
    proc (args: StackView, argc: int): Value =
      let n = resolveNode(args[0], args[1].stringVal[])
      if n != nil and n.kind == yamlArray:
        result = initValue(yamlToJson(n))
      else:
        result = initValue(newJArray()))

  script.addProc(module, "hasKey", @[paramDef("data", ttyPointer), paramDef("key", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(resolveNode(args[0], args[1].stringVal[]) != nil))

  script.addProc(module, "len", @[paramDef("data", ttyPointer)], ttyInt,
    proc (args: StackView, argc: int): Value =
      let v = args[0]
      if v.typeId == tyNil:
        result = initValue(0'i64)
      elif v.objectVal.foreign.tag == "YAMLObject":
        result = initValue(cast[YAMLObject](v.objectVal.foreign.data).len.int64)
      else:
        let n = cast[YamlNode](v.objectVal.foreign.data)
        if n != nil and n.kind == yamlArray:
          result = initValue(n.arrValue.len.int64)
        elif n != nil and n.kind == yamlObject:
          result = initValue(n.objValue.len.int64)
        else:
          result = initValue(0'i64))

  script.addProc(module, "toYaml", @[paramDef("data", ttyJson)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(dump(args[0].jsonVal)))
