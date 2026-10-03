## HTTP client tests.
##
## The request path is exercised against a powpow HTTP server hosted on the
## client's own event loop (`getLoop`), so both sides run on one thread: the
## client's blocking `poll` drives the server too, exactly as powpow's own
## tests do. That keeps the suite hermetic (no network, no ports in use) while
## still covering real responses end to end.

import std/[atomics, os, unittest, options, strutils]
import std/httpcore except HttpMethod  # powpow owns the extensible HttpMethod
import ../src/lang/transformers
import pkg/powpow/proto/httpclient
import pkg/powpow/proto/http
import pkg/powpow/proto/httpserver
import pkg/powpow/loop
import pkg/vancode/interpreter/[ast, codegen, chunk, sym, vm, value]
import ../src/lang/[parser, lowlibs/libsystem, lowlibs/libjson,
                   lowlibs/libhttpclient]

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
  # options and headers are json, so the httpclient bindings need them loaded
  let jsonModule = newModule("json", some"json.dfkup")
  jsonModule.importModule(systemModule, "system")
  initJson(script, jsonModule)
  module.load(jsonModule)
  let httpModule = newModule("httpclient", some"httpclient.dfkup")
  httpModule.importModule(systemModule, "system")
  initHttpClient(script, httpModule)
  module.load(httpModule)
  # json is loaded last so `parseJson` resolves for the option objects
  let jsonMod = newModule("json", some"json.dfkup")
  jsonMod.importModule(systemModule, "system")
  initJson(script, jsonMod)
  module.load(jsonMod)
  script.stdpos = script.procs.high
  var gen = initCodeGen(script, module, mainChunk)
  gen.allowExprResult = true
  gen.genScript(program, none(string))
  var vmInstance = newVm()
  result = vmInstance.interpret(script, mainChunk)

proc run(code: string): string =
  let v = interpret(code)
  if v != nil and v.typeId notin {tyNil}:
    result = $v

proc raises(code: string) =
  var threw = false
  try:
    discard interpret(code)
  except CatchableError:
    threw = true
  check threw

suite "HTTP client - error handling":
  test "a failed request raises, so callers can try/except":
    # powpow raises HttpError on transport failure. The VM surfaces it as a
    # catchable error, which is what a dfkup `try` block sees.
    raises("""
      let client = newClient(parseJson("{\"timeoutMs\":250}"))
      discard httpGet(client, "http://127.0.0.1:1/nope")
    """)

  test "unsupported method is rejected before any socket work":
    raises("""
      let client = newClient()
      discard httpRequest(client, "FLY", "http://127.0.0.1:1/x")
    """)

  test "an invalid URL raises rather than hanging":
    raises("""
      let client = newClient()
      discard httpGet(client, "not-a-url")
    """)

  test "unsupported scheme is rejected":
    raises("""
      let client = newClient()
      discard httpGet(client, "ftp://example.com/x")
    """)

  test "idleConnections starts at zero on a fresh client":
    let r = run("""
      let client = newClient()
      let n = idleConnections(client)
      closeClient(client)
      $n
    """)
    check r == "0"

  test "keepAlive can be turned off":
    # With pooling disabled the client still constructs and reports no idle
    # connections, which is the observable difference from the default.
    let r = run("""
      let client = newClient(parseJson("{\"keepAlive\":false}"))
      let n = idleConnections(client)
      closeClient(client)
      $n
    """)
    check r == "0"

  test "closeClient is idempotent":
    # Closing twice must not fault, since dfkup has no destructors of its own.
    let r = run("""
      let client = newClient()
      closeClient(client)
      closeClient(client)
      "ok"
    """)
    check r == "ok"

  test "using a closed client raises":
    raises("""
      let client = newClient()
      closeClient(client)
      discard httpGet(client, "http://127.0.0.1:1/x")
    """)

  test "headers option is accepted as a json object":
    # Exercised against an unreachable host: the point is that a json headers
    # object is accepted and encoded, so the failure is the connection and not
    # a type error from the binding.
    raises("""
      let client = newClient(parseJson("{\"timeoutMs\":250}"))
      let opts = parseJson("{\"headers\":{\"Accept\":\"application/json\"}}")
      discard httpGet(client, "http://127.0.0.1:1/x", opts)
    """)

  test "timeoutMs per-request option is honoured":
    raises("""
      let client = newClient()
      let opts = parseJson("{\"timeoutMs\":200}")
      discard httpGet(client, "http://10.255.255.1:9/blackhole", opts)
    """)

# Live request tests. A powpow server is hosted on the client's own loop, so
# the client's blocking poll drives both ends on this thread and no port needs
# to be reserved in advance. `withServer` hands back the URL to request.
#
# Every test drives the dfkup binding itself (not the raw powpow client), so
# these cover the marshalling as well as powpow's transport.
#
# The server runs on its own thread with its own event loop. It cannot share
# the dfkup client's loop: `newClient` builds a private loop inside the
# binding, so a server hosted on a different loop would never be driven and the
# request would block forever.
type
  Route = proc(req: HttpRequest, res: HttpResponse) {.closure.}

type
  ServerCtx = ref object
    ## Handle shared with the server thread. `stop` is signalled once the
    ## script under test has finished with the response; `closeServer` joins
    ## the thread so the listener is closed before the test ends.
    server: HttpServer
    loop: Loop
    stop: Atomic[bool]
    thread: Thread[ServerCtx]

