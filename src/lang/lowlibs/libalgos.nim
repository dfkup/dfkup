# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/[strutils]
import pkg/nimcypher/[utils, hash, encrypt, aes, password]
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

proc hexDecode(s: string): seq[byte] =
  try:
    let decoded = parseHexStr(s)
    result = newSeq[byte](decoded.len)
    for i, c in decoded:
      result[i] = byte(c)
  except ValueError:
    raise newException(ValueError, "invalid hex string")

proc key32FromHex(s: string): Key32 =
  let b = hexDecode(s)
  if b.len != 32:
    raise newException(ValueError, "key must be 32 bytes (64 hex chars)")
  result = toArray[32](b)

proc initAlgos*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  script.addProc(module, "genKey32", @[], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(toHex(randomBytes[32]())))

  script.addProc(module, "blakeHex", @[paramDef("msg", ttyString),
      paramDef("size", ttyInt, initValue(32'i64))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(blakeHex(args[0].stringVal[], args[1].intVal.int)))

  script.addProc(module, "sha512Hex", @[paramDef("msg", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(sha512Hex(args[0].stringVal[])))

  script.addProc(module, "hmacSha512Hex", @[paramDef("keyHex", ttyString),
      paramDef("msg", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      let key = hexDecode(args[0].stringVal[])
      result = initValue(sha512HmacHex(key, toBytes(args[1].stringVal[]))))

  script.addProc(module, "hkdfSha512Hex", @[paramDef("ikm", ttyString),
      paramDef("salt", ttyString), paramDef("info", ttyString),
      paramDef("len", ttyInt, initValue(32'i64))], ttyString,
    proc (args: StackView, argc: int): Value =
      let okm = hkdfSha512(toBytes(args[0].stringVal[]), toBytes(args[1].stringVal[]),
        toBytes(args[2].stringVal[]), args[3].intVal.int)
      result = initValue(toHex(okm)))

  script.addProc(module, "seal", @[paramDef("msg", ttyString),
      paramDef("keyHex", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      let key = key32FromHex(args[1].stringVal[])
      let sealed = seal(args[0].stringVal[], key)
      result = initValue(toHex(sealed.nonce) & "." & toHex(sealed.mac) &
        "." & toHex(sealed.cipherText)))

  script.addProc(module, "unseal", @[paramDef("packed", ttyString),
      paramDef("keyHex", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      let parts = (args[0].stringVal[]).split('.')
      if parts.len != 3:
        raise newException(ValueError, "invalid sealed message format")
      let key = key32FromHex(args[1].stringVal[])
      let nonceBytes = hexDecode(parts[0])
      let macBytes = hexDecode(parts[1])
      let ct = hexDecode(parts[2])
      if nonceBytes.len != 24 or macBytes.len != 16:
        raise newException(ValueError, "invalid sealed message format")
      var msg = SealedMessage(nonce: toArray[24](nonceBytes),
        mac: toArray[16](macBytes), cipherText: ct)
      result = initValue(toString(unseal(msg, key))))

  script.addProc(module, "gcmSealHex", @[paramDef("msg", ttyString),
      paramDef("keyHex", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      let key = hexDecode(args[1].stringVal[])
      if key.len notin {16, 24, 32}:
        raise newException(ValueError, "AES key must be 16, 24 or 32 bytes")
      let sealed = gcmSeal(args[0].stringVal[], key)
      result = initValue(toHex(sealed.nonce) & "." & toHex(sealed.tag) &
        "." & toHex(sealed.cipherText)))

  script.addProc(module, "gcmOpenHex", @[paramDef("packed", ttyString),
      paramDef("keyHex", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      let parts = (args[0].stringVal[]).split('.')
      if parts.len != 3:
        raise newException(ValueError, "invalid sealed message format")
      let key = hexDecode(args[1].stringVal[])
      let nonceBytes = hexDecode(parts[0])
      let tagBytes = hexDecode(parts[1])
      let ct = hexDecode(parts[2])
      if nonceBytes.len != 12 or tagBytes.len != 16:
        raise newException(ValueError, "invalid sealed message format")
      var msg = GcmSealed(nonce: toArray[12](nonceBytes),
        tag: toArray[16](tagBytes), cipherText: ct)
      result = initValue(gcmOpenStr(msg, key)))

  script.addProc(module, "hashPassword", @[paramDef("pw", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(hashPassword(args[0].stringVal[])))

  script.addProc(module, "verifyPassword", @[paramDef("pw", ttyString),
      paramDef("stored", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(verifyPassword(args[0].stringVal[], args[1].stringVal[])))
