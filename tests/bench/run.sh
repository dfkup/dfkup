#!/bin/bash
set -e
BENCH_DIR="$(cd "$(dirname "$0")" && pwd)"
DFKUP_BIN="$BENCH_DIR/../../bin/dfkup"

command -v hyperfine >/dev/null 2>&1 || { echo "hyperfine required"; exit 1; }

BENCHMARKS="fib_recursive nested_loops prime_sieve string_concat"

echo ""
echo "## dfkup Benchmark Results"
echo ""
echo "| Benchmark | dfkup |"
echo "|-----------|-------|"

for B in $BENCHMARKS; do
  FILE="$BENCH_DIR/dfkup/$B.dfkup"
  echo "  $B..." >&2
  RAW=$(hyperfine --warmup 2 --min-runs 3 --ignore-failure "$DFKUP_BIN run $FILE" 2>&1) || true
  if echo "$RAW" | grep -q "Ignoring non-zero exit code"; then
    echo "| $B | CRASHED |"
  else
    T=$(echo "$RAW" | grep "Time.*mean" | head -1 | sed 's/.*Time(mean.s.): *//;s/ *\[User.*//')
    if [ -z "$T" ]; then
      echo "| $B | FAILED |"
    else
      echo "| $B | $T |"
    fi
  fi
done