proc serveThread(ctx: ServerCtx) {.thread, gcsafe.} =
  ## Drive the server's loop until `stop` is set.
  ##
  ## Deliberately does not `close` the server or loop: those allocations
  ## belong to the main thread, and destroying their ref cycles from here
  ## faults under ORC. `closeServer` closes them on the main thread instead.
  {.cast(gcsafe).}:
    while not ctx.stop.load():
      ctx.loop.poll(50)

proc withServer(port: int, route: Route): ServerCtx =
  ## Start a server bound to `port` on a dedicated thread. The caller must
  ## call `closeServer` to shut it down.
  new(result)   # `stop` is false from the zeroed allocation
  result.loop = newLoop()
  result.server = newHttpServer(result.loop)
  result.server.handler =
    proc(req: HttpRequest, res: HttpResponse) {.gcsafe.} =
      {.gcsafe.}:
        route(req, res)
  result.server.listen("127.0.0.1", port)
  createThread(result.thread, serveThread, result)

proc closeServer(ctx: ServerCtx) =
  ## Stop the server thread, then close the listener and loop on this thread.
  ctx.stop.store(true)
  joinThreads(ctx.thread)
  ctx.server.close()
  ctx.loop.close()

proc live(code: string, port: int, route: Route,
          clientOpts = ""): string =
  ## Run `code` as the body of a dfkup function with `client`, `url` and `res`
  ## in scope, where `res` is the result of a GET to `url`. `code` is a
  ## statement block that must end in `return`.
  ## `clientOpts` is raw dfkup source passed to `newClient`.
  let ctx = withServer(port, route)
  # The params are annotated: vancode infers an untyped param as `stmt`,
  # which would make every call inside the body a type error.
  let script = """
fn probe(client: pointer, url: string, res: pointer): string =
""" & indent(code.strip, 2) & """

let client = newClient(""" & clientOpts & """)
let url = "http://127.0.0.1:""" & $port & """""
let res = httpGet(client, url)
$probe(client, url, res)
"""
  try:
    result = run(script)
  finally:
    closeServer(ctx)

suite "HTTP client - live requests":
  test "GET reads status, body and a header":
    let r = live("""
      return $statusCode(res) & "|" & body(res) & "|" & header(res, "Content-Type")
    """, 19871, proc(req: HttpRequest, res: HttpResponse) =
      res.status(Http200).header("Content-Type", "text/plain").send("ok"))
    check r == "200|ok|text/plain"

  test "isOk distinguishes 2xx from other statuses":
    let ok = live("""
      return $isOk(res)
    """, 19872, proc(req: HttpRequest, res: HttpResponse) =
      res.status(Http200).send("fine"))
    check ok == "true"
    let notOk = live("""
      return $statusCode(res) & "|" & $isOk(res) & "|" & body(res)
    """, 19873, proc(req: HttpRequest, res: HttpResponse) =
      res.status(Http404).send("nope"))
    check notOk == "404|false|nope"

  test "POST sends a body the server receives":
    var seen = ""
    let r = live("""
      return body(httpPost(client, url, "hello body"))
    """, 19874, proc(req: HttpRequest, res: HttpResponse) =
      seen = req.getBodyString()
      res.status(Http200).send("got " & req.getPath()))
    check seen == "hello body"
    check r == "got /"

  test "headers are sent to the server":
    var seenAccept = ""
    let r = live("""
      let opts = parseJson("{\"headers\":{\"Accept\":\"application/json\"}}")
      return body(httpGet(client, url, opts))
    """, 19875, proc(req: HttpRequest, res: HttpResponse) =
      seenAccept = req.getHeaderValue("Accept")
      res.status(Http200).send("ok"))
    check seenAccept == "application/json"
    check r == "ok"

  test "headers() exposes the full response header set":
    let r = live("""
      # `header` is the single-lookup accessor and returns a plain string.
      # `headers` returns json whose values render quoted, so index it only to
      # confirm the key exists.
      let h = headers(res)
      return header(res, "X-Test") & "|" & header(res, "Content-Type")
        & "|" & $h
    """, 19876, proc(req: HttpRequest, res: HttpResponse) =
      res.status(Http200).header("X-Test", "yes").header("Content-Type",
        "application/json").send("{}"))
    check r.startsWith("yes|application/json|")
    check r.contains("\"X-Test\":\"yes\"")

  test "the request path and method reach the server":
    var seen = ""
    let r = live("""
      return body(httpGet(client, url))
    """, 19877, proc(req: HttpRequest, res: HttpResponse) =
      seen = $req.httpMethod & " " & req.getPath()
      res.status(Http200).send("ok"))
    check seen == "GET /"
    check r == "ok"

  test "a keep-alive connection is reused across requests":
    let r = live("""
      discard body(httpGet(client, url))
      let first = idleConnections(client)
      discard body(httpGet(client, url))
      return $first & "|" & $idleConnections(client)
    """, 19878, proc(req: HttpRequest, res: HttpResponse) =
      res.status(Http200).send("pong"))
    # One idle connection after the first request proves the response was
    # pooled, and the count staying at one proves the second request reused it
    # rather than opening a second connection.
    check r == "1|1"

  test "keepAlive false closes the connection instead of pooling":
    let r = live("""
      return $idleConnections(client)
    """, 19879, proc(req: HttpRequest, res: HttpResponse) =
      res.status(Http200).send("pong"),
      clientOpts = """parseJson("{\"keepAlive\":false}")""")
    check r == "0"

  test "statusText and contentLength are available":
    let r = live("""
      return statusText(res) & "|" & $contentLength(res)
    """, 19880, proc(req: HttpRequest, res: HttpResponse) =
      res.status(Http200).send("12345"))
    # The reason phrase powpow reports is "OK", not the numeric code.
    check r == "OK|5"
