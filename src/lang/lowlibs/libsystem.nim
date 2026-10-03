# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/[json, os, options, osproc, strutils, envvars, tables]
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, value, vm]
import pkg/vancode/interpreter/stdlib/[syslib, utils]
import ../parser
import ../sysinfo as sys

import pkg/openparser/json

proc compileCode*(script: Script, module: Module, code: string) =
  ## Parse and compile inline dfkup source into the given script and module.
  var astProgram: Ast
  try:
    parseScript(astProgram, code)
  except DfkupParserError:
    return
  var gen = initCodeGen(script, module, script.mainChunk)
  gen.genScript(astProgram, none(string), emitHalt = false)

const InlineCode* = """
iterator range*(min: int, max: int): int =
  var i = min
  if i >= max:
    yield min
  else:
    while i <= max:
      yield i
      i = i + 1

iterator items*(data: json): json =
  var i = 0
  let total = len(data)
  while i < total:
    yield data[i]
    i = i + 1

iterator items*(data: array[string]): string =
  var i = 0
  let total = len(data)
  while i < total:
    yield data[i]
    i = i + 1

iterator items*(data: array[int]): int =
  var i = 0
  let total = len(data)
  while i < total:
    yield data[i]
    i = i + 1

iterator items*(data: array[float]): float =
  var i = 0
  let total = len(data)
  while i < total:
    yield data[i]
    i = i + 1

iterator items*(data: array[bool]): bool =
  var i = 0
  let total = len(data)
  while i < total:
    yield data[i]
    i = i + 1
"""

