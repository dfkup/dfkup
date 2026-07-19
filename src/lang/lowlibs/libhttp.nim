# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/[net, httpcore]
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]
import pkg/supranim/network/backends/webserver_powpow

type
  DfkupWebServer = ref object
    inner: WebServer
    callback: Value

proc callCallback*(procScript: cstring, procId: int32,
                   flatArgs: ptr int64, argc: int32,
                   argTypes: ptr int32): int64 {.cdecl, importc.}

proc execCallback*(procScript: cstring, procId: int32,
                   flatArgs: ptr int64, argc: int32,
                   argTypes: ptr int32): int64 {.cdecl, importc.}

proc initHttp*(script: Script, module: Module) =
  module.initSystemTypes()
  discard module.genPtr(tyPointer, "WebServer")
  discard module.genPtr(tyPointer, "Request")
  let ptrTy = module.sym"WebServer"

  script.addProc(module, "newWebServer", returnTy = ttyPointer,
    returnTySym = ptrTy,
    impl = proc (args: StackView, argc: int): Value =
      let server = DfkupWebServer(
        inner: newWebServer(Port(8000)))
      GC_ref(server)
      result = Value(typeId: tyPointer)
      result.objectVal = Object(isForeign: true,
        foreign: ForeignData(data: cast[pointer](server),
          destructor: proc (data: pointer) {.nimcall.} =
            GC_unref(cast[DfkupWebServer](data)))))

  script.addProc(module, "listen",
    params = @[paramDef("server", ttyPointer), paramDef("port", ttyInt), paramDef("callback", ttyProc)],
    returnTy = ttyVoid, impl =
    proc (args: StackView, argc: int): Value =
      let s = cast[DfkupWebServer](args[0].objectVal.foreign.data)
      let port = Port(args[1].intVal.int)
      s.inner.port = port
      s.callback = args[2]
      let cb = s.callback
      s.inner.start(
        # dfkup is compiling with `-d:supranimUseGlobalOnRequest`
        # to allow using the onRequest callback as a closure
        proc(req: var Request) {.gcsafe.} =
          {.gcsafe.}:
            var body: string
            if cb.typeId != tyNil:
              let path = req.path
              let meth = $req.httpMethod
              var flatArgs: array[2, int64]
              var argTypes: array[2, int32]
              var bridgeBuf: array[2, Value]
              bridgeBuf[0] = initValue(path)
              flatArgs[0] = cast[int64](bridgeBuf[0])
              argTypes[0] = tyString.int32
              bridgeBuf[1] = initValue(meth)
              flatArgs[1] = cast[int64](bridgeBuf[1])
              argTypes[1] = tyString.int32
              let raw = execCallback(cstring(cb.procVal.procScript),
                cb.procVal.procId.int32, addr flatArgs[0], 2, addr argTypes[0])
              let rv = cast[Value](raw)
              if rv != nil and rv.typeId == tyString:
                body = rv.stringVal[]
            req.send(Http200, body,
              newHttpHeaders([("Content-Type", "text/plain")]))))

  script.addProc(module, "echo",
    params = @[paramDef("x", ttyPointer)],
    returnTy = ttyVoid, impl =
    proc (args: StackView, argc: int): Value =
      echo $args[0])
