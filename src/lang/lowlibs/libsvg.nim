# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import pkg/openparser/svg
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

type
  SvgBox = ref object
    doc: SvgDocument

proc getDoc(v: Value): SvgDocument =
  cast[SvgBox](v.objectVal.foreign.data).doc

proc countNodes(n: SvgNode): int =
  if n == nil:
    return 0
  result = 1
  if n.kind == svgElement:
    for c in n.children:
      result += countNodes(c)

proc countTag(n: SvgNode, tag: SvgTag): int =
  if n == nil:
    return 0
  if n.kind == svgElement:
    if n.tag == tag:
      inc result
    for c in n.children:
      result += countTag(c, tag)

proc initSvg*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  script.addProc(module, "parseSvg", @[paramDef("s", ttyString)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = initValue(tyPointer, SvgBox(doc: parseSvg(args[0].stringVal[])))
      result.objectVal.foreign.tag = "SVGDocument")

  script.addProc(module, "parseSvgFile", @[paramDef("path", ttyString)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = initValue(tyPointer, SvgBox(doc: parseSvg(readFile(args[0].stringVal[]))))
      result.objectVal.foreign.tag = "SVGDocument")

  script.addProc(module, "toSvg", @[paramDef("doc", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(toSvg(getDoc(args[0]))))

  script.addProc(module, "rootTag", @[paramDef("doc", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(tagName(getDoc(args[0]).root)))

  script.addProc(module, "nodeCount", @[paramDef("doc", ttyPointer)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(countNodes(getDoc(args[0]).root).int64))

  script.addProc(module, "countTag", @[paramDef("doc", ttyPointer),
      paramDef("tag", ttyString)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(countTag(getDoc(args[0]).root,
        getSvgTag(args[1].stringVal[])).int64))
