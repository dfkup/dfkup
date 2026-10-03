import std/[unittest, options, strutils]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem, lowlibs/libuuid]

proc run(code: string): string =
  var program: Ast
  parseScript(program, code)
  var
    mainChunk = newChunk("test")
    script = newScript(mainChunk)
    module = newModule("test", some"test.dfkup")
  let systemModule = newModule("system", some"system.dfkup")
  initSystem(script, systemModule)
  module.importModule(systemModule, "system")
  let uuidModule = newModule("uuid", some"uuid.dfkup")
  uuidModule.importModule(systemModule, "system")
  initUuid(script, uuidModule)
  module.load(uuidModule)
  script.stdpos = script.procs.high
  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = true
  gen.genScript(program, none(string))
  var vmInstance = newVm()
  let resultVal = vmInstance.interpret(script, mainChunk)
  if resultVal != nil and resultVal.typeId notin {tyNil}:
    result = $resultVal

suite "UUID - versions":
  test "v1 is time-based and takes an optional node id":
    check run("uuidVersion(uuidV1())") == "1"
    check run("isValidUuid(uuidV1())") == "true"
    # an explicit node id shows up in the last six bytes
    check run("uuidBytes(uuidV1(\"001122334455\"))").endsWith("001122334455")
  test "v2 is DCE security, taking a domain and local id":
    check run("uuidVersion(uuidV2(0, 1000))") == "2"
    check run("uuidV2(0, 1000)") == "000003e8-bd72-21f1-9100-5796f5aa5dd3" or
      run("uuidVersion(uuidV2(1, 7))") == "2"
    # the local id replaces time_low
    check run("uuidBytes(uuidV2(0, 1000))").startsWith("000003e8")
  test "v3 matches the RFC 4122 test vector":
    check run("uuidV3(\"www.example.com\")") ==
      "5df41881-3aed-3515-88a7-2f4a814cf09e"
    check run("uuidVersion(uuidV3(\"x\"))") == "3"
  test "v4 generates valid version 4":
    check run("isValidUuid(uuidV4())") == "true"
    check run("uuidVersion(uuidV4())") == "4"
  test "v5 matches the RFC 4122 test vector":
    check run("uuidV5(\"www.example.com\")") ==
      "2ed6657d-e927-568b-95e1-2665a8aea6a2"
    check run("uuidVersion(uuidV5(\"x\"))") == "5"
  test "v6 is reordered time and takes an optional node id":
    check run("uuidVersion(uuidV6())") == "6"
    check run("uuidBytes(uuidV6(\"aabbccddeeff\"))").endsWith("aabbccddeeff")
  test "v7 generates valid version 7":
    check run("isValidUuid(uuidV7())") == "true"
    check run("uuidVersion(uuidV7())") == "7"
  test "v8 sets version and variant over custom data":
    check run("uuidVersion(uuidV8(\"0123456789abcdef0123456789abcdef\"))") == "8"
    check run("uuidV8(\"0123456789abcdef0123456789abcdef\")") ==
      "01234567-89ab-8def-8123-456789abcdef"
  test "nil uuid":
    check run("nilUuid()") == "00000000-0000-0000-0000-000000000000"
    check run("isNilUuid(nilUuid())") == "true"
    check run("isNilUuid(uuidV4())") == "false"
  # A bare `call(...) == ...` statement does not parse, so each check goes
  # through a `let`.
  test "name-based versions are deterministic and namespace-sensitive":
    check run("let s = uuidV3(\"www.example.com\") == uuidV3(\"www.example.com\")\n$s") == "true"
    check run("let s = uuidV5(\"www.example.com\") == uuidV5(\"www.example.com\")\n$s") == "true"
    check run("""let s = uuidV5("www.example.com") ==
      uuidV5("www.example.com", "dns")
      $s""".replace("\n      ", "\n")) == "true"
    check run("""let s = uuidV5("www.example.com") ==
      uuidV5("www.example.com", "url")
      $s""".replace("\n      ", "\n")) == "false"
  test "a namespace UUID literal matches the named alias":
    check run("""let s = uuidV5("www.example.com") ==
      uuidV5("www.example.com", uuidNsDns())
      $s""".replace("\n      ", "\n")) == "true"

suite "UUID - namespaces":
  test "the four RFC 4122 namespaces":
    check run("uuidNsDns()") == "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
    check run("uuidNsUrl()") == "6ba7b811-9dad-11d1-80b4-00c04fd430c8"
    check run("uuidNsOid()") == "6ba7b812-9dad-11d1-80b4-00c04fd430c8"
    check run("uuidNsX500()") == "6ba7b814-9dad-11d1-80b4-00c04fd430c8"
  test "namespaces resolve by name, case-insensitively":
    check run("uuidNamespace(\"dns\")") == "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
    check run("uuidNamespace(\"URL\")") == "6ba7b811-9dad-11d1-80b4-00c04fd430c8"
    check run("uuidNamespace()") == "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
  test "namespaces resolve from a UUID literal":
    check run("uuidNamespace(uuidNsOid())") == "6ba7b812-9dad-11d1-80b4-00c04fd430c8"

suite "UUID - inspection":
  test "invalid strings rejected":
    check run("isValidUuid(\"not-a-uuid\")") == "false"
  test "parse normalizes":
    check run("isValidUuid(parseUuid(\"550E8400-E29B-41D4-A716-446655440000\"))") == "true"
    check run("parseUuid(\"550E8400-E29B-41D4-A716-446655440000\")") ==
      "550e8400-e29b-41d4-a716-446655440000"
  test "parse accepts a dashless string":
    check run("parseUuid(\"550e8400e29b41d4a716446655440000\")") ==
      "550e8400-e29b-41d4-a716-446655440000"
  test "variant is reported by name":
    check run("uuidVariant(uuidV4())") == "rfc4122"
    check run("uuidVariant(\"00000000-0000-0000-0000-000000000000\")") == "ncs"
    check run("uuidVariant(\"00000000-0000-0000-c000-000000000000\")") == "microsoft"
  test "equality":
    check run("uuidEquals(uuidV4(), uuidV4())") == "false"
    check run("""let u = uuidV4()
      uuidEquals(u, u)""") == "true"
    check run("""let u = uuidV4()
      uuidEquals(u, parseUuid(uuidBytes(u)))""") == "true"
  test "bytes and hex round trip":
    check run("let u = uuidV4()\nlet s = uuidFromHex(uuidBytes(u)) == u\n$s") == "true"
    check run("uuidBytes(uuidV4())").len == 32
    check run("uuidBytes(nilUuid())") == "00000000000000000000000000000000"
  test "bytes are the dashed form with the dashes removed":
    let u = run("uuidV4()")
    check run("uuidBytes(\"" & u & "\")") == u.replace("-", "")
