# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup
#
# `std/algos` is the dfkup front end to nimcypher, a pure-Nim port of
# Monocypher 4.0.3 plus AES, RSA and ECDSA. It is dfkup's main cryptographic
# library.
#
# Conventions, applied uniformly across the whole surface:
#
#   * Binary values cross the boundary as *hex strings*, never as dfkup
#     arrays. So `keyHex`, `nonceHex`, `sigHex`, and a `...Hex` suffix on
#     anything that returns bytes. Strings themselves are byte-transparent,
#     so `bytesToHex`/`hexToBytes` move between the two representations.
#   * Anything stateful (an incremental hash, an AEAD stream, an RSA or EC
#     key) is an opaque handle. dfkup has no user types, so these come back
#     as `ttyPointer` boxes tagged with the family name, and `getState`
#     rejects a handle of the wrong family with a readable error instead of
#     reinterpreting the bytes.
#   * Anything with more than one meaningful field comes back as a *packed
#     string*: the parts joined with "." in a fixed order, hex throughout.
#     So a key pair is `"<secretHex>.<publicHex>"`. Nothing here returns json,
#     because dfkup cannot turn a json value back into a string, and a key
#     pair whose fields you cannot feed to `seal` would be useless.
#
# Packed formats, all dot-separated hex:
#
#   seal / gcmSealHex   nonce . mac/tag . cipherText
#   x25519KeyPair       secret . public
#   generateSigningKeyPair  public . secret
#   keyPairFromPasswordHex   secret . public . salt
#   aeadEncryptHex      cipherText . mac
#   aesGcmEncryptHex    cipherText . tag
#   rsaPublicKeyToHex   n . e
#   rsaPrivateKeyToHex  n . e . d . p . q . dp . dq . qinv
#   ecPublicKeyToHex    curve . x . y
#   ecPrivateKeyToHex   curve . d

import std/[strutils, options]
import pkg/bigints
import pkg/nimcypher/[utils, secret, hash, encrypt, aes, sign, password]
import pkg/nimcypher/[rsa as rsaHigh, ecdsa as ecHigh]
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

# ---------------------------------------------------------------------------
# Byte / hex plumbing
# ---------------------------------------------------------------------------

proc hexDecode(s: string): seq[byte] =
  ## Decode a hex string. Raises with a dfkup-friendly message on garbage.
  if s.len mod 2 != 0:
    raise newException(ValueError, "hex string must have an even length")
  try:
    let decoded = parseHexStr(s)
    result = newSeq[byte](decoded.len)
    for i, c in decoded:
      result[i] = byte(c)
  except ValueError:
    raise newException(ValueError, "invalid hex string")

proc hexEncode(data: openArray[byte]): string = toHex(data)

proc hexEncode(s: string): string =
  ## A dfkup string is already a byte buffer, so this is `toHex` over it.
  toHex(toBytes(s))

proc fixedBytes(s: string, len: static int, what: string): array[len, uint8] =
  ## Decode exactly `len` bytes of hex, with an error that names the field
  ## rather than just "invalid hex length".
  let b = hexDecode(s)
  if b.len != len:
    raise newException(ValueError,
      what & " must be " & $len & " bytes (" & $(len * 2) &
      " hex chars), got " & $b.len)
  toArray[len](b)

proc key32FromHex(s: string): Key32 =
  fixedBytes(s, 32, "key")

proc nonce24FromHex(s: string): Nonce24 =
  fixedBytes(s, 24, "nonce")

proc mac16FromHex(s: string): Mac16 =
  fixedBytes(s, 16, "mac")

proc aesKeyFromHex(s: string): seq[byte] =
  ## AES accepts 128/192/256-bit keys; return the bytes and let the caller
  ## validate the length so the error names the mode in play.
  let b = hexDecode(s)
  if b.len notin {16, 24, 32}:
    raise newException(ValueError,
      "AES key must be 16, 24 or 32 bytes, got " & $b.len)
  b

proc randomHex(n: int): string =
  ## `randomBytes` needs a compile-time size, so fill a runtime-length buffer
  ## a 32-byte chunk at a time.
  if n < 1:
    raise newException(ValueError, "byte count must be at least 1")
  if n > 65536:
    raise newException(ValueError, "byte count must be at most 65536")
  var raw = newString(n)
  var i = 0
  while i < n:
    for b in randomBytes[32]():
      if i >= n: break
      raw[i] = char(b)
      inc i
  result = toHex(toBytes(raw))

# ---------------------------------------------------------------------------
# Opaque handles
# ---------------------------------------------------------------------------

type
  StateBox[T] = ref object
    ## Boxes a stateful nimcypher value so dfkup can hold on to it. The
    ## `tag` rides along so `getState` can reject a mismatched handle.
    state: T

proc wrapState[T](s: T, tag: string): Value =
  result = initValue(tyPointer, StateBox[T](state: s))
  result.objectVal.foreign.tag = tag

proc getState[T](v: Value, expectTag: string): var T =
  ## Recover the boxed state, or raise rather than reinterpret foreign bytes.
  if v.typeId != tyPointer or v.objectVal.foreign.data == nil:
    raise newException(ValueError,
      expectTag & " handle expected, got " & $v.typeId)
  let actual = v.objectVal.foreign.tag
  if actual != expectTag:
    raise newException(ValueError,
      expectTag & " handle expected, got a " & $actual & " handle")
  result = cast[StateBox[T]](v.objectVal.foreign.data).state

# ---------------------------------------------------------------------------
# BigInt (RSA / EC) hex serialization
# ---------------------------------------------------------------------------

proc bigToHex(a: BigInt, width: int): string =
  ## Big-endian hex, left-padded to exactly `width` bytes. The padding is what
  ## makes a round trip stable: without it `n` and `0n` are the same BigInt
  ## but different key encodings.
  var s = toString(a, 16)
  if s.len > width * 2:
    raise newException(ValueError, "integer does not fit in " & $width & " bytes")
  result = repeat('0', width * 2 - s.len) & s

proc bigFromHex(s: string, width: int, what: string): BigInt =
  if s.len != width * 2:
    raise newException(ValueError,
      what & " must be " & $width & " bytes (" & $(width * 2) & " hex chars)")
  for c in s:
    if c notin HexDigits:
      raise newException(ValueError, "invalid hex string")
  result = initBigInt(s, 16)

# ---------------------------------------------------------------------------
# Enum parsing for the string-keyed algorithm selectors
# ---------------------------------------------------------------------------

proc parseCurve(s: string): EcCurve =
  case s.toLowerAscii()
  of "p256", "secp256r1", "prime256v1": EcCurve.P256
  of "p384", "secp384r1": EcCurve.P384
  of "p521", "secp521r1": EcCurve.P521
  of "secp256k1", "k256": EcCurve.Secp256k1
  else:
    raise newException(ValueError,
      "unknown curve '" & s & "' (use P256, P384, P521 or Secp256k1)")

