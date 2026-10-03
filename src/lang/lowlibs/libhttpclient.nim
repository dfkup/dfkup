# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

## `std/httpclient` exposes powpow's blocking HTTP/1.1 client.
##
## powpow's `HttpClient` owns a private event loop and returns the response
## directly, which is exactly what the synchronous VM wants. The async
## `AsyncHttpClient` is deliberately not bound: an await-able Nim future
## cannot be driven from a foreign VM thread without the coroutine plumbing
## `std/llm` does.
##
##   ```nim
##   import "std/httpclient"
##
##   let client = newClient()
##   let res = httpGet(client, "http://example.com")
##   echo statusCode(res), " ", body(res)
##   closeClient(client)
##   ```
##
## Known limitation: https does not work against public servers yet. The TLS
## context is created correctly, but powpow's handshake stalls or drops
## against real endpoints (its own tests only cover a powpow TLS server, which
## passes). Plain HTTP, Unix-socket requests and the keep-alive pool are all
## fine, so `tls: true` is plumbed through and left off by default.
##
## Keep-alive connections are pooled per origin by default. Because a pooled
## response is only valid until the next request reuses its connection,
## read `body`/`headers` before issuing another request on the same client.

import std/[json, strutils, tables]
import std/httpcore except HttpMethod  # powpow owns the extensible HttpMethod
import pkg/powpow/proto/httpclient
import pkg/powpow/net/tls
import pkg/powpow/types
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

type
  HttpClientBindError* = object of ValueError

  DfkupHttpClient = ref object
    inner: HttpClient

  DfkupHttpResponse = ref object
    inner: HttpClientResponse

#
# Option reading
#

proc optArg(args: StackView, argc: int, i: int): JsonNode =
  ## Read an optional options argument. An omitted one arrives as a json null,
  ## so anything that is not an object means "no options".
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

proc parseMethod(raw: string): HttpMethod =
  ## Map a dfkup method name onto powpow's `HttpMethod`. The enum is extensible
  ## via pkg/voodoo, so accept the wire token too.
  case raw.toUpperAscii
  of "GET": HttpGet
  of "POST": HttpPost
  of "PUT": HttpPut
  of "DELETE": HttpDelete
  of "HEAD": HttpHead
  of "PATCH": HttpPatch
  of "OPTIONS": HttpOptions
  of "TRACE": HttpTrace
  of "CONNECT": HttpConnect
  else:
    raise newException(HttpClientBindError, "unsupported HTTP method: " & raw)

#
# Argument helpers
#

proc titleCaseHeader(key: string): string =
  ## Render a lower-cased httpcore header key as `Title-Case`, so `etag`
  ## becomes `Etag` and `x-test` becomes `X-Test`.
  result = newString(key.len)
  for i, c in key:
    result[i] = if i == 0 or key[i - 1] == '-': c.toUpperAscii else: c

proc argStr(args: StackView, i: int): string =
  ## A string argument that may be omitted or nil.
  if args[i].typeId == tyString: args[i].stringVal[] else: ""

proc splitBodyOpts(args: StackView, argc: int, bodyIdx, optsIdx: int):
    tuple[body: string, opts: JsonNode] =
  ## dfkup has no named arguments, so a call like `httpPost(client, url, o)`
  ## cannot say whether the third argument is a body or an options object.
  ## Accept either: a string is the request body, a json object is read as
  ## options (whose `body` key, if present, is the request body).
  if bodyIdx < argc and args[bodyIdx].typeId == tyJsonStorage and
     args[bodyIdx].jsonVal != nil:
    return (optStr(args[bodyIdx].jsonVal, "body", ""),
            if args[bodyIdx].jsonVal.kind == JObject: args[bodyIdx].jsonVal
            else: newJObject())
  (argStr(args, bodyIdx), optArg(args, argc, optsIdx))

proc optObj(o: JsonNode, key: string): JsonNode =
  ## Read a nested json object, defaulting to an empty one when the key is
  ## absent or is not an object. Direct indexing would raise a KeyError.
  if o != nil and o.kind == JObject and o.hasKey(key) and
     o[key].kind == JObject:
    return o[key]
  newJObject()

proc readHeaders(o: JsonNode): seq[(string, string)] =
  ## Headers arrive as a json object of string -> string. A repeated key is
  ## passed through as written; powpow writes each pair verbatim.
  if o == nil or o.kind != JObject:
    return @[]
  for key, val in o.pairs:
    result.add((key, (if val.isNil: "" else: val.getStr())))

