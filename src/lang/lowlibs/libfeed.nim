# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/[json, options]
import pkg/openparser/feed
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

type
  FeedBox = ref object
    feed: AtomFeed

proc getFeed(v: Value): AtomFeed =
  cast[FeedBox](v.objectVal.foreign.data).feed

proc optStr(o: Option[string]): JsonNode =
  if o.isSome: %(o.get()) else: newJNull()

proc textToJson(t: AtomText): JsonNode =
  result = newJObject()
  result["kind"] = %(t.kind)
  result["value"] = %(t.value)

proc personToJson(p: AtomPerson): JsonNode =
  result = newJObject()
  result["name"] = %(p.name)
  result["uri"] = optStr(p.uri)
  result["email"] = optStr(p.email)

proc linkToJson(l: AtomLink): JsonNode =
  result = newJObject()
  result["href"] = %(l.href)
  result["rel"] = optStr(l.rel)
  result["type"] = optStr(l.mimeType)
  result["hreflang"] = optStr(l.hreflang)
  result["title"] = optStr(l.title)
  if l.length.isSome: result["length"] = %(l.length.get())
  else: result["length"] = newJNull()

proc categoryToJson(c: AtomCategory): JsonNode =
  result = newJObject()
  result["term"] = %(c.term)
  result["scheme"] = optStr(c.scheme)
  result["label"] = optStr(c.label)

proc contentToJson(c: AtomContent): JsonNode =
  result = newJObject()
  result["type"] = optStr(c.kind)
  result["src"] = optStr(c.src)
  result["value"] = optStr(c.value)

proc entryToJson(e: AtomEntry): JsonNode =
  result = newJObject()
  result["id"] = %(e.id)
  result["title"] = textToJson(e.title)
  result["updated"] = %(e.updated)
  result["published"] = optStr(e.published)
  if e.summary.isSome: result["summary"] = textToJson(e.summary.get())
  else: result["summary"] = newJNull()
  if e.content.isSome: result["content"] = contentToJson(e.content.get())
  else: result["content"] = newJNull()
  var authors = newJArray()
  for a in e.authors: authors.add(personToJson(a))
  result["authors"] = authors
  var links = newJArray()
  for l in e.links: links.add(linkToJson(l))
  result["links"] = links
  var cats = newJArray()
  for c in e.categories: cats.add(categoryToJson(c))
  result["categories"] = cats

proc feedToJson(f: AtomFeed): JsonNode =
  result = newJObject()
  result["id"] = %(f.id)
  result["title"] = textToJson(f.title)
  result["updated"] = %(f.updated)
  result["subtitle"] = if f.subtitle.isSome: textToJson(f.subtitle.get()) else: newJNull()
  result["icon"] = optStr(f.icon)
  result["logo"] = optStr(f.logo)
  result["lang"] = optStr(f.lang)
  var authors = newJArray()
  for a in f.authors: authors.add(personToJson(a))
  result["authors"] = authors
  var links = newJArray()
  for l in f.links: links.add(linkToJson(l))
  result["links"] = links
  var entries = newJArray()
  for e in f.entries: entries.add(entryToJson(e))
  result["entries"] = entries

proc wrapFeed(f: AtomFeed): Value =
  result = initValue(tyPointer, FeedBox(feed: f))
  result.objectVal.foreign.tag = "AtomFeed"

proc initFeed*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  script.addProc(module, "parseAtom", @[paramDef("s", ttyString)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapFeed(parseAtom(args[0].stringVal[])))

  script.addProc(module, "fetchAtom", @[paramDef("url", ttyString)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapFeed(fetchAtom(args[0].stringVal[])))

  script.addProc(module, "feedInfo", @[paramDef("feed", ttyPointer)], ttyJson,
    proc (args: StackView, argc: int): Value =
      result = initValue(feedToJson(getFeed(args[0]))))

  script.addProc(module, "entries", @[paramDef("feed", ttyPointer)], ttyJson,
    proc (args: StackView, argc: int): Value =
      var arr = newJArray()
      for e in getFeed(args[0]).entries:
        arr.add(entryToJson(e))
      result = initValue(arr))

  script.addProc(module, "entryCount", @[paramDef("feed", ttyPointer)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(getFeed(args[0]).entries.len.int64))

  script.addProc(module, "toAtomXml", @[paramDef("feed", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(toAtomXml(getFeed(args[0]))))
