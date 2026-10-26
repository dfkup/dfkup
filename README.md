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

## Key Features
- Interpreted language with runtime type checking
- Compiled to bytecode and executed on a Stack-based Virtual Machine
- JIT Compilation [powered by DynASM JIT](https://github.com/nimbase/dynasm-nim) assembling code at runtime!
- Pratt parser for expressive and flexible syntax
- **Compilation policy** settings to restrict features: deny std modules, `for` loops, conditionals, or any other language construct
- Control flow: `if`/`elif`/`else`, `for` loops, `while` loops
- Variable declarations: `var` (mutable), `const` (compile-time)
- Function definitions with named parameters, `return` types, and **generics** (`[T]`, `[T: string]`, `[T: array[string]]`, `[T: string, X: int]`)
- First-class function calls with positional and named arguments
- Data literals: integers, floats, strings (single/double/triple-quoted, backtick)
- String interpolation with $var syntax
- Array and object storage (JSON-like) literals
- Built-in JSON support: parse, dump, pretty-print, field access
- Doc comments (`##`) and line comments (`#`)
- Built-in DFS (depth-first search) package manager (same engine used at [pkg/clue](https://github.com/openpeeps/clue))
- Powered by [VanCode language framework](https://github.com/openpeeps/vancode)
- Written in [Nim](https://github.com/nim-lang/nim)

### Installation
You need Nim. 

### CLI usage
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

### Examples

`var` is mutable, `let` is immutable, `const` is compile-time:
```
var score = 42
score = score + 8
let name = "dfkup"
const max = 100
var total: int = 0
```

Infix expressions for arithmetic, comparison, logic and strings:
```
echo 1 + 2 * 3        # 7
echo 10 - 4           # 6
echo 42 == 42         # true
echo true and false   # false
echo "Hi, " & "you"   # Hi, you
```

Branching with `if` / `elif` / `else`:
```
var temperature = 75
if temperature > 80:
  echo "hot"
elif temperature > 60:
  echo "nice"
else:
  echo "cool"
```

`for` loops over ranges and iterators:
```
for i in 1..5:
  echo i
```

`while` loops with a mutable counter:
```
var i = 1
while i <= 5:
  echo i
  i = i + 1
```

Functions with typed parameters and a return type (`result` carries it):
```
fn add(a, b: int): int =
  result = a + b

echo add(10, 20)      # 30
```

Generic functions take type parameters in brackets, with an optional
constraint after a colon. Constraints are checked at the call site:
```
func hello[T: string](name: T): T =
  return name

func first[T: array[string]](xs: T): string =
  return xs[0]

func pair[T: string, X: int](a: T, b: X): X =
  return b

echo hello("world")     # world
echo first(["a", "b"])  # a
echo pair("hi", 42)     # 42
```

### Build Standard Library
Only `system` is statically linked into the `dfkup` binary. Every other
standard module (`json`, `yaml`, `qr`, `http`, ... — 30 in total) ships as
a prebuilt `libdfkup_<name>` dylib shard inside the release archive,
loaded on the first `import "std/<name>"`. Scripts that import nothing
pay nothing.

The shards are built from the [stdlib](https://github.com/dfkup/stdlib)
repo at workflow level (no nimble task, and no `requires "stdkups"` in
`dfkup.nimble`). Each release packages them next to the binary, and the
host locates them via `stdlibLibPath`: home libraries first
(`~/.dfkup/libraries`, `DFKUP_HOME`-aware), then next to the binary. On
Windows the extension is `.dll`, on Linux `.so`.

Low-level users can build the shards themselves from a stdlib checkout
(a plain `nim c -r` program; it generates one wrapper per shard from the
template and compiles with the same flags as the host,
`--threads:on --mm:arc`, uniform across the dylib boundary):

```sh
# from a stdkups checkout (dfkup resolves via clue, develop wins locally)
nim c -r tools/build_shards.nim --out=dist/shards

# single shard, explicit dfkup sources
nim c -r tools/build_shards.nim --dfkup-src=../dfkup --out=dist/shards --libs=qr,json
```

Requirements: Nim on `PATH`, the shard dependencies resolvable by clue
(`clue install --depsOnly` in the stdlib checkout), and the dfkup
sources for `lang/transformers` and `lang/parser` — a checkout, or the
published package (`clue install dfkup --build`).

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
DFkup is built on top of [VanCode, a modular CodeGen, VM and JIT compiler](https://github.com/openpeeps/vancode) written in Nim. The JIT compiler is powered by a pure Nim [DynASM (dynamic assembler)](https://github.com/nimbase/dynasm-nim).

## Roadmap
- [x] Lexer (`tests/test_lexer.nim`)
- [x] Parser with AST output (`dfkup ast`, `tests/test_parser.nim`)
- [x] VanCode wiring — bytecode compiler, VM and JIT, on by default (`--nojit` opts out; `tests/test_vm.nim`)
- [x] Standard library — 30 `std/*` modules, 5 linked in, rest as dylib shards
- [x] Package manager (`pkg/` imports, `dfkup pkg` on datpkgr)
- [x] Config files (`config.kup` via `dfkup conf`)
- [x] Node.js native addon via denim (`dfkup` on npm, lives in the [dfkup-js](https://github.com/dfkup/dfkup-js) repo)
- [ ] Add more tests
- [ ] Add more benchmarks (including languages)
- [ ] Publish a [Booyaka](https://github.com/openpeeps/booyaka) Documentation

### ❤ Contributions & Support
- 🐛 Found a bug? [Create a new Issue](https://github.com/dfkup/dfkup/issues)
- 👋 Wanna help? [Fork it!](https://github.com/dfkup/dfkup/fork)

### 🎩 License
LGPLv3 license. [Made by Humans from OpenPeeps](https://github.com/openpeeps).<br>
Copyright OpenPeeps & Contributors &mdash; All rights reserved.