proc clientAt(args: StackView, i: int): DfkupHttpClient =
  result = cast[DfkupHttpClient](args[i].objectVal.foreign.data)
  if result == nil:
    raise newException(HttpClientBindError, "client is not valid")

proc responseAt(args: StackView, i: int): DfkupHttpResponse =
  result = cast[DfkupHttpResponse](args[i].objectVal.foreign.data)
  if result == nil:
    raise newException(HttpClientBindError, "response is not valid")

#
# Foreign value construction
#

proc clientValue(c: DfkupHttpClient): Value =
  GC_ref(c)
  result = Value(typeId: tyPointer)
  result.objectVal = Object(isForeign: true,
    foreign: ForeignData(data: cast[pointer](c), tag: "HttpClient",
      destructor: proc (data: pointer) {.nimcall.} =
        let box = cast[DfkupHttpClient](data)
        if box.inner != nil:
          box.inner.close()
        GC_unref(box)))

proc responseValue(r: DfkupHttpResponse): Value =
  GC_ref(r)
  result = Value(typeId: tyPointer)
  result.objectVal = Object(isForeign: true,
    foreign: ForeignData(data: cast[pointer](r), tag: "HttpResponse",
      destructor: proc (data: pointer) {.nimcall.} =
        GC_unref(cast[DfkupHttpResponse](data))))

