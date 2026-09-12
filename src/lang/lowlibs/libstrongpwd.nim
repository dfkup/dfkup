# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/[json]
import pkg/blackpaper
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

type
  PwdDictBox = ref object
    dict: PasswordStrengthDictionary

proc resultToJson(r: PasswordStrengthResult): JsonNode =
  result = newJObject()
  result["strength"] = %($r.strength)
  result["score"] = %(r.score)
  result["reason"] = %($r.reason)

proc wrapDict(d: PasswordStrengthDictionary): Value =
  result = initValue(tyPointer, PwdDictBox(dict: d))
  result.objectVal.foreign.tag = "PwdDict"

proc getDict(v: Value): PasswordStrengthDictionary =
  cast[PwdDictBox](v.objectVal.foreign.data).dict

proc seqFromJson(n: JsonNode): seq[string] =
  result = @[]
  if n != nil and n.kind == JArray:
    for item in n:
      result.add(item.getStr())

proc initStrongpwd*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  script.addProc(module, "checkPassword", @[paramDef("pw", ttyString)], ttyJson,
    proc (args: StackView, argc: int): Value =
      result = initValue(resultToJson(passwordStrength(args[0].stringVal[]))))

  script.addProc(module, "checkPasswordWithWords", @[paramDef("pw", ttyString),
      paramDef("words", ttyJson)], ttyJson,
    proc (args: StackView, argc: int): Value =
      let words = seqFromJson(args[1].jsonVal)
      result = initValue(resultToJson(passwordStrength(args[0].stringVal[], words))))

  script.addProc(module, "newPwdDict", @[paramDef("words", ttyJson)], ttyPointer,
    proc (args: StackView, argc: int): Value =
      result = wrapDict(preparePasswordStrengthDictionary(seqFromJson(args[0].jsonVal))))

  script.addProc(module, "pwdDictAdd", @[paramDef("dict", ttyPointer),
      paramDef("words", ttyJson)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      getDict(args[0]).addToDictionary(seqFromJson(args[1].jsonVal)))

  script.addProc(module, "checkPasswordWithDict", @[paramDef("pw", ttyString),
      paramDef("dict", ttyPointer)], ttyJson,
    proc (args: StackView, argc: int): Value =
      result = initValue(resultToJson(passwordStrength(args[0].stringVal[], getDict(args[1])))))

  script.addProc(module, "pwdStrength", @[paramDef("pw", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue($passwordStrength(args[0].stringVal[]).strength))

  script.addProc(module, "pwdScore", @[paramDef("pw", ttyString)], ttyFloat,
    proc (args: StackView, argc: int): Value =
      result = initValue(passwordStrength(args[0].stringVal[]).score.float64))
