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
requires "vancode >= 0.2.6"

# mostly required for exporting as libraries
requires "openparser >= 0.1.9"
requires "marvdown >= 0.1.0"
requires "mimedb >= 0.1.1"
requires "supranim >= 0.1.11"
requires "blackpaper >= 0.1.0"
requires "nimcypher >= 0.2.5"
requires "twofa >= 0.1.0"
requires "powpow >= 0.2.2"
requires "money >= 0.1.0"
requires "chopchop >= 0.1.0"
requires "chachachat >= 0.1.0"
requires "voodoo >= 0.1.9"

task stdlibs, "Build dfkup stdlib dylibs into bin/stdlib":
  ## Generates a per-stdlib wrapper from
  ## src/lang/lowlibs/stdlib_plugin.tmpl (this toolchain ignores
  ## `-d:name=value`, so generation replaces flag dispatch) and builds
  ## libdfkup_<name>.dylib with the same toolchain and flags as the host
  ## binary (layout compatibility across the dylib boundary depends on
  ## it). Develop/registry search paths come from clue.lock, so no
  ## ~/.nimble registry is involved.
  ## Run with: clue task stdlibs
  # (name, lowlib module, init proc). Pilot first; rollout extends this.
  const stdlibMap = [("json", "libjson", "initJson"),
    ("httpclient", "libhttpclient", "initHttpClient"),
    ("http", "libhttp", "initHttp"),
    ("fswatch", "libfswatch", "initFswatch"),
    ("browser", "libbrowser", "initBrowser")]
  # `http` excluded for now: its supranim/powpow chain needs threads:on,
  # which disagrees with the dylib heap contract (see plans/stdlib-dylibs.md).
  const pilotLibs = ["json", "httpclient", "fswatch", "browser"]
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
  for name in pilotLibs:
    var module, initProc, cleanup = ""
    for entry in stdlibMap:
      if entry[0] == name:
        module = entry[1]
        initProc = entry[2]
    if module.len == 0:
      echo "no mapping for stdlib: " & name
      quit(1)
    if name == "browser":
      cleanup = "proc dfkupStdlibCleanup*() =\n    closeAllBrowsers()\n"
    let genFile = "bin/stdlib_gen/stdlib_" & name & ".nim"
    writeFile(genFile, tmpl.replace("%%NAME%%", name)
      .replace("%%MODULE%%", module).replace("%%INIT%%", initProc)
      .replace("%%CLEANUP%%", cleanup))
    # Drop any stale dylib first: same-second rewrites can otherwise
    # look up-to-date to nim's incremental check and silently skip.
    let outLib = "bin/stdlib/libdfkup_" & name & ".dylib"
    exec("rm -f " & outLib)
    # NB: `-d:release`, not `--release` (this toolchain rejects it).
    # `--path:src` resolves the `lang/lowlibs/<module>` import above.
    # `--threads:off` must match src/dfkup.nims (host): table heap
    # must agree across the dylib boundary (see plans/stdlib-dylibs.md).
    # `--mm:arc` must match too: ORC's cycle collector traces only its
    # own image's roots, so host-referenced dylib objects look like
    # unreachable cycles and get collected live (heap corruption).
    # ARC is pure refcounting with no tracing, so it is boundary-safe.
    let cmd = nimExe & " c --app:lib --threads:off --mm:arc -d:release --opt:speed" &
      " --hints:off --verbosity:0" &
      " -d:vancodeJitDynasm -d:nimPreviewHashRef" &
      " -d:supranimUseGlobalOnRequest" &
      pathArgs & " --path:\"src\"" &
      " --out:" & outLib & " " & genFile
    echo "building libdfkup_" & name & ".dylib ..."
    exec(cmd)
  echo "stdlib dylibs in bin/stdlib/ (dev fallback; install to ~/.dfkup/stdlib for normal runs)"