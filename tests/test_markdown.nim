import std/[unittest, options, strutils]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem, lowlibs/libjson, lowlibs/libmarkdown]

proc run(code: string): string =
  var program: Ast
  parseScript(program, code)
  var
    mainChunk = newChunk("test")
    script = newScript(mainChunk)
    module = newModule("test", some"test.dfkup")
  let systemModule = newModule("system", some"system.dfkup")
  initSystem(script, systemModule)
  module.load(systemModule)
  let mdModule = newModule("markdown", some"markdown.dfkup")
  initMarkdown(script, mdModule)
  module.load(mdModule)
  let jsonModule = newModule("json", some"json.dfkup")
  initJson(script, jsonModule)
  module.load(jsonModule)
  script.stdpos = script.procs.high
  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = true
  gen.genScript(program, none(string))
  var vmInstance = newVm()
  let resultVal = vmInstance.interpret(script, mainChunk)
  if resultVal != nil and resultVal.typeId notin {tyNil}:
    result = $resultVal

const docSrc = "\"# Hello\\n\\nworld\\n\\n## Sub\\n\""

proc md(code: string): string =
  run("let md = parseMarkdown(" & docSrc & ")\nmd." & code)

suite "Markdown":
  test "title and headings":
    check md("getTitle()") == "Hello"
    check md("getHeadings()") == "[{\"level\":1,\"anchor\":\"hello\",\"title\":\"Hello\"},{\"level\":2,\"anchor\":\"sub\",\"title\":\"Sub\"}]"
    check md("hasHeadings()") == "true"
    check run("let md = parseMarkdown(\"no headings\")\nmd.hasHeadings()") == "false"
    check run("let md = parseMarkdown(\"no headings\")\nmd.getTitle()") == "Untitled document"
  test "html rendering":
    let html = md("getHtml()")
    check html.contains("<h1")
    check html.contains("Hello")
    check html.contains("<h2")
  test "options disable anchors":
    check md("getHtml()").contains("anchor-link")
    let noAnchors = run("let md = parseMarkdown(\"# Hello\\n\\nworld\\n\\n## Sub\\n\", parseJson(\"{\\\"anchors\\\": false}\"))\nmd.getHtml()")
    check not noAnchors.contains("anchor-link")
    check noAnchors.contains("<h1>")
  test "ast json":
    let j = md("getJson()")
    check j.len > 10
  test "front matter":
    check run("let md = parseMarkdown(\"---\\ntitle: Hi\\n---\\n\\nbody\")\nmd.getMeta()") == "{\"title\":\"Hi\"}"
    check run("let md = parseMarkdown(\"no front matter\")\nmd.getMeta()") == "null"
  test "footnotes flag":
    check md("hasFootnotes()") == "false"
  test "parse file":
    check run("let md = parseMarkdownFile(\"tests/fixtures/sample.md\")\nmd.getTitle()") == "Sample Doc"
    check run("let md = parseMarkdownFile(\"tests/fixtures/sample.md\")\nmd.hasFootnotes()") == "true"
    check run("let md = parseMarkdownFile(\"tests/fixtures/sample.md\")\nmd.getMeta()").contains("\"title\":\"Sample Doc\"")
    let headings = run("let md = parseMarkdownFile(\"tests/fixtures/sample.md\")\nmd.getHeadings()")
    check headings.contains("\"level\":1")
    check headings.contains("\"level\":3")
