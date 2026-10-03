# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

## `std/llm` binds `chachachat`, which is async Nim, over a synchronous VM.
##
## Rather than hide `waitFor` behind every proc, the client is split into a
## start/step/result trio so a dfkup `async func` can drive one request at a
## time and yield in between:
##
##   async func chat(client, prompt): string =
##     let job = llmStart(client, prompt)
##     while not llmDone(job):
##       llmStep(job)
##       yield "thinking"
##     return llmText(job)
##
## `llmChat` and `llmChatChunks` are the blocking convenience forms, and both
## are written in dfkup so they compose with `await` like any other coroutine.

import std/[strutils, asyncdispatch, sequtils]
import pkg/chachachat/[llmclient]
import pkg/openparser/json
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]
import ./libsystem

type
  LlmBindError* = object of ValueError

  LlmSession = ref object
    ## One chachachat client plus the conversation state dfkup scripts drive.
    inner: LLMClient
    conv: Conversation

  LlmRequest = ref object
    ## One in-flight request. Chachachat hands back a `Future`, so the request
    ## holds that plus whatever the stream callback has collected so far.
    future: Future[LLMResponse]
    client: LLMClient
    chunks: seq[string]
    reasoning: seq[string]

# Clients live for the life of the VM, so a global registry keyed by an integer
# is simpler than threading `ref` counts through foreign values. Requests are
# keyed the same way and released explicitly with `llmRelease`.
var
  sessions = newSeq[LlmSession]()
  requests = newSeq[LlmRequest]()

# The stream callback runs on the event loop thread while `llmDone` pumps, so
# it only appends to buffers. Nothing here touches the VM.
proc makeStreamCb(j: LlmRequest): ResponseStreamCb =
  result = proc (chunk: ResponseChunk) =
    case chunk.chunkType
    of chunkContent:
      if chunk.text.len > 0: j.chunks.add chunk.text
    of chunkReasoning:
      if chunk.text.len > 0: j.reasoning.add chunk.text
    else:
      discard

# The registry index is what travels to dfkup as a pointer, so the foreign
# value stays opaque and releasing a request just clears its slot.
proc handleValue(id: int): Value =
  result = Value(typeId: tyPointer)
  result.objectVal = Object(isForeign: true,
    foreign: ForeignData(data: cast[pointer](id), destructor: nil))

proc sessionValue(c: LlmSession): Value =
  sessions.add c
  handleValue(sessions.high)

proc requestValue(j: LlmRequest): Value =
  requests.add j
  handleValue(requests.high)

proc sessionAt(args: StackView, i: int): LlmSession =
  let id = cast[int](args[i].objectVal.foreign.data)
  if id < 0 or id >= sessions.len or sessions[id].isNil:
    raise newException(LlmBindError,
      "llm client " & $id & " is no longer valid")
  result = sessions[id]

proc requestAt(args: StackView, i: int): LlmRequest =
  let id = cast[int](args[i].objectVal.foreign.data)
  if id < 0 or id >= requests.len or requests[id].isNil:
    raise newException(LlmBindError,
      "llm job " & $id & " is no longer valid")
  result = requests[id]

# Options ──

proc parseOpts(node: JsonNode): LLMOptions =
  ## Read a dfkup json options object into chachachat's `LLMOptions`. Anything
  ## absent keeps the chachachat default.
  result = defaultOpts
  if node.isNil or node.kind != JObject:
    return
  if node.hasKey("maxTokens"):
    result.maxTokens = node["maxTokens"].getInt()
  if node.hasKey("temperature"):
    result.temperature = node["temperature"].getFloat()
  if node.hasKey("topP"):
    result.topP = node["topP"].getFloat()
  if node.hasKey("stream"):
    result.stream = node["stream"].getBool()
  if node.hasKey("timeout"):
    result.timeout = node["timeout"].getInt()
  if node.hasKey("toolChoice"):
    result.toolChoice = node["toolChoice"].getStr()

proc responseJson(r: LLMResponse): JsonNode =
  ## Expose the fields a dfkup script can reasonably use.
  result = newJObject()
  result["id"] = %r.id
  result["finishReason"] = %r.finishReason
  result["text"] = %r.chunks.filterIt(it.chunkType == chunkContent)
    .mapIt(it.text).join()
  result["reasoning"] = %r.chunks.filterIt(it.chunkType == chunkReasoning)
    .mapIt(it.text).join()
  var calls = newJArray()
  for tc in r.toolCalls:
    var entry = newJObject()
    entry["id"] = %tc.id
    entry["name"] = %tc.name
    entry["arguments"] = tc.argumentsJson()
    calls.add entry
  result["toolCalls"] = calls
  var usage = newJObject()
  usage["promptTokens"] = %r.usage.promptTokens
  usage["completionTokens"] = %r.usage.completionTokens
  usage["totalTokens"] = %r.usage.totalTokens
  result["usage"] = usage

