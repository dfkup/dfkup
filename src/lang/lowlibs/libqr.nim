# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/[json, strutils, math]
import pkg/openparser/qr
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

type
  QrBindError* = object of ValueError

proc familyName(f: QrFamily): string =
  ## Human-readable name for a QR symbology family.
  case f
  of famModel1: "model1"
  of famModel2: "model2"
  of famMicro: "micro"
  of famRmqr: "rmqr"

#
# Option reading
#
# Most entry points take an options object rather than a long positional
# list, so scripts can pass only what they care about. Anything absent falls
# back to openparser's default.
#

proc optArg(args: StackView, argc: int, i: int): JsonNode =
  ## Read an optional `options` argument. An omitted one arrives as a json
  ## null, so treat anything that is not an object as "no options".
  if i >= 0 and i < argc and args[i].typeId == tyJsonStorage and
     args[i].jsonVal != nil and args[i].jsonVal.kind == JObject:
    return args[i].jsonVal
  newJObject()

proc optStr(o: JsonNode, key: string, default: string): string =
  if o != nil and o.kind == JObject and o.hasKey(key) and
     o[key].kind == JString:
    return o[key].getStr()
  default

proc optInt(o: JsonNode, key: string, default: int): int =
  if o != nil and o.kind == JObject and o.hasKey(key):
    case o[key].kind
    of JInt: return o[key].getInt()
    of JFloat: return o[key].getFloat.int
    else: discard
  default

proc optBool(o: JsonNode, key: string, default: bool): bool =
  if o != nil and o.kind == JObject and o.hasKey(key) and
     o[key].kind == JBool:
    return o[key].getBool()
  default

proc parseEc(raw: string, default: QrEcLevel): QrEcLevel =
  ## Parse an error correction level, accepting a letter or a word.
  case raw.toLowerAscii
  of "": default
  of "l", "low": ecLow
  of "m", "medium": ecMedium
  of "q", "quartile": ecQuartile
  of "h", "high": ecHigh
  else: raise newException(QrBindError, "unknown error correction level: " & raw)

proc optEc(o: JsonNode, default: QrEcLevel): QrEcLevel =
  ## Read an error correction level out of an options object.
  parseEc(optStr(o, "ec", ""), default)

proc optOptions(o: JsonNode): QrEncodeOptions =
  ## Build a `QrEncodeOptions` from a dfkup options object.
  result = defaultQrEncodeOptions()
  if o == nil or o.kind != JObject: return
  result.ecLevel = optEc(o, result.ecLevel)
  result.minVersion = optInt(o, "minVersion", result.minVersion)
  result.maxVersion = optInt(o, "maxVersion", result.maxVersion)
  result.mask = optInt(o, "mask", result.mask)
  result.eci = optInt(o, "eci", result.eci)
  if o.hasKey("structuredAppend") and o["structuredAppend"].kind == JObject:
    let sa = o["structuredAppend"]
    result.structuredAppend.enabled = optBool(sa, "enabled", false)
    result.structuredAppend.index = optInt(sa, "index", 0)
    result.structuredAppend.total = optInt(sa, "total", 0)
    result.structuredAppend.parity = byte(optInt(sa, "parity", 0))

#
# Matrix conversion
#
# A `QrMatrix` cannot cross into dfkup, so matrices travel as an array of
# row strings, one character per module: "1" is dark, "0" is light.
#

proc matrixToRows(m: QrMatrix): JsonNode =
  result = newJArray()
  for y in 0 ..< m.height:
    var row = newStringOfCap(m.width)
    for x in 0 ..< m.width:
      row.add(if m[x, y]: '1' else: '0')
    result.add(newJString(row))

