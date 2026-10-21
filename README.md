<p align="center">
  <img src="https://raw.githubusercontent.com/dfkup/dfkup/main/.github/dfkup_logo.svg" alt=“dfkup logo" width="140px"><br>
  A fast scripting language<br>
  Typed &bullet; Stack-based VM &bullet; JIT Compiler
</p>

<p align="center">
  <code>nimble install dfkup</code> / <code>clue install dfkup --build</code>
</p>

<p align="center">
  <a href="https://marketplace.visualstudio.com/items?itemName=openpeeps.dfkup-vscode">VSCode Extension</a> | <a href="https://dfkup.github.io/dfkup/">API reference</a><br>
  <img src="https://github.com/dfkup/dfkup/workflows/test/badge.svg" alt="Github Actions">  <img src="https://github.com/dfkup/dfkup/workflows/docs/badge.svg" alt="Github Actions">
</p>

## What is this?
This is DFkup, /diː ɛf kʌp/ (or simply: "dee-ef-cup") &bullet; A functional, indent-based, scripting language, designed to be enjoyable, easy to learn and work with so you **don't f*ck up!**

> [!NOTE]
> Totally unstable API!

## Key Features
- Interpreted language with runtime type checking
- Compiled to bytecode and executed on a Stack-based Virtual Machine
- JIT Compilation powered by **DynASM JIT** assembling code at runtime!
- Pratt parser for expressive and flexible syntax
- **Compilation policy** settings to restrict features: deny std modules, `for` loops, conditionals, or any other language construct
- Control flow: `if`/`elif`/`else`, `for` loops, `while` loops
- Variable declarations: `var` (mutable), `const` (compile-time)
- Function definitions with named parameters, `return` types, and **generics**
- First-class function calls with positional and named arguments
- Data literals: integers, floats, strings (single/double/triple-quoted, backtick)
- String interpolation with $var syntax
- Array and object storage (JSON-like) literals
- Built-in JSON support: parse, dump, pretty-print, field access
- Doc comments (`##`) and line comments (`#`)
- Powered by [VanCode language framework](https://github.com/openpeeps/vancode)
- Written in [Nim](https://github.com/nim-lang/nim)

### Installation
You need Nim. 

### Build Standard Library
Only `system` is statically linked into the `dfkup` binary. Every other
standard module (`json`, `yaml`, `qr`, `http`, … — 30 in total) lives in
the [stdkups](https://github.com/dfkup/stdlib) package and ships as a
`libdfkup_<name>` dylib shard, loaded on the first `import "std/<name>"`.
Scripts that import nothing pay nothing.

Shards are built at workflow level with `tools/build_shards.nim`
(a plain `nim c -r` program, no nimble task). It generates one wrapper
per shard from the template and compiles with the same flags as the
host (`--threads:on --mm:arc`, uniform across the dylib boundary):

```sh
# from a dfkup checkout (finds ../stdlib or a registered stdkups checkout)
nim c -r /path/to/stdlib/tools/build_shards.nim \
  --stdkups=/path/to/stdlib --dfkup-src=. --out=bin/stdlib

# from a stdkups checkout (dfkup resolves via clue, develop wins locally)
nim c -r tools/build_shards.nim --out=dist/shards

# single shard
nim c -r tools/build_shards.nim --dfkup-src=. --out=bin/stdlib --libs=qr,json
```

Requirements: Nim on `PATH`, the shard dependencies resolvable by clue
(`clue install --depsOnly` in either repo), and the dfkup sources for
`lang/transformers` and `lang/parser` — a checkout, or the published
package (`clue install dfkup --build`). Built shards land in `--out`
(`bin/stdlib/`, also the release-archive layout) and are installed to
`~/.dfkup/libraries` (`DFKUP_HOME`-aware). The host locates them via
`stdlibLibPath`: home libraries first, then next to the binary. On
Windows the extension is `.dll`, on Linux `.so`.

### Examples
```
A tiny scripting language. Enjoyable, easy to learn and work with so you don't f*ck up
  (c) OpenPeeps | LGPL-3.0-or-later License
  Build Version: 0.1.0

usage: dfkup <command> [args] [options]

Scripting
  run <script>            run a .dfkup/.kup script
          --nojit         disable the JIT compiler
  exec <code>             execute dfkup code inline
  conf [command]          run a config.kup, optionally executing one configured command

Packages
  pkg install <spec>      install a package by name, git URL (--url=... pins a source URL)
  pkg remove <name> [ver] uninstall a package (one version, or all)
  pkg update [name]       update one package, or all when omitted
  pkg list                list installed packages
  pkg develop <path>      editable install from a local directory
  pkg prune               remove orphaned packages
  pkg refresh             re-download registry data

Codegen & Debugging
  ast <script>            generate AST from a DFkup script file
          --dumptree      print the AST as a tree instead of JSON

  -h, --help              show this help
  --version               show version
```

### Packages
Powered by [datpkgr](https://github.com/openpeeps/datpkgr). The first `pkg`
command creates the `~/.dfkup` home (`DFKUP_HOME` overrides it):

```
~/.dfkup/
  dfkup.db, versions.db   package-manager databases
  packages/<name>/<ver>/  installed kup packages
  develop/<name>          editable installs (symlinks)
  libraries/              shared libraries (stdlib dylibs live here)
```

A kup package is a source tree declared by `package.kup`:
```
package({
  name: "myutils",
  version: "0.1.0",
  description: "handy string helpers",
  license: "MIT",
  main: "src/myutils.kup",
  dependencies: {
    otherlib: ">= 0.2.0"
  }
})
```
Only `name` is required; `main` defaults to `src/<name>.kup`. Install by
registry name, git URL or editable directory (`dfkup pkg install <name>`,
`dfkup pkg install <url>`, `dfkup pkg develop <path>`). The registry lives
at [github.com/dfkup/pkgs](https://github.com/dfkup/pkgs) and seeds into
`~/.dfkup` on first use; `dfkup pkg refresh` re-downloads it when version
discovery goes stale. Scripts consume packages with the `pkg/` prefix, which
resolves to the installed entry point (develop checkouts win):
```
import "pkg/myutils"

echo shout("hello")
```
Exported functions carry the `*` marker (`func shout*(s: string): string`).

### Benchmarks
Multi-language benchmark results live in [benchmarks/README.md](./benchmarks/README.md).


### Notes
DFkup is built on top of [VanCode, a modular CodeGen, VM and JIT compiler](https://github.com/openpeeps/vancode) written in Nim. The JIT compiler is powered by [DynASM](https://staff.fnwi.uva.nl/h.vandermeer/docs/lua/luajit/dynasm_features.html).

## Roadmap
- [ ] Add more tests
- [ ] A stable VM
- [ ] A stable JIT compiler
- [ ] Add more benchmarks (including languages)
- [ ] Publish a [Booyaka](https://github.com/openpeeps/booyaka) Documentation
- [x] Implement VanCode package manager API (`pkg/` imports via `pkgResolver`, `dfkup pkg` on datpkgr)

### ❤ Contributions & Support
- 🐛 Found a bug? [Create a new Issue](https://github.com/dfkup/dfkup/issues)
- 👋 Wanna help? [Fork it!](https://github.com/dfkup/dfkup/fork)

### 🎩 License
LGPLv3 license. [Made by Humans from OpenPeeps](https://github.com/openpeeps).<br>
Copyright OpenPeeps & Contributors &mdash; All rights reserved.
