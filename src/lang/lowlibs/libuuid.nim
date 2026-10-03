# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/[strutils]
import pkg/openparser/uuid
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

type
  Node6 = array[6, byte]

  UuidBindError* = object of ValueError

proc variantName(v: UuidVariant): string =
  ## Human-readable name for a UUID variant.
  case v
  of variantNCS: "ncs"
  of variantRFC4122: "rfc4122"
  of variantMicrosoft: "microsoft"
  of variantFuture: "future"

proc hexToBytes(s: string, dest: var openArray[byte], what: string) =
  ## Decode `s` as lowercase hex into `dest`, which must be exactly
  ## `dest.len` bytes.
  if s.len != dest.len * 2:
    raise newException(UuidBindError,
      what & " needs " & $(dest.len * 2) & " hex characters, got " & $s.len)
  for i in 0 ..< dest.len:
    try:
      dest[i] = byte(parseHexInt(s[i * 2 .. i * 2 + 1]))
    except ValueError:
      raise newException(UuidBindError,
        what & " is not valid hex: " & s)

proc hexToBytes16(s: string): UuidBytes =
  ## Decode a 32-character hex string into 16 UUID bytes.
  if s.len != 32:
    raise newException(UuidBindError,
      "uuid v8 needs 32 hex characters, got " & $s.len)
  for i in 0 ..< 16:
    try:
      result[i] = byte(parseHexInt(s[i * 2 .. i * 2 + 1]))
    except ValueError:
      raise newException(UuidBindError, "uuid v8 data is not valid hex: " & s)

proc bytesToHex(b: openArray[byte]): string =
  ## Encode bytes as lowercase hex.
  result = newStringOfCap(b.len * 2)
  for c in b:
    result.add toHex(int(c), 2).toLowerAscii()

proc toNode(s: string): Node6 =
  ## Decode a MAC address / node id, or return zeros for a blank string.
  if s.len == 0: return
  hexToBytes(s, result, "uuid node id")

proc nodeArg(args: StackView, argc: int): Node6 =
  ## Read the optional node id argument, falling back to a random one.
  # `StackView` is an unchecked view, so the bound is `argc` rather than a
  # length on the pointer.
  if argc >= 1:
    if args[0].typeId == tyString:
      return toNode(args[0].stringVal[])
    if args[0].typeId == tyInt:
      return toNode($args[0].intVal)
  result = toNode("")

proc namespaceArg(s: string): Uuid =
  ## Resolve a namespace to its UUID. Accepts one of the RFC 4122 names
  ## ("dns", "url", "oid", "x500") or a namespace UUID literal.
  if s.len == 0: return parseUuid($nsDNS)
  case s.toLowerAscii
  of "dns": parseUuid($nsDNS)
  of "url": parseUuid($nsURL)
  of "oid": parseUuid($nsOID)
  of "x500": parseUuid($nsX500)
  else: parseUuid(s)

proc initUuid*(script: Script, module: Module) =

  #
  # Generation
  #

  script.addProc(module, "uuidV1",
    @[paramDef("node", ttyString, initValue(""))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue($newUuidV1(nodeArg(args, argc))))

  script.addProc(module, "uuidV2",
    @[paramDef("domain", ttyInt), paramDef("localId", ttyInt)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue($newUuidV2(byte(args[0].intVal.int and 0xFF),
        uint32(args[1].intVal.int and 0xFFFFFFFF))))

  script.addProc(module, "uuidV3",
    @[paramDef("name", ttyString),
      paramDef("namespace", ttyString, initValue("dns"))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue($newUuidV3(namespaceArg(args[1].stringVal[]),
        args[0].stringVal[])))

  script.addProc(module, "uuidV4", returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      result = initValue($newUuidV4()))

  script.addProc(module, "uuidV5",
    @[paramDef("name", ttyString),
      paramDef("namespace", ttyString, initValue("dns"))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue($newUuidV5(namespaceArg(args[1].stringVal[]),
        args[0].stringVal[])))

  script.addProc(module, "uuidV6",
    @[paramDef("node", ttyString, initValue(""))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue($newUuidV6(nodeArg(args, argc))))

  script.addProc(module, "uuidV7", returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      result = initValue($newUuidV7()))

  script.addProc(module, "uuidV8", @[paramDef("data", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue($newUuidV8(hexToBytes16(args[0].stringVal[]))))

  script.addProc(module, "nilUuid", returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      result = initValue($nilUuid()))

  #
  # Namespaces
  #

  script.addProc(module, "uuidNsDns", returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      result = initValue($parseUuid($nsDNS)))

  script.addProc(module, "uuidNsUrl", returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      result = initValue($parseUuid($nsURL)))

  script.addProc(module, "uuidNsOid", returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      result = initValue($parseUuid($nsOID)))

  script.addProc(module, "uuidNsX500", returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      result = initValue($parseUuid($nsX500)))

  # Resolve a namespace name to its UUID, e.g. "dns" or "URL".
  script.addProc(module, "uuidNamespace", @[
      paramDef("name", ttyString, initValue("dns"))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue($namespaceArg(args[0].stringVal[])))

  #
  # Inspection
  #

  script.addProc(module, "parseUuid", @[paramDef("s", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue($parseUuid(args[0].stringVal[])))

  script.addProc(module, "isValidUuid", @[paramDef("s", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(isValidUuid(args[0].stringVal[])))

  script.addProc(module, "uuidVersion", @[paramDef("s", ttyString)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(parseUuid(args[0].stringVal[]).version().int64))

  script.addProc(module, "uuidVariant", @[paramDef("s", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(variantName(parseUuid(args[0].stringVal[]).variant())))

  script.addProc(module, "isNilUuid", @[paramDef("s", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(parseUuid(args[0].stringVal[]).isNil()))

  script.addProc(module, "uuidEquals",
    @[paramDef("a", ttyString), paramDef("b", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(parseUuid(args[0].stringVal[]) ==
        parseUuid(args[1].stringVal[])))

  #
  # Bytes and hex
  #

  script.addProc(module, "uuidBytes", @[paramDef("s", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(bytesToHex(parseUuid(args[0].stringVal[]).bytes)))

  script.addProc(module, "uuidFromHex", @[paramDef("hex", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue($parseUuid(args[0].stringVal[])))
