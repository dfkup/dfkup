# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/[json, sequtils, strutils]
import pkg/openparser/css
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

type
  CssBox = ref object
    sheet: CssStyleSheet

var cssDataCache {.global.}: CssData
var cssDataReady {.global.}: bool

proc getCssData(): CssData =
  if not cssDataReady:
    cssDataCache = loadCssData()
    cssDataReady = true
  result = cssDataCache

proc getSheet(v: Value): CssStyleSheet =
  cast[CssBox](v.objectVal.foreign.data).sheet

proc selectorText(node: CssNode): string =
  node.selectors.mapIt(toString(it)).join(", ")

proc validateSheet(sheet: CssStyleSheet): JsonNode =
  let data = getCssData()
  var total = 0
  var invalid = 0
  var errors = newJArray()
  for node in sheet.nodes:
    case node.kind
    of cssRuleSet:
      let sel = selectorText(node)
      let res = validateRuleSet(data, node)
      total += node.declarations.len
      if not res.valid:
        invalid += res.errors.len
        for e in res.errors:
          var err = newJObject()
          err["selector"] = %sel
          err["property"] = %e.property
          err["value"] = %e.value
          err["message"] = %e.message
          errors.add(err)
    of cssAtRule:
      let res = validateAtRule(data, node)
      if not res.valid:
        for e in res.errors:
          var err = newJObject()
          err["selector"] = %"@"
          err["property"] = %e.property
          err["value"] = %e.value
          err["message"] = %e.message
          errors.add(err)
        invalid += res.errors.len
    else: discard
  result = newJObject()
  result["total"] = %total
  result["invalid"] = %invalid
  result["valid"] = %(invalid == 0)
  result["errors"] = errors

proc initCss*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  script.addProc(module, "parseCss", @[paramDef("s", ttyString)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = initValue(tyPointer, CssBox(sheet: parseCss(args[0].stringVal[])))
      result.objectVal.foreign.tag = "CSSStylesheet")

  script.addProc(module, "parseCssFile", @[paramDef("path", ttyString)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = initValue(tyPointer, CssBox(sheet: parseCss(readFile(args[0].stringVal[]))))
      result.objectVal.foreign.tag = "CSSStylesheet")

  script.addProc(module, "getCss", @[paramDef("sheet", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue($getSheet(args[0])))

  script.addProc(module, "ruleCount", @[paramDef("sheet", ttyPointer)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(getSheet(args[0]).nodes.len.int64))

  script.addProc(module, "selectors", @[paramDef("sheet", ttyPointer)], ttyJson,
    proc (args: StackView, argc: int): Value =
      var arr = newJArray()
      for node in getSheet(args[0]).nodes:
        if node.kind == cssRuleSet:
          arr.add(%selectorText(node))
      result = initValue(arr))

  script.addProc(module, "cssValidate", @[paramDef("sheet", ttyPointer)], ttyJson,
    proc (args: StackView, argc: int): Value =
      result = initValue(validateSheet(getSheet(args[0]))))
