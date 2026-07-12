<p align="center">
  <img src="https://raw.githubusercontent.com/dfkup/dfkup/main/.github/dfkup.png" alt="DFkup logo" width="80px" height="80px"><br>
  A fast scripting language<br>
  Typed &bullet; Stack-based VM &bullet; JIT Compiler
</p>

<p align="center">
  <code>nimble install dfkup</code>
</p>

<p align="center">
  <a href="https://dfkup.github.io/dfkup/">API reference</a><br>
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
A scripting language with VM + JIT compiler
  (c) OpenPeeps | LGPL-3.0-or-later License  
  Build Version: 0.1.0

Scripting
  run <script:path>           Run a DFkup script file
          --nojit:bool
  ast <script:path>           Generate AST from a DFkup script file
          --dumptree:bool
```

### Benchmarks
```
bash ./tests/bench/runall.sh 2>&1
```

```
## Multi-Language Benchmark Results

fib_recursive:
  fib_recursive    dfkup        Time (mean ± σ):       8.8 ms ±   0.3 ms   
  fib_recursive    node         Time (mean ± σ):      90.1 ms ±   2.9 ms   
  fib_recursive    python3      Time (mean ± σ):      1.043 s ±  0.026 s   
  fib_recursive    ruby         Time (mean ± σ):     524.8 ms ±   3.8 ms   
  fib_recursive    luajit       Time (mean ± σ):      76.5 ms ±   2.6 ms   
  fib_recursive    php83        Time (mean ± σ):     512.4 ms ±   0.9 ms   

nested_loops:
  nested_loops     dfkup        Time (mean ± σ):      75.4 ms ±   5.2 ms   
  nested_loops     node         Time (mean ± σ):      40.3 ms ±   0.3 ms   
  nested_loops     python3      Time (mean ± σ):      29.2 ms ±   0.9 ms   
  nested_loops     ruby         Time (mean ± σ):      84.0 ms ±   9.1 ms   
  nested_loops     luajit       Time (mean ± σ):       5.5 ms ±   0.3 ms   
  nested_loops     php83        Time (mean ± σ):      24.3 ms ±   1.5 ms   

prime_sieve:
  prime_sieve      dfkup        Time (mean ± σ):     125.1 ms ±   9.1 ms   
  prime_sieve      node         Time (mean ± σ):      40.3 ms ±   2.3 ms   
  prime_sieve      python3      Time (mean ± σ):      25.8 ms ±   1.0 ms   
  prime_sieve      ruby         Time (mean ± σ):      72.9 ms ±   3.9 ms   
  prime_sieve      luajit       Time (mean ± σ):       5.5 ms ±   0.6 ms   
  prime_sieve      php83        Time (mean ± σ):      23.0 ms ±   0.3 ms   

string_concat:
  string_concat    dfkup        Time (mean ± σ):      15.3 ms ±   1.2 ms   
  string_concat    node         Time (mean ± σ):      43.1 ms ±   4.1 ms   
  string_concat    python3      Time (mean ± σ):      24.4 ms ±   1.5 ms   
  string_concat    ruby         Time (mean ± σ):      75.7 ms ±   6.9 ms   
  string_concat    luajit       Time (mean ± σ):      12.4 ms ±   5.5 ms   
  string_concat    php83        Time (mean ± σ):      22.8 ms ±   1.6 ms   

tail_recursive:
  tail_recursive   dfkup        Time (mean ± σ):     569.2 ms ±   2.2 ms   
```

_todo investigate why `tail_recursive` is not completed for all langs_

### Notes
DFkup is built on top of [VanCode, a modular CodeGen, VM and JIT compiler](https://github.com/openpeeps/vancode) written in Nim. The JIT compiler is powered by [DynASM](https://staff.fnwi.uva.nl/h.vandermeer/docs/lua/luajit/dynasm_features.html).

## Roadmap
- [ ] Add more tests
- [ ] A stable VM
- [ ] A stable JIT compiler
- [ ] Add more benchmarks (including languages)
- [ ] Publish a [Booyaka](https://github.com/openpeeps/booyaka) Documentation
- [ ] Implement VanCode package manager API

### ❤ Contributions & Support
- 🐛 Found a bug? [Create a new Issue](https://github.com/dfkup/dfkup/issues)
- 👋 Wanna help? [Fork it!](https://github.com/dfkup/dfkup/fork)

|  |  |
|---|---|
| <a href="https://opencode.ai/go?ref=BHMEEK48QX"><img src="https://github.com/openpeeps/pistachio/blob/main/.github/opencode.png" alt="OpenCode"></a> | Switch to **Open-Source LLMs** via OpenCode GO, choosing from a variety of powerful models such as DeepSeek, Qwen, Kimi, GLM-5, MiniMax, MiMo. 🍕 [Use our referral link to get started!](https://opencode.ai/go?ref=BHMEEK48QX)|

### 🎩 License
LGPLv3 license. [Made by Humans from OpenPeeps](https://github.com/openpeeps).<br>
Copyright OpenPeeps & Contributors &mdash; All rights reserved.
