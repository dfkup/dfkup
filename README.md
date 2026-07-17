<p align="center">
  <img src="https://raw.githubusercontent.com/dfkup/dfkup/main/.github/dfkup.png" alt="DFkup logo" width="80px" height="80px"><br>
  A fast scripting language<br>
  Typed &bullet; Stack-based VM &bullet; JIT Compiler
</p>

<p align="center">
  <code>nimble install dfkup</code>
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
fib_recursive:
  fib_recursive    dfkup        Time (mean ± σ):       7.3 ms ±   1.0 ms   
  fib_recursive    node         Time (mean ± σ):      93.2 ms ±  11.9 ms   
  fib_recursive    python3      Time (mean ± σ):      1.017 s ±  0.016 s   
  fib_recursive    ruby         Time (mean ± σ):     521.0 ms ±   4.0 ms   
  fib_recursive    luajit       Time (mean ± σ):      76.5 ms ±   2.2 ms   
  fib_recursive    php83        Time (mean ± σ):     520.2 ms ±  11.5 ms   

nested_loops:
  nested_loops     dfkup        Time (mean ± σ):      72.5 ms ±   0.5 ms   
  nested_loops     node         Time (mean ± σ):      40.5 ms ±   0.4 ms   
  nested_loops     python3      Time (mean ± σ):      30.9 ms ±   1.0 ms   
  nested_loops     ruby         Time (mean ± σ):      81.6 ms ±   2.6 ms   
  nested_loops     luajit       Time (mean ± σ):       6.5 ms ±   0.4 ms   
  nested_loops     php83        Time (mean ± σ):      25.3 ms ±   0.9 ms   

prime_sieve:
  prime_sieve      dfkup        Time (mean ± σ):     113.8 ms ±   1.4 ms   
  prime_sieve      node         Time (mean ± σ):      40.1 ms ±   0.7 ms   
  prime_sieve      python3      Time (mean ± σ):      26.6 ms ±   1.1 ms   
  prime_sieve      ruby         Time (mean ± σ):      73.6 ms ±   0.7 ms   
  prime_sieve      luajit       Time (mean ± σ):       6.0 ms ±   0.5 ms   
  prime_sieve      php83        Time (mean ± σ):      24.1 ms ±   0.6 ms   

string_concat:
  string_concat    dfkup        Time (mean ± σ):      15.4 ms ±   0.7 ms   
  string_concat    node         Time (mean ± σ):      39.4 ms ±   0.4 ms   
  string_concat    python3      Time (mean ± σ):      25.1 ms ±   0.8 ms   
  string_concat    ruby         Time (mean ± σ):      73.5 ms ±   1.3 ms   
  string_concat    luajit       Time (mean ± σ):      11.5 ms ±   0.3 ms   
  string_concat    php83        Time (mean ± σ):      23.1 ms ±   0.7 ms   

tail_recursive:
  tail_recursive   dfkup        Time (mean ± σ):     548.4 ms ±   1.4 ms   
  tail_recursive   node         CRASHED
  tail_recursive   python3      CRASHED
  tail_recursive   ruby         CRASHED
  tail_recursive   luajit       CRASHED
  tail_recursive   php83        Time (mean ± σ):      23.2 ms ±   0.4 ms   

range_sum:
  range_sum        dfkup        Time (mean ± σ):      31.3 ms ±   2.6 ms   
  range_sum        node         Time (mean ± σ):      49.9 ms ±   1.2 ms   
  range_sum        python3      Time (mean ± σ):     717.9 ms ±  19.9 ms   
  range_sum        ruby         Time (mean ± σ):     421.2 ms ±   7.5 ms   
  range_sum        luajit       Time (mean ± σ):      13.6 ms ±   0.4 ms   
  range_sum        php83        Time (mean ± σ):      93.9 ms ±   1.8 ms  
```


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
