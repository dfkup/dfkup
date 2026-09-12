# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/tables
import pkg/openparser/xml
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

proc getNode(v: Value): XmlNode =
  if v.typeId == tyNil:
    return nil
  cast[XmlNode](v.objectVal.foreign.data)

proc wrapNode(n: XmlNode): Value =
  if n == nil:
    result = Value(typeId: tyNil)
  else:
    result = initValue(tyPointer, n)
    result.objectVal.foreign.tag = "XMLNode"

proc textOf(n: XmlNode): string =
  if n == nil:
    return ""
  case n.kind
  of xnText: result = n.text
  of xnElement:
    for c in n.children:
      result.add(textOf(c))
  else: discard

proc initXml*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  script.addProc(module, "parseXml", @[paramDef("s", ttyString)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapNode(fromXml(args[0].stringVal[])))

  script.addProc(module, "parseXmlFile", @[paramDef("path", ttyString)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapNode(fromXml(readFile(args[0].stringVal[]))))

  script.addProc(module, "tagName", @[paramDef("node", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      let n = getNode(args[0])
      if n != nil and n.kind == xnElement:
        result = initValue(n.tag)
      else:
        result = initValue(""))

  script.addProc(module, "getText", @[paramDef("node", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(textOf(getNode(args[0]))))

  script.addProc(module, "getAttr", @[paramDef("node", ttyPointer),
      paramDef("key", ttyString),
      paramDef("default", ttyString, initValue(""))], ttyString,
    proc (args: StackView, argc: int): Value =
      let n = getNode(args[0])
      if n != nil and n.kind == xnElement and n.attrs.hasKey(args[1].stringVal[]):
        result = initValue(n.attrs[args[1].stringVal[]])
      else:
        result = initValue(args[2].stringVal[]))

  script.addProc(module, "childCount", @[paramDef("node", ttyPointer)], ttyInt,
    proc (args: StackView, argc: int): Value =
      let n = getNode(args[0])
      if n != nil and n.kind == xnElement:
        result = initValue(n.children.len.int64)
      else:
        result = initValue(0'i64))

  script.addProc(module, "child", @[paramDef("node", ttyPointer),
      paramDef("index", ttyInt)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      let n = getNode(args[0])
      let i = args[1].intVal.int
      if n != nil and n.kind == xnElement and i >= 0 and i < n.children.len:
        result = wrapNode(n.children[i])
      else:
        result = Value(typeId: tyNil))

  script.addProc(module, "findChild", @[paramDef("node", ttyPointer),
      paramDef("tag", ttyString)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      let n = getNode(args[0])
      var found: XmlNode = nil
      if n != nil and n.kind == xnElement:
        for c in n.children:
          if c.kind == xnElement and c.tag == args[1].stringVal[]:
            found = c
            break
      result = wrapNode(found))

  script.addProc(module, "getXml", @[paramDef("node", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      let n = getNode(args[0])
      if n == nil:
        result = initValue("")
      else:
        result = initValue(toXml(n)))
