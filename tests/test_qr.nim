import std/[unittest, options, strutils, os]
import ../src/lang/transformers
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import pkg/openparser/qr
import ../src/lang/[parser, lowlibs/libsystem, lowlibs/libjson, lowlibs/libqr]

proc interpret(code: string): Value =
  var program: Ast
  parseScript(program, code)
  var
    mainChunk = newChunk("test")
    script = newScript(mainChunk)
    module = newModule("test", some"test.dfkup")
  let systemModule = newModule("system", some"system.dfkup")
  initSystem(script, systemModule)
  module.importModule(systemModule, "system")
  let qrModule = newModule("qr", some"qr.dfkup")
  qrModule.importModule(systemModule, "system")
  initQr(script, qrModule)
  module.load(qrModule)
  # options arguments are json, so the qr bindings need them to be loaded
  let jsonModule = newModule("json", some"json.dfkup")
  jsonModule.importModule(systemModule, "system")
  initJson(script, jsonModule)
  module.load(jsonModule)
  script.stdpos = script.procs.high
  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = true
  gen.genScript(program, none(string))
  var vmInstance = newVm()
  result = vmInstance.interpret(script, mainChunk)

# The SQRC tests splice their 32-hex-digit keys into dfkup source: the literal
# `"KEY"` becomes the right key and `"BADKEY"` a different one.
const
  SqrcKey = "000102030405060708090a0b0c0d0e0f"
  SqrcBadKey = "0f0e0d0c0b0a09080706050403020100"

proc substKeys(code: string): string =
  code.replace("\"BADKEY\"", "\"" & SqrcBadKey & "\"").replace(
    "\"KEY\"", "\"" & SqrcKey & "\"")

proc run(code: string): string =
  let v = interpret(substKeys(code))
  if v != nil and v.typeId notin {tyNil}:
    result = $v

proc raises(code: string) =
  var threw = false
  try:
    discard interpret(code)
  except CatchableError:
    threw = true
  check threw

suite "QR - Model 2 rendering":
  test "svg output":
    let r = run("qrSvg(\"hello\", 4, 2)")
    check r.contains("<svg")
    check r.contains("<path")
  test "terminal output":
    let r = run("qrTerminal(\"hi\", 1)")
    check r.len > 10
  test "render options are honoured":
    let small = run("qrSvg(\"hello\", 2, 1)")
    let big = run("qrSvg(\"hello\", 12, 4)")
    check len(small) < len(big)
  test "svg colours":
    let r = run("""let o = parseJson("{\"scale\":4,\"border\":2,\"dark\":\"#ff0000\"}")
      qrSvg("hello", o)""")
    check r.contains("#ff0000")
  test "error correction level changes the matrix":
    let low = run("""let r = qrRows("hello", parseJson("{\"ec\":\"L\"}"))
      $r[0]""")
    let high = run("""let r = qrRows("hello", parseJson("{\"ec\":\"H\"}"))
      $r[0]""")
    check low != high

suite "QR - encoding families":
  test "model 2 round trips":
    check run("qrDecodeText(qrRows(\"hello world\"))") == "hello world"
  test "model 2 handles unicode":
    check run("qrDecodeText(qrRows(\"Héllo wörld ünïcode ✓\"))") ==
      "Héllo wörld ünïcode ✓"
  test "model 2 with options":
    check run("""let o = parseJson("{\"ec\":\"Q\",\"minVersion\":3,\"maxVersion\":5}")
      qrDecodeText(qrRows("opts", o))""") == "opts"
  test "raw bytes":
    check run("qrDecodeText(qrRowsBytes(parseJson(\"[104,105]\")))") == "hi"
  test "micro round trips and reports its family":
    check run("""let d = qrDecodeRows(qrMicroRows("hi"))
      $d["ok"] & " " & $d["family"] & " " & $d["text"]""") ==
      "true \"micro\" \"hi\""
  test "micro svg renders":
    check run("qrMicroSvg(\"hi\")").contains("<svg")
  test "rmqr round trips and reports its family":
    check run("""let d = qrDecodeRows(qrRmqrRows("hello"))
      $d["ok"] & " " & $d["family"] & " " & $d["text"]""") ==
      "true \"rmqr\" \"hello\""
  test "rmqr svg renders":
    check run("qrRmqrSvg(\"hi\")").contains("<svg")
  test "rmqr honours a fixed size designation":
    check run("""let o = parseJson("{\"version\":\"R11x139\"}")
      $len(qrRmqrSvg("1234", o))""") == "12285"
  test "model 1 round trips and reports its family":
    check run("""let d = qrDecodeRows(qrModel1Rows("hi"))
      $d["ok"] & " " & $d["family"] & " " & $d["text"]""") ==
      "true \"model1\" \"hi\""
  test "model 1 svg renders":
    check run("qrModel1Svg(\"hi\")").contains("<svg")

