import std/[unittest, strutils]
import ../src/dfkup

# `json` and `strings` are owned by dfkup (`src/lang/lowlibs`) and served
# in-image by the loader — these tests drive them through real
# `import "std/..."` scripts, so they cover the internal loading path
# with no dylib shards involved.

proc run(code: string): string =
  exec(code, "test_json_strings.dfkup", true, false)

suite "Internal stdlib - json":
  test "parse and dump roundtrip":
    check run("import \"std/json\"\n" &
      "let d = parseJson(\"{\\\"a\\\":1}\")\ndumpJson(d)") == "{\"a\":1}"

  test "get string field":
    check run("import \"std/json\"\n" &
      "let d = parseJson(\"{\\\"n\\\":\\\"x\\\"}\")\nget(d, \"n\", \"\")") == "\"x\""

  test "get with default":
    check run("import \"std/json\"\n" &
      "let d = parseJson(\"{}\")\nget(d, \"k\", \"fallback\")") == "\"fallback\""

  test "keys joined":
    check run("import \"std/json\"\n" &
      "let d = parseJson(\"{\\\"a\\\":1,\\\"b\\\":2}\")\njoin(keys(d), \",\")") == "a,b"

  test "dot access on json is rejected":
    try:
      discard run("import \"std/json\"\n" &
        "let d = parseJson(\"{\\\"a\\\":1}\")\necho $d.a")
      check false
    except CatchableError as e:
      check "bracket notation" in e.msg

  test "bracket then scalar accessors":
    check run("import \"std/json\"\n" &
      "let u = parseJson(\"{\\\"n\\\": 40}\")\nu[\"n\"].getInt()") == "40"
    check run("import \"std/json\"\n" &
      "let u = parseJson(\"{\\\"pi\\\": 3.5}\")\nu[\"pi\"].getFloat()") == "3.5"
    check run("import \"std/json\"\n" &
      "let u = parseJson(\"{\\\"name\\\": \\\"WASM\\\"}\")\nu[\"name\"].getStr()") == "WASM"
    check run("import \"std/json\"\n" &
      "let u = parseJson(\"{\\\"ok\\\": true}\")\nu[\"ok\"].getBool()") == "true"
    check run("import \"std/json\"\n" &
      "let u = parseJson(\"{\\\"nothing\\\": null}\")\nu[\"nothing\"].getBool()") == "false"

  test "scalar accessors convert scalar kinds":
    check run("import \"std/json\"\n" &
      "parseJson(\"\\\"42\\\"\").getInt()") == "42"
    check run("import \"std/json\"\n" &
      "parseJson(\"40\").getFloat()") == "40.0"
    check run("import \"std/json\"\n" &
      "parseJson(\"40\").getStr()") == "40"
    check run("import \"std/json\"\n" &
      "parseJson(\"1\").getBool()") == "true"

  test "scalar accessors reject containers":
    try:
      discard run("import \"std/json\"\n" &
        "parseJson(\"[1, 2]\").getInt()")
      check false
    except CatchableError as e:
      check "cannot convert JSON JArray to int" in e.msg
    try:
      discard run("import \"std/json\"\n" &
        "parseJson(\"\\\"abc\\\"\").getInt()")
      check false
    except CatchableError as e:
      check "cannot convert JSON string to int" in e.msg

  test "unknown json method is a compile error":
    try:
      discard run("import \"std/json\"\n" &
        "let n = parseJson(\"40\")\necho n.foobar()")
      check false
    except CatchableError as e:
      check "does not exist for <json>" in e.msg

suite "Internal stdlib - strings":
  test "case conversion":
    check run("import \"std/strings\"\ntoUpper(\"hello\")") == "HELLO"
    check run("import \"std/strings\"\ntoLower(\"WORLD\")") == "world"

  test "predicates":
    check run("import \"std/strings\"\ncontains(\"hello\", \"ell\")") == "true"
    check run("import \"std/strings\"\nstartsWith(\"hello\", \"hel\")") == "true"
    check run("import \"std/strings\"\nendsWith(\"hello\", \"lo\")") == "true"

  test "split and join":
    check run("import \"std/strings\"\n" &
      "join(split(\"a,b,c\", \",\"), \" | \")") == "a | b | c"

  test "parse helpers":
    check run("import \"std/strings\"\nparseInt(\"42\")") == "42"
    check run("import \"std/strings\"\nparseBool(\"true\")") == "true"
