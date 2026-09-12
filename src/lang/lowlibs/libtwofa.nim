# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/[strutils]
import pkg/twofa
import pkg/twofa/[otp, base32]
import pkg/nimcypher/utils as cryptoUtils
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

type
  TotpBox = ref object
    totp: TOTP
  HotpBox = ref object
    hotp: HOTP

proc wrapTotp(t: sink TOTP): Value =
  let box = TotpBox(totp: ensureMove(t))
  result = initValue(tyPointer, box)
  result.objectVal.foreign.tag = "TOTP"

proc wrapHotp(h: sink HOTP): Value =
  let box = HotpBox(hotp: ensureMove(h))
  result = initValue(tyPointer, box)
  result.objectVal.foreign.tag = "HOTP"

proc getTotp(v: Value): var TOTP =
  cast[TotpBox](v.objectVal.foreign.data).totp

proc getHotp(v: Value): var HOTP =
  cast[HotpBox](v.objectVal.foreign.data).hotp

proc parseAlgo(s: string): OTPAlgorithm =
  case s.toUpperAscii()
  of "SHA512", "SHA-512": algSHA512
  else: algSHA1

proc padCode(code: int, digits: int): string =
  result = $code
  while result.len < digits:
    result = "0" & result

proc initTwofa*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  script.addProc(module, "genSecret", @[
      paramDef("nbytes", ttyInt, initValue(20'i64))], ttyString,
    proc (args: StackView, argc: int): Value =
      var raw = newStringOfCap(args[0].intVal.int)
      var produced = 0
      while produced < args[0].intVal.int:
        let rnd = cryptoUtils.randomBytes[32]()
        for b in rnd:
          if produced >= args[0].intVal.int: break
          raw.add(char(b))
          inc produced
      result = initValue(base32.encode(raw, false).toUpperAscii()))

  script.addProc(module, "newTotp", @[paramDef("secret", ttyString),
      paramDef("issuer", ttyString, initValue("")),
      paramDef("account", ttyString, initValue("")),
      paramDef("digits", ttyInt, initValue(6'i64)),
      paramDef("interval", ttyInt, initValue(30'i64)),
      paramDef("algo", ttyString, initValue("SHA1"))], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapTotp(initTotp(args[0].stringVal[],
        digits = args[3].intVal.int.OTPDigits,
        interval = args[4].intVal.int,
        algorithm = parseAlgo(args[5].stringVal[]),
        issuer = args[1].stringVal[],
        accountName = args[2].stringVal[])))

  script.addProc(module, "totpNow", @[paramDef("h", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(padCode(getTotp(args[0]).now(), getTotp(args[0]).digits.int)))

  script.addProc(module, "totpAt", @[paramDef("h", ttyPointer),
      paramDef("timestamp", ttyInt)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(padCode(getTotp(args[0]).at(args[1].intVal.int),
        getTotp(args[0]).digits.int)))

  script.addProc(module, "totpVerify", @[paramDef("h", ttyPointer),
      paramDef("code", ttyString),
      paramDef("timestamp", ttyInt, initValue(0'i64)),
      paramDef("window", ttyInt, initValue(1'i64))], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(getTotp(args[0]).verify(parseInt(args[1].stringVal[]),
        args[2].intVal.int, args[3].intVal.int)))

  script.addProc(module, "totpUri", @[paramDef("h", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(getTotp(args[0]).provisioningUri()))

  script.addProc(module, "totpQrSvg", @[paramDef("h", ttyPointer),
      paramDef("scale", ttyInt, initValue(8'i64)),
      paramDef("border", ttyInt, initValue(4'i64))], ttyString,
    proc (args: StackView, argc: int): Value =
      let uri: AuthURI = getTotp(args[0]).provisioningUri()
      result = initValue(uri.getQr(scale = args[1].intVal.int,
        border = args[2].intVal.int)))

  script.addProc(module, "newHotp", @[paramDef("secret", ttyString),
      paramDef("counter", ttyInt, initValue(0'i64)),
      paramDef("issuer", ttyString, initValue("")),
      paramDef("account", ttyString, initValue("")),
      paramDef("digits", ttyInt, initValue(6'i64)),
      paramDef("algo", ttyString, initValue("SHA1"))], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapHotp(initHotp(args[0].stringVal[],
        digits = args[4].intVal.int.OTPDigits,
        algorithm = parseAlgo(args[5].stringVal[]),
        issuer = args[2].stringVal[],
        accountName = args[3].stringVal[],
        counter = args[1].intVal.int)))

  script.addProc(module, "hotpAt", @[paramDef("h", ttyPointer),
      paramDef("counter", ttyInt)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(padCode(getHotp(args[0]).at(args[1].intVal.int),
        getHotp(args[0]).digits.int)))

  script.addProc(module, "hotpNext", @[paramDef("h", ttyPointer)], ttyString,
    proc (args: StackView, argc: int): Value =
      let d = getHotp(args[0]).digits.int
      result = initValue(padCode(getHotp(args[0]).next(), d)))

  script.addProc(module, "hotpVerify", @[paramDef("h", ttyPointer),
      paramDef("code", ttyString),
      paramDef("counter", ttyInt, initValue(0'i64))], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(getHotp(args[0]).verify(parseInt(args[1].stringVal[]),
        args[2].intVal.int)))

  script.addProc(module, "hotpUri", @[paramDef("h", ttyPointer),
      paramDef("counter", ttyInt, initValue(0'i64))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(getHotp(args[0]).provisioningUri(args[1].intVal.int)))

  script.addProc(module, "genTotpUri", @[paramDef("secret", ttyString),
      paramDef("label", ttyString),
      paramDef("issuer", ttyString, initValue(""))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(genTotpUri(args[0].stringVal[], args[1].stringVal[],
        args[2].stringVal[])))

  script.addProc(module, "genHotpUri", @[paramDef("secret", ttyString),
      paramDef("label", ttyString),
      paramDef("issuer", ttyString, initValue(""))], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(genHotpUri(args[0].stringVal[], args[1].stringVal[],
        args[2].stringVal[])))
