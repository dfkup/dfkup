# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

## dfkup package management on top of datpkgr.
##
## Owns the `~/.dfkup` home (`DFKUP_HOME` overrides it): datpkgr keeps its
## databases, `packages/`, `develop/` and caches there, and dfkup adds
## `libraries/` for shared libraries (see `stdlibLibPath`). The home is
## created on the first package operation - there is no setup step.
##
## Packages are kup source trees declared by `package.kup` (see
## `pkgmanifest`). This phase supports installs by git URL and editable
## `develop` checkouts; registry-backed installs arrive with the dfkup
## packages source.
##
## NOTE: importing `datpkgr/operations` pulls the install thread pool, so
## any binary linking this module must build with `--threads:on` (the
## dfkup host does; see `src/dfkup.nims`).

import std/[algorithm, json, options, os, sequtils, strutils, tables]
import pkg/datpkgr/[config, install, operations, store, types]
import ./pkgmanifest

export config, install, operations, store, types

const pkgManifestFileName* = "package.kup"
  ## The kup package manifest filename.

const pkgRegistryUrl* =
  "https://raw.githubusercontent.com/dfkup/pkgs/main/packages.json"
  ## The default packages registry (github.com/dfkup/pkgs).

const pkgDefaultSourceName* = "dfkup"
  ## The default registry source name in sources.json.

proc dfkupHome*(): string =
  ## Package-manager home: `DFKUP_HOME` or `~/.dfkup`.
  getEnv("DFKUP_HOME", getHomeDir() / ".dfkup")

proc findPackageKup*(dir: string): string =
  ## `ManifestFinder` for kup packages: walk up from `dir` looking for
  ## `package.kup`, "" when none is found.
  var cur = dir
  var depth = 0
  while depth < 15:
    let cand = cur / pkgManifestFileName
    if fileExists(cand):
      return cand
    let parent = cur.parentDir()
    if parent == cur:
      break
    cur = parent
    inc depth
  ""

proc dfkupLogCb(level: LogLevel, msg: string) {.gcsafe.} =
  case level
  of lvlDebug:
    stderr.writeLine("[pkg] " & msg)
  of lvlInfo, lvlSuccess:
    echo msg
  of lvlWarn:
    stderr.writeLine("warning: " & msg)
  of lvlError:
    stderr.writeLine("error: " & msg)

proc ensurePkgSource*(cfg: DatpkgrConfig) =
  ## Make sure the dfkup registry source is registered. Fresh homes get
  ## it from datpkgr's own defaults; homes created before the registry
  ## existed carry a sourceless sources.json that `ensureSourcesFile`
  ## never upgrades (it only writes when missing), so add it here.
  ##
  ## NB: consult the raw file, not `loadSources` - its fallback fabricates
  ## a usable-looking entry named `defaultSourceName` when the file yields
  ## nothing, which is indistinguishable from a registered source.
  var present = false
  try:
    let content = readFile(cfg.rootPath / cfg.sourcesPath())
    let j = parseJson(content)
    let arr = if j.kind == JArray: j
      elif j.kind == JObject and j.hasKey("sources"): j["sources"]
      else: newJArray()
    if arr.kind == JArray:
      for item in arr:
        if item.kind == JObject and item.hasKey("name") and
            item["name"].getStr == cfg.defaultSourceName and
            item.hasKey("url") and item["url"].getStr.len > 0:
          present = true
          break
  except CatchableError:
    discard
  if present:
    return
  # Drop sourceless entries on the way through (the pre-registry
  # default has an empty URL and can never seed anything).
  var sources: seq[Source] = @[]
  for src in cfg.loadSources():
    if src.url.len > 0 and src.name != cfg.defaultSourceName:
      sources.add(src)
  sources.add(Source(name: cfg.defaultSourceName,
    url: cfg.defaultRegistryUrl))
  cfg.saveSources(sources)

proc newDfkupPkgConfig*(rootPath = "", debug = false,
    ensureSource = true): DatpkgrConfig =
  ## datpkgr config rooted at the dfkup home, wired to `package.kup`
  ## manifests, the dfkup packages registry and plain CLI logging.
  ## `rootPath` overrides the home (tests point it at a temp dir for
  ## hermetic runs). `ensureSource = false` skips the home-dir IO;
  ## the caller must then run `ensurePkgSource` before resolving —
  ## `exec` defers it to the first `pkg/` import so plain `run`
  ## scripts never touch the home dir.
  let root = if rootPath.len > 0: rootPath else: dfkupHome()
  var cbs: Callbacks
  cbs.log = dfkupLogCb
  result = newDatpkgrConfig("dfkup", root, debugEnabled = debug,
    callbacks = cbs)
  result.manifestParser = parsePackageManifest
  result.manifestFinder = findPackageKup
  result.manifestFileName = proc(pkg: string): string = pkgManifestFileName
  result.defaultRegistryUrl = pkgRegistryUrl
  result.defaultSourceName = pkgDefaultSourceName
  if ensureSource:
    result.ensurePkgSource()

