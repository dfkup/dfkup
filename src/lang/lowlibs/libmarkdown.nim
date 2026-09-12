# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/[json, options, tables]
import pkg/marvdown
import pkg/marvdown/parser
import pkg/openparser/[html, yaml]
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

proc yamlNodeToJson(n: YamlNode): JsonNode =
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
      result[k] = yamlNodeToJson(v)
  of yamlArray:
    result = newJArray()
    for item in n.arrValue:
      result.add(yamlNodeToJson(item))

proc optBool(opts: JsonNode, key: string, default: bool): bool =
  if opts != nil and opts.kind == JObject and opts.hasKey(key):
    try: opts[key].getBool()
    except CatchableError: default
  else: default

proc optStr(opts: JsonNode, key: string, default: string): string =
  if opts != nil and opts.kind == JObject and opts.hasKey(key):
    try: opts[key].getStr()
    except CatchableError: default
  else: default

proc buildOptions(opts: JsonNode): MarkdownOptions =
  result = MarkdownOptions(
    allowed: @[
      tagA, tagAbbr, tagB, tagBlockquote, tagBr,
      tagCode, tagDel, tagEm, tagH1, tagH2, tagH3, tagH4, tagH5, tagH6,
      tagHr, tagI, tagImg, tagLi, tagOl, tagP, tagPre, tagStrong, tagTable,
      tagTbody, tagTd, tagTh, tagThead, tagTr, tagUl, tagMark, tagSmall,
      tagSub, tagSup
    ],
    allowTagsByType: none(TagType),
    allowInlineStyle: optBool(opts, "inlineStyle", false),
    allowHtmlAttributes: optBool(opts, "htmlAttrs", false),
    enableAnchors: optBool(opts, "anchors", true),
    anchorIcon: optStr(opts, "anchorIcon", "🔗"),
    showFootnotes: true,
    htmlTableClasses: none(seq[string]),
    enableEmailAutolinks: optBool(opts, "emailAutolinks", false),
    enableComponents: optBool(opts, "components", false),
    componentBaseDir: optStr(opts, "baseDir", ""),
    customTransform: nil,
    lazyloadIframes: false,
    lazyloadVideos: false,
    lazyloadImages: false,
    parseYaml: optBool(opts, "parseYaml", true)
  )

proc initMarkdown*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  script.addProc(module, "markdownToHtml", @[paramDef("md", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(marvdown.toHtml(args[0].stringVal[])))

  script.addProc(module, "markdownToHtmlOpts", @[paramDef("md", ttyString),
      paramDef("opts", ttyJson)], ttyString,
    proc (args: StackView, argc: int): Value =
      let opts = buildOptions(args[1].jsonVal)
      var md = newMarkdown(args[0].stringVal[], opts)
      result = initValue(md.toHtml()))

  script.addProc(module, "markdownToJson", @[paramDef("md", ttyString)], ttyJson,
    proc (args: StackView, argc: int): Value =
      var md = newMarkdown(args[0].stringVal[])
      result = initValue(parseJson(md.toJson())))

  script.addProc(module, "markdownTitle", @[paramDef("md", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      var md = newMarkdown(args[0].stringVal[])
      discard md.toHtml()
      result = initValue(md.getTitle()))

  script.addProc(module, "markdownToc", @[paramDef("md", ttyString)], ttyJson,
    proc (args: StackView, argc: int): Value =
      var md = newMarkdown(args[0].stringVal[])
      discard md.toHtml()
      var arr = newJArray()
      for item in md.getSelectorItems():
        var o = newJObject()
        o["level"] = %(item.level)
        o["anchor"] = %(item.anchor)
        o["title"] = %(item.title)
        arr.add(o)
      result = initValue(arr))

  script.addProc(module, "markdownHasHeadings", @[paramDef("md", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      var md = newMarkdown(args[0].stringVal[])
      discard md.toHtml()
      result = initValue(md.hasSelectors()))

  script.addProc(module, "markdownMeta", @[paramDef("md", ttyString)], ttyJson,
    proc (args: StackView, argc: int): Value =
      var md = newMarkdown(args[0].stringVal[])
      let header = md.getHeader()
      if header == nil:
        result = initValue(newJNull())
      else:
        var o = newJObject()
        for k, v in header:
          o[k] = yamlNodeToJson(v)
        result = initValue(o))

  script.addProc(module, "markdownHasFootnotes", @[paramDef("md", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      var md = newMarkdown(args[0].stringVal[])
      result = initValue(md.hasFootnotes()))
