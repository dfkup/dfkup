<p align="center">
  <img src="https://raw.githubusercontent.com/dfkup/dfkup/main/.github/dfkup.png" alt="DFkup logo" width="80px" height="80px"><br>
  A fast scripting language<br>
  Typed interpreted &bullet; Stack-based VM &bullet; JIT Compiler
</p>

<p align="center">
  <code>nimble install dfkup</code>
</p>

<p align="center">
  <a href="https://dfkup.github.io/dfkup/">API reference</a><br>
  <img src="https://github.com/dfkup/dfkup/workflows/test/badge.svg" alt="Github Actions">  <img src="https://github.com/dfkup/dfkup/workflows/docs/badge.svg" alt="Github Actions">
</p>

## What is this?
DFkup is a fast, indent-based scripting language. Designed to be enjoyable, easy to learn and work with so you **don't f*ck up!**.


## Key Features
- Typed interpreted language with runtime type checking
- Compiled to bytecode and executed on a stack-based virtual machine
- JIT Compilation powered by LibgccJIT
- Pratt parser for expressive and flexible syntax
- Control flow: if/elif/else, for loops, while loops
- Variable declarations: var (mutable), let (immutable), const (compile-time)
- Function definitions with named parameters, return types, and generics
- First-class function calls with positional and named arguments
- Data literals: integers, floats, strings (single/double/triple-quoted, backtick)
- String interpolation with $var syntax
- Array and object storage (JSON-like) literals
- Built-in JSON support: parse, dump, pretty-print, field access
- Doc comments (/* */) and line comments (//)
- Powered by [VanCode language framework](https://github.com/openpeeps/vancode)
- Written in [Nim](https://github.com/nim-lang/nim)

### Installation
_todo_

### Examples
_todo_


### Benchmarks
```
bash ./tests/bench/runall.sh 2>&1
```

```
## Multi-Language Benchmark Results

fib_recursive:
  fib_recursive    dfkup        Time (mean ± σ):     286.4 ms ±   9.9 ms   
  fib_recursive    node         Time (mean ± σ):      46.0 ms ±   0.7 ms   
  fib_recursive    python3      Time (mean ± σ):     431.8 ms ±  33.7 ms   
  fib_recursive    ruby         Time (mean ± σ):     249.1 ms ±   7.0 ms   
  fib_recursive    luajit       Time (mean ± σ):      17.5 ms ±   3.6 ms   
  fib_recursive    php83        Time (mean ± σ):      94.0 ms ±   1.4 ms   

nested_loops:
  nested_loops     dfkup        Time (mean ± σ):     369.5 ms ±   1.1 ms   
  nested_loops     node         Time (mean ± σ):      39.2 ms ±   0.4 ms   
  nested_loops     python3      Time (mean ± σ):      29.7 ms ±   7.4 ms   
  nested_loops     ruby         Time (mean ± σ):      85.4 ms ±   7.0 ms   
  nested_loops     luajit       Time (mean ± σ):       6.3 ms ±   1.0 ms   
  nested_loops     php83        Time (mean ± σ):      23.2 ms ±   0.9 ms   

prime_sieve:
  prime_sieve      dfkup        Time (mean ± σ):     280.5 ms ±   1.0 ms   
  prime_sieve      node         Time (mean ± σ):      38.3 ms ±   0.4 ms   
  prime_sieve      python3      Time (mean ± σ):      24.4 ms ±   0.5 ms   
  prime_sieve      ruby         Time (mean ± σ):      71.0 ms ±   5.3 ms   
  prime_sieve      luajit       Time (mean ± σ):       5.4 ms ±   0.3 ms   
  prime_sieve      php83        Time (mean ± σ):      22.5 ms ±   1.7 ms   

string_concat:
  string_concat    dfkup        Time (mean ± σ):      18.8 ms ±   1.8 ms   
  string_concat    node         Time (mean ± σ):      37.9 ms ±   0.4 ms   
  string_concat    python3      Time (mean ± σ):      22.3 ms ±   0.4 ms   
  string_concat    ruby         Time (mean ± σ):      69.9 ms ±   4.5 ms   
  string_concat    luajit       Time (mean ± σ):      10.9 ms ±   1.0 ms   
  string_concat    php83        Time (mean ± σ):      22.3 ms ±   1.8 ms 
```

### Notes
DFkup is built on top of [VanCode, a modular CodeGen, VM and JIT compiler](https://github.com/openpeeps/vancode) written in Nim. The JIT compiler is powered by [GNU GCC JIT](https://gcc.gnu.org/wiki/JIT) using the [libgccjit Nim bindings from here](https://github.com/openpeeps/gccjit.nim).

### ❤ Contributions & Support
- 🐛 Found a bug? [Create a new Issue](https://github.com/dfkup/dfkup/issues)
- 👋 Wanna help? [Fork it!](https://github.com/dfkup/dfkup/fork)

|  |  |
|---|---|
| <a href="https://opencode.ai/go?ref=BHMEEK48QX"><img src="https://github.com/openpeeps/pistachio/blob/main/.github/opencode.png" alt="OpenCode"></a> | Switch to **Open-Source LLMs** via OpenCode GO, choosing from a variety of powerful models such as DeepSeek, Qwen, Kimi, GLM-5, MiniMax, MiMo. 🍕 [Use our referral link to get started!](https://opencode.ai/go?ref=BHMEEK48QX)|

### 🎩 License
LGPLv3 license. [Made by Humans from OpenPeeps](https://github.com/openpeeps).<br>
Copyright OpenPeeps & Contributors &mdash; All rights reserved.
