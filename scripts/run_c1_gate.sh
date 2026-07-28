#!/usr/bin/env bash
# C1 gate (collector-design-note.md section 5): the own allocator
# in leak mode must prove BOTH halves of the allocation story.
#
#   Parallel: parfib/parsort at 2/4 workers >= 1.8x/2.4x versus
#   the own build's own sequential time (the plain-malloc control
#   measured 2.06x/2.58x - the allocator may cost a little, not a
#   lot).
#
#   Sequential: run_bench workloads under AHC_GC=own within 5% of
#   the AHC_GC=boehm build (geometric mean of ratios).
#
# Interleaved best-of-3 everywhere; outputs verified identical
# before timing. Usage: scripts/run_c1_gate.sh
set -u
cd "$(dirname "$0")/.."
[ -x ./bin/ahc ] || { echo "build first: alr build --validation" >&2; exit 2; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
now_ms() { python3 -c 'import time; print(int(time.time()*1000))'; }

best3() { # binary [env...] -> best ms of 3
  local bin=$1; shift
  local best=999999999 t0 t1 dt i
  for i in 1 2 3; do
    t0=$(now_ms); env "$@" "$bin" >/dev/null; t1=$(now_ms)
    dt=$((t1 - t0)); [ $dt -lt $best ] && best=$dt
  done
  echo $best
}

echo "== parallel half (own build) =="
par_ok=1
for hs in tests/bench/b_parfib.hs tests/bench/b_parsort.hs; do
  base=$(basename "$hs" .hs)
  AHC_GC=own scripts/ahc-build.sh "$hs" "$tmp/$base" >/dev/null 2>&1 || { echo "BUILD-FAIL $hs"; exit 1; }
  AHC_WORKERS=0 "$tmp/$base" > "$tmp/ref.txt"
  for w in 2 4; do
    AHC_WORKERS=$w "$tmp/$base" > "$tmp/w.txt"
    cmp -s "$tmp/ref.txt" "$tmp/w.txt" || { echo "OUTPUT DIFFERS at $w workers: $hs"; exit 1; }
  done
  b0=$(best3 "$tmp/$base" AHC_WORKERS=0)
  b2=$(best3 "$tmp/$base" AHC_WORKERS=2)
  b4=$(best3 "$tmp/$base" AHC_WORKERS=4)
  s2=$(python3 -c "print(f'{$b0/$b2:.2f}')")
  s4=$(python3 -c "print(f'{$b0/$b4:.2f}')")
  echo "$base: seq ${b0}ms | 2w ${b2}ms (${s2}x) | 4w ${b4}ms (${s4}x)"
  python3 -c "exit(0 if $b0/$b2 >= 1.8 and $b0/$b4 >= 2.4 else 1)" || par_ok=0
done

echo "== sequential half (own vs boehm) =="
ratios=""
for hs in tests/bench/b_fib.hs tests/bench/b_sumfold.hs \
          tests/bench/b_strictfold.hs tests/bench/b_sort.hs \
          tests/bench/b_bignum.hs tests/bench/b_map.hs; do
  base=$(basename "$hs" .hs)
  AHC_GC=boehm scripts/ahc-build.sh "$hs" "$tmp/${base}_bo" >/dev/null 2>&1 || { echo "BUILD-FAIL boehm $hs"; exit 1; }
  AHC_GC=own scripts/ahc-build.sh "$hs" "$tmp/${base}_ow" >/dev/null 2>&1 || { echo "BUILD-FAIL own $hs"; exit 1; }
  "$tmp/${base}_bo" > "$tmp/a.txt"; "$tmp/${base}_ow" > "$tmp/b.txt"
  cmp -s "$tmp/a.txt" "$tmp/b.txt" || { echo "OUTPUT DIFFERS: $hs"; exit 1; }
  bb=$(best3 "$tmp/${base}_bo")
  bo=$(best3 "$tmp/${base}_ow")
  r=$(python3 -c "print(f'{$bo/$bb:.3f}')")
  ratios="$ratios $r"
  echo "$base: boehm ${bb}ms | own ${bo}ms (ratio ${r})"
done
gm=$(python3 -c "
import math
rs = [float(x) for x in '''$ratios'''.split()]
print(f'{math.exp(sum(map(math.log, rs)) / len(rs)):.3f}')")
echo "sequential geometric-mean ratio own/boehm: $gm"

seq_ok=$(python3 -c "print(1 if $gm <= 1.05 else 0)")
if [ "$par_ok" = 1 ] && [ "$seq_ok" = 1 ]; then
  echo "C1 GATE: PASS (parallel >= 1.8x/2.4x; sequential gm $gm <= 1.05)"
else
  echo "C1 GATE: FAIL (parallel ok=$par_ok; sequential gm $gm, need <= 1.05)"
fi
exit 0
