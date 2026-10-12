import std/[json, unittest]
import pkg/datpkgr/types
import pkg/semver
# Must precede everything dfkup-side: voodoo registers the NodeKind
# extension (nkEnumDef...) for modules compiled after this import.
import ../src/lang/transformers
import ../src/pkg/pkgmanifest

suite "Package manifest - package.kup":
  test "full manifest":
    let m = parsePackageManifest("""
package({
  name: "myutils",
  version: "0.1.0",
  description: "handy helpers",
  license: "MIT",
  main: "src/myutils.kup",
  dependencies: {
    otherlib: ">= 0.2.0"
  }
})
""", "package.kup")
    check m.name == "myutils"
    check m.version == "0.1.0"
    check m.description == "handy helpers"
    check m.license == "MIT"
    check m.extra["main"].getStr == "src/myutils.kup"
    check m.dependencies.len == 1
    check m.dependencies[0].name == "otherlib"
    check m.dependencies[0].constraint.kind == vcGte
    check m.dependencies[0].constraint.version == parseVersion("0.2.0")

  test "minimal manifest":
    let m = parsePackageManifest("package({name: \"tiny\"})", "package.kup")
    check m.name == "tiny"
    check m.version == ""
    check m.dependencies.len == 0
    check not m.extra.hasKey("main")

  test "no package declaration":
    expect PackageManifestError:
      discard parsePackageManifest("let x = 1", "package.kup")

  test "missing name":
    expect PackageManifestError:
      discard parsePackageManifest("package({version: \"1.0.0\"})",
        "package.kup")

  test "non-string field":
    expect PackageManifestError:
      discard parsePackageManifest("package({name: 42})", "package.kup")

  test "bad constraint":
    expect PackageManifestError:
      discard parsePackageManifest(
        "package({name: \"x\", dependencies: {y: \"not-a-version\"}})",
        "package.kup")

  test "non-object package arg":
    expect PackageManifestError:
      discard parsePackageManifest("package(\"x\")", "package.kup")