proc initHttpClient*(script: Script, module: Module) =
  discard module.genPtr(tyPointer, "HttpClient")
  discard module.genPtr(tyPointer, "HttpResponse")

  #
  # Clients
  #

  script.addProc(module, "newTlsContext",
    params = @[paramDef("verifyPeer", ttyBool, initValue(true))],
    returnTy = ttyPointer,
    impl = proc (args: StackView, argc: int): Value =
      GC_ref(newClientTlsContext(verifyPeer = optBool(
        optArg(args, argc, 0), "verifyPeer", true))))

  script.addProc(module, "newClient",
    params = @[paramDef("opts", ttyJson, initValue(newJObject()))],
    returnTy = ttyPointer,
    impl = proc (args: StackView, argc: int): Value =
      let o = optArg(args, argc, 0)
      let tlsCtx =
        if o.hasKey("tls"): newClientTlsContext(verifyPeer =
            optBool(o, "verifyPeer", true))
        else: nil
      let inner = newHttpClient(
        tlsCtx = tlsCtx,
        keepAlive = optBool(o, "keepAlive", true),
        timeoutMs = optInt(o, "timeoutMs", 0),
        maxBodySize = optInt(o, "maxBodySize", DefaultMaxResponseBody),
        maxIdlePerHost = optInt(o, "maxIdlePerHost", DefaultMaxIdlePerHost),
        maxIdleTotal = optInt(o, "maxIdleTotal", DefaultMaxIdleTotal),
        idleTimeoutMs = optInt(o, "idleTimeoutMs", DefaultIdleTimeoutMs))
      result = clientValue(DfkupHttpClient(inner: inner)))

  script.addProc(module, "closeClient",
    params = @[paramDef("client", ttyPointer)], returnTy = ttyVoid,
    impl = proc (args: StackView, argc: int): Value =
      let c = clientAt(args, 0)
      if c.inner != nil:
        c.inner.close()
        c.inner = nil)

  script.addProc(module, "idleConnections",
    params = @[paramDef("client", ttyPointer)], returnTy = ttyInt,
    impl = proc (args: StackView, argc: int): Value =
      let c = clientAt(args, 0)
      result = initValue(if c.inner != nil: c.inner.idleConnections().int64
        else: 0))

  #
  # Requests
  #

  # The verbs are prefixed: `get`, `delete` and `status` already exist in
  # libjson/libstrings/libsystem, and since every stdlib module shares one
  # namespace an unprefixed `get(client, url)` would resolve to json's `get`.
  script.addProc(module, "httpRequest",
    params = @[paramDef("client", ttyPointer), paramDef("method", ttyString),
               paramDef("url", ttyString),
               paramDef("body", ttyAny, initValue("")),
               paramDef("opts", ttyJson, initValue(newJObject()))],
    returnTy = ttyPointer,
    impl = proc (args: StackView, argc: int): Value =
      let c = clientAt(args, 0)
      if c.inner == nil:
        raise newException(HttpClientBindError, "client is closed")
      let split = splitBodyOpts(args, argc, 3, 4)
      let o = split.opts
      try:
        let res = c.inner.request(parseMethod(argStr(args, 1)),
          argStr(args, 2), split.body,
          readHeaders(o.optObj("headers")),
          unixSocket = optStr(o, "unixSocket", ""),
          timeoutMs = optInt(o, "timeoutMs", -1))
        result = responseValue(DfkupHttpResponse(inner: res))
      except HttpError as e:
        raise newException(HttpClientBindError, e.msg))

  template verb(name: string, meth: HttpMethod) =
    script.addProc(module, name,
      params = @[paramDef("client", ttyPointer), paramDef("url", ttyString),
                 paramDef("body", ttyAny, initValue("")),
                 paramDef("opts", ttyJson, initValue(newJObject()))],
      returnTy = ttyPointer,
      impl = proc (args: StackView, argc: int): Value =
        let c = clientAt(args, 0)
        if c.inner == nil:
          raise newException(HttpClientBindError, "client is closed")
        let split = splitBodyOpts(args, argc, 2, 3)
        let o = split.opts
        try:
          let res = c.inner.request(meth, argStr(args, 1), split.body,
            readHeaders(o.optObj("headers")),
            unixSocket = optStr(o, "unixSocket", ""),
            timeoutMs = optInt(o, "timeoutMs", -1))
          result = responseValue(DfkupHttpResponse(inner: res))
        except HttpError as e:
          raise newException(HttpClientBindError, e.msg))

  verb("httpGet", HttpGet)
  verb("httpPost", HttpPost)
  verb("httpPut", HttpPut)
  verb("httpDelete", HttpDelete)
  verb("httpHead", HttpHead)
  verb("httpPatch", HttpPatch)
  verb("httpOptions", HttpOptions)

  #
  # Responses
  #
  # A pooled response is only valid until the next request on its client
  # reuses the connection, so read what you need before issuing another one.
  #

  # `statusCode`, not `status`: libsystem already exports `status` for
  # coroutine state, so an unprefixed `status` here would resolve to that and
  # report "invalid" for every response.
  script.addProc(module, "statusCode",
    params = @[paramDef("res", ttyPointer)], returnTy = ttyInt,
    impl = proc (args: StackView, argc: int): Value =
      result = initValue(responseAt(args, 0).inner.getStatusCode().int.int64))

  script.addProc(module, "statusText",
    params = @[paramDef("res", ttyPointer)], returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      result = initValue($responseAt(args, 0).inner.getStatusText()))

  script.addProc(module, "isOk",
    params = @[paramDef("res", ttyPointer)], returnTy = ttyBool,
    impl = proc (args: StackView, argc: int): Value =
      result = initValue(responseAt(args, 0).inner.isOk()))

  script.addProc(module, "body",
    params = @[paramDef("res", ttyPointer)], returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      result = initValue(responseAt(args, 0).inner.getBodyString()))

  # httpcore's HttpHeaders lower-cases every key, so the raw map is keyed
  # "x-test"/"content-type". Expose the conventional Title-Case spelling
  # instead: it is what a script author expects to index, and header names are
  # case-insensitive on the wire anyway.
  script.addProc(module, "headers",
    params = @[paramDef("res", ttyPointer)], returnTy = ttyJson,
    impl = proc (args: StackView, argc: int): Value =
      var obj = newJObject()
      for key, val in responseAt(args, 0).inner.getHeaders().pairs:
        obj[titleCaseHeader(key)] = %val
      result = initValue(obj))

  script.addProc(module, "header",
    params = @[paramDef("res", ttyPointer), paramDef("name", ttyString)],
    returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      let h = responseAt(args, 0).inner.getHeaders()
      let name = argStr(args, 1)
      # Header names are case-insensitive, so fall back to a scan when the
      # server used a different capitalization than the caller asked for.
      if h.hasKey(name):
        return initValue(h[name])
      for key, val in h.pairs:
        if key.toLowerAscii == name.toLowerAscii:
          return initValue(val)
      result = initValue(""))

  script.addProc(module, "contentLength",
    params = @[paramDef("res", ttyPointer)], returnTy = ttyInt,
    impl = proc (args: StackView, argc: int): Value =
      result = initValue(responseAt(args, 0).inner.getContentLength().int64))
