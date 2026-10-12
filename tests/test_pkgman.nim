import std/[json, options, os, tempfiles, unittest]
import ../src/lang/transformers
import ../src/pkg/pkgman
import ../src/dfkup

proc tempPkgCfg(): DatpkgrConfig =
  let dir = createTempDir("dfkup_pkg_", "")
  result = newDfkupPkgConfig(dir)
  result.callbacks.log = proc(lvl: LogLevel, msg: string) {.gcsafe.} = discard

suite "Package manager - develop and resolve":
  test "develop, resolve, entry, remove":
    let cfg = tempPkgCfg()
    defer: removeDir(cfg.rootPath)
    let fixture = absolutePath("tests/fixtures/kup_hello")
    check cfg.pkgDevelop(fixture)
    let root = cfg.resolveInstalledPath("hello", "")
    check root.len > 0
    check dirExists(root)
    let entry = cfg.packageEntryPoint(root, "hello")
    check entry == root / "src" / "hello.kup"
    let resolved = cfg.resolvePkgImport("pkg/hello")
    check resolved.isSome
    check resolved.get() == entry
    check cfg.resolvePkgImport("pkg/nope").isNone
    check cfg.resolvePkgImport("pkg/hello/../../dfkup").isNone
    check cfg.pkgRemove("hello")
    check cfg.resolveInstalledPath("hello", "").len == 0

  test "import pkg from a script":
    let cfg = tempPkgCfg()
    defer: removeDir(cfg.rootPath)
    let fixture = absolutePath("tests/fixtures/kup_hello")
    check cfg.pkgDevelop(fixture)
    putEnv("DFKUP_HOME", cfg.rootPath)
    try:
      let outp = exec("import \"pkg/hello\"\nhello()",
        "pkg_e2e", true, false)
      check outp == "hi from hello pkg"
    finally:
      delEnv("DFKUP_HOME")

suite "Package manager - registry":
  test "registry defaults":
    let cfg = tempPkgCfg()
    defer: removeDir(cfg.rootPath)
    check cfg.defaultRegistryUrl == pkgRegistryUrl
    check cfg.defaultSourceName == "dfkup"
    check cfg.defaultSourceName == pkgDefaultSourceName

  test "fresh home registers the dfkup source":
    let cfg = tempPkgCfg()
    defer: removeDir(cfg.rootPath)
    var found = false
    for src in cfg.loadSources():
      if src.name == "dfkup" and src.url == pkgRegistryUrl:
        found = true
    check found

  test "pre-registry home migrates to the dfkup source":
    let dir = createTempDir("dfkup_pkg_", "")
    defer: removeDir(dir)
    writeFile(dir / "sources.json",
      """{"sources": [{"name": "default", "url": ""}]}""")
    let cfg = newDfkupPkgConfig(dir)
    var names: seq[string] = @[]
    for src in cfg.loadSources():
      names.add(src.name & "=" & src.url)
    check names == @["dfkup=" & pkgRegistryUrl]

  test "seeded registry resolves by name":
    let cfg = tempPkgCfg()
    defer: removeDir(cfg.rootPath)
    # Pre-touched (empty) database skips the first-run registry download,
    # keeping this test hermetic: seeding + resolution are pure DB work.
    writeFile(cfg.dbPath(), "")
    let data = %*[
      {"name": "demo", "url": "https://github.com/dfkup/demo",
        "method": "git", "tags": [], "description": "demo pkg",
        "license": "MIT", "web": "https://github.com/dfkup/demo"},
      {"name": "nope", "url": "https://github.com/dfkup/nope",
        "method": "git", "tags": [], "description": "noweb pkg",
        "license": "MIT"}]
    cfg.withDatpkgrDB:
      check cfg.seedPackagesTable(data, "dfkup") == 1
    let hit = cfg.resolveRootMeta("demo", "")
    check hit.isSome
    check hit.get().url == "https://github.com/dfkup/demo"
    check cfg.resolveRootMeta("missing", "").isNone