proc curveWidths(c: EcCurve): tuple[coord, order: int] =
  case c
  of EcCurve.P256: (32, 32)
  of EcCurve.P384: (48, 48)
  of EcCurve.P521: (66, 66)
  of EcCurve.Secp256k1: (32, 32)

proc parseRsaHash(s: string): rsaHigh.RsaHash =
  case s.toLowerAscii()
  of "sha1": rsaHigh.RsaHash.rhSha1
  of "sha256": rsaHigh.RsaHash.rhSha256
  of "sha384": rsaHigh.rhSha384
  of "sha512": rsaHigh.rhSha512
  else:
    raise newException(ValueError,
      "unknown RSA hash '" & s & "' (use SHA1, SHA256, SHA384 or SHA512)")

# ---------------------------------------------------------------------------
# Packed sealed-message formats
# ---------------------------------------------------------------------------

proc pack3(a, b, c: openArray[byte]): string =
  hexEncode(a) & "." & hexEncode(b) & "." & hexEncode(c)

proc unpack(packed: string, count: int, what: string): seq[string] =
  ## Split a packed value and insist on the expected field count, so a
  ## truncated or hand-edited blob fails with a name instead of a cast error.
  let parts = packed.split('.')
  if parts.len != count:
    raise newException(ValueError,
      what & " must have " & $count & " '.'-separated parts, got " & $parts.len)
  result = parts

proc unpack3(packed: string, what: string): tuple[a, b, c: string] =
  let parts = unpack(packed, 3, what)
  (parts[0], parts[1], parts[2])

