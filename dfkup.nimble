# Package

import std/[os, strutils]

version       = "0.1.0"
author        = "OpenPeeps"
description   = "A tiny scripting language. Enjoyable, easy to learn and work with so you don't f*ck up"
license       = "LGPL-3.0-or-later"
srcDir        = "src"
bin           = @["dfkup"]
binDir        = "bin"


# Dependencies

requires "nim >= 2.2.0"
requires "vancode >= 0.2.14"
requires "datpkgr >= 0.1.9"
requires "dynasm >= 0.1.0"

# mostly required for exporting as libraries
requires "openparser >= 0.3.10"
requires "marvdown >= 0.2.4"
requires "mimedb >= 0.1.4"
requires "supranim >= 0.1.11"
requires "blackpaper >= 0.2.0"
requires "nimcypher >= 0.2.5"
requires "twofa >= 0.1.0"
requires "powpow >= 0.2.2"
requires "money >= 0.1.0"
requires "chopchop >= 0.1.0"
requires "chachachat >= 0.1.0"
requires "voodoo >= 0.2.3"
# Pinned: flysystem 0.2.1 rewired the local driver onto POSIX-only
# securejoin with no Windows fallback (undeclared `sandboxPassthrough`
# on windows); 0.2.0 is the last version that compiles there. Unpin
# once upstream restores the documented non-POSIX fallback.
requires "flysystem == 0.2.0"