proc rowsToMatrix(n: JsonNode): QrMatrix =
  ## Rebuild a matrix from its rows. rMQR symbols are rectangular, so the
  ## width comes from the row length and the height from the row count.
  if n == nil or n.kind != JArray or n.len == 0:
    raise newException(QrBindError, "expected a non-empty array of row strings")
  var rows: seq[string]
  for item in n:
    if item.kind != JString:
      raise newException(QrBindError, "matrix rows must be strings")
    let r = item.getStr()
    if r.len == 0:
      raise newException(QrBindError, "matrix rows must not be empty")
    rows.add(r)
  let w = rows[0].len
  for r in rows:
    if r.len != w:
      raise newException(QrBindError, "matrix rows must all be the same width")
    for c in r:
      if c != '0' and c != '1':
        raise newException(QrBindError,
          "matrix rows must contain only '0' and '1', got '" & c & "'")
  result = initQrMatrix(w, rows.len)
  for y, r in rows:
    for x, c in r:
      result[x, y] = c == '1'

proc bytesToHex(b: openArray[byte]): string =
  result = newStringOfCap(b.len * 2)
  for c in b:
    result.add toHex(int(c), 2).toLowerAscii()

proc hexToBytes(s: string): seq[byte] =
  let clean = s.replace("-", "").replace(" ", "")
  if clean.len mod 2 != 0:
    raise newException(QrBindError, "hex string must have an even length")
  for i in 0 ..< clean.len div 2:
    try:
      result.add byte(parseHexInt(clean[i * 2 .. i * 2 + 1]))
    except ValueError:
      raise newException(QrBindError, "not a valid hex string: " & s)

proc hexToBytes16(s: string): array[16, byte] =
  let b = hexToBytes(s)
  if b.len != 16:
    raise newException(QrBindError, "a 16-byte key needs 32 hex characters")
  for i in 0 ..< 16:
    result[i] = b[i]

proc bytesToJson(b: openArray[byte]): JsonNode =
  result = newJArray()
  for c in b:
    result.add(%int(c))

proc jsonToBytes(n: JsonNode, what: string): seq[byte] =
  if n == nil or n.kind != JArray:
    raise newException(QrBindError, what & " must be an array of bytes")
  for item in n:
    case item.kind
    of JInt: result.add byte(item.getInt() and 0xFF)
    of JFloat: result.add byte(item.getFloat.int and 0xFF)
    else: raise newException(QrBindError, what & " must contain only numbers")

#
# Decode results
#

proc decodeResultToJson(r: QrDecodeResult): JsonNode =
  result = newJObject()
  result["ok"] = %r.ok
  if not r.ok: return
  result["text"] = %r.text
  result["family"] = %(familyName(r.family))
  result["version"] = %r.version
  result["ec"] = %($r.ecLevel)
  result["mask"] = %r.mask
  result["eci"] = %r.eci
  result["structuredAppend"] = %*{
    "enabled": r.structuredAppend.enabled,
    "index": r.structuredAppend.index,
    "total": r.structuredAppend.total,
    "parity": int(r.structuredAppend.parity)
  }
  var segs = newJArray()
  for s in r.segments:
    var o = newJObject()
    o["mode"] = %(int(s.mode))
    o["nchars"] = %s.nchars
    o["data"] = %bytesToHex(s.data)
    segs.add(o)
  result["segments"] = segs
  result["rows"] = matrixToRows(r.matrix)

proc sqrcResultToJson(r: SqrcOpenResult): JsonNode =
  result = newJObject()
  result["ok"] = %r.ok
  result["publicText"] = %r.publicText
  result["privateText"] = %r.privateText
  result["scannedText"] = %r.scannedText

#
# Image decoding
#

proc grayImage(w, h: int, pixels: JsonNode): GrayImage =
  ## Build a `GrayImage` from a dfkup array of 0-255 pixel values.
  if w < 1 or h < 1:
    raise newException(QrBindError, "image dimensions must be positive")
  if pixels == nil or pixels.kind != JArray:
    raise newException(QrBindError, "pixels must be an array of 0-255 values")
  if pixels.len != w * h:
    raise newException(QrBindError,
      "expected " & $(w * h) & " pixels for a " & $w & "x" & $h &
      " image, got " & $pixels.len)
  result = initGrayImage(w, h)
  for i in 0 ..< pixels.len:
    let p = pixels[i]
    case p.kind
    of JInt: result.pixels[i] = uint8(clamp(p.getInt(), 0, 255))
    of JFloat: result.pixels[i] = uint8(clamp(p.getFloat.int, 0, 255))
    else: raise newException(QrBindError, "pixels must contain only numbers")

