# DFkup Benchmarks

Multi-language benchmark results for the DFkup scripting language.

Last run: 10/17/2026

## Running the benchmarks

The harness lives in [`tests/bench`](../tests/bench) and needs
[hyperfine](https://github.com/sharkdp/hyperfine) plus the compared
runtimes (`node`, `python3`, `ruby`, `luajit`, `php83`). A built `dfkup`
binary is expected at `bin/dfkup`.

```sh
brew install hyperfine          # or: cargo install hyperfine
cd tests/bench && ./runall.sh
```

Each benchmark exists in every language (`dfkup/`, `js/`, `python/`,
`ruby/`, `lua/`, `php/`), and the harness runs them all through
`hyperfine --warmup 2 --min-runs 3` so the numbers are directly
comparable. A runtime that is missing or crashes is reported as `-` or
`CRASHED` rather than aborting the run.

## Results

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

## Notes

- Numbers are from a single machine; treat them as relative, not
  absolute. Re-run `tests/bench/runall.sh` to refresh this file.
- `CRASHED` means the runtime exceeded the recursion/stack limits for
  that benchmark (not a dfkup failure) — those languages abort on deep
  recursion where dfkup's stack grows on demand.
- The dfkup column is the JIT-compiled path; `--nojit` compares the
  interpreter.

## License

MIT license. Made by Humans from OpenPeeps.