proc pkgInstall*(cfg: DatpkgrConfig, spec: string, url = "",
    verbose = true): bool =
  ## Install one package: `spec` is a registry name (needs the dfkup
  ## packages source), a git URL, or a name with explicit `--url`.
  if url.len > 0:
    cfg.installPackage(spec, url = url, verbose = verbose)
  elif isGitUrl(spec):
    cfg.installPackage(pkgNameFromUrl(spec), url = spec, verbose = verbose)
  else:
    cfg.installPackage(spec, verbose = verbose)

proc pkgRemove*(cfg: DatpkgrConfig, name: string,
    version = ""): bool =
  ## Uninstall `name` (one version, or all when `version` is empty).
  ## No confirm callback: the CLI confirms nothing, removal is immediate.
  cfg.uninstallPackage(name, version)

proc pkgUpdate*(cfg: DatpkgrConfig, name = "",
    verbose = true): bool =
  ## Update one package, or every installed package when `name` is empty.
  if name.len == 0:
    cfg.updateAllPackages(verbose = verbose)
  else:
    cfg.updatePackage(name, verbose = verbose)

proc pkgDevelop*(cfg: DatpkgrConfig, dir: string): bool =
  ## Editable install: link `~/.dfkup/develop/<name>` at `dir`.
  ## The directory must carry a `package.kup` manifest.
  cfg.developPackage(dir)

proc pkgPrune*(cfg: DatpkgrConfig) =
  ## Drop orphaned packages (installed but no longer reachable).
  cfg.prunePackages()

proc pkgList*(cfg: DatpkgrConfig) =
  ## Print installed packages as `name@version  path`, roots first.
  let all = cfg.installedRecordsAll()
  if all.len == 0:
    echo "no packages installed"
    return
  var roots: seq[string] = @[]
  var rest: seq[string] = @[]
  for name in sorted(all.keys.toSeq):
    var isRoot = false
    for rec in all[name]:
      if rec.root:
        isRoot = true
        break
    if isRoot:
      roots.add(name)
    else:
      rest.add(name)
  for name in roots & rest:
    for rec in all[name]:
      var line = name & "@" & rec.version
      if rec.path.len > 0:
        line.add("  " & rec.path)
      echo line

proc firstExisting(paths: varargs[string]): string =
  for p in paths:
    if p.len > 0 and fileExists(p):
      return p
  ""

proc packageEntryPoint*(cfg: DatpkgrConfig, root, name: string): string =
  ## Absolute path of a package's entry file: manifest `main` when set,
  ## else `src/<name>.kup`, `src/<name>.dfkup`, `<name>.kup`,
  ## `<name>.dfkup` - first hit wins, "" when nothing exists.
  let mf = cfg.findManifestInDir(root)
  if mf.len > 0:
    try:
      let m = cfg.parseManifest(readFile(mf), mf)
      if m.extra != nil and m.extra.hasKey("main"):
        let main = m.extra["main"].getStr
        if main.len > 0:
          let hit = firstExisting(root / main)
          if hit.len > 0:
            return hit
    except CatchableError:
      discard
  firstExisting(root / "src" / name & ".kup", root / "src" / name & ".dfkup",
    root / name & ".kup", root / name & ".dfkup")

proc resolvePkgImport*(cfg: DatpkgrConfig,
    spec: string): Option[string] =
  ## vancode `pkgResolver`: map `pkg/<name>` (or `pkg/<name>/sub/path`)
  ## to an absolute script path, none when unresolvable (vancode then
  ## reports ErrImportError). Develop checkouts win automatically via
  ## `resolveInstalledPath`. `..` escapes are rejected.
  const prefix = "pkg/"
  if not spec.startsWith(prefix):
    return none(string)
  let tail = spec[prefix.len .. ^1]
  if tail.len == 0:
    return none(string)
  let slash = tail.find('/')
  let name = if slash < 0: tail else: tail[0 ..< slash]
  let rest = if slash < 0: "" else: tail[slash + 1 .. ^1]
  if name.len == 0 or name == "." or name == "..":
    return none(string)
  let root = cfg.resolveInstalledPath(name, "")
  if root.len == 0 or not dirExists(root):
    return none(string)
  if rest.len == 0:
    let entry = cfg.packageEntryPoint(root, name)
    if entry.len == 0:
      return none(string)
    return some(entry)
  let joined = normalizedPath(root / rest)
  if joined != root and not joined.startsWith(root & DirSep):
    return none(string)
  if splitFile(joined).ext.len > 0:
    if fileExists(joined):
      return some(joined)
    return none(string)
  let hit = firstExisting(joined & ".kup", joined & ".dfkup")
  if hit.len > 0:
    return some(hit)
  none(string)
