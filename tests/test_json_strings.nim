import std/unittest
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
