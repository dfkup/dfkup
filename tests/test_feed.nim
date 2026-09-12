import std/[unittest, options]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem, lowlibs/libfeed]

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
  let feedModule = newModule("feed", some"feed.dfkup")
  initFeed(script, feedModule)
  module.load(feedModule)
  script.stdpos = script.procs.high
  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = true
  gen.genScript(program, none(string))
  var vmInstance = newVm()
  let resultVal = vmInstance.interpret(script, mainChunk)
  if resultVal != nil and resultVal.typeId notin {tyNil}:
    result = $resultVal

const atomDoc = "<?xml version='1.0'?><feed xmlns=\\\"http://www.w3.org/2005/Atom\\\"><id>urn:x</id><title>t</title><updated>2026-01-01T00:00:00Z</updated><author><name>Ann</name></author><entry><id>urn:e1</id><title>First</title><updated>2026-01-02T00:00:00Z</updated></entry></feed>"

suite "Feed":
  test "entry count":
    check run("let f = parseAtom(\"" & atomDoc & "\")\nentryCount(f)") == "1"
  test "entries as json":
    check run("let f = parseAtom(\"" & atomDoc & "\")\nentries(f)") == "[{\"id\":\"urn:e1\",\"title\":{\"kind\":\"text\",\"value\":\"First\"},\"updated\":\"2026-01-02T00:00:00Z\",\"published\":null,\"summary\":null,\"content\":null,\"authors\":[],\"links\":[],\"categories\":[]}]"
  test "feed info":
    check run("let f = parseAtom(\"" & atomDoc & "\")\nfeedInfo(f)") == "{\"id\":\"urn:x\",\"title\":{\"kind\":\"text\",\"value\":\"t\"},\"updated\":\"2026-01-01T00:00:00Z\",\"subtitle\":null,\"icon\":null,\"logo\":null,\"lang\":null,\"authors\":[{\"name\":\"Ann\",\"uri\":null,\"email\":null}],\"links\":[],\"entries\":[{\"id\":\"urn:e1\",\"title\":{\"kind\":\"text\",\"value\":\"First\"},\"updated\":\"2026-01-02T00:00:00Z\",\"published\":null,\"summary\":null,\"content\":null,\"authors\":[],\"links\":[],\"categories\":[]}]}"
  test "serialize round trip":
    let r = run("let f = parseAtom(\"" & atomDoc & "\")\ntoAtomXml(f)")
    check r.len > 50
