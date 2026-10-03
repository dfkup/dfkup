# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

## `std/config` exposes a runtime config declaration.
##
##   ```nim
##   import "std/config"
##
##   config({name: "demo"})
##   ```
##
## The parser has already evaluated the object literal before this runs, so
## there is deliberately no static interception, task selection, or execution
## here. The validated value is retained as the process-global active config
## so the `conf` command can look commands up after the file has run.
##
## `commands` is reserved: when present, it must be an object whose values are
## strings. Those strings are the executable commands selected by the `conf`
## command. This declaration returns nothing; the CLI retains the validated
## object separately.
##
##   ```nim
##   import "std/config"
##
##   config({commands: {hello: "echo hello"}})
##   ```

import std/strutils
import pkg/vancode/interpreter/[chunk, sym, value]
import pkg/vancode/interpreter/stdlib/[syslib, utils]

const commandsField = "commands"

# The most recently evaluated config value in this process. Foreign procs do
# not receive the surrounding Script, so this is how the `conf` command finds
# the commands after running a config file. It is process-global state: the
# CLI takes and clears it around each config run.
var activeConfig: Value = nil

proc clearActiveConfig*() =
  activeConfig = nil

proc takeActiveConfig*(): Value =
  result = activeConfig
  activeConfig = nil

proc commandName(commands: Value, index: int): string =
  if index < commands.objectVal.keys.len:
    result = commands.objectVal.keys[index]
  else:
    result = "command #" & $index

proc commandsObject(cfg: Value): Value =
  if cfg == nil or cfg.typeId != tyObjectStorage:
    raise newException(ValueError, "config requires an object")
  for i, key in cfg.objectVal.keys:
    if key != commandsField:
      continue
    result = cfg.objectVal.fields[i].toValue
    if result == nil or result.typeId != tyObjectStorage:
      raise newException(ValueError,
        "config.commands must be an object mapping command names to strings")
    for j, command in result.objectVal.fields:
      if command.toValue == nil or command.toValue.typeId != tyString:
        let name = commandName(result, j)
        raise newException(ValueError, "config.commands[\"" & name &
          "\"] must be a string")
    return result
  raise newException(ValueError, "config has no \"commands\" object")

proc checkCommandsField(cfg: Value) =
  for key in cfg.objectVal.keys:
    if key == commandsField:
      discard commandsObject(cfg)
      return
  if cfg == nil or cfg.typeId != tyObjectStorage:
    raise newException(ValueError, "config requires an object")

proc findConfigCommand*(cfg: Value, name: string): string =
  ## Return the shell text for one configured command.
  let commands = commandsObject(cfg)
  for i, command in commands.objectVal.fields:
    if commandName(commands, i) == name:
      # Entries were already validated as strings by `commandsObject`.
      return command.toValue.stringVal[]
  let available = commands.objectVal.keys.join(", ")
  if available.len == 0:
    raise newException(ValueError, "unknown config command \"" & name &
      "\" (no commands are available)")
  raise newException(ValueError, "unknown config command \"" & name &
    "\" (available: " & available & ")")

proc initConfig*(script: Script, module: Module) =

  script.addProc(module, "config", @[paramDef("data", ttyObject)], ttyVoid,
    proc (args: StackView, argc: int): Value =
      checkCommandsField(args[0])
      activeConfig = args[0])
