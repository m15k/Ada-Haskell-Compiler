#!/usr/bin/env bash
# Benchmark harness (M74): wall time per program, optimizer on vs
# off, best of 3. Verifies each program's output agrees between the
# two builds before timing. Usage: scripts/run_bench.sh
set -u
cd "$(dirname "$0")/.."
[ -x ./bin/ahc ] || { echo "build first" >&2; exit 2; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

now_ms() { python3 -c 'import time; print(int(time.time()*1000))'; }

# Interleaved best-of-5 with one warmup each: A/B noise (cache,
# thermal) hits both builds equally.
bench_pair() { # progA progB -> "bestA bestA_B"
  local a=$1 b=$2 ba=999999999 bb=999999999 t0 t1 dt
  "$a" >/dev/null; "$b" >/dev/null
  for _ in 1 2 3 4 5; do
    t0=$(now_ms); "$a" >/dev/null; t1=$(now_ms); dt=$((t1-t0))
    [ "$dt" -lt "$ba" ] && ba=$dt
    t0=$(now_ms); "$b" >/dev/null; t1=$(now_ms); dt=$((t1-t0))
    [ "$dt" -lt "$bb" ] && bb=$dt
  done
  echo "$ba $bb"
}

printf '%-14s %9s %9s %8s\n' program no-opt opt speedup
for hs in tests/bench/*.hs; do
  base=$(basename "$hs" .hs)
  AHC_NOOPT=1 scripts/ahc-build.sh "$hs" "$tmp/${base}_n" >/dev/null 2>&1
  scripts/ahc-build.sh "$hs" "$tmp/${base}_o" >/dev/null 2>&1
  if ! diff <("$tmp/${base}_n") <("$tmp/${base}_o") >/dev/null; then
    echo "$base: OUTPUT MISMATCH between opt and no-opt"; exit 1
  fi
  read -r n o <<< "$(bench_pair "$tmp/${base}_n" "$tmp/${base}_o")"
  printf '%-14s %8sms %8sms %7sx\n' "$base" "$n" "$o" \
    "$(python3 -c "print(f'{$n/$o:.2f}')" 2>/dev/null || echo '?')"
done
