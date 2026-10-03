import std/[os, unittest, strutils]
import ../src/dfkup

proc writeConfigFile(name, code: string): string =
  result = getTempDir() / ("dfkup-config-" & name & ".kup")
  writeFile(result, code)

suite "Config":
  test "empty config is a void declaration":
    check exec("import \"std/config\"\nconfig({})", "config.dfkup", true,
      false) == ""

  test "config accepts a plain object":
    check exec("import \"std/config\"\nconfig({name: \"demo\"})",
      "config.dfkup", true, false) == ""

  test "config accepts string commands":
    check exec("import \"std/config\"\n" &
        "config({commands: {hello: \"echo hello\"}})",
      "config.dfkup", true, false) == ""

  test "config rejects a non-object commands field":
    try:
      discard exec("import \"std/config\"\nconfig({commands: \"echo hello\"})",
        "config.dfkup", true, false)
      fail()
    except DfkupError as e:
      check "config.commands must be an object" in e.msg

  test "config rejects a non-string command":
    try:
      discard exec("import \"std/config\"\nconfig({commands: {hello: 1}})",
        "config.dfkup", true, false)
      fail()
    except DfkupError as e:
      check "config.commands[\"hello\"] must be a string" in e.msg

  test "config is unavailable without its stdlib import":
    try:
      discard exec("config({})", "config.dfkup", true, false)
      fail()
    except DfkupError as e:
      check "undeclared identifier 'config'" in e.msg

suite "Config files":
  test "conf mode loads std/config automatically":
    let path = writeConfigFile("autoload", "config({name: \"demo\"})")
    check runConfigFile(path) == ""

  test "conf mode executes a selected command":
    let path = writeConfigFile("hello",
      "config({commands: {hello: \"echo hello\"}})")
    check runConfigFile(path, "hello") == "hello\n"

  test "conf mode reports an unknown command":
    let path = writeConfigFile("unknown",
      "config({commands: {hello: \"echo hello\"}})")
    try:
      discard runConfigFile(path, "goodbye")
      fail()
    except DfkupError as e:
      check "unknown config command \"goodbye\"" in e.msg
      check "hello" in e.msg

  test "conf mode requires a config declaration":
    let path = writeConfigFile("missing", "let name = \"demo\"")
    try:
      discard runConfigFile(path, "hello")
      fail()
    except DfkupError as e:
      check "no config declaration found" in e.msg

  test "conf mode reports a failing command":
    let path = writeConfigFile("failing", "config({commands: {bad: \"exit 3\"}})")
    try:
      discard runConfigFile(path, "bad")
      fail()
    except DfkupError as e:
      check "failed with exit code 3" in e.msg
