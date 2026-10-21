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
Last run: 10/17/2026

```
## Multi-Language Benchmark Results

fib_recursive:
  fib_recursive    dfkup        Time (mean ± σ):       7.9 ms ±   0.4 ms   
  fib_recursive    node         Time (mean ± σ):      86.1 ms ±   1.5 ms   
  fib_recursive    python3      Time (mean ± σ):      1.076 s ±  0.001 s   
  fib_recursive    ruby         Time (mean ± σ):     526.8 ms ±   2.7 ms   
  fib_recursive    luajit       Time (mean ± σ):      77.2 ms ±   1.8 ms   
  fib_recursive    php83        Time (mean ± σ):     517.4 ms ±   8.8 ms   

nested_loops:
  nested_loops     dfkup        Time (mean ± σ):      10.4 ms ±   0.4 ms   
  nested_loops     node         Time (mean ± σ):      36.3 ms ±   1.1 ms   
  nested_loops     python3      Time (mean ± σ):      31.6 ms ±   0.6 ms   
  nested_loops     ruby         Time (mean ± σ):      82.5 ms ±   1.7 ms   
  nested_loops     luajit       Time (mean ± σ):       6.8 ms ±   0.5 ms   
  nested_loops     php83        Time (mean ± σ):      25.6 ms ±   0.8 ms   

prime_sieve:
  prime_sieve      dfkup        Time (mean ± σ):       8.6 ms ±   0.7 ms   
  prime_sieve      node         Time (mean ± σ):      34.8 ms ±   0.9 ms   
  prime_sieve      python3      Time (mean ± σ):      28.2 ms ±   0.7 ms   
  prime_sieve      ruby         Time (mean ± σ):      74.3 ms ±   1.8 ms   
  prime_sieve      luajit       Time (mean ± σ):       6.7 ms ±   0.6 ms   
  prime_sieve      php83        Time (mean ± σ):      25.6 ms ±   0.6 ms   

string_concat:
  string_concat    dfkup        Time (mean ± σ):      14.2 ms ±   1.5 ms   
  string_concat    node         Time (mean ± σ):      35.0 ms ±   1.5 ms   
  string_concat    python3      Time (mean ± σ):      26.4 ms ±   0.9 ms   
  string_concat    ruby         Time (mean ± σ):      73.9 ms ±   2.5 ms   
  string_concat    luajit       Time (mean ± σ):      12.2 ms ±   0.4 ms   
  string_concat    php83        Time (mean ± σ):      24.6 ms ±   0.7 ms   

tail_recursive:
  tail_recursive   dfkup        Time (mean ± σ):     380.1 ms ±   2.8 ms   
  tail_recursive   node         CRASHED
  tail_recursive   python3      CRASHED
  tail_recursive   ruby         CRASHED
  tail_recursive   luajit       CRASHED
  tail_recursive   php83        Time (mean ± σ):      23.9 ms ±   0.5 ms   

range_sum:
  range_sum        dfkup        Time (mean ± σ):      30.2 ms ±   0.8 ms   
  range_sum        node         Time (mean ± σ):      44.4 ms ±   0.6 ms   
  range_sum        python3      Time (mean ± σ):     728.0 ms ±  15.4 ms   
  range_sum        ruby         Time (mean ± σ):     437.8 ms ±  13.3 ms   
  range_sum        luajit       Time (mean ± σ):      14.2 ms ±   0.7 ms   
  range_sum        php83        Time (mean ± σ):     100.9 ms ±   5.4 ms   

collatz:
  collatz          dfkup        Time (mean ± σ):     251.7 ms ±   5.2 ms   
  collatz          node         Time (mean ± σ):      71.0 ms ±   3.3 ms   
  collatz          python3      Time (mean ± σ):      1.710 s ±  0.308 s   
  collatz          ruby         Time (mean ± σ):     701.8 ms ±   3.5 ms   
  collatz          luajit       Time (mean ± σ):      44.5 ms ±   1.2 ms   
  collatz          php83        Time (mean ± σ):     587.6 ms ±   7.2 ms   

array_sum:
  array_sum        dfkup        Time (mean ± σ):     145.9 ms ±   5.6 ms   
  array_sum        node         Time (mean ± σ):      43.1 ms ±   3.1 ms   
  array_sum        python3      Time (mean ± σ):      89.3 ms ±   2.0 ms   
  array_sum        ruby         Time (mean ± σ):      84.9 ms ±   3.8 ms   
  array_sum        luajit       Time (mean ± σ):       9.1 ms ±   0.4 ms   
  array_sum        php83        Time (mean ± σ):      32.7 ms ±   1.0 ms   

bubble_sort:
  bubble_sort      dfkup        Time (mean ± σ):     183.3 ms ±   3.3 ms   
  bubble_sort      node         Time (mean ± σ):      39.7 ms ±   1.6 ms   
  bubble_sort      python3      Time (mean ± σ):     232.3 ms ±   6.1 ms   
  bubble_sort      ruby         Time (mean ± σ):     112.8 ms ±   1.2 ms   
  bubble_sort      luajit       Time (mean ± σ):       7.0 ms ±   0.6 ms   
  bubble_sort      php83        Time (mean ± σ):      50.0 ms ±   1.8 ms   

object_access:
  object_access    dfkup        Time (mean ± σ):      23.9 ms ±   1.8 ms   
  object_access    node         Time (mean ± σ):      54.5 ms ±  29.1 ms   
  object_access    python3      Time (mean ± σ):     224.1 ms ±   6.7 ms   
  object_access    ruby         Time (mean ± σ):     341.8 ms ±   3.7 ms   
  object_access    luajit       Time (mean ± σ):       8.2 ms ±   0.7 ms   
  object_access    php83        Time (mean ± σ):      72.7 ms ±   2.5 ms   

float_math:
  float_math       dfkup        Time (mean ± σ):      25.1 ms ±   0.5 ms   
  float_math       node         Time (mean ± σ):      42.1 ms ±   2.5 ms   
  float_math       python3      Time (mean ± σ):     160.5 ms ±   5.7 ms   
  float_math       ruby         Time (mean ± σ):     116.6 ms ±   0.9 ms   
  float_math       luajit       Time (mean ± σ):       9.4 ms ±   0.5 ms   
  float_math       php83        Time (mean ± σ):      49.9 ms ±   0.6 ms   

call_overhead:
  call_overhead    dfkup        Time (mean ± σ):      16.5 ms ±   0.4 ms   
  call_overhead    node         Time (mean ± σ):      35.9 ms ±   1.1 ms   
  call_overhead    python3      Time (mean ± σ):      73.0 ms ±   2.7 ms   
  call_overhead    ruby         Time (mean ± σ):      90.5 ms ±   1.0 ms   
  call_overhead    luajit       Time (mean ± σ):       7.0 ms ±   0.4 ms   
  call_overhead    php83        Time (mean ± σ):      37.7 ms ±   1.2 ms   

fizzbuzz_count:
  fizzbuzz_count   dfkup        Time (mean ± σ):      82.9 ms ±   0.9 ms   
  fizzbuzz_count   node         Time (mean ± σ):      65.2 ms ±   0.4 ms   
  fizzbuzz_count   python3      Time (mean ± σ):      2.417 s ±  0.019 s   
  fizzbuzz_count   ruby         Time (mean ± σ):     981.4 ms ±   1.6 ms   
  fizzbuzz_count   luajit       Time (mean ± σ):     116.1 ms ±   0.9 ms   
  fizzbuzz_count   php83        Time (mean ± σ):     380.8 ms ±   2.6 ms 
```


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
