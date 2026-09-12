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

type
  MarkdownDoc = ref object
    md: Markdown
    html: string
    rendered: bool

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

proc wrapDoc(doc: MarkdownDoc): Value =
  result = initValue(tyPointer, doc)
  result.objectVal.foreign.tag = "MarkdownDoc"

proc getDoc(v: Value): MarkdownDoc =
  result = cast[MarkdownDoc](v.objectVal.foreign.data)

proc ensureRendered(doc: MarkdownDoc) =
  ## Render once and cache: marvdown fills heading selectors during toHtml,
  ## so every selector-based getter must render first.
  if not doc.rendered:
    var m = doc.md
    doc.html = m.toHtml()
    doc.rendered = true

proc initMarkdown*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  script.addProc(module, "parseMarkdown", @[paramDef("source", ttyString)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapDoc(MarkdownDoc(md: newMarkdown(args[0].stringVal[]))))

  script.addProc(module, "parseMarkdown", @[paramDef("source", ttyString),
      paramDef("opts", ttyJson)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      let opts = buildOptions(args[1].jsonVal)
      result = wrapDoc(MarkdownDoc(md: newMarkdown(args[0].stringVal[], opts))))

  script.addProc(module, "parseMarkdownFile", @[paramDef("path", ttyString)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapDoc(MarkdownDoc(md: newMarkdown(readFile(args[0].stringVal[])))))

  script.addProc(module, "parseMarkdownFile", @[paramDef("path", ttyString),
      paramDef("opts", ttyJson)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      let opts = buildOptions(args[1].jsonVal)
      result = wrapDoc(MarkdownDoc(md: newMarkdown(readFile(args[0].stringVal[]), opts))))

  script.addProc(module, "getHtml", @[paramDef("doc", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      let doc = getDoc(args[0])
      ensureRendered(doc)
      result = initValue(doc.html))

  script.addProc(module, "getHeadings", @[paramDef("doc", ttyPointer)], ttyJson,
    proc (args: StackView, argc: int): Value =
      let doc = getDoc(args[0])
      ensureRendered(doc)
      var arr = newJArray()
      for item in doc.md.getSelectorItems():
        var o = newJObject()
        o["level"] = %(item.level)
        o["anchor"] = %(item.anchor)
        o["title"] = %(item.title)
        arr.add(o)
      result = initValue(arr))

  script.addProc(module, "getTitle", @[paramDef("doc", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      let doc = getDoc(args[0])
      ensureRendered(doc)
      result = initValue(doc.md.getTitle()))

  script.addProc(module, "getMeta", @[paramDef("doc", ttyPointer)], ttyJson,
    proc (args: StackView, argc: int): Value =
      let doc = getDoc(args[0])
      let header = doc.md.getHeader()
      if header == nil:
        result = initValue(newJNull())
      else:
        var o = newJObject()
        for k, v in header:
          o[k] = yamlNodeToJson(v)
        result = initValue(o))

  script.addProc(module, "hasHeadings", @[paramDef("doc", ttyPointer)], ttyBool,
    proc (args: StackView, argc: int): Value =
      let doc = getDoc(args[0])
      ensureRendered(doc)
      result = initValue(doc.md.hasSelectors()))

  script.addProc(module, "hasFootnotes", @[paramDef("doc", ttyPointer)], ttyBool,
    proc (args: StackView, argc: int): Value =
      let doc = getDoc(args[0])
      result = initValue(doc.md.hasFootnotes()))

  script.addProc(module, "getJson", @[paramDef("doc", ttyPointer)], ttyJson,
    proc (args: StackView, argc: int): Value =
      let doc = getDoc(args[0])
      result = initValue(parseJson(doc.md.toJson())))
