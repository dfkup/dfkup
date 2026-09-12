import std/[unittest, options]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem, lowlibs/libcsv]

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
  let csvModule = newModule("csv", some"csv.dfkup")
  initCsv(script, csvModule)
  module.load(csvModule)
  script.stdpos = script.procs.high
  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = true
  gen.genScript(program, none(string))
  var vmInstance = newVm()
  let resultVal = vmInstance.interpret(script, mainChunk)
  if resultVal != nil and resultVal.typeId notin {tyNil}:
    result = $resultVal

suite "CSV":
  test "basic parse":
    check run("parseCsv(\"name,age\\nAda,36\")") == "[[\"name\",\"age\"],[\"Ada\",\"36\"]]"
  test "quoted field with delimiter":
    check run("parseCsv(\"a,b\\n\\\"Grace,H.\\\",85\")") == "[[\"a\",\"b\"],[\"Grace,H.\",\"85\"]]"
  test "custom delimiter":
    check run("parseCsv(\"a;b\\n1;2\", \";\")") == "[[\"a\",\"b\"],[\"1\",\"2\"]]"
  test "empty input":
    check run("parseCsv(\"\")") == "[]"
  test "parse file":
    check run("parseCsvFile(\"tests/fixtures/sample.csv\")") == "[[\"name\",\"age\"],[\"Ada\",\"36\"]]"