suite "QR - decode text is family agnostic":
  # qrDecodeText used to only try model 2, so it raised on the other three
  test "qrDecodeText handles every family":
    check run("qrDecodeText(qrRows(\"m2\"))") == "m2"
    check run("qrDecodeText(qrMicroRows(\"micro\"))") == "micro"
    check run("qrDecodeText(qrRmqrRows(\"rmqr\"))") == "rmqr"
    check run("qrDecodeText(qrModel1Rows(\"model1\"))") == "model1"
  test "a decode after another family still works":
    check run("""let a = qrDecodeText(qrRows("first"))
      let b = qrDecodeText(qrMicroRows("second"))
      a & "/" & b""") == "first/second"

suite "QR - decode details":
  test "decode reports the symbol metadata":
    check run("""let d = qrDecodeRows(qrRows("01234567"))
      let v = d["version"]
      let e = d["ec"]
      let s = d["segments"]
      $v & " " & $e & " " & $len(s)""") == "1 \"M\" 1"
  test "a failed decode reports ok=false":
    check run("""let d = qrDecodeRows(parseJson("[\"00000\",\"11111\",\"00000\",\"11111\",\"00000\"]"))
      $d["ok"]""") == "false"
  test "malformed matrices are rejected":
    check run("""let d = qrDecodeRows(parseJson("[\"00\"]"))
      $d["ok"]""") == "false"
    raises """qrDecodeRows(parseJson("[\"0x1\",\"10\"]"))"""
    raises """qrDecodeRows(parseJson("[\"01\",\"0\"]"))"""

suite "QR - payload builders":
  test "wifi escapes special characters":
    check run("qrWifiPayload(\"home\", \"pass;word\")") ==
      "WIFI:T:WPA;S:home;P:pass\\;word;;"
  test "wifi without a password":
    check run("qrWifiPayload(\"open\")") == "WIFI:T:nopass;S:open;;"
  test "mecard":
    check run("qrMecardPayload(\"Doe;John\", \"+1555000111\")") ==
      "MECARD:N:Doe\\;John;TEL:+1555000111;;"
  test "url gains a scheme":
    check run("qrUrlPayload(\"example.org/path\")") == "https://example.org/path"
    check run("qrUrlPayload(\"http://insecure.example\")") ==
      "http://insecure.example"
  test "sms":
    check run("qrSmsPayload(\"+1555000111\", \"hi\")") == "SMSTO:+1555000111:hi"
  test "email":
    check run("qrEmailPayload(\"a@b.org\", \"Hello\")") ==
      "mailto:a@b.org?subject=Hello"
    check run("qrEmailPayload(\"a@b.org\", \"Hi\", \"Body\")") ==
      "mailto:a@b.org?subject=Hi&body=Body"
  test "vcard":
    check run("""let c = parseJson("{\"fullName\":\"Ada Lovelace\",\"org\":\"OpenPeeps\"}")
      qrVcardPayload(c)""").contains("FN:Ada Lovelace")
  test "payloads feed the encoder":
    check run("qrDecodeText(qrRows(qrWifiPayload(\"net\", \"secret1234\")))") ==
      "WIFI:T:WPA;S:net;P:secret1234;;"

suite "QR - AQR dual payload":
  test "ring round trip":
    check run("qrAqrRing(qrAqrRows(\"https://example.org\", \"RING-42\"))") ==
      "RING-42"
  test "the core stays decodable":
    check run("""let rows = qrAqrRows("https://example.org/main", "X1")
      let core = qrAqrDecodeCore(qrAqrCoreRows(rows))
      $core["text"]""") == "\"https://example.org/main\""
  test "aqr svg renders":
    check run("qrAqrSvg(\"main\", \"ring\")").contains("<svg")

suite "QR - SQRC sealed payloads":
  test "compat round trip":
    check run("""let s = qrDecodeText(qrSqrcRows("serial 4711", "code 99-FOO", "KEY"))
      let o = qrSqrcOpenText(s, "KEY")
      $o["ok"] & " " & $o["publicText"] & " " & $o["privateText"]""") == "true \"serial 4711\" \"code 99-FOO\""
  test "seal and open round trip":
    check run("""let blob = qrSqrcSeal("top secret", "KEY", "public", true)
      qrSqrcOpen(blob, "KEY", "public", true)""") == "top secret"
  test "split exposes the public area without a key":
    check run("""let s = qrDecodeText(qrSqrcRows("pub", "priv", "KEY"))
      let p = qrSqrcSplit(s)
      $p["publicData"]""") == "\"pub\""
  test "a wrong key fails cleanly":
    check run("""let s = qrDecodeText(qrSqrcRows("pub", "priv", "KEY"))
      let o = qrSqrcOpenText(s, "BADKEY")
      $o["ok"] & " " & $o["privateText"]""") == "false \"\""
  test "a plain payload is not sqrc":
    raises """qrSqrcSplit(qrDecodeText(qrRows("just a normal qr code")))"""