task stdlibs, "Build dfkup stdlib dylibs into bin/stdlib":
  ## Generates a per-stdlib wrapper from
  ## src/lang/lowlibs/stdlib_plugin.tmpl (this toolchain ignores
  ## `-d:name=value`, so generation replaces flag dispatch) and builds
  ## libdfkup_<name>.dylib with the same toolchain and flags as the host
  ## binary (layout compatibility across the dylib boundary depends on
  ## it). Develop/registry search paths come from clue.lock, so no
  ## ~/.nimble registry is involved.
  ## Run with: clue task stdlibs
  # (name, lowlib module, init proc). Full rollout: every entry of
  # `dfkupStdlibNames` (stdlib_loader.nim) except `system`, which stays
  # statically linked in the core binary.
  const stdlibMap = [("json", "libjson", "initJson"),
    ("httpclient", "libhttpclient", "initHttpClient"),
    ("http", "libhttp", "initHttp"),
    ("fswatch", "libfswatch", "initFswatch"),
    ("browser", "libbrowser", "initBrowser"),
    ("yaml", "libyaml", "initYaml"),
    ("strings", "libstrings", "initStrings"),
    ("sequtils", "libsequtils", "initSequtils"),
    ("cli", "libcli", "initCliLib"),
    ("config", "libconfig", "initConfig"),
    ("regex", "libregex", "initRegex"),
    ("toml", "libtoml", "initToml"),
    ("uuid", "libuuid", "initUuid"),
    ("dotenv", "libdotenv", "initDotenv"),
    ("csv", "libcsv", "initCsv"),
    ("bson", "libbson", "initBson"),
    ("colors", "libcolors", "initColors"),
    ("qr", "libqr", "initQr"),
    ("nanoid", "libnanoid", "initNanoId"),
    ("llm", "libllm", "initLlm"),
    ("xml", "libxml", "initXml"),
    ("feed", "libfeed", "initFeed"),
    ("ical", "libical", "initIcal"),
    ("css", "libcss", "initCss"),
    ("svg", "libsvg", "initSvg"),
    ("markdown", "libmarkdown", "initMarkdown"),
    ("strongpwd", "libstrongpwd", "initStrongpwd"),
    ("twofa", "libtwofa", "initTwofa"),
    ("algos", "libalgos", "initAlgos"),
    ("bench", "libbench", "initBench")]
  # Uniform `--threads:on --mm:arc` on host and dylibs (see flags below)
  # keeps the heap contract sound, so `http`/`browser` build as dylibs
  # too (their threads-bound deps used to rule that out).
  const stdlibLibs = ["json", "httpclient", "fswatch", "browser",
    "yaml", "strings", "sequtils", "cli", "config", "regex", "toml", "uuid",
    "dotenv", "csv", "bson", "colors", "qr", "nanoid", "llm", "xml",
    "feed", "ical", "css", "svg", "markdown", "strongpwd", "twofa",
    "algos", "http", "bench"]
  let lock = readFile("clue.lock")
  var paths: seq[string] = @[]
  for piece in lock.split("\"path\":\""):
    if piece.len == 0 or piece[0] == '{':
      continue
    let endIdx = piece.find('"')
    if endIdx < 0:
      continue
    let p = piece[0 ..< endIdx]
    if p.len > 0 and p notin paths:
      paths.add(p)
  if paths.len == 0:
    echo "clue.lock has no package paths; run `clue build` first"
    quit(1)
  mkDir("bin/stdlib")
  mkDir("bin/stdlib_gen")
  let tmpl = readFile("src/lang/lowlibs/stdlib_plugin.tmpl")
  # Same toolchain clue itself uses (clue.lock nimVersion). PATH `nim`
  # is a shim that rejects release flags; resolve choosenim directly.
  var nimVersion = ""
  let nimKey = "\"nimVersion\":\""
  let nimIdx = lock.find(nimKey)
  if nimIdx >= 0:
    let start = nimIdx + nimKey.len
    let nimEnd = lock.find('"', start)
    if nimEnd > start:
      nimVersion = lock[start ..< nimEnd]
  var nimExe = getHomeDir() / ".choosenim/toolchains/nim-" &
    nimVersion / "bin/nim"
  if nimVersion.len == 0 or not fileExists(nimExe):
    nimExe = findExe("nim")
  if nimExe.len == 0:
    echo "no Nim toolchain found"
    quit(1)
  var pathArgs = ""
  for p in paths:
    pathArgs.add(" --path:\"" & p & "\"")
  for name in stdlibLibs:
    var module, initProc, cleanup, setvm, extra = ""
    for entry in stdlibMap:
      if entry[0] == name:
        module = entry[1]
        initProc = entry[2]
    if module.len == 0:
      echo "no mapping for stdlib: " & name
      quit(1)
    if name == "browser":
      cleanup = "proc dfkupStdlibCleanup*() =\n    closeAllBrowsers()\n"
    if name == "http":
      # Server callbacks re-enter the host VM through this image's
      # JIT-bridge globals; the host pushes its VM after creating it
      # (see setStdlibVms in src/lang/stdlib_loader.nim).
      setvm = "proc dfkupStdlibSetVm*(vm: pointer) =\n    setHttpHostVm(vm)\n"
    if name == "config":
      # The `conf` command reads the active config back across the dylib
      # boundary (see config helpers in src/lang/stdlib_loader.nim).
      # Results travel as opaque pointers / cstrings with a global holder
      # so no dangling pointer ever crosses the boundary. Take is a peek:
      # it keeps the dylib-global reference alive (a raw pointer carries
      # no ARC ownership, so a destructive move would free the object on
      # return); the host releases via clear (its `finally` already does).
      extra = "var configLastResult {.global.}: string\n" &
        "proc dfkupConfigTakeActive*(): pointer =\n" &
        "    cast[pointer](peekActiveConfig())\n" &
        "proc dfkupConfigClearActive*() =\n" &
        "    clearActiveConfig()\n" &
        "proc dfkupConfigFindCommand*(cfg: pointer, name: cstring): cstring =\n" &
        "    try:\n" &
        "      configLastResult = findConfigCommand(cast[Value](cfg), $name)\n" &
        "      return configLastResult.cstring\n" &
        "    except CatchableError as e:\n" &
        "      pluginLastErr = e.msg\n" &
        "      return nil\n" &
        "proc dfkupConfigTakeErr*(): cstring =\n" &
        "    pluginLastErr.cstring\n"
    let genFile = "bin/stdlib_gen/stdlib_" & name & ".nim"
    writeFile(genFile, tmpl.replace("%%NAME%%", name)
      .replace("%%MODULE%%", module).replace("%%INIT%%", initProc)
      .replace("%%CLEANUP%%", cleanup).replace("%%SETVM%%", setvm)
      .replace("%%EXTRA%%", extra))
    # Drop any stale dylib first: same-second rewrites can otherwise
    # look up-to-date to nim's incremental check and silently skip.
    let outLib = "bin/stdlib/libdfkup_" & name & ".dylib"
    exec("rm -f " & outLib)
    # NB: `-d:release`, not `--release` (this toolchain rejects it).
    # `--path:src` resolves the `lang/lowlibs/<module>` import above.
    # `--threads:on --mm:arc` must match src/dfkup.nims (host): the heap
    # contract across the dylib boundary is uniform flags on every image
    # (mixed thread settings fault in every variant: region-heap mismatch
    # segfaults, useMalloc breaks dylib init and cross-heap frees abort).
    # ARC (no tracing, pure refcounting) is the boundary-safe collector.
    # See plans/stdlib-dylibs.md.
    let cmd = nimExe & " c --app:lib --threads:on --mm:arc -d:release --opt:speed" &
      " --hints:off --verbosity:0" &
      " -d:vancodeJitNim -d:nimPreviewHashRef" &
      " -d:supranimUseGlobalOnRequest" &
      pathArgs & " --path:\"src\"" &
      " --out:" & outLib & " " & genFile
    echo "building libdfkup_" & name & ".dylib ..."
    exec(cmd)
    # Install into the package-manager-owned libraries dir
    # (DFKUP_HOME-aware); bin/stdlib stays the dev fallback.
    let libHome = getEnv("DFKUP_HOME", getHomeDir() / ".dfkup") / "libraries"
    mkDir(libHome)
    cpFile(outLib, libHome / "libdfkup_" & name & ".dylib")
  echo "stdlib dylibs in bin/stdlib/ and " & getEnv("DFKUP_HOME",
    getHomeDir() / ".dfkup") / "libraries/"