proc initSystem*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  # `$expr` renders any value as a string.
  script.addProc(module, "toStr", @[paramDef("v", ttyAny)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue($args[0]))

  script.addProc(module, "echo", @[paramDef("x", ttyString)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      if likely(args[0].typeId == tyString):
        echo args[0].stringVal[]
      else:
        echo "<nil>"
    )

  script.addProc(module, "echo", @[paramDef("x", ttyInt)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      echo args[0].intVal)

  script.addProc(module, "echo", @[paramDef("x", ttyFloat)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      echo args[0].floatVal)

  script.addProc(module, "echo", @[paramDef("x", ttyBool)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      echo args[0].boolVal)

  script.addProc(module, "echo", @[paramDef("x", ttyNil)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      echo "nil")

  script.addProc(module, "echo", @[paramDef("x", ttyJson)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      let j = args[0].jsonVal
      if j.kind == JString:
        echo j.getStr()
      else:
        echo $j)

  script.addProc(module, "echo", @[paramDef("x", ttyPointer)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      echo $args[0])

  script.addProc(module, "echo", @[paramDef("x", ttyArray)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      var vs = newSeq[Value](args[0].objectVal.fields.len)
      for i, f in args[0].objectVal.fields: vs[i] = f.toValue
      echo toJson(vs)
  )

  script.addProc(module, "echo", @[paramDef("x", ttyObject)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      echo toJsonStr(args[0])
      # var obj = newJObject()
      # for i, f in args[0].objectVal.fields: echo f
  )

  script.addProc(module, "assert", @[paramDef("x", ttyBool)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      if not args[0].boolVal:
        raise newException(ValueError, "assertion failed"))

  script.addProc(module, "&", @[paramDef("a", ttyString), paramDef("b", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[] & args[1].stringVal[]))

  #
  # File operations
  #
  script.addProc(module, "fileExists", @[paramDef("path", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(os.fileExists(args[0].stringVal[])))

  script.addProc(module, "dirExists", @[paramDef("path", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(os.dirExists(args[0].stringVal[])))

  script.addProc(module, "readFile", @[paramDef("path", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(readFile(args[0].stringVal[])))

  script.addProc(module, "writeFile", @[paramDef("path", ttyString), paramDef("content", ttyString)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      writeFile(args[0].stringVal[], args[1].stringVal[]))

  script.addProc(module, "copyFile", @[paramDef("src", ttyString), paramDef("dest", ttyString)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      os.copyFile(args[0].stringVal[], args[1].stringVal[]))

  script.addProc(module, "moveFile", @[paramDef("src", ttyString), paramDef("dest", ttyString)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      os.moveFile(args[0].stringVal[], args[1].stringVal[]))

  script.addProc(module, "removeFile", @[paramDef("path", ttyString)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      os.removeFile(args[0].stringVal[]))

  script.addProc(module, "createDir", @[paramDef("path", ttyString)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      os.createDir(args[0].stringVal[]))

  script.addProc(module, "removeDir", @[paramDef("path", ttyString)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      os.removeDir(args[0].stringVal[]))

  #
  # Directory listing
  #
  script.addProc(module, "listDir", @[paramDef("path", ttyString)], ttyJson,
    proc (args: StackView, argc: int): Value =
      var arr = newJArray()
      for kind, name in os.walkDir(args[0].stringVal[]):
        var entry = newJObject()
        entry["kind"] = %($kind)
        entry["name"] = %name
        arr.add(entry)
      result = initValue(arr))

  let arrStrTy = module.sym("array").clone
  arrStrTy.arrayTy = module.sym("string")

  script.addProc(module, "ls", @[paramDef("path", ttyString)], ttyArray,
    proc (args: StackView, argc: int): Value =
      var names: seq[string]
      for kind, name in os.walkDir(args[0].stringVal[]):
        names.add(name)
      result = initArray(names.len)
      for i, n in names:
        result.objectVal.fields[i] = initValue(n).toStorage
    , returnTySym = arrStrTy)

  #
  # Short utility aliases
  #
  script.addProc(module, "cd", @[paramDef("path", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      try:
        os.setCurrentDir(args[0].stringVal[])
        result = initValue(true)
      except:
        result = initValue(false))

  script.addProc(module, "cp", @[paramDef("src", ttyString), paramDef("dest", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      try:
        os.copyFile(args[0].stringVal[], args[1].stringVal[])
        result = initValue(true)
      except:
        result = initValue(false))

  script.addProc(module, "mv", @[paramDef("src", ttyString), paramDef("dest", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      try:
        os.moveFile(args[0].stringVal[], args[1].stringVal[])
        result = initValue(true)
      except:
        result = initValue(false))

  script.addProc(module, "rm", @[paramDef("path", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      try:
        os.removeFile(args[0].stringVal[])
        result = initValue(true)
      except:
        try:
          os.removeDir(args[0].stringVal[])
          result = initValue(true)
        except:
          result = initValue(false))

  script.addProc(module, "findExe", @[paramDef("exe", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(os.findExe(args[0].stringVal[])))

  script.addProc(module, "pwd", @[], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(os.getCurrentDir()))

  script.addProc(module, "putEnv", @[paramDef("key", ttyString), paramDef("val", ttyString)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      envvars.putEnv(args[0].stringVal[], args[1].stringVal[]))

  script.addProc(module, "delEnv", @[paramDef("key", ttyString)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      envvars.delEnv(args[0].stringVal[]))

  #
  # Path operations
  #
  script.addProc(module, "getCurrentDir", @[], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(os.getCurrentDir()))

  script.addProc(module, "setCurrentDir", @[paramDef("path", ttyString)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      os.setCurrentDir(args[0].stringVal[]))

  script.addProc(module, "joinPath", @[paramDef("a", ttyString), paramDef("b", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(os.joinPath(args[0].stringVal[], args[1].stringVal[])))

  script.addProc(module, "parentDir", @[paramDef("path", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(os.parentDir(args[0].stringVal[])))

  script.addProc(module, "expandFilename", @[paramDef("path", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(os.expandFilename(args[0].stringVal[])))

  script.addProc(module, "absolutePath", @[paramDef("path", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(os.absolutePath(args[0].stringVal[])))

  #
  # Environment
  #
  script.addProc(module, "getEnv", @[paramDef("key", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(os.getEnv(args[0].stringVal[])))

  script.addProc(module, "existsEnv", @[paramDef("key", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(os.existsEnv(args[0].stringVal[])))

  script.addProc(module, "getAppDir", @[], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(os.getAppDir()))

  script.addProc(module, "getAppFilename", @[], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(os.getAppFilename()))

  #
  # System
  #
  script.addProc(module, "sleep", @[paramDef("milliseconds", ttyInt)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      os.sleep(args[0].intVal.int))

  script.addProc(module, "getCurrentProcessId", @[], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(os.getCurrentProcessId().int64))

  #
  # System information
  #
  # The return type is a real object symbol carrying `objectFields`, not the
  # builtin `object`. dfkup is built without `vancodeGradualTypes`, so type
  # checking is strict: a foreign proc returning the builtin `object` resolves
  # to a type with no declared fields, and `info.cpuCores` would then be
  # rejected as a non-existent field at compile time. Declaring the fields the
  # way `genObject` does is what makes dot access resolve to an `opcGetF`
  # index. The field order here is the runtime layout.
  #
  let sysInfoFields: array[6, string] = ["osName", "arch", "cpuCores",
      "cpuEndian", "totalMemory", "executablePath"]
  let
    stringTy = module.sym("string")
    intTy = module.sym("int")
    sysInfoTy = newType(ttyObject, ast.newIdent("SystemInfo"))
  sysInfoTy.objectId = globalTypeCounter
  inc(globalTypeCounter)
  for i, fieldName in sysInfoFields:
    sysInfoTy.objectFields[fieldName] = (
      id: i,
      name: ast.newIdent(fieldName),
      ty: if fieldName in ["cpuCores", "totalMemory"]: intTy else: stringTy,
      implVal: nil
    )
  discard module.add(sysInfoTy, ast.newIdent("SystemInfo"))

  script.addProc(module, "getSystemInfo", @[], ttyObject,
    proc (args: StackView, argc: int): Value =
      let info = sys.collectSystemInfo()
      result = initObject(tyObjectStorage, sysInfoFields.len)
      for i, fieldName in sysInfoFields:
        result.objectVal.keys.add(fieldName)
      result.objectVal.fields[0] = initValue(info.osName).toStorage
      result.objectVal.fields[1] = initValue(info.arch).toStorage
      result.objectVal.fields[2] = initValue(info.cpuCores.int64).toStorage
      result.objectVal.fields[3] = initValue(info.cpuEndian).toStorage
      result.objectVal.fields[4] = initValue(info.totalMemory).toStorage
      result.objectVal.fields[5] = initValue(info.executablePath).toStorage
    , returnTySym = sysInfoTy)

  #
  # File info
  #
  script.addProc(module, "getFileSize", @[paramDef("path", ttyString)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(os.getFileSize(args[0].stringVal[]).int64))

  #
  # Shell execution
  #
  script.addProc(module, "exec", @[paramDef("cmd", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      result = initValue(osproc.execCmd(args[0].stringVal[]) == 0))

  script.addProc(module, "execOut", @[paramDef("cmd", ttyString)], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(osproc.execCmdEx(args[0].stringVal[]).output))

  # `execShell` hands the command to the system shell, so `&&`, pipes and
  # `$VAR` all work, unlike `exec` which execs directly. That means the command
  # is shell-interpreted and must come from a trusted source, not user input.
  #
  # This deliberately runs through `startProcess` rather than `execCmdEx`:
  # `execCmdEx` reads the child's output, which is incompatible with
  # `poParentStreams`, and a build command's output belongs on the terminal
  # anyway. `execShellOut` below is the capturing counterpart.
  script.addProc(module, "execShell", @[paramDef("cmd", ttyString)], ttyBool,
    proc (args: StackView, argc: int): Value =
      var process = osproc.startProcess(args[0].stringVal[],
        options = {poEvalCommand, poUsePath, poParentStreams})
      defer: close(process)
      result = initValue(process.waitForExit() == 0))

  # The output-capturing counterpart, so a build script can both report what a
  # command printed and branch on whether it succeeded. `execCmdEx` already
  # merges stderr into stdout by default, which is what you want here.
  script.addProc(module, "execShellOut", @[paramDef("cmd", ttyString)], ttyJson,
    proc (args: StackView, argc: int): Value =
      let p = osproc.execCmdEx(args[0].stringVal[],
        options = {poEvalCommand, poUsePath})
      var j = newJObject()
      j["output"] = %p.output
      j["exitCode"] = %p.exitCode
      result = initValue(j))

  #
  # String formatting
  #
  script.addProc(module, "fmt", @[paramDef("tmpl", ttyString), paramDef("args", ttyObject)], ttyString,
    proc (args: StackView, argc: int): Value =
      var s = args[0].stringVal[]
      let obj = args[1].objectVal
      for i, key in obj.keys:
        let valRep =
          case obj.fields[i].typeId
          of tyString: obj.fields[i].refVal.stringVal[]
          of tyInt: $obj.fields[i].intVal
          of tyFloat: $obj.fields[i].floatVal
          of tyBool: $obj.fields[i].boolVal
          else: "nil"
        s = s.replace("{" & key & "}", valRep)
      result = initValue(s))

  #
  # Stdin / pipe support
  #
  script.addProc(module, "readStdin", @[], ttyString,
    proc (args: StackView, argc: int): Value =
      result = initValue(stdin.readAll()))

  script.addProc(module, "readStdinLines", @[], ttyJson,
    proc (args: StackView, argc: int): Value =
      var lines = newJArray()
      for line in stdin.lines:
        lines.add(newJString(line))
      result = initValue(lines))

  #
  # Built-in functions needed by iterators
  #
  script.addProc(module, "inc", @[paramDef("x", ttyInt)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].intVal + 1))

  script.addProc(module, "len", @[paramDef("data", ttyJson)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].jsonVal.elems.len.int64))

  script.addProc(module, "len", @[paramDef("data", ttyString)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue(args[0].stringVal[].len.int64))

  script.addProc(module, "high", @[paramDef("data", ttyJson)], ttyInt,
    proc (args: StackView, argc: int): Value =
      result = initValue((args[0].jsonVal.elems.len - 1).int64))

  #
  # len for array types (needed by inline iterators)
  #
  block:
    let arrTy = module.sym("array")
    let intTy = module.sym("int")
    var nodeParams: seq[ProcParam]
    nodeParams.add((ast.newIdent("data"), arrTy, nil, false, false))
    let (lenSym, lenProc) = script.newProc(
      ast.newIdent("len"), impl = nil, nodeParams,
      intTy, pkForeign, exported = true)
    lenProc.foreign = proc (args: StackView, argc: int): Value =
      result = initValue(args[0].objectVal.fields.len.int64)
    discard module.addCallable(lenSym, lenSym.name)
    script.procs.add(lenProc)

  block:
    let arrTy = module.sym("array")
    let intTy = module.sym("int")
    var nodeParams: seq[ProcParam]
    nodeParams.add((ast.newIdent("data"), arrTy, nil, false, false))
    let (highSym, highProc) = script.newProc(
      ast.newIdent("high"), impl = nil, nodeParams,
      intTy, pkForeign, exported = true)
    highProc.foreign = proc (args: StackView, argc: int): Value =
      result = initValue((args[0].objectVal.fields.len - 1).int64)
    discard module.addCallable(highSym, highSym.name)
    script.procs.add(highProc)

  #
  # Coroutine builtins
  #
  script.addProc(module, "createCoro", @[paramDef("proc", ttyProc)], ttyCoroutine,
    proc (args: StackView, argc: int): Value =
      raise newException(ValueError, "createCoro must be used as a compiler intrinsic"))
  script.addProc(module, "dispatch", @[paramDef("proc", ttyProc),
      paramDef("args", ttyAny)], ttyCoroutine,
    proc (args: StackView, argc: int): Value =
      raise newException(ValueError, "dispatch must be used as a compiler intrinsic"))
  script.addProc(module, "resume", @[paramDef("coro", ttyCoroutine), paramDef("args", ttyAny)], ttyAny,
    proc (args: StackView, argc: int): Value =
      raise newException(ValueError, "resume must be used as a compiler intrinsic"))
  script.addProc(module, "status", @[paramDef("coro", ttyCoroutine)], ttyString,
    proc (args: StackView, argc: int): Value =
      if args[0].typeId != tyCoroutine or args[0].objectVal == nil or args[0].objectVal.foreign.data == nil:
        return initValue("invalid")
      let coro = cast[Coroutine](args[0].objectVal.foreign.data)
      result = initValue($coro.state))

  #
  # Compile inline iterators
  #
  compileCode(script, module, InlineCode)
