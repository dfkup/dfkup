import std/[unittest, options, strutils]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem, lowlibs/libical]

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
  let icalModule = newModule("ical", some"ical.dfkup")
  initIcal(script, icalModule)
  module.load(icalModule)
  script.stdpos = script.procs.high
  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = true
  gen.genScript(program, none(string))
  var vmInstance = newVm()
  let resultVal = vmInstance.interpret(script, mainChunk)
  if resultVal != nil and resultVal.typeId notin {tyNil}:
    result = $resultVal

const calDoc = "BEGIN:VCALENDAR\\r\\nVERSION:2.0\\r\\nPRODID:-//x//y//EN\\r\\nBEGIN:VEVENT\\r\\nUID:abc123\\r\\nDTSTAMP:20260101T000000Z\\r\\nDTSTART:20260301T100000Z\\r\\nSUMMARY:Party\\r\\nLOCATION:Home\\r\\nEND:VEVENT\\r\\nEND:VCALENDAR"

suite "ICal":
  test "event count":
    check run("let c = parseIcal(\"" & calDoc & "\")\neventCount(c)") == "1"
  test "events as json":
    check run("let c = parseIcal(\"" & calDoc & "\")\nevents(c)") == "[{\"uid\":\"abc123\",\"summary\":\"Party\",\"description\":null,\"location\":\"Home\",\"status\":null,\"url\":null,\"rrule\":null,\"dtstart\":\"20260301T100000Z\",\"dtend\":null,\"categories\":[]}]"
  test "calendar info":
    check run("let c = parseIcal(\"" & calDoc & "\")\ncalendarInfo(c)") == "{\"prodId\":\"-//x//y//EN\",\"version\":\"2.0\",\"eventCount\":1}"
  test "serialize round trip":
    let r = run("let c = parseIcal(\"" & calDoc & "\")\ntoIcal(c)")
    check r.len > 50
  test "parse file":
    check run("let c = parseIcalFile(\"tests/fixtures/sample.ics\")\neventCount(c)") == "1"
    check run("let c = parseIcalFile(\"tests/fixtures/sample.ics\")\ncalendarInfo(c)").contains("-//x//y//EN")