proc initAlgos*(script: Script, module: Module) =

  # -------------------------------------------------------------------------
  # Encoding and randomness
  # -------------------------------------------------------------------------

  script.addProc(module, "genKey32", @[], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(randomHex(32)))

  script.addProc(module, "genKeyHex", @[
      paramDef("nbytes", ttyInt, initValue(32'i64))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(randomHex(args[0].intVal.int)))

  script.addProc(module, "genSaltHex", @[
      paramDef("nbytes", ttyInt, initValue(16'i64))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(randomHex(args[0].intVal.int)))

  script.addProc(module, "genNonceHex", @[], ttyString,
    proc (args: StackView, argc: int): Value =
      ## A fresh 24-byte XChaCha20 nonce.
      result = initValue(randomHex(24)))

  script.addProc(module, "bytesToHex", @[paramDef("bytes", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(hexEncode(args[0].stringVal[])))

  script.addProc(module, "hexToBytes", @[paramDef("hex", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(toString(hexDecode(args[0].stringVal[]))))

  script.addProc(module, "constantTimeEqual", @[paramDef("a", ttyString),
      paramDef("b", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(constantTimeEqual(toBytes(args[0].stringVal[]),
        toBytes(args[1].stringVal[]))))

  script.addProc(module, "constantTimeEqualHex", @[paramDef("aHex", ttyString),
      paramDef("bHex", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      ## Constant-time compare of two hex digests, e.g. a MAC check.
      result = initValue(constantTimeEqual(hexDecode(args[0].stringVal[]),
        hexDecode(args[1].stringVal[]))))

  # -------------------------------------------------------------------------
  # One-shot hashing
  # -------------------------------------------------------------------------

  script.addProc(module, "blakeHex", @[paramDef("msg", ttyString),
      paramDef("size", ttyInt, initValue(32'i64))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(blakeHex(args[0].stringVal[], args[1].intVal.int)))

  script.addProc(module, "blakeKeyedHex", @[paramDef("msg", ttyString),
      paramDef("keyHex", ttyString),
      paramDef("size", ttyInt, initValue(32'i64))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(blakeKeyedHex(args[0].stringVal[],
        toString(hexDecode(args[1].stringVal[])), args[2].intVal.int)))

  script.addProc(module, "sha512Hex", @[paramDef("msg", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(sha512Hex(args[0].stringVal[])))

  script.addProc(module, "sha256Hex", @[paramDef("msg", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(sha256Hex(args[0].stringVal[])))

  script.addProc(module, "sha384Hex", @[paramDef("msg", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(sha384Hex(args[0].stringVal[])))

  script.addProc(module, "md5Hex", @[paramDef("msg", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      ## MD5 is here for legacy checksums only. Never use it for security.
      result = initValue(md5Hex(args[0].stringVal[])))

  script.addProc(module, "hmacSha1Hex", @[paramDef("keyHex", ttyString),
      paramDef("msg", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(sha1HmacHex(hexDecode(args[0].stringVal[]),
        toBytes(args[1].stringVal[]))))

  script.addProc(module, "hmacSha256Hex", @[paramDef("keyHex", ttyString),
      paramDef("msg", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(sha256HmacHex(hexDecode(args[0].stringVal[]),
        toBytes(args[1].stringVal[]))))

  script.addProc(module, "hmacSha384Hex", @[paramDef("keyHex", ttyString),
      paramDef("msg", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(sha384HmacHex(hexDecode(args[0].stringVal[]),
        toBytes(args[1].stringVal[]))))

  script.addProc(module, "hmacSha512Hex", @[paramDef("keyHex", ttyString),
      paramDef("msg", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(sha512HmacHex(hexDecode(args[0].stringVal[]),
        toBytes(args[1].stringVal[]))))

  script.addProc(module, "hmacMd5Hex", @[paramDef("keyHex", ttyString),
      paramDef("msg", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(md5HmacHex(hexDecode(args[0].stringVal[]),
        toBytes(args[1].stringVal[]))))

  script.addProc(module, "verifyDigestHex", @[paramDef("aHex", ttyString),
      paramDef("bHex", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      ## Constant-time digest comparison.
      result = initValue(verifyDigest(hexDecode(args[0].stringVal[]),
        hexDecode(args[1].stringVal[]))))

  # -------------------------------------------------------------------------
  # xxHash (non-cryptographic)
  # -------------------------------------------------------------------------

  script.addProc(module, "xxh32", @[paramDef("data", ttyString),
      paramDef("seed", ttyInt, initValue(0'i64))], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(int64(xxh32(args[0].stringVal[],
        uint32(args[1].intVal.int)))))

  script.addProc(module, "xxh32Hex", @[paramDef("data", ttyString),
      paramDef("seed", ttyInt, initValue(0'i64))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(xxh32Hex(args[0].stringVal[],
        uint32(args[1].intVal.int))))

  script.addProc(module, "xxh64Hex", @[paramDef("data", ttyString),
      paramDef("seed", ttyInt, initValue(0'i64))], ttyString,
    proc (args: StackView, argc: int): Value =
      ## Hex rather than an integer: a 64-bit hash does not fit a dfkup int.
      result = initValue(xxh64Hex(args[0].stringVal[],
        uint64(args[1].intVal.int))))

  script.addProc(module, "xxh3Hex", @[paramDef("data", ttyString),
      paramDef("seed", ttyInt, initValue(0'i64))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(xxh3_64bitsHex(args[0].stringVal[],
        uint64(args[1].intVal.int))))

  script.addProc(module, "xxh128Hex", @[paramDef("data", ttyString),
      paramDef("seed", ttyInt, initValue(0'i64))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(xxh128Hex(args[0].stringVal[],
        uint64(args[1].intVal.int))))

  # -------------------------------------------------------------------------
  # Key derivation (HKDF)
  # -------------------------------------------------------------------------

  script.addProc(module, "hkdfSha512Hex", @[paramDef("ikm", ttyString),
      paramDef("salt", ttyString), paramDef("info", ttyString),
      paramDef("len", ttyInt, initValue(32'i64))], ttyString,
    proc (args: StackView, argc: int): Value =
      let okm = hkdfSha512(args[0].stringVal[], args[1].stringVal[],
        args[2].stringVal[], args[3].intVal.int)
      result = initValue(hexEncode(okm)))

  script.addProc(module, "hkdfSha256Hex", @[paramDef("ikm", ttyString),
      paramDef("salt", ttyString), paramDef("info", ttyString),
      paramDef("len", ttyInt, initValue(32'i64))], ttyString,
    proc (args: StackView, argc: int): Value =
      let okm = hkdfSha256(args[0].stringVal[], args[1].stringVal[],
        args[2].stringVal[], args[3].intVal.int)
      result = initValue(hexEncode(okm)))

  script.addProc(module, "hkdfSha384Hex", @[paramDef("ikm", ttyString),
      paramDef("salt", ttyString), paramDef("info", ttyString),
      paramDef("len", ttyInt, initValue(32'i64))], ttyString,
    proc (args: StackView, argc: int): Value =
      let okm = hkdfSha384(args[0].stringVal[], args[1].stringVal[],
        args[2].stringVal[], args[3].intVal.int)
      result = initValue(hexEncode(okm)))

  script.addProc(module, "hkdfExpandSha512Hex", @[paramDef("prk", ttyString),
      paramDef("info", ttyString),
      paramDef("len", ttyInt, initValue(32'i64))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(hexEncode(hkdfExpandSha512(args[0].stringVal[],
        args[1].stringVal[], args[2].intVal.int))))

  script.addProc(module, "hkdfExpandSha256Hex", @[paramDef("prk", ttyString),
      paramDef("info", ttyString),
      paramDef("len", ttyInt, initValue(32'i64))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(hexEncode(hkdfExpandSha256(args[0].stringVal[],
        args[1].stringVal[], args[2].intVal.int))))

  script.addProc(module, "hkdfExpandSha384Hex", @[paramDef("prk", ttyString),
      paramDef("info", ttyString),
      paramDef("len", ttyInt, initValue(32'i64))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(hexEncode(hkdfExpandSha384(args[0].stringVal[],
        args[1].stringVal[], args[2].intVal.int))))

  # -------------------------------------------------------------------------
  # Incremental hashing
  #
  # Each family is `newX` / `xUpdate` / `xFinishHex`. The handle carries the
  # running state, so a large file can be hashed without holding it in
  # memory or building one huge dfkup string.
  # -------------------------------------------------------------------------

  script.addProc(module, "newBlake2b", @[
      paramDef("size", ttyInt, initValue(32'i64))], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapState(initBlake2b(args[0].intVal.int), "BLAKE2B"))

  script.addProc(module, "newBlake2bKeyed", @[paramDef("keyHex", ttyString),
      paramDef("size", ttyInt, initValue(32'i64))], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapState(initBlake2bKeyed(toString(hexDecode(args[0].stringVal[])),
        args[1].intVal.int), "BLAKE2B"))

  script.addProc(module, "blake2bUpdate", @[paramDef("h", ttyPointer),
      paramDef("chunk", ttyString)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      var st = getState[Blake2b](args[0], "BLAKE2B")
      st.update(args[1].stringVal[]))

  script.addProc(module, "blake2bFinishHex", @[paramDef("h", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(getState[Blake2b](args[0], "BLAKE2B").finishHex()))

  script.addProc(module, "newSha512", @[], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapState(initSha512(), "SHA512"))

  script.addProc(module, "sha512Update", @[paramDef("h", ttyPointer),
      paramDef("chunk", ttyString)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      var st = getState[Sha512State](args[0], "SHA512")
      st.update(args[1].stringVal[]))

  script.addProc(module, "sha512FinishHex", @[paramDef("h", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(getState[Sha512State](args[0], "SHA512").finishHex()))

  script.addProc(module, "newSha256", @[], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapState(initSha256(), "SHA256"))

  script.addProc(module, "sha256Update", @[paramDef("h", ttyPointer),
      paramDef("chunk", ttyString)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      var st = getState[Sha256State](args[0], "SHA256")
      st.update(args[1].stringVal[]))

  script.addProc(module, "sha256FinishHex", @[paramDef("h", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(getState[Sha256State](args[0], "SHA256").finishHex()))

  script.addProc(module, "newSha384", @[], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapState(initSha384(), "SHA384"))

  script.addProc(module, "sha384Update", @[paramDef("h", ttyPointer),
      paramDef("chunk", ttyString)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      var st = getState[Sha384State](args[0], "SHA384")
      st.update(args[1].stringVal[]))

  script.addProc(module, "sha384FinishHex", @[paramDef("h", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(getState[Sha384State](args[0], "SHA384").finishHex()))

  script.addProc(module, "newMd5", @[], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapState(initMd5(), "MD5"))

  script.addProc(module, "md5Update", @[paramDef("h", ttyPointer),
      paramDef("chunk", ttyString)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      var st = getState[Md5State](args[0], "MD5")
      st.update(args[1].stringVal[]))

  script.addProc(module, "md5FinishHex", @[paramDef("h", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(getState[Md5State](args[0], "MD5").finishHex()))

  script.addProc(module, "newHmacSha512", @[paramDef("keyHex", ttyString)],
      ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapState(initSha512Hmac(hexDecode(args[0].stringVal[])),
        "SHA512HMAC"))

  script.addProc(module, "hmacSha512Update", @[paramDef("h", ttyPointer),
      paramDef("chunk", ttyString)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      var st = getState[Sha512HmacState](args[0], "SHA512HMAC")
      st.update(args[1].stringVal[]))

  script.addProc(module, "hmacSha512FinishHex", @[paramDef("h", ttyPointer)],
      ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(getState[Sha512HmacState](args[0],
        "SHA512HMAC").finishHex()))

  script.addProc(module, "newHmacSha256", @[paramDef("keyHex", ttyString)],
      ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapState(initSha256Hmac(hexDecode(args[0].stringVal[])),
        "SHA256HMAC"))

  script.addProc(module, "hmacSha256Update", @[paramDef("h", ttyPointer),
      paramDef("chunk", ttyString)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      var st = getState[Sha256HmacState](args[0], "SHA256HMAC")
      st.update(args[1].stringVal[]))

  script.addProc(module, "hmacSha256FinishHex", @[paramDef("h", ttyPointer)],
      ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(getState[Sha256HmacState](args[0],
        "SHA256HMAC").finishHex()))

  script.addProc(module, "newHmacSha384", @[paramDef("keyHex", ttyString)],
      ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapState(initSha384Hmac(hexDecode(args[0].stringVal[])),
        "SHA384HMAC"))

  script.addProc(module, "hmacSha384Update", @[paramDef("h", ttyPointer),
      paramDef("chunk", ttyString)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      var st = getState[Sha384HmacState](args[0], "SHA384HMAC")
      st.update(args[1].stringVal[]))

  script.addProc(module, "hmacSha384FinishHex", @[paramDef("h", ttyPointer)],
      ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(getState[Sha384HmacState](args[0],
        "SHA384HMAC").finishHex()))

  script.addProc(module, "newHmacMd5", @[paramDef("keyHex", ttyString)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapState(initMd5Hmac(hexDecode(args[0].stringVal[])), "MD5HMAC"))

  script.addProc(module, "hmacMd5Update", @[paramDef("h", ttyPointer),
      paramDef("chunk", ttyString)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      var st = getState[Md5HmacState](args[0], "MD5HMAC")
      st.update(args[1].stringVal[]))

  script.addProc(module, "hmacMd5FinishHex", @[paramDef("h", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(getState[Md5HmacState](args[0], "MD5HMAC").finishHex()))

  script.addProc(module, "newXxh32", @[
      paramDef("seed", ttyInt, initValue(0'i64))], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapState(initXxh32(uint32(args[0].intVal.int)), "XXH32"))

  script.addProc(module, "xxh32Update", @[paramDef("h", ttyPointer),
      paramDef("chunk", ttyString)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      var st = getState[Xxh32](args[0], "XXH32")
      st.update(args[1].stringVal[]))

  script.addProc(module, "xxh32FinishHex", @[paramDef("h", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(getState[Xxh32](args[0], "XXH32").finishHex()))

  script.addProc(module, "newXxh64", @[
      paramDef("seed", ttyInt, initValue(0'i64))], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapState(initXxh64(uint64(args[0].intVal.int)), "XXH64"))

  script.addProc(module, "xxh64Update", @[paramDef("h", ttyPointer),
      paramDef("chunk", ttyString)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      var st = getState[Xxh64](args[0], "XXH64")
      st.update(args[1].stringVal[]))

  script.addProc(module, "xxh64FinishHex", @[paramDef("h", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(getState[Xxh64](args[0], "XXH64").finishHex()))

  script.addProc(module, "newXxh3", @[
      paramDef("seed", ttyInt, initValue(0'i64))], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapState(initXxh3_64(uint64(args[0].intVal.int)), "XXH3"))

  script.addProc(module, "xxh3Update", @[paramDef("h", ttyPointer),
      paramDef("chunk", ttyString)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      var st = getState[Xxh3_64](args[0], "XXH3")
      st.update(args[1].stringVal[]))

  script.addProc(module, "xxh3FinishHex", @[paramDef("h", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(getState[Xxh3_64](args[0], "XXH3").finishHex()))

  script.addProc(module, "newXxh128", @[
      paramDef("seed", ttyInt, initValue(0'i64))], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapState(initXxh3_128(uint64(args[0].intVal.int)), "XXH128"))

  script.addProc(module, "xxh128Update", @[paramDef("h", ttyPointer),
      paramDef("chunk", ttyString)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      var st = getState[Xxh3_128](args[0], "XXH128")
      st.update(args[1].stringVal[]))

  script.addProc(module, "xxh128FinishHex", @[paramDef("h", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(getState[Xxh3_128](args[0], "XXH128").finishHex()))

  # -------------------------------------------------------------------------
  # X25519 key exchange
  # -------------------------------------------------------------------------

  script.addProc(module, "x25519KeyPair", @[], ttyString,
    proc (args: StackView, argc: int): Value =
      ## {"secret": hex, "public": hex}
      let (secretKey, publicKey) = x25519KeyPair()
      result = initValue(hexEncode(secretKey) & "." & hexEncode(publicKey)))

  script.addProc(module, "x25519KeyPairFromSecret", @[
      paramDef("secretHex", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      let (secretKey, publicKey) = x25519KeyPair(key32FromHex(args[0].stringVal[]))
      result = initValue(hexEncode(secretKey) & "." & hexEncode(publicKey)))

  script.addProc(module, "x25519SecretOf", @[paramDef("packed", ttyString)],
      ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(unpack(args[0].stringVal[], 2, "X25519 key pair")[0]))

  script.addProc(module, "x25519PublicOf", @[paramDef("packed", ttyString)],
      ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(unpack(args[0].stringVal[], 2, "X25519 key pair")[1]))

  script.addProc(module, "sharedSecretHex", @[paramDef("mySecretHex", ttyString),
      paramDef("theirPublicHex", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      ## Raw X25519 output. Run it through `sharedSecretHashedHex` before
      ## using it as a symmetric key.
      let s = sharedSecret(key32FromHex(args[0].stringVal[]),
        key32FromHex(args[1].stringVal[]))
      result = initValue(hexEncode(s.data)))

  script.addProc(module, "sharedSecretHashedHex", @[
      paramDef("mySecretHex", ttyString),
      paramDef("theirPublicHex", ttyString),
      paramDef("info", ttyString, initValue(""))], ttyString,
    proc (args: StackView, argc: int): Value =
      ## X25519 shared secret through HKDF-SHA-256. This is the one to use
      ## for symmetric keys.
      let s = sharedSecretHashed(key32FromHex(args[0].stringVal[]),
        key32FromHex(args[1].stringVal[]), toBytes(args[2].stringVal[]))
      result = initValue(hexEncode(s.data)))

  script.addProc(module, "challengeMacHex", @[paramDef("secretHex", ttyString),
      paramDef("challengeHex", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(hexEncode(computeChallengeMac(
        key32FromHex(args[0].stringVal[]),
        mac16FromHex(args[1].stringVal[])))))

  script.addProc(module, "verifyChallengeMac", @[
      paramDef("secretHex", ttyString),
      paramDef("challengeHex", ttyString),
      paramDef("receivedHex", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(verifyChallengeMac(key32FromHex(args[0].stringVal[]),
        mac16FromHex(args[1].stringVal[]),
        mac16FromHex(args[2].stringVal[]))))

  # -------------------------------------------------------------------------
  # AEAD: XChaCha20-Poly1305
  # -------------------------------------------------------------------------

  script.addProc(module, "seal", @[paramDef("msg", ttyString),
      paramDef("keyHex", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      ## Packs as `hex(nonce) "." hex(mac) "." hex(cipher)`.
      let sealed = seal(args[0].stringVal[], key32FromHex(args[1].stringVal[]))
      result = initValue(pack3(sealed.nonce, sealed.mac, sealed.cipherText)))

  script.addProc(module, "unseal", @[paramDef("packed", ttyString),
      paramDef("keyHex", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      let (n, m, c) = unpack3(args[0].stringVal[], "sealed message")
      var msg = SealedMessage(nonce: nonce24FromHex(n), mac: mac16FromHex(m),
        cipherText: hexDecode(c))
      result = initValue(toString(unseal(msg, key32FromHex(args[1].stringVal[])))))

  script.addProc(module, "aeadEncryptHex", @[paramDef("msg", ttyString),
      paramDef("keyHex", ttyString),
      paramDef("nonceHex", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      ## AEAD with a nonce you supply, so you control (and must not reuse)
      ## it. Returns {"cipherText": hex, "mac": hex}.
      let (ct, mac) = encrypt(args[0].stringVal[],
        key32FromHex(args[1].stringVal[]), nonce24FromHex(args[2].stringVal[]))
      result = initValue(hexEncode(ct) & "." & hexEncode(mac)))

  script.addProc(module, "aeadDecryptHex", @[paramDef("cipherTextHex", ttyString),
      paramDef("macHex", ttyString), paramDef("keyHex", ttyString),
      paramDef("nonceHex", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      let plain = decrypt(hexDecode(args[0].stringVal[]),
        mac16FromHex(args[1].stringVal[]),
        key32FromHex(args[2].stringVal[]),
        nonce24FromHex(args[3].stringVal[]))
      result = initValue(toString(plain)))

  script.addProc(module, "aeadOpenPackedHex", @[paramDef("packed", ttyString),
      paramDef("keyHex", ttyString),
      paramDef("nonceHex", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      ## Inverse of `aeadEncryptHex`, taking the same packed value back.
      let parts = unpack(args[0].stringVal[], 2, "AEAD result")
      let plain = decrypt(hexDecode(parts[0]), mac16FromHex(parts[1]),
        key32FromHex(args[1].stringVal[]), nonce24FromHex(args[2].stringVal[]))
      result = initValue(toString(plain)))

  script.addProc(module, "newAeadStream", @[
      paramDef("mode", ttyString, initValue("X")),
      paramDef("keyHex", ttyString),
      paramDef("nonceHex", ttyString)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      ## mode is "X" (24-byte nonce, XChaCha20), "DJB" (8) or "IETF" (12).
      let key = key32FromHex(args[1].stringVal[])
      let modeName = args[0].stringVal[].toUpperAscii()
      var stream: AeadStream
      case modeName
      of "X":
        stream = aeadStreamInitX(key, nonce24FromHex(args[2].stringVal[]))
      of "DJB":
        stream = aeadStreamInitDjb(key, fixedBytes(
          args[2].stringVal[], 8, "nonce"))
      of "IETF":
        stream = aeadStreamInitIetf(key, fixedBytes(
          args[2].stringVal[], 12, "nonce"))
      else:
        raise newException(ValueError,
          "unknown AEAD mode '" & modeName & "' (use X, DJB or IETF)")
      result = wrapState(stream, "AEADSTREAM"))

  script.addProc(module, "aeadStreamWrite", @[paramDef("h", ttyPointer),
      paramDef("plainText", ttyString),
      paramDef("ad", ttyString, initValue(""))], ttyString,
    proc (args: StackView, argc: int): Value =
      var st = getState[AeadStream](args[0], "AEADSTREAM")
      let (ct, mac) = aeadStreamWrite(st, toBytes(args[1].stringVal[]),
        toBytes(args[2].stringVal[]))
      result = initValue(hexEncode(ct) & "." & hexEncode(mac)))

  script.addProc(module, "aeadStreamRead", @[paramDef("h", ttyPointer),
      paramDef("cipherTextHex", ttyString), paramDef("macHex", ttyString),
      paramDef("ad", ttyString, initValue(""))], ttyString,
    proc (args: StackView, argc: int): Value =
      var st = getState[AeadStream](args[0], "AEADSTREAM")
      let plain = aeadStreamRead(st, hexDecode(args[1].stringVal[]),
        mac16FromHex(args[2].stringVal[]), toBytes(args[3].stringVal[]))
      result = initValue(toString(plain)))

  # -------------------------------------------------------------------------
  # AES block modes
  #
  # `padded` defaults to true for ECB/CBC (PKCS#7). CTR/OFB/CFB are
  # stream-like and never pad, so they take no flag.
  # -------------------------------------------------------------------------

  script.addProc(module, "aesEcbEncryptHex", @[paramDef("keyHex", ttyString),
      paramDef("plainText", ttyString),
      paramDef("padded", ttyBool, initValue(true))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(hexEncode(aesEcbEncrypt(aesKeyFromHex(args[0].stringVal[]),
        toBytes(args[1].stringVal[]), args[2].boolVal))))

  script.addProc(module, "aesEcbDecryptHex", @[paramDef("keyHex", ttyString),
      paramDef("cipherTextHex", ttyString),
      paramDef("padded", ttyBool, initValue(true))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(toString(aesEcbDecrypt(
        aesKeyFromHex(args[0].stringVal[]),
        hexDecode(args[1].stringVal[]), args[2].boolVal))))

  script.addProc(module, "aesCbcEncryptHex", @[paramDef("keyHex", ttyString),
      paramDef("ivHex", ttyString), paramDef("plainText", ttyString),
      paramDef("padded", ttyBool, initValue(true))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(hexEncode(aesCbcEncrypt(
        aesKeyFromHex(args[0].stringVal[]),
        hexDecode(args[1].stringVal[]),
        toBytes(args[2].stringVal[]), args[3].boolVal))))

  script.addProc(module, "aesCbcDecryptHex", @[paramDef("keyHex", ttyString),
      paramDef("ivHex", ttyString), paramDef("cipherTextHex", ttyString),
      paramDef("padded", ttyBool, initValue(true))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(toString(aesCbcDecrypt(
        aesKeyFromHex(args[0].stringVal[]),
        hexDecode(args[1].stringVal[]),
        hexDecode(args[2].stringVal[]), args[3].boolVal))))

  script.addProc(module, "aesCtrCryptHex", @[paramDef("keyHex", ttyString),
      paramDef("counterHex", ttyString), paramDef("text", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(hexEncode(aesCtrCrypt(
        aesKeyFromHex(args[0].stringVal[]),
        hexDecode(args[1].stringVal[]),
        toBytes(args[2].stringVal[])))))

  script.addProc(module, "aesOfbCryptHex", @[paramDef("keyHex", ttyString),
      paramDef("ivHex", ttyString), paramDef("text", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(hexEncode(aesOfbCrypt(
        aesKeyFromHex(args[0].stringVal[]),
        hexDecode(args[1].stringVal[]),
        toBytes(args[2].stringVal[])))))

  script.addProc(module, "aesCfbEncryptHex", @[paramDef("keyHex", ttyString),
      paramDef("ivHex", ttyString), paramDef("plainText", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(hexEncode(aesCfbEncrypt(
        aesKeyFromHex(args[0].stringVal[]),
        hexDecode(args[1].stringVal[]),
        toBytes(args[2].stringVal[])))))

  script.addProc(module, "aesCfbDecryptHex", @[paramDef("keyHex", ttyString),
      paramDef("ivHex", ttystring), paramDef("cipherTextHex", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(toString(aesCfbDecrypt(
        aesKeyFromHex(args[0].stringVal[]),
        hexDecode(args[1].stringVal[]),
        hexDecode(args[2].stringVal[])))))

  # -------------------------------------------------------------------------
  # AES-GCM
  # -------------------------------------------------------------------------

  script.addProc(module, "gcmSealHex", @[paramDef("msg", ttyString),
      paramDef("keyHex", ttyString),
      paramDef("ad", ttyString, initValue(""))], ttyString,
    proc (args: StackView, argc: int): Value =
      ## Packs as `hex(nonce) "." hex(tag) "." hex(cipher)`.
      let sealed = gcmSeal(args[0].stringVal[],
        aesKeyFromHex(args[1].stringVal[]), toBytes(args[2].stringVal[]))
      result = initValue(pack3(sealed.nonce, sealed.tag, sealed.cipherText)))

  script.addProc(module, "gcmOpenHex", @[paramDef("packed", ttyString),
      paramDef("keyHex", ttyString),
      paramDef("ad", ttyString, initValue(""))], ttyString,
    proc (args: StackView, argc: int): Value =
      let (n, t, c) = unpack3(args[0].stringVal[], "sealed message")
      var msg = GcmSealed(nonce: fixedBytes(n, 12, "nonce"),
        tag: mac16FromHex(t), cipherText: hexDecode(c))
      result = initValue(gcmOpenStr(msg, aesKeyFromHex(args[1].stringVal[]),
        toBytes(args[2].stringVal[]))))

  script.addProc(module, "aesGcmEncryptHex", @[paramDef("keyHex", ttyString),
      paramDef("nonceHex", ttyString), paramDef("plainText", ttyString),
      paramDef("ad", ttyString, initValue(""))], ttyString,
    proc (args: StackView, argc: int): Value =
      let (ct, tag) = aesGcmEncrypt(aesKeyFromHex(args[0].stringVal[]),
        hexDecode(args[1].stringVal[]), toBytes(args[2].stringVal[]),
        toBytes(args[3].stringVal[]))
      result = initValue(hexEncode(ct) & "." & hexEncode(tag)))

  script.addProc(module, "aesGcmDecryptHex", @[paramDef("keyHex", ttyString),
      paramDef("nonceHex", ttyString), paramDef("cipherTextHex", ttyString),
      paramDef("tagHex", ttyString),
      paramDef("ad", ttyString, initValue(""))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(aesGcmDecryptStr(aesKeyFromHex(args[0].stringVal[]),
        hexDecode(args[1].stringVal[]), hexDecode(args[2].stringVal[]),
        hexDecode(args[3].stringVal[]), toBytes(args[4].stringVal[]))))

  script.addProc(module, "aesGcmOpenPackedHex", @[paramDef("packed", ttyString),
      paramDef("keyHex", ttyString), paramDef("nonceHex", ttyString),
      paramDef("ad", ttyString, initValue(""))], ttyString,
    proc (args: StackView, argc: int): Value =
      ## Inverse of `aesGcmEncryptHex`. The nonce stays yours to supply, so it
      ## is a separate argument rather than part of the packed value.
      let parts = unpack(args[0].stringVal[], 2, "AES-GCM result")
      result = initValue(aesGcmDecryptStr(aesKeyFromHex(args[1].stringVal[]),
        hexDecode(args[2].stringVal[]), hexDecode(parts[0]), hexDecode(parts[1]),
        toBytes(args[3].stringVal[]))))

  script.addProc(module, "newGcmStream", @[paramDef("keyHex", ttyString),
      paramDef("nonceHex", ttyString),
      paramDef("ad", ttyString, initValue("")),
      paramDef("encrypting", ttyBool, initValue(true))], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapState(gcmStreamInit(aesKeyFromHex(args[0].stringVal[]),
        hexDecode(args[1].stringVal[]), toBytes(args[2].stringVal[]),
        args[3].boolVal), "GCMSTREAM"))

  script.addProc(module, "gcmStreamUpdate", @[paramDef("h", ttyPointer),
      paramDef("chunk", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      var st = getState[AesGcmStream](args[0], "GCMSTREAM")
      result = initValue(hexEncode(gcmStreamUpdate(st, toBytes(args[1].stringVal[])))))

  script.addProc(module, "gcmStreamFinal", @[paramDef("h", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      var st = getState[AesGcmStream](args[0], "GCMSTREAM")
      result = initValue(hexEncode(gcmStreamFinal(st))))

  script.addProc(module, "gcmStreamVerify", @[paramDef("h", ttyPointer),
      paramDef("tagHex", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      var st = getState[AesGcmStream](args[0], "GCMSTREAM")
      result = initValue(gcmStreamVerify(st, hexDecode(args[1].stringVal[]))))

  # -------------------------------------------------------------------------
  # Ed25519 signatures
  # -------------------------------------------------------------------------

  script.addProc(module, "generateSigningKeyPair", @[
      paramDef("seedHex", ttyString, initValue(""))], ttyString,
    proc (args: StackView, argc: int): Value =
      ## With a seedHex the key pair is deterministic; without one it is
      ## random. Packed as `publicHex.secretHex`.
      var kp: SigningKeyPair
      let seed = args[0].stringVal[]
      if seed.len == 0:
        kp = generateSigningKeyPair()
      else:
        kp = generateSigningKeyPair(key32FromHex(seed))
      result = initValue(publicKeyToHex(kp.publicKey) & "." &
        secretKeyToHex(kp.secretKey.data)))

  script.addProc(module, "signPublicOf", @[paramDef("packed", ttyString)],
      ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(unpack(args[0].stringVal[], 2, "signing key pair")[0]))

  script.addProc(module, "signSecretOf", @[paramDef("packed", ttyString)],
      ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(unpack(args[0].stringVal[], 2, "signing key pair")[1]))

  script.addProc(module, "signHex", @[paramDef("secretHex", ttyString),
      paramDef("msg", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(signatureToHex(sign(
        secretKeyFromHex(args[0].stringVal[]), args[1].stringVal[]))))

  script.addProc(module, "verifySignature", @[paramDef("publicHex", ttyString),
      paramDef("msg", ttyString), paramDef("sigHex", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(verify(publicKeyFromHex(args[0].stringVal[]),
        args[1].stringVal[], signatureFromHex(args[2].stringVal[]))))

  # -------------------------------------------------------------------------
  # Password hashing (Argon2id)
  # -------------------------------------------------------------------------

  script.addProc(module, "hashPassword", @[paramDef("pw", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      ## Returns `hex(salt) ":" hex(hash)`.
      result = initValue(hashPassword(args[0].stringVal[])))

  script.addProc(module, "verifyPassword", @[paramDef("pw", ttyString),
      paramDef("stored", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(verifyPassword(args[0].stringVal[], args[1].stringVal[])))

  script.addProc(module, "deriveKeyFromPasswordHex", @[
      paramDef("pw", ttyString),
      paramDef("saltHex", ttyString, initValue(""))], ttyString,
    proc (args: StackView, argc: int): Value =
      ## Argon2id to a 32-byte key. A blank saltHex generates a fresh one,
      ## which you then need to store alongside whatever you protect.
      var salt = generateSalt()
      let s = args[1].stringVal[]
      if s.len != 0:
        salt = fixedBytes(s, 16, "salt")
      result = initValue(hexEncode(
        deriveKeyFromPassword(args[0].stringVal[], salt).data)))

  script.addProc(module, "keyPairFromPasswordHex", @[
      paramDef("pw", ttyString),
      paramDef("saltHex", ttyString, initValue(""))], ttyString,
    proc (args: StackView, argc: int): Value =
      ## Argon2id to an X25519 key pair. Returns {"secret": hex,
      ## "public": hex, "salt": hex}.
      var salt = generateSalt()
      let s = args[1].stringVal[]
      if s.len != 0:
        salt = fixedBytes(s, 16, "salt")
      let (secretKey, publicKey) = keyPairFromPassword(args[0].stringVal[], salt)
      result = initValue(hexEncode(secretKey.data) & "." & hexEncode(publicKey) &
        "." & hexEncode(salt)))

  script.addProc(module, "passwordKeyPairSalt", @[paramDef("packed", ttyString)],
      ttyString,
    proc (args: StackView, argc: int): Value =
      ## The salt Argon2 used, so you can re-derive the same key later.
      result = initValue(unpack(args[0].stringVal[], 3, "password key pair")[2]))

  # -------------------------------------------------------------------------
  # RSA
  #
  # Keys are opaque handles: the modulus is a BigInt and does not belong in
  # a dfkup string. `...ToHex` / `...FromHex` move a key across a trust
  # boundary (a file, a config), which is the only reason to serialize one.
  # -------------------------------------------------------------------------

  script.addProc(module, "newRsaKeyPair", @[
      paramDef("bits", ttyInt, initValue(2048'i64)),
      paramDef("e", ttyInt, initValue(65537'i64))], ttyPointer,
    proc (args: StackView, argc: int): Value =
      ## Key generation is pure Nim, so it is slow. Prefer Ed25519 or X25519
      ## unless you specifically need RSA interchange.
      result = wrapState(generateRsaKeyPair(bits = args[0].intVal.int,
        e = args[1].intVal.int), "RSAPRIV"))

  script.addProc(module, "rsaPublicKeyOf", @[paramDef("priv", ttyPointer)],
      ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapState(rsaPublicKey(getState[rsaHigh.RsaPrivateKey](args[0],
        "RSAPRIV")), "RSAPUB"))

  script.addProc(module, "rsaPrivateKeyToHex", @[paramDef("priv", ttyPointer)],
      ttyString,
    proc (args: StackView, argc: int): Value =
      let k = getState[rsaHigh.RsaPrivateKey](args[0], "RSAPRIV")
      let half = (k.k + 1) div 2
      result = initValue(bigToHex(k.n, k.k) & "." & bigToHex(k.e, 8) & "." &
        bigToHex(k.d, k.k) & "." & bigToHex(k.p, half) & "." &
        bigToHex(k.q, half) & "." & bigToHex(k.dp, half) & "." &
        bigToHex(k.dq, half) & "." & bigToHex(k.qinv, half)))

  script.addProc(module, "rsaPublicKeyToHex", @[paramDef("pub", ttyPointer)],
      ttyString,
    proc (args: StackView, argc: int): Value =
      let k = getState[rsaHigh.RsaPublicKey](args[0], "RSAPUB")
      result = initValue(bigToHex(k.n, k.k) & "." & bigToHex(k.e, 8)))

  script.addProc(module, "rsaPrivateKeyFromHex", @[paramDef("packed", ttyString)],
      ttyPointer,
    proc (args: StackView, argc: int): Value =
      let f = unpack(args[0].stringVal[], 8, "RSA private key")
      var k: rsaHigh.RsaPrivateKey
      k.k = f[0].len div 2
      let half = (k.k + 1) div 2
      k.n = bigFromHex(f[0], k.k, "n")
      k.e = bigFromHex(f[1], 8, "e")
      k.d = bigFromHex(f[2], k.k, "d")
      k.p = bigFromHex(f[3], half, "p")
      k.q = bigFromHex(f[4], half, "q")
      k.dp = bigFromHex(f[5], half, "dp")
      k.dq = bigFromHex(f[6], half, "dq")
      k.qinv = bigFromHex(f[7], half, "qinv")
      result = wrapState(k, "RSAPRIV"))

  script.addProc(module, "rsaPublicKeyFromHex", @[paramDef("packed", ttyString)],
      ttyPointer,
    proc (args: StackView, argc: int): Value =
      let f = unpack(args[0].stringVal[], 2, "RSA public key")
      var k: rsaHigh.RsaPublicKey
      k.k = f[0].len div 2
      k.n = bigFromHex(f[0], k.k, "n")
      k.e = bigFromHex(f[1], 8, "e")
      result = wrapState(k, "RSAPUB"))

  script.addProc(module, "wipeRsaKey", @[paramDef("priv", ttyPointer)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      ## Drop the private scalars. Good hygiene once a key is retired.
      var st = getState[rsaHigh.RsaPrivateKey](args[0], "RSAPRIV")
      wipeRsaKey(st))

  script.addProc(module, "rsaPkcs1v15SignHex", @[paramDef("priv", ttyPointer),
      paramDef("hash", ttyString), paramDef("msg", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(hexEncode(rsaPkcs1v15Sign(
        getState[rsaHigh.RsaPrivateKey](args[0], "RSAPRIV"),
        parseRsaHash(args[1].stringVal[]), args[2].stringVal[]))))

  script.addProc(module, "rsaPkcs1v15Verify", @[paramDef("pub", ttyPointer),
      paramDef("hash", ttyString), paramDef("msg", ttyString),
      paramDef("sigHex", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(rsaPkcs1v15Verify(
        getState[rsaHigh.RsaPublicKey](args[0], "RSAPUB"),
        parseRsaHash(args[1].stringVal[]), args[2].stringVal[],
        hexDecode(args[3].stringVal[]))))

  script.addProc(module, "rsaPssSignHex", @[paramDef("priv", ttyPointer),
      paramDef("hash", ttyString), paramDef("msg", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(hexEncode(rsaPssSign(
        getState[rsaHigh.RsaPrivateKey](args[0], "RSAPRIV"),
        parseRsaHash(args[1].stringVal[]), args[2].stringVal[]))))

  script.addProc(module, "rsaPssVerify", @[paramDef("pub", ttyPointer),
      paramDef("hash", ttyString), paramDef("msg", ttyString),
      paramDef("sigHex", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(rsaPssVerify(
        getState[rsaHigh.RsaPublicKey](args[0], "RSAPUB"),
        parseRsaHash(args[1].stringVal[]), args[2].stringVal[],
        hexDecode(args[3].stringVal[]))))

  script.addProc(module, "rsaOaepEncryptHex", @[paramDef("pub", ttyPointer),
      paramDef("hash", ttyString), paramDef("msg", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(hexEncode(rsaOaepEncrypt(
        getState[rsaHigh.RsaPublicKey](args[0], "RSAPUB"),
        parseRsaHash(args[1].stringVal[]), args[2].stringVal[]))))

  script.addProc(module, "rsaOaepDecryptHex", @[paramDef("priv", ttyPointer),
      paramDef("hash", ttyString), paramDef("cipherTextHex", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(hexEncode(rsaOaepDecrypt(
        getState[rsaHigh.RsaPrivateKey](args[0], "RSAPRIV"),
        parseRsaHash(args[1].stringVal[]),
        hexDecode(args[2].stringVal[])))))

  script.addProc(module, "rsaPkcs1v15EncryptHex", @[paramDef("pub", ttyPointer),
      paramDef("msg", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(hexEncode(rsaPkcs1v15Encrypt(
        getState[rsaHigh.RsaPublicKey](args[0], "RSAPUB"), args[1].stringVal[]))))

  script.addProc(module, "rsaPkcs1v15DecryptHex", @[paramDef("priv", ttyPointer),
      paramDef("cipherTextHex", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(hexEncode(rsaPkcs1v15Decrypt(
        getState[rsaHigh.RsaPrivateKey](args[0], "RSAPRIV"),
        hexDecode(args[1].stringVal[])))))

  # -------------------------------------------------------------------------
  # ECDSA / ECDH
  #
  # JOSE mapping: P-256/SHA-256 = ES256, P-384/SHA-384 = ES384,
  # P-521/SHA-512 = ES512, secp256k1/SHA-256 = ES256K.
  # -------------------------------------------------------------------------

  script.addProc(module, "newEcKeyPair", @[
      paramDef("curve", ttyString, initValue("P256"))], ttyPointer,
    proc (args: StackView, argc: int): Value =
      ## Handle to the private key; `ecPublicKeyOf` derives the public half.
      let (priv, _) = generateEcKeyPair(parseCurve(args[0].stringVal[]))
      result = wrapState(priv, "ECPRIV"))

  script.addProc(module, "ecPublicKeyOf", @[paramDef("priv", ttyPointer)],
      ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapState(ecPublicKeyFromPrivate(
        getState[ecHigh.EcPrivateKey](args[0], "ECPRIV")), "ECPUB"))

  script.addProc(module, "validateEcPublicKey", @[paramDef("pub", ttyPointer)],
      ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(ecValidatePublicKey(
        getState[ecHigh.EcPublicKey](args[0], "ECPUB"))))

  script.addProc(module, "ecPrivateKeyToHex", @[paramDef("priv", ttyPointer)],
      ttyString,
    proc (args: StackView, argc: int): Value =
      let k = getState[ecHigh.EcPrivateKey](args[0], "ECPRIV")
      result = initValue($k.curve & "." &
        bigToHex(k.d, curveWidths(k.curve).order)))

  script.addProc(module, "ecPublicKeyToHex", @[paramDef("pub", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      let k = getState[ecHigh.EcPublicKey](args[0], "ECPUB")
      let w = curveWidths(k.curve).coord
      result = initValue($k.curve & "." & bigToHex(k.x, w) & "." &
        bigToHex(k.y, w)))

  script.addProc(module, "ecPrivateKeyFromHex", @[paramDef("packed", ttyString)],
      ttyPointer,
    proc (args: StackView, argc: int): Value =
      let f = unpack(args[0].stringVal[], 2, "EC private key")
      let curve = parseCurve(f[0])
      var k: ecHigh.EcPrivateKey
      k.curve = curve
      k.d = bigFromHex(f[1], curveWidths(curve).order, "d")
      result = wrapState(k, "ECPRIV"))

  script.addProc(module, "ecPublicKeyFromHex", @[paramDef("packed", ttyString)],
      ttyPointer,
    proc (args: StackView, argc: int): Value =
      let f = unpack(args[0].stringVal[], 3, "EC public key")
      let curve = parseCurve(f[0])
      var k: ecHigh.EcPublicKey
      k.curve = curve
      let w = curveWidths(curve).coord
      k.x = bigFromHex(f[1], w, "x")
      k.y = bigFromHex(f[2], w, "y")
      result = wrapState(k, "ECPUB"))

  script.addProc(module, "wipeEcKey", @[paramDef("priv", ttyPointer)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      var st = getState[ecHigh.EcPrivateKey](args[0], "ECPRIV")
      wipeEcKey(st))

  script.addProc(module, "ecdsaSignHex", @[paramDef("priv", ttyPointer),
      paramDef("msg", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(hexEncode(ecdsaSign(
        getState[ecHigh.EcPrivateKey](args[0], "ECPRIV"),
        args[1].stringVal[]))))

  script.addProc(module, "ecdsaVerify", @[paramDef("pub", ttyPointer),
      paramDef("msg", ttyString), paramDef("sigHex", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(ecdsaVerify(
        getState[ecHigh.EcPublicKey](args[0], "ECPUB"),
        args[1].stringVal[], hexDecode(args[2].stringVal[]))))

  script.addProc(module, "ecdhSharedSecretHex", @[paramDef("priv", ttyPointer),
      paramDef("peerPub", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      ## Raw ECDH output; run it through a KDF before using it as a key.
      result = initValue(hexEncode(ecdhSharedSecret(
        getState[ecHigh.EcPrivateKey](args[0], "ECPRIV"),
        getState[ecHigh.EcPublicKey](args[1], "ECPUB")))))

  script.addProc(module, "ecdhHashedSecretHex", @[paramDef("priv", ttyPointer),
      paramDef("peerPub", ttyPointer),
      paramDef("info", ttyString, initValue(""))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(hexEncode(ecdhHashedSecret(
        getState[ecHigh.EcPrivateKey](args[0], "ECPRIV"),
        getState[ecHigh.EcPublicKey](args[1], "ECPUB"),
        toBytes(args[2].stringVal[])))))
