#!/bin/bash
set -e
BENCH_DIR="$(cd "$(dirname "$0")" && pwd)"
DFKUP_BIN="$BENCH_DIR/../../bin/dfkup"

command -v hyperfine >/dev/null 2>&1 || { echo "hyperfine required"; exit 1; }

BENCHMARKS="fib_recursive nested_loops prime_sieve string_concat"
HYPF="hyperfine --warmup 2 --min-runs 3"

echo ""
echo "## Multi-Language Benchmark Results"
echo ""

run_one() {
  local bench=$1 lang=$2 cmd=$3 file=$4
  if ! command -v "$(echo "$cmd" | awk '{print $1}')" >/dev/null 2>&1; then
    printf "  %-16s %-10s   -\n" "$bench" "$lang"
    return
  fi
  if [ ! -f "$file" ]; then
    printf "  %-16s %-10s   -\n" "$bench" "$lang"
    return
  fi
  local raw
  raw=$($HYPF "$cmd $file" 2>&1)
  local line
  line=$(echo "$raw" | grep "Time.*mean" | head -1 | sed 's/ \[User.*//')
  printf "  %-16s %-10s %s\n" "$bench" "$lang" "$line"
}

for B in $BENCHMARKS; do
  echo "$B:"
  run_one "$B" "dfkup"   "$DFKUP_BIN run"         "$BENCH_DIR/dfkup/$B.dfkup"
  run_one "$B" "node"    "node"                    "$BENCH_DIR/js/$B.js"
  run_one "$B" "python3" "python3"                 "$BENCH_DIR/python/$B.py"
  run_one "$B" "ruby"    "ruby"                    "$BENCH_DIR/ruby/$B.rb"
  run_one "$B" "luajit"  "luajit"                  "$BENCH_DIR/lua/$B.lua"
  run_one "$B" "php83"   "php83"                   "$BENCH_DIR/php/$B.php"
  echo ""
done
