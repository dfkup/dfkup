import std/[unittest, options, strutils]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem, lowlibs/libalgos]

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
  let algosModule = newModule("algos", some"algos.dfkup")
  initAlgos(script, algosModule)
  module.load(algosModule)
  script.stdpos = script.procs.high
  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = true
  gen.genScript(program, none(string))
  var vmInstance = newVm()
  let resultVal = vmInstance.interpret(script, mainChunk)
  if resultVal != nil and resultVal.typeId notin {tyNil}:
    result = $resultVal

suite "Algos":
  test "known answer hashes":
    check run("sha512Hex(\"abc\")") == "DDAF35A193617ABACC417349AE20413112E6FA4E89A97EA20A9EEEE64B55D39A2192992A274FC1A836BA3C23A3FEEBBD454D4423643CE80E2A9AC94FA54CA49F"
    check run("blakeHex(\"abc\", 32)") == "BDDD813C634239723171EF3FEE98579B94964E3BB1CB3E427262C8C068D52319"
  test "hmac and hkdf":
    let h = run("hmacSha512Hex(\"6b6579\", \"The quick brown fox jumps over the lazy dog\")")
    check h == "B42AF09057BAC1E2D41708E48A902E09B5FF7F12AB428A4FE86653C73DD248FB82F948A549F7B791A5B41915EE4D1EC3935357E4E2317250D0372AFA2EBEEB3A"
    check run("hmacSha512Hex(\"6b6579\", \"x\")").len == 128
    check run("hkdfSha512Hex(\"ikm\", \"salt\", \"info\", 42)").len == 84
  test "xchacha seal round trip":
    check run("let k = genKey32()\nlet s = seal(\"hello dfkup\", k)\nunseal(s, k)") == "hello dfkup"
    check run("len(genKey32())") == "64"
  test "aes-gcm seal round trip":
    check run("let k = genKey32()\nlet s = gcmSealHex(\"hello dfkup\", k)\ngcmOpenHex(s, k)") == "hello dfkup"
  test "argon2 password hashing":
    check run("let h = hashPassword(\"hunter2\")\nverifyPassword(\"hunter2\", h)") == "true"
    check run("let h = hashPassword(\"hunter2\")\nverifyPassword(\"wrong\", h)") == "false"