suite "QR - Reed-Solomon":
  test "parity round trips through a valid check":
    check run("""let parity = qrRsEncode(parseJson("[32,91,11,120,209,114,220,77,67]"), 10)
      $len(parity)""") == "10"
  test "hex helpers agree with the array form":
    check run("""let h = qrRsEncodeHex("205b0b78d172dc4d43", 10)
      $len(h)""") == "20"
  test "a clean codeword validates":
    check run("""let data = "205b0b78d172dc4d43"
      let parity = qrRsEncodeHex(data, 10)
      $qrRsIsValid(data & parity, 10)""") == "true"
  test "decoding repairs a corrupted codeword":
    check run("""let data = "205b0b78d172dc4d43"
      let parity = qrRsEncodeHex(data, 10)
      # flip one hex digit in the data region
      let damaged = "305b0b78d172dc4d43" & parity
      let r = qrRsDecodeHex(damaged, 10)
      $r["ok"]""") == "true"
  test "galois arithmetic":
    check run("qrGalois(\"mul\", 3, 4)") == "12"
    check run("qrGalois(\"div\", 12, 3)") == "4"
    check run("qrGalois(\"inv\", 1)") == "1"
    check run("qrGalois(\"inv\", 3)") == "244"
  test "an unknown galois op is rejected":
    raises """qrGalois("nope", 1, 2)"""
  test "polynomial helpers":
    check run("qrPolyMul(parseJson(\"[1,2]\"), parseJson(\"[1,1]\"))") == "[1,3,2]"
    check run("qrPolyEval(parseJson(\"[1,2,3]\"), 2)") == "3"

suite "QR - geometry and capacity":
  test "data codeword capacity":
    check run("qrDataCodewords(1, \"L\")") == "19"
    check run("qrDataCodewords(1, \"H\")") == "9"
    check run("qrDataCodewords(10, \"M\")") == "216"
  test "alignment positions":
    check run("qrAlignmentPositions(7)") == "[6,22,38]"
    check run("qrAlignmentPositions(1)") == "[]"
  test "model 1 size":
    check run("qrModel1Size(1)") == "21"
    check run("qrModel1Size(3)") == "29"
  test "micro capacity is reported in bits":
    check run("qrMicroCapacity(4, \"L\")") == "128"
  test "rmqr size names":
    check run("qrRmqrSizeName(0)") == "R7x43"
  test "penalty score of a real symbol is positive":
    check run("""let s = qrPenaltyScore(qrRows("x"))
      $s""") == "353"
  test "the reserved map covers every module of a version":
    check run("""let m = qrReservedMap(1)
      $len(m)""") == "441"

suite "QR - image decoding":
  # The PGM writer lives here rather than in dfkup because dfkup arrays do
  # not support `&` concatenation, which a pixel buffer needs.
  proc writePgm(path, text: string, scale, border: int) =
    let m = encodeQr(text)
    let side = m.width
    let total = (side + border + border) * scale
    var pixels = newString(total * total)
    for y in 0 ..< total:
      for x in 0 ..< total:
        # inverted, because PGM is 0 = black
        let mx = (x div scale) - border
        let my = (y div scale) - border
        let dark =
          if mx >= 0 and my >= 0 and mx < m.width and my < m.height and m[mx, my]:
            true
          else:
            false
        pixels[y * total + x] = (if dark: '\x00' else: '\xFF')
    writeFile(path, "P5\n" & $total & " " & $total & "\n255\n" & pixels)

  test "decodes a symbol from a binary PGM":
    let path = getTempDir() / "dfkup_qr_test.pgm"
    writePgm(path, "https://openparser.dev/qr", 8, 4)
    try:
      check run("let d = qrDecodePgm(\"" & $path & "\")\n$d[\"ok\"]") == "true"
      check run("let d = qrDecodePgm(\"" & $path & "\")\n$d[\"text\"]") ==
        "\"https://openparser.dev/qr\""
    finally:
      removeFile(path)

  test "decodes a symbol from a raw pixel array":
    # the decoder needs about four pixels per module to find the grid
    let scale = 4
    let border = 4
    let m = encodeQr("https://openparser.dev/qr")
    let total = (m.width + border + border) * scale
    var pixels = newSeq[int](total * total)
    for y in 0 ..< total:
      for x in 0 ..< total:
        let mx = (x div scale) - border
        let my = (y div scale) - border
        pixels[y * total + x] =
          if mx >= 0 and my >= 0 and mx < m.width and my < m.height and m[mx, my]:
            0
          else:
            255
    let json = "[" & pixels.join(",") & "]"
    check run("let d = qrDecodeImage(" & $total & ", " & $total &
      ", parseJson(\"" & json & "\"))\n$d[\"ok\"]") == "true"

  test "a pixel count mismatch is reported":
    raises """qrDecodeImage(4, 4, parseJson("[0,0,0]"))"""

  test "a non-PGM file is rejected":
    let path = getTempDir() / "dfkup_qr_not.pgm"
    writeFile(path, "not an image at all")
    try:
      raises "qrDecodePgm(\"" & $path & "\")"
    finally:
      removeFile(path)