proc readPgm(path: string): GrayImage =
  ## Read a binary (P5) or ASCII (P2) portable graymap. This is the simplest
  ## image format that needs no dependency to decode.
  let raw = readFile(path)
  if raw.len < 2 or raw[0] != 'P' or (raw[1] != '5' and raw[1] != '2'):
    raise newException(QrBindError,
      path & " is not a portable graymap (P2 or P5)")
  let binary = raw[1] == '5'
  var pos = 2

  # header tokens are whitespace separated; in P2 a '#' runs to end of line
  proc nextToken(): string =
    while true:
      while pos < raw.len and raw[pos] in Whitespace: inc pos
      if pos < raw.len and raw[pos] == '#':
        while pos < raw.len and raw[pos] notin {'\n', '\r'}: inc pos
        continue
      break
    let start = pos
    while pos < raw.len and raw[pos] notin Whitespace: inc pos
    raw[start ..< pos]

  let
    w = parseInt(nextToken())
    h = parseInt(nextToken())
    maxVal = parseInt(nextToken())
  if w < 1 or h < 1:
    raise newException(QrBindError, path & " has invalid dimensions")
  if maxVal < 1 or maxVal > 255:
    raise newException(QrBindError, path & " must be 8-bit (maxval 1-255)")
  # exactly one whitespace byte separates the header from binary data
  if binary and pos < raw.len and raw[pos] in Whitespace: inc pos

  result = initGrayImage(w, h)
  if binary:
    if raw.len - pos < w * h:
      raise newException(QrBindError, path & " is truncated")
    for i in 0 ..< w * h:
      result.pixels[i] = uint8(raw[pos + i])
  else:
    for i in 0 ..< w * h:
      result.pixels[i] = uint8(clamp(parseInt(nextToken()), 0, 255))

#
# The module
#