# dfkup coroutine drivers, so `await` drives them like any other coroutine.
const
  ChatCoroSrc* = """
async func llmChat*(client, prompt, opts = nil): string =
  let job = llmStart(client, prompt, opts)
  while not llmDone(job):
    llmStep(job)
    yield "llm: waiting"
  if llmFailed(job):
    return llmError(job)
  return llmText(job)
"""

  ChatChunksCoroSrc* = """
async func llmChatChunks*(client, prompt, opts = nil): array =
  let job = llmStart(client, prompt, opts)
  var out: array = []
  while not llmDone(job):
    for c in llmTakeChunks(job):
      out.add(c)
    llmStep(job)
    yield "llm: waiting"
  for c in llmTakeChunks(job):
    out.add(c)
  return out
"""

proc initLlm*(script: Script, module: Module) =
  discard module.genPtr(tyPointer, "LlmSession")
  discard module.genPtr(tyPointer, "LlmRequest")
  let sessionTy = module.sym"LlmSession"
  let requestTy = module.sym"LlmRequest"

  #
  # Clients
  #

  script.addProc(module, "llmNewClient",
    params = @[paramDef("baseUrl", ttyString), paramDef("apiKey", ttyString),
               paramDef("model", ttyString)],
    returnTy = ttyPointer, returnTySym = sessionTy,
    impl = proc (args: StackView, argc: int): Value =
      let
        baseUrl = args[0].stringVal[]
        apiKey = args[1].stringVal[]
        model = args[2].stringVal[]
      if baseUrl.len == 0:
        raise newException(LlmBindError, "llmNewClient needs a baseUrl")
      if model.len == 0:
        raise newException(LlmBindError, "llmNewClient needs a model")
      result = sessionValue(LlmSession(
        inner: newLlmClient(baseUrl, apiKey, model))))

  script.addProc(module, "llmOpenRouterClient",
    params = @[paramDef("apiKey", ttyString), paramDef("model", ttyString)],
    returnTy = ttyPointer, returnTySym = sessionTy,
    impl = proc (args: StackView, argc: int): Value =
      result = sessionValue(LlmSession(inner: newOpenRouterClient(
        args[0].stringVal[], args[1].stringVal[]))))

  script.addProc(module, "llmOpenCodeClient",
    params = @[paramDef("apiKey", ttyString), paramDef("model", ttyString)],
    returnTy = ttyPointer, returnTySym = sessionTy,
    impl = proc (args: StackView, argc: int): Value =
      result = sessionValue(LlmSession(inner: newOpenCodeClient(
        args[0].stringVal[], args[1].stringVal[]))))

  script.addProc(module, "llmModel",
    params = @[paramDef("client", ttyPointer)], returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      result = initValue(sessionAt(args, 0).inner.model))

  script.addProc(module, "llmBaseUrl",
    params = @[paramDef("client", ttyPointer)], returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      result = initValue(sessionAt(args, 0).inner.baseUrl))

  script.addProc(module, "llmUserAgent",
    params = @[paramDef("client", ttyPointer)], returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      result = initValue(getUserAgent(sessionAt(args, 0).inner)))

  #
  # Requests: start, step, then read the result
  #

  script.addProc(module, "llmStart",
    params = @[paramDef("client", ttyPointer), paramDef("prompt", ttyString),
               paramDef("opts", ttyJson, initValue(newJObject()))],
    returnTy = ttyPointer, returnTySym = requestTy,
    impl = proc (args: StackView, argc: int): Value =
      let c = sessionAt(args, 0)
      let j = LlmRequest(client: c.inner)
      let opts = parseOpts(if argc > 2: args[2].jsonVal else: newJObject())
      j.future = c.inner.chat(args[1].stringVal[], opts, j.makeStreamCb())
      result = requestValue(j))

  script.addProc(module, "llmStep",
    params = @[paramDef("job", ttyPointer)], returnTy = ttyVoid,
    impl = proc (args: StackView, argc: int): Value =
      ## Poll point for the request. `llmDone` does the actual event loop pass,
      ## so this is a no-op kept for symmetry with the dfkup driver.
      discard requestAt(args, 0))

  script.addProc(module, "llmDone",
    params = @[paramDef("job", ttyPointer)], returnTy = ttyBool,
    impl = proc (args: StackView, argc: int): Value =
      let j = requestAt(args, 0)
      if not j.future.finished:
        # one non-blocking pass over the event loop, so the VM stays responsive
        try:
          poll(0)
        except ValueError:
          discard # nothing registered yet
      result = initValue(j.future.finished))

  script.addProc(module, "llmFailed",
    params = @[paramDef("job", ttyPointer)], returnTy = ttyBool,
    impl = proc (args: StackView, argc: int): Value =
      result = initValue(requestAt(args, 0).future.failed))

  script.addProc(module, "llmError",
    params = @[paramDef("job", ttyPointer)], returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      let j = requestAt(args, 0)
      result = initValue(if j.future.failed: j.future.error.msg else: ""))

  script.addProc(module, "llmText",
    params = @[paramDef("job", ttyPointer)], returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      let j = requestAt(args, 0)
      if not j.future.finished:
        raise newException(LlmBindError,
          "llmText called before the request finished, check llmDone first")
      if j.future.failed:
        raise newException(LlmBindError, j.future.error.msg)
      result = initValue(j.chunks.join()))

  script.addProc(module, "llmReasoning",
    params = @[paramDef("job", ttyPointer)], returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      result = initValue(requestAt(args, 0).reasoning.join()))

  script.addProc(module, "llmTakeChunks",
    params = @[paramDef("job", ttyPointer)], returnTy = ttyJson,
    impl = proc (args: StackView, argc: int): Value =
      ## Drain the chunks buffered since the last call, so a coroutine can
      ## stream them out incrementally.
      let j = requestAt(args, 0)
      var drained = newJArray()
      for c in j.chunks:
        drained.add %c
      j.chunks = @[]
      result = initValue(drained))

  script.addProc(module, "llmResponse",
    params = @[paramDef("job", ttyPointer)], returnTy = ttyJson,
    impl = proc (args: StackView, argc: int): Value =
      let j = requestAt(args, 0)
      if not j.future.finished:
        raise newException(LlmBindError,
          "llmResponse called before the request finished")
      if j.future.failed:
        raise newException(LlmBindError, j.future.error.msg)
      result = initValue(j.future.read.responseJson()))

  script.addProc(module, "llmRelease",
    params = @[paramDef("job", ttyPointer)], returnTy = ttyVoid,
    impl = proc (args: StackView, argc: int): Value =
      requests[cast[int](args[0].objectVal.foreign.data)] = nil)

  #
  # Conversations
  #

  script.addProc(module, "llmNewConversation",
    params = @[paramDef("client", ttyPointer),
               paramDef("title", ttyString, initValue("New Conversation"))],
    returnTy = ttyVoid,
    impl = proc (args: StackView, argc: int): Value =
      let c = sessionAt(args, 0)
      c.conv = newConversation(c.inner, nil,
        (if argc > 1: args[1].stringVal[] else: "New Conversation")))

  script.addProc(module, "llmAddMessage",
    params = @[paramDef("client", ttyPointer), paramDef("role", ttyString),
               paramDef("content", ttyString)],
    returnTy = ttyVoid,
    impl = proc (args: StackView, argc: int): Value =
      let c = sessionAt(args, 0)
      if c.conv.isNil:
        raise newException(LlmBindError,
          "call llmNewConversation before llmAddMessage")
      let role =
        case args[1].stringVal[]
        of "user": UserMessageRole.user
        of "assistant": UserMessageRole.assistant
        of "system": UserMessageRole.system
        else: raise newException(LlmBindError,
          "unknown role: " & args[1].stringVal[] &
          " (expected user, assistant or system)")
      c.conv.addMessage(role, args[2].stringVal[]))

  script.addProc(module, "llmHistory",
    params = @[paramDef("client", ttyPointer)], returnTy = ttyJson,
    impl = proc (args: StackView, argc: int): Value =
      let c = sessionAt(args, 0)
      if c.conv.isNil:
        raise newException(LlmBindError, "no conversation has been started")
      var msgs = newJArray()
      for m in c.conv.getHistory():
        var entry = newJObject()
        entry["role"] = %($m.role)
        entry["content"] = %m.content
        msgs.add entry
      result = initValue(msgs))

  script.addProc(module, "llmConversationTitle",
    params = @[paramDef("client", ttyPointer)], returnTy = ttyString,
    impl = proc (args: StackView, argc: int): Value =
      let c = sessionAt(args, 0)
      if c.conv.isNil:
        raise newException(LlmBindError, "no conversation has been started")
      result = initValue(c.conv.getTitle()))

  compileCode(script, module, ChatCoroSrc & ChatChunksCoroSrc)
