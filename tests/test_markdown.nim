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

const doc = "# Hello\\n\\nworld\\n\\n## Sub\\n"

suite "Markdown":
  test "title and toc":
    check run("markdownTitle(\"" & doc & "\")") == "Hello"
    check run("markdownToc(\"" & doc & "\")") == "[{\"level\":1,\"anchor\":\"hello\",\"title\":\"Hello\"},{\"level\":2,\"anchor\":\"sub\",\"title\":\"Sub\"}]"
    check run("markdownHasHeadings(\"" & doc & "\")") == "true"
    check run("markdownHasHeadings(\"no headings\")") == "false"
    check run("markdownTitle(\"no headings\")") == "Untitled document"
  test "html rendering":
    let html = run("markdownToHtml(\"" & doc & "\")")
    check html.contains("<h1")
    check html.contains("Hello")
    check html.contains("<h2")
  test "options disable anchors":
    let html = run("markdownToHtmlOpts(\"" & doc & "\", parseJson(\"{\\\"anchors\\\": false}\"))")
    check not html.contains("anchor-link")
    check html.contains("<h1>")
  test "ast json":
    let j = run("markdownToJson(\"" & doc & "\")")
    check j.len > 10
  test "front matter":
    check run("markdownMeta(\"---\\ntitle: Hi\\n---\\n\\nbody\")") == "{\"title\":\"Hi\"}"
    check run("markdownMeta(\"no front matter\")") == "null"
  test "footnotes flag":
    check run("markdownHasFootnotes(\"" & doc & "\")") == "false"
