import std/unittest
import ../src/dfkup

# `sequtils` and `regex` are owned by dfkup (`src/lang/lowlibs`) and
# served in-image by the loader — these tests drive them through real
# `import "std/..."` scripts, so they cover the internal loading path
# with no dylib shards involved.

proc run(code: string): string =
  exec(code, "test_sequtils_regex.dfkup", true, false)

suite "Internal stdlib - sequtils":
  test "min and max":
    check run("import \"std/sequtils\"\nlet a = [3, 1, 2]\nmin(a)") == "1"
    check run("import \"std/sequtils\"\nlet a = [3, 1, 2]\nmax(a)") == "3"

  test "contains, count and indexOf":
    check run("import \"std/sequtils\"\ncontains([1, 2, 3], 2)") == "true"
    check run("import \"std/sequtils\"\ncontains([1, 2, 3], 9)") == "false"
    check run("import \"std/sequtils\"\ncount([1, 2, 2, 3], 2)") == "2"
    check run("import \"std/sequtils\"\nindexOf([1, 2, 3], 3)") == "2"

  test "first, last and isEmpty":
    check run("import \"std/sequtils\"\nfirst([5, 6])") == "5"
    check run("import \"std/sequtils\"\nlast([5, 6])") == "6"
    check run("import \"std/sequtils\"\nisEmpty([1])") == "false"

  test "sort, distinct and concat compose":
    check run("import \"std/sequtils\"\nfirst(sort([3, 1, 2]))") == "1"
    check run("import \"std/sequtils\"\nlast(sort([3, 1, 2]))") == "3"
    check run("import \"std/sequtils\"\nlen(distinct([1, 2, 2, 3]))") == "3"
    check run("import \"std/sequtils\"\nlen(concat([1, 2], [3]))") == "3"

suite "Internal stdlib - regex":
  test "find with groups":
    check run("import \"std/regex\"\n" &
      "let m = find(\"hello42world\", \"([a-z]+)(\\\\d+)\")\nm[\"groups\"]") == "[\"hello\",\"42\"]"
    check run("import \"std/regex\"\n" &
      "let m = find(\"hello42world\", \"([a-z]+)(\\\\d+)\")\nm[\"matched\"]") == "true"
    check run("import \"std/regex\"\n" &
      "let m = find(\"hello42world\", \"([a-z]+)(\\\\d+)\")\nm[\"start\"]") == "0"

  test "match requires full match":
    check run("import \"std/regex\"\n" &
      "let m = match(\"42\", \"\\\\d+\")\nm[\"matched\"]") == "true"
    check run("import \"std/regex\"\n" &
      "let m = match(\"42hello\", \"\\\\d+\")\nm[\"matched\"]") == "false"
    check run("import \"std/regex\"\n" &
      "let m = match(\"hello\", \"\\\\d+\")\nm[\"matched\"]") == "false"

  test "findAll":
    check run("import \"std/regex\"\nlen(findAll(\"a1b22\", \"\\\\d+\"))") == "2"
    check run("import \"std/regex\"\nlen(findAll(\"abc\", \"\\\\d+\"))") == "0"
