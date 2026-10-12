# DFkup - A fast scripting language for cool kids!
#
# (c) 2026 George Lemon | LGPLv3 License
#          Made by Humans from OpenPeeps
#          https://dfkup.dev
#          https://github.com/dfkup/dfkup

## `package.kup` manifest parser (datpkgr `ManifestParser` compatible).
##
## A kup package declares itself with a single top-level call, mirroring
## the `config({...})` idiom:
##
##   ```kup
##   package({
##     name: "myutils",
##     version: "0.1.0",
##     description: "handy string helpers",
##     license: "MIT",
##     main: "src/myutils.kup",
##     dependencies: {
##       otherlib: ">= 0.2.0"
##     }
##   })
##   ```
##
## Only `name` is required. `version` may be empty (datpkgr discovers real
## versions from git tags at install time). `main` defaults at resolution
## time to `src/<name>.kup`, falling back to `<name>.kup`; the raw value
## (when present) is kept in `extra["main"]`. The manifest is parsed, never
## evaluated: no VM runs, so this module stays threads-free and importable
## from unit tests under default flags.

import std/[json, options, strutils, tables]
import pkg/vancode/interpreter/ast
import pkg/datpkgr/types
# transformers extends vancode's NodeKind (nkEnumDef...); parser.nim needs
# the extension registered, so this must come before the parser import.
import ../lang/transformers
import ../lang/parser

type
  PackageManifestError* = object of CatchableError

proc manifestErr(path, msg: string): ref PackageManifestError =
  newException(PackageManifestError, path & ": " & msg)

proc stringField(obj: Node, path, field: string): string =
  ## Value of a string-valued `field: "..."` pair, "" when absent.
  ## Anything present but not a string is a manifest error.
  for child in obj.children:
    if child.kind != nkColon or child.len < 2:
      continue
    if child[0].kind != nkIdent or child[0].ident != field:
      continue
    if child[1].kind != nkString:
      raise manifestErr(path, "\"" & field & "\" must be a string")
    return child[1].stringVal
  ""

proc findPackageObject(nodes: seq[Node], path: string): Node =
  ## The object literal of the first top-level `package({...})` call,
  ## nil when the file declares no package.
  for node in nodes:
    if node.kind != nkCall or node.len < 2:
      continue
    if node[0].kind != nkIdent or node[0].ident != "package":
      continue
    if node[1].kind != nkObjectStorage:
      raise manifestErr(path, "package(...) expects a single object literal")
    return node[1]
  nil

proc parseDependencies(obj: Node, path: string): seq[PkgDependency] =
  ## `dependencies: {name: "constraint"}` pairs. Values must be strings
  ## in datpkgr constraint syntax (`*`, `1.2.3`, `>= 1.0.0`, `^`, `~`).
  for child in obj.children:
    if child.kind != nkColon or child.len < 2:
      continue
    if child[0].kind != nkIdent or child[0].ident != "dependencies":
      continue
    if child[1].kind != nkObjectStorage:
      raise manifestErr(path, "\"dependencies\" must be an object")
    for dep in child[1].children:
      if dep.kind != nkColon or dep.len < 2 or dep[0].kind != nkIdent:
        raise manifestErr(path,
          "dependencies must map names to version constraints")
      if dep[1].kind != nkString:
        raise manifestErr(path, "constraint for \"" & dep[0].ident &
          "\" must be a string")
      try:
        let constraint = parseConstraint(dep[1].stringVal)
        result.add(PkgDependency(name: dep[0].ident, url: "",
          constraint: constraint, branch: "", tag: "", features: @[],
          isToolchain: false))
      except CatchableError as e:
        raise manifestErr(path, "bad constraint for \"" & dep[0].ident &
          "\": " & e.msg)
    return result
  @[]

proc parsePackageManifest*(content: string, path: string): Manifest =
  ## Parse `package.kup` source into a datpkgr `Manifest`. Raises
  ## `PackageManifestError` (a `CatchableError`, safe through datpkgr)
  ## on syntax errors and on malformed declarations.
  var program: Ast
  try:
    parseScript(program, content)
  except DfkupParserError as e:
    raise manifestErr(path, "syntax error at (" & $e.ln & "," & $e.col &
      "): " & e.msg)
  let obj = findPackageObject(program.nodes, path)
  if obj == nil:
    raise manifestErr(path, "no package({...}) declaration found")
  let name = obj.stringField(path, "name")
  if name.strip().len == 0:
    raise manifestErr(path, "\"name\" is required")
  let version = obj.stringField(path, "version")
  let main = obj.stringField(path, "main")
  var extra = newJObject()
  if main.len > 0:
    extra["main"] = newJString(main)
  Manifest(path: path, name: name, version: version,
    description: obj.stringField(path, "description"),
    license: obj.stringField(path, "license"),
    dependencies: obj.parseDependencies(path),
    features: initTable[string, seq[PkgDependency]](),
    devDependencies: @[], extra: extra)
