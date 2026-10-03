import std/[unittest, os, strutils]
import ../src/dfkup

# These tests drive real files rather than in-process ASTs, because the behaviour
# under test is how separate source files resolve each other's types. That path
# needs a parser callback and a real module graph, which the in-process `run`
# helpers in the other suites do not build.

# Absolute, because the test binary runs from a temp directory rather than from
# the project root.
let fixtures = currentSourcePath.parentDir / "fixtures" / "enumabc"

proc runFixture(name: string): string =
  # `allowExprResult` so a fixture can end in a bare expression and hand its
  # result back. `runFile` hardcodes it off, and `echo` writes straight to
  # stdout rather than producing a value the caller can see.
  let path = fixtures / name
  exec(readFile(path), path, true, false)

proc runFixtureFails(name: string, want: string): string =
  try:
    let got = runFixture(name)
    doAssert false, "expected " & name & " to fail, but it produced: " & got
  except DfkupError as e:
    result = e.msg
  doAssert want in result,
    "expected " & want & " in: " & result

suite "Imports - a file's own type wins over an imported one":
  test "a local declaration resolves even when an import declares the same name":
    # a_local_wins.dfkup declares `Veg` and imports b.dfkup, which also declares
    # `Veg`. Flattening both into one table meant whichever module was loaded
    # first claimed the name.
    check runFixture("a_local_wins.dfkup") == "Pea/sprout"

suite "Imports - types are per-file":
  test "a type from one file is not accepted where another is expected":
    # The point of the whole exercise: a.dfkup's `Veg` passed to c's `wantsB`,
    # whose parameter is b's `Veg`.
    discard runFixtureFails("a_cross_type.dfkup", "type mismatch")

  test "the error names both files":
    let msg = runFixtureFails("a_cross_type.dfkup", "type mismatch")
    check "a_cross_type.dfkup" in msg
    check "b.dfkup" in msg

suite "Imports - a name in two files":
  test "a bare name is reported as ambiguous rather than resolved silently":
    let msg = runFixtureFails("a_ambiguous.dfkup", "more than one imported file")
    check "b.dfkup" in msg
    check "amb.dfkup" in msg

  test "`import as` disambiguates and both remain usable":
    check runFixture("a_aliased.dfkup") == "yes/Turnip"