proc initQr*(script: Script, module: Module) =

  #
  # Model 2 rendering
  #

  script.addProc(module, "qrSvg", @[paramDef("text", ttyString),
      paramDef("scale", ttyInt, initValue(8'i64)),
      paramDef("border", ttyInt, initValue(4'i64))], ttyString,
    proc (args: StackView, argc: int): Value =
      let m = encodeQr(args[0].stringVal[])
      result = initValue(m.toSvg(
        scale = args[1].intVal.int, border = args[2].intVal.int)))

  script.addProc(module, "qrSvg", @[paramDef("text", ttyString),
      paramDef("options", ttyJson, initValue(newJObject()))], ttyString,
    proc (args: StackView, argc: int): Value =
      let o = optArg(args, argc, 1)
      let m = encodeQr(args[0].stringVal[], optOptions(o))
      result = initValue(m.toSvg(
        scale = optInt(o, "scale", 8),
        border = optInt(o, "border", 4),
        dark = optStr(o, "dark", "#000000"),
        light = optStr(o, "light", "#ffffff"))))

  script.addProc(module, "qrTerminal", @[paramDef("text", ttyString),
      paramDef("border", ttyInt, initValue(2'i64))], ttyString,
    proc (args: StackView, argc: int): Value =
      let m = encodeQr(args[0].stringVal[])
      result = initValue(m.toTerminal(border = args[1].intVal.int)))

  script.addProc(module, "qrTerminal", @[paramDef("text", ttyString),
      paramDef("options", ttyJson, initValue(newJObject()))], ttyString,
    proc (args: StackView, argc: int): Value =
      let o = optArg(args, argc, 1)
      result = initValue(encodeQr(args[0].stringVal[], optOptions(o))
        .toTerminal(border = optInt(o, "border", 2))))

  #
  # Other families
  #

  script.addProc(module, "qrMicroSvg", @[paramDef("text", ttyString),
      paramDef("options", ttyJson, initValue(newJObject()))], ttyString,
    proc (args: StackView, argc: int): Value =
      let o = optArg(args, argc, 1)
      let m = encodeMicro(args[0].stringVal[],
        ec = optEc(o, ecLow),
        version = MicroVersion(optInt(o, "version", int(mvAuto))),
        mask = optInt(o, "mask", -1))
      result = initValue(m.toSvg(
        scale = optInt(o, "scale", 8), border = optInt(o, "border", 4))))

  script.addProc(module, "qrMicroTerminal", @[paramDef("text", ttyString),
      paramDef("options", ttyJson, initValue(newJObject()))], ttyString,
    proc (args: StackView, argc: int): Value =
      let o = optArg(args, argc, 1)
      result = initValue(encodeMicro(args[0].stringVal[],
        ec = optEc(o, ecLow),
        version = MicroVersion(optInt(o, "version", int(mvAuto))),
        mask = optInt(o, "mask", -1))
        .toTerminal(border = optInt(o, "border", 2))))

  script.addProc(module, "qrRmqrSvg", @[paramDef("text", ttyString),
      paramDef("options", ttyJson, initValue(newJObject()))], ttyString,
    proc (args: StackView, argc: int): Value =
      let o = optArg(args, argc, 1)
      result = initValue(encodeRmqr(args[0].stringVal[],
        ec = optEc(o, ecMedium),
        version = optStr(o, "version", ""))
        .toSvg(scale = optInt(o, "scale", 8),
               border = optInt(o, "border", 4))))

  script.addProc(module, "qrRmqrTerminal", @[paramDef("text", ttyString),
      paramDef("options", ttyJson, initValue(newJObject()))], ttyString,
    proc (args: StackView, argc: int): Value =
      let o = optArg(args, argc, 1)
      result = initValue(encodeRmqr(args[0].stringVal[],
        ec = optEc(o, ecMedium),
        version = optStr(o, "version", ""))
        .toTerminal(border = optInt(o, "border", 2))))

  script.addProc(module, "qrModel1Svg", @[paramDef("text", ttyString),
      paramDef("options", ttyJson, initValue(newJObject()))], ttyString,
    proc (args: StackView, argc: int): Value =
      let o = optArg(args, argc, 1)
      result = initValue(encodeModel1(args[0].stringVal[],
        ec = optEc(o, ecMedium),
        version = optInt(o, "version", 0),
        mask = optInt(o, "mask", -1))
        .toSvg(scale = optInt(o, "scale", 8),
               border = optInt(o, "border", 4))))

  script.addProc(module, "qrModel1Terminal", @[paramDef("text", ttyString),
      paramDef("options", ttyJson, initValue(newJObject()))], ttyString,
    proc (args: StackView, argc: int): Value =
      let o = optArg(args, argc, 1)
      result = initValue(encodeModel1(args[0].stringVal[],
        ec = optEc(o, ecMedium),
        version = optInt(o, "version", 0),
        mask = optInt(o, "mask", -1))
        .toTerminal(border = optInt(o, "border", 2))))

  #
  # AQR: a Model 2 core with a second payload in a data ring
  #

  script.addProc(module, "qrAqrSvg", @[paramDef("main", ttyString),
      paramDef("ring", ttyString), paramDef("options", ttyJson, initValue(newJObject()))], ttyString,
    proc (args: StackView, argc: int): Value =
      let o = optArg(args, argc, 2)
      result = initValue(encodeAqr(args[0].stringVal[], args[1].stringVal[],
        ec = optEc(o, ecMedium),
        version = optInt(o, "version", 0))
        .toSvg(scale = optInt(o, "scale", 8),
               border = optInt(o, "border", 4))))

  script.addProc(module, "qrAqrTerminal", @[paramDef("main", ttyString),
      paramDef("ring", ttyString), paramDef("options", ttyJson, initValue(newJObject()))], ttyString,
    proc (args: StackView, argc: int): Value =
      let o = optArg(args, argc, 2)
      result = initValue(encodeAqr(args[0].stringVal[], args[1].stringVal[],
        ec = optEc(o, ecMedium),
        version = optInt(o, "version", 0))
        .toTerminal(border = optInt(o, "border", 2))))

  #
  # SQRC: a public area plus an AES-sealed private area
  #

  script.addProc(module, "qrSqrcSvg", @[paramDef("publicData", ttyString),
      paramDef("privateData", ttyString), paramDef("key", ttyString),
      paramDef("options", ttyJson, initValue(newJObject()))], ttyString,
    proc (args: StackView, argc: int): Value =
      let o = optArg(args, argc, 3)
      result = initValue(encodeSqrc(args[0].stringVal[], args[1].stringVal[],
        hexToBytes16(args[2].stringVal[]), optOptions(o),
        extended = optBool(o, "extended", false))
        .toSvg(scale = optInt(o, "scale", 8),
               border = optInt(o, "border", 4))))

  script.addProc(module, "qrSqrcTerminal", @[paramDef("publicData", ttyString),
      paramDef("privateData", ttyString), paramDef("key", ttyString),
      paramDef("options", ttyJson, initValue(newJObject()))], ttyString,
    proc (args: StackView, argc: int): Value =
      let o = optArg(args, argc, 3)
      result = initValue(encodeSqrc(args[0].stringVal[], args[1].stringVal[],
        hexToBytes16(args[2].stringVal[]), optOptions(o),
        extended = optBool(o, "extended", false))
        .toTerminal(border = optInt(o, "border", 2))))

  script.addProc(module, "qrSqrcSeal", @[paramDef("privateData", ttyString),
      paramDef("key", ttyString),
      paramDef("publicData", ttyString, initValue("")),
      paramDef("extended", ttyBool, initValue(false))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(sealPrivate(args[0].stringVal[],
        hexToBytes16(args[1].stringVal[]),
        publicData = args[2].stringVal[],
        extended = args[3].boolVal)))

  script.addProc(module, "qrSqrcOpen", @[paramDef("blob", ttyString),
      paramDef("key", ttyString),
      paramDef("publicData", ttyString, initValue("")),
      paramDef("extended", ttyBool, initValue(false))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(openPrivate(args[0].stringVal[],
        hexToBytes16(args[1].stringVal[]),
        publicData = args[2].stringVal[],
        extended = args[3].boolVal)))

  script.addProc(module, "qrSqrcSplit", @[paramDef("text", ttyString)], ttyJson,
    proc (args: StackView, argc: int): Value =
      let parts = splitSqrcText(args[0].stringVal[])
      result = initValue(%*{
        "extended": parts.extended,
        "blob": parts.blob,
        "publicData": parts.publicData
      }))

  script.addProc(module, "qrSqrcOpenText", @[paramDef("text", ttyString),
      paramDef("key", ttyString)], ttyJson,
    proc (args: StackView, argc: int): Value =
      result = initValue(sqrcResultToJson(decodeSqrcText(
        args[0].stringVal[], hexToBytes16(args[1].stringVal[])))))

  script.addProc(module, "qrSqrcDecodeRows", @[paramDef("rows", ttyJson),
      paramDef("key", ttyString)], ttyJson,
    proc (args: StackView, argc: int): Value =
      result = initValue(sqrcResultToJson(decodeSqrcMatrix(
        rowsToMatrix(args[0].jsonVal), hexToBytes16(args[1].stringVal[])))))

  #
  # Payload builders
  #

  script.addProc(module, "qrWifiPayload", @[paramDef("ssid", ttyString),
      paramDef("password", ttyString, initValue("")),
      paramDef("encryption", ttyString, initValue("WPA")),
      paramDef("hidden", ttyBool, initValue(false))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(makeWifi(args[0].stringVal[],
        password = args[1].stringVal[],
        encryption = args[2].stringVal[],
        hidden = args[3].boolVal)))

  script.addProc(module, "qrMecardPayload", @[paramDef("name", ttyString),
      paramDef("phone", ttyString, initValue("")),
      paramDef("email", ttyString, initValue("")),
      paramDef("url", ttyString, initValue(""))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(makeMecard(args[0].stringVal[],
        phone = args[1].stringVal[],
        email = args[2].stringVal[],
        url = args[3].stringVal[])))

  script.addProc(module, "qrVcardPayload", @[paramDef("card", ttyJson)], ttyString,
    proc (args: StackView, argc: int): Value =
      let c = optArg(args, argc, 0)
      if c == nil or c.kind != JObject:
        raise newException(QrBindError, "vCard fields must be an object")
      result = initValue(makeVCard(VCard(
        fullName: optStr(c, "fullName", ""),
        org: optStr(c, "org", ""),
        title: optStr(c, "title", ""),
        phone: optStr(c, "phone", ""),
        email: optStr(c, "email", ""),
        url: optStr(c, "url", ""),
        address: optStr(c, "address", ""),
        note: optStr(c, "note", "")))))

  script.addProc(module, "qrUrlPayload", @[paramDef("url", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(makeUrl(args[0].stringVal[])))

  script.addProc(module, "qrSmsPayload", @[paramDef("phone", ttyString),
      paramDef("message", ttyString, initValue(""))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(makeSms(args[0].stringVal[],
        message = args[1].stringVal[])))

  script.addProc(module, "qrEmailPayload", @[paramDef("to", ttyString),
      paramDef("subject", ttyString, initValue("")),
      paramDef("body", ttyString, initValue(""))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(makeEmail(args[0].stringVal[],
        subject = args[1].stringVal[],
        body = args[2].stringVal[])))

  #
  # Encoding to a matrix
  #

  script.addProc(module, "qrRows", @[paramDef("text", ttyString),
      paramDef("options", ttyJson, initValue(newJObject()))], ttyJson,
    proc (args: StackView, argc: int): Value =
      result = initValue(matrixToRows(
        encodeQr(args[0].stringVal[], optOptions(optArg(args, argc, 1))))))

  script.addProc(module, "qrRowsBytes", @[paramDef("data", ttyJson),
      paramDef("options", ttyJson, initValue(newJObject()))], ttyJson,
    proc (args: StackView, argc: int): Value =
      let bytes = jsonToBytes(args[0].jsonVal, "data")
      result = initValue(matrixToRows(
        encodeQrBytes(bytes, optOptions(optArg(args, argc, 1))))))

  script.addProc(module, "qrMicroRows", @[paramDef("text", ttyString),
      paramDef("options", ttyJson, initValue(newJObject()))], ttyJson,
    proc (args: StackView, argc: int): Value =
      let o = optArg(args, argc, 1)
      result = initValue(matrixToRows(encodeMicro(args[0].stringVal[],
        ec = optEc(o, ecLow),
        version = MicroVersion(optInt(o, "version", int(mvAuto))),
        mask = optInt(o, "mask", -1)))))

  script.addProc(module, "qrRmqrRows", @[paramDef("text", ttyString),
      paramDef("options", ttyJson, initValue(newJObject()))], ttyJson,
    proc (args: StackView, argc: int): Value =
      let o = optArg(args, argc, 1)
      result = initValue(matrixToRows(encodeRmqr(args[0].stringVal[],
        ec = optEc(o, ecMedium),
        version = optStr(o, "version", "")))))

  script.addProc(module, "qrModel1Rows", @[paramDef("text", ttyString),
      paramDef("options", ttyJson, initValue(newJObject()))], ttyJson,
    proc (args: StackView, argc: int): Value =
      let o = optArg(args, argc, 1)
      result = initValue(matrixToRows(encodeModel1(args[0].stringVal[],
        ec = optEc(o, ecMedium),
        version = optInt(o, "version", 0),
        mask = optInt(o, "mask", -1)))))

  script.addProc(module, "qrAqrRows", @[paramDef("main", ttyString),
      paramDef("ring", ttyString), paramDef("options", ttyJson, initValue(newJObject()))], ttyJson,
    proc (args: StackView, argc: int): Value =
      let o = optArg(args, argc, 2)
      result = initValue(matrixToRows(encodeAqr(args[0].stringVal[],
        args[1].stringVal[],
        ec = optEc(o, ecMedium),
        version = optInt(o, "version", 0)))))

  script.addProc(module, "qrSqrcRows", @[paramDef("publicData", ttyString),
      paramDef("privateData", ttyString), paramDef("key", ttyString),
      paramDef("options", ttyJson, initValue(newJObject()))], ttyJson,
    proc (args: StackView, argc: int): Value =
      let o = optArg(args, argc, 3)
      result = initValue(matrixToRows(encodeSqrc(args[0].stringVal[],
        args[1].stringVal[], hexToBytes16(args[2].stringVal[]),
        optOptions(o), extended = optBool(o, "extended", false)))))

  #
  # Decoding
  #

  # Tries each family in turn and reports the first that decodes, so a script
  # does not have to know which symbology produced the matrix.
  script.addProc(module, "qrDecodeRows", @[paramDef("rows", ttyJson)], ttyJson,
    proc (args: StackView, argc: int): Value =
      let m = rowsToMatrix(args[0].jsonVal)
      var last = QrDecodeResult(ok: false, eci: -1)
      for attempt in [decodeQrMatrix(m), decodeMicroMatrix(m),
                      decodeRmqrMatrix(m), decodeModel1Matrix(m)]:
        if attempt.ok:
          result = initValue(decodeResultToJson(attempt))
          return
        last = attempt
      result = initValue(decodeResultToJson(last)))

  script.addProc(module, "qrDecodeImage", @[paramDef("width", ttyInt),
      paramDef("height", ttyInt), paramDef("pixels", ttyJson)], ttyJson,
    proc (args: StackView, argc: int): Value =
      let img = grayImage(args[0].intVal.int, args[1].intVal.int,
        args[2].jsonVal)
      result = initValue(decodeResultToJson(decodeQrImage(img))))

  script.addProc(module, "qrDecodePgm", @[paramDef("path", ttyString)], ttyJson,
    proc (args: StackView, argc: int): Value =
      result = initValue(decodeResultToJson(decodeQrImage(
        readPgm(args[0].stringVal[])))))

  script.addProc(module, "qrDecodeText", @[paramDef("rows", ttyJson)], ttyString,
    proc (args: StackView, argc: int): Value =
      # try every family, not just model 2, so qrDecodeText works on whatever
      # qrMicroRows, qrRmqrRows and qrModel1Rows produced
      let m = rowsToMatrix(args[0].jsonVal)
      for attempt in [decodeQrMatrix(m), decodeMicroMatrix(m),
                      decodeRmqrMatrix(m), decodeModel1Matrix(m)]:
        if attempt.ok:
          result = initValue(attempt.text)
          return
      raise newException(QrBindError, "could not decode the QR matrix"))

  #
  # AQR and Reed-Solomon internals
  #

  script.addProc(module, "qrAqrRing", @[paramDef("rows", ttyJson)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(readAqrRing(rowsToMatrix(args[0].jsonVal))))

  script.addProc(module, "qrAqrCoreRows", @[paramDef("rows", ttyJson)], ttyJson,
    proc (args: StackView, argc: int): Value =
      result = initValue(matrixToRows(
        aqrCore(rowsToMatrix(args[0].jsonVal)))))

  # Takes the *core* rows, not the whole AQR symbol: `decodeAqrCore` already
  # strips the ring, and re-stripping a core is not an AQR symbol.
  script.addProc(module, "qrAqrDecodeCore", @[paramDef("rows", ttyJson)], ttyJson,
    proc (args: StackView, argc: int): Value =
      result = initValue(decodeResultToJson(
        decodeQrMatrix(rowsToMatrix(args[0].jsonVal)))))

  script.addProc(module, "qrRsEncode", @[paramDef("data", ttyJson),
      paramDef("nsym", ttyInt)], ttyJson,
    proc (args: StackView, argc: int): Value =
      let parity = rsEncodeParity(jsonToBytes(args[0].jsonVal, "data"),
        args[1].intVal.int)
      result = initValue(bytesToJson(parity)))

  script.addProc(module, "qrRsEncodeHex", @[paramDef("data", ttyString),
      paramDef("nsym", ttyInt)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(bytesToHex(rsEncodeParity(
        hexToBytes(args[0].stringVal[]), args[1].intVal.int))))

  # rsDecode corrects in place and raises when the errors exceed the budget,
  # so a failure is reported as ok=false rather than thrown.
  script.addProc(module, "qrRsDecodeHex", @[paramDef("codewords", ttyString),
      paramDef("nsym", ttyInt)], ttyJson,
    proc (args: StackView, argc: int): Value =
      var cw = hexToBytes(args[0].stringVal[])
      var ok = true
      try:
        rsDecode(cw, args[1].intVal.int)
      except QrError:
        ok = false
      result = initValue(%*{"ok": ok, "codewords": bytesToJson(cw)}))

  script.addProc(module, "qrRsIsValid", @[paramDef("codewords", ttyString),
      paramDef("nsym", ttyInt)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(rsIsValid(hexToBytes(args[0].stringVal[]),
        args[1].intVal.int)))

  script.addProc(module, "qrGalois", @[paramDef("op", ttyString),
      paramDef("a", ttyInt), paramDef("b", ttyInt)], ttyInt,
    proc (args: StackView, argc: int): Value =
      let
        a = uint8(args[1].intVal.int and 0xFF)
        b = uint8(args[2].intVal.int and 0xFF)
      case args[0].stringVal[]
      of "mul": result = initValue(int(gfMul(a, b)))
      of "div": result = initValue(int(gfDiv(a, b)))
      of "inv": result = initValue(int(gfInv(a)))
      of "pow": result = initValue(int(gfPow(a, b.int)))
      else: raise newException(QrBindError,
        "unknown galois op: " & args[0].stringVal[] &
        " (expected mul, div, inv or pow)"))

  # `inv` takes one operand, everything else two
  script.addProc(module, "qrGalois", @[paramDef("op", ttyString),
      paramDef("a", ttyInt)], ttyInt,
    proc (args: StackView, argc: int): Value =
      let a = uint8(args[1].intVal.int and 0xFF)
      case args[0].stringVal[]
      of "inv": result = initValue(int(gfInv(a)))
      else: raise newException(QrBindError,
        "galois op '" & args[0].stringVal[] &
        "' needs two operands, only 'inv' takes one"))

  script.addProc(module, "qrPolyMul", @[paramDef("p", ttyJson),
      paramDef("q", ttyJson)], ttyJson,
    proc (args: StackView, argc: int): Value =
      result = initValue(bytesToJson(polyMul(
        jsonToBytes(args[0].jsonVal, "p"),
        jsonToBytes(args[1].jsonVal, "q")))))

  script.addProc(module, "qrPolyEval", @[paramDef("p", ttyJson),
      paramDef("x", ttyInt)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(int(polyEval(
        jsonToBytes(args[0].jsonVal, "p"),
        uint8(args[1].intVal.int and 0xFF)))))

  #
  # Geometry and capacity introspection
  #

  script.addProc(module, "qrDataCodewords", @[paramDef("version", ttyInt),
      paramDef("ec", ttyString, initValue("M"))], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(int(numDataCodewords(args[0].intVal.int,
        parseEc(args[1].stringVal[], ecMedium)))))

  script.addProc(module, "qrAlignmentPositions",
    @[paramDef("version", ttyInt)], ttyJson,
    proc (args: StackView, argc: int): Value =
      result = initValue(%*alignmentPositions(args[0].intVal.int)))

  script.addProc(module, "qrPenaltyScore", @[paramDef("rows", ttyJson)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(int(penaltyScore(rowsToMatrix(args[0].jsonVal)))))

  script.addProc(module, "qrModel1Size", @[paramDef("version", ttyInt)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(int(model1Size(args[0].intVal.int))))

  script.addProc(module, "qrMicroCapacity", @[paramDef("version", ttyInt),
      paramDef("ec", ttyString, initValue("L"))], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(microDataCapacity(
        MicroVersion(args[0].intVal.int),
        parseEc(args[1].stringVal[], ecLow))))

  script.addProc(module, "qrRmqrSizeName", @[paramDef("version", ttyInt)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(rmqrSizeName(args[0].intVal.int)))

  # the reserved map is one flag per module, row-major
  script.addProc(module, "qrReservedMap", @[paramDef("version", ttyInt)], ttyJson,
    proc (args: StackView, argc: int): Value =
      result = initValue(%*reservedMap(args[0].intVal.int)))
