# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

import std/[json, tables]
import pkg/powpow/loop as powLoop
import pkg/powpow/fswatch
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

var
  watchLoop: Loop
  watchers: Table[int, FileWatcher] = initTable[int, FileWatcher]()
  watcherPaths: Table[int, string] = initTable[int, string]()
  nextWatchId = 1
  pendingEvents: seq[tuple[id: int, events: seq[string]]] = @[]

proc eventName(e: FileSystemEvent): string =
  case e
  of fseModified: "modified"
  of fseCreated: "created"
  of fseDeleted: "deleted"
  of fseRenamed: "renamed"
  of fseAttrib: "attrib"
  of fseLinkCount: "linkcount"
  of fseRevoke: "revoke"

proc ensureLoop() =
  if watchLoop == nil:
    watchLoop = newLoop()

proc initFswatch*(script: Script, module: Module) =
  module.initSystemTypes()
  script.initSystemOps(module)

  script.addProc(module, "watch", @[paramDef("path", ttyString)], ttyInt,
    proc (args: StackView, argc: int): Value =
      ensureLoop()
      let id = nextWatchId
      inc nextWatchId
      let path = args[0].stringVal[]
      let cb: FileWatcherCb = proc (w: FileWatcher, events: set[FileSystemEvent]) {.closure.} =
        var names: seq[string] = @[]
        for e in events:
          names.add(eventName(e))
        pendingEvents.add((id, names))
      let watcher = newFileWatcher(watchLoop, path, cb)
      if watcher == nil:
        result = initValue(-1'i64)
      else:
        watchers[id] = watcher
        watcherPaths[id] = path
        result = initValue(id.int64))

  script.addProc(module, "unwatch", @[paramDef("id", ttyInt)], ttyBool,
    proc (args: StackView, argc: int): Value =
      let id = args[0].intVal.int
      if watchers.hasKey(id):
        watchers[id].close()
        watchers.del(id)
        watcherPaths.del(id)
        result = initValue(true)
      else:
        result = initValue(false))

  script.addProc(module, "watchPath", @[paramDef("id", ttyInt)], ttyString,
    proc (args: StackView, argc: int): Value =
      let id = args[0].intVal.int
      result = initValue(watcherPaths.getOrDefault(id, "")))

  script.addProc(module, "pollWatchers", @[
      paramDef("timeoutMs", ttyInt, initValue(100'i64))], ttyJson,
    proc (args: StackView, argc: int): Value =
      ensureLoop()
      powLoop.poll(watchLoop, args[0].intVal.int)
      var arr = newJArray()
      for (id, events) in pendingEvents:
        var o = newJObject()
        o["id"] = %(id)
        o["path"] = %(watcherPaths.getOrDefault(id, ""))
        var evs = newJArray()
        for e in events:
          evs.add(%e)
        o["events"] = evs
        arr.add(o)
      pendingEvents = @[]
      result = initValue(arr))
