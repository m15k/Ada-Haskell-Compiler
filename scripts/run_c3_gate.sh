#!/usr/bin/env bash
# C3 gate (collector-design-note.md section 5): the generational
# collector must (a) hold sequential run_bench parity or better
# against the Boehm build - the write barrier must earn its
# branch - and (b) clear the ORIGINAL B1 parallel gate at last:
# >= 1.6x on 2 workers and >= 2.5x on 4, on the own build whose
# recycling allocator can actually feed the workers. Workers
# default ON under AHC_GC=own as of C3.
set -u
cd "$(dirname "$0")/.."
[ -x ./bin/ahc ] || { echo "build first: alr build --validation" >&2; exit 2; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
now_ms() { python3 -c 'import time; print(int(time.time()*1000))'; }

# Run a command with a wall-clock limit. macOS has no timeout(1).
# A hung benchmark used to block a gate indefinitely - 2.5 hours of
# a stuck b_parsort before a human noticed (M119). Now it fails.
AHC_RUN_LIMIT="${AHC_RUN_LIMIT:-300}"
with_limit() {
  ( "$@" ) & local p=$!
  # The watchdog MUST NOT inherit the caller's stdout. If it does
  # and with_limit is used inside $(...), the command substitution
  # waits for the watchdog to exit too - so every call blocks for
  # the full limit even when the command returns instantly, and a
  # 5-minute limit turned C2's RSS loop into a 2.5 hour stall.
  ( sleep "$AHC_RUN_LIMIT"; kill -9 $p 2>/dev/null ) >/dev/null 2>&1 &
  local w=$!
  wait $p 2>/dev/null; local rc=$?
  kill -9 $w 2>/dev/null; wait $w 2>/dev/null
  if [ $rc -eq 137 ]; then
    echo "TIMEOUT after ${AHC_RUN_LIMIT}s: $*" >&2
    return 124
  fi
  return $rc
}

# INTERLEAVED best-of-3. Timing each configuration to completion in
# turn lets machine drift (thermal, background load) masquerade as a
# difference between configurations - which is exactly how an earlier
# revision of this script "measured" 4 workers as slower than 2 when
# interleaving shows it is 10-25% FASTER. run_bench.sh has interleaved
# since M74 for this reason; these gates now do too.
# Usage: interleaved OUTVAR_PREFIX BIN "ENV1" "ENV2" ...
interleaved() {
  local bin=$1; shift
  local n=$#
  local i j cfg t0 t1 dt
  local args=("$@") off k
  IL_RESULT=()
  for j in $(seq 1 $n); do IL_RESULT[$j]=999999999; done
  # Rotate the starting configuration each round. Interleaving alone
  # is not enough: with a fixed order the last configuration in each
  # round is always measured on the hottest machine, which is a
  # systematic bias, not noise. Rotation spreads that penalty evenly.
  for i in $(seq 0 $((n * 2 - 1))); do
    for k in $(seq 0 $((n - 1))); do
      off=$(( (k + i) % n ))
      j=$((off + 1))
      t0=$(now_ms); with_limit env ${args[$off]} "$bin" >/dev/null \
        || { echo "GATE ABORTED: $bin hung"; exit 2; }
      t1=$(now_ms)
      dt=$((t1 - t0))
      [ $dt -lt ${IL_RESULT[$j]} ] && IL_RESULT[$j]=$dt
    done
  done
}

best3() { local bin=$1; shift; local best=999999999 t0 t1 dt i
  for i in 1 2 3; do t0=$(now_ms); env "$@" "$bin" >/dev/null; t1=$(now_ms)
    dt=$((t1 - t0)); [ $dt -lt $best ] && best=$dt; done; echo $best; }

echo "== sequential half (own vs boehm, workers pinned off) =="
ratios=""
seq_ok=1
for hs in tests/bench/b_fib.hs tests/bench/b_sumfold.hs \
          tests/bench/b_strictfold.hs tests/bench/b_sort.hs \
          tests/bench/b_bignum.hs tests/bench/b_map.hs; do
  base=$(basename "$hs" .hs)
  AHC_GC=boehm scripts/ahc-build.sh "$hs" "$tmp/${base}_b" >/dev/null 2>&1 || { echo "BUILD-FAIL $hs"; exit 1; }
  AHC_GC=own scripts/ahc-build.sh "$hs" "$tmp/${base}_o" >/dev/null 2>&1 || { echo "BUILD-FAIL $hs"; exit 1; }
  with_limit "$tmp/${base}_b" > "$tmp/a.txt" \
    || { echo "GATE ABORTED: ${base}_b hung"; exit 2; }
  with_limit env AHC_WORKERS=0 "$tmp/${base}_o" > "$tmp/b.txt" \
    || { echo "GATE ABORTED: ${base}_o hung"; exit 2; }
  cmp -s "$tmp/a.txt" "$tmp/b.txt" || { echo "OUTPUT DIFFERS: $hs"; exit 1; }
  bb=999999999; bo=999999999
  for _i in 1 2 3; do
    _t0=$(now_ms); with_limit "$tmp/${base}_b" >/dev/null \
      || { echo "GATE ABORTED: ${base}_b hung"; exit 2; }
    _t1=$(now_ms)
    _d=$((_t1-_t0)); [ $_d -lt $bb ] && bb=$_d
    _t0=$(now_ms); with_limit env AHC_WORKERS=0 "$tmp/${base}_o" >/dev/null \
      || { echo "GATE ABORTED: ${base}_o hung"; exit 2; }
    _t1=$(now_ms)
    _d=$((_t1-_t0)); [ $_d -lt $bo ] && bo=$_d
  done
  r=$(python3 -c "print(f'{$bo/$bb:.3f}')")
  ratios="$ratios $r"
  echo "$base: boehm ${bb}ms | own ${bo}ms (${r})"
done
# full precision for the decision, rounded for the eye (M117)
gm=$(python3 -c "
import math
rs = [float(x) for x in '''$ratios'''.split()]
print(repr(math.exp(sum(map(math.log, rs)) / len(rs))))")
printf 'sequential geometric mean own/boehm: %.3f (gate: <= 1.00)\n' "$gm"
python3 -c "exit(0 if $gm <= 1.00 else 1)" || seq_ok=0

echo "== parallel half (own build, the original B1 gate) =="
par_ok=1
for hs in tests/bench/b_parfib.hs tests/bench/b_parsort.hs \
          tests/bench/b_parmap.hs; do
  base=$(basename "$hs" .hs)
  AHC_GC=own scripts/ahc-build.sh "$hs" "$tmp/$base" >/dev/null 2>&1 || { echo "BUILD-FAIL $hs"; exit 1; }
  with_limit env AHC_WORKERS=0 "$tmp/$base" > "$tmp/ref.txt" \
    || { echo "GATE ABORTED: $base hung (0 workers)"; exit 2; }
  for w in 2 4; do
    with_limit env AHC_WORKERS=$w "$tmp/$base" > "$tmp/w.txt" \
      || { echo "GATE ABORTED: $base hung ($w workers)"; exit 2; }
    cmp -s "$tmp/ref.txt" "$tmp/w.txt" || { echo "OUTPUT DIFFERS at $w workers: $hs"; exit 1; }
  done
  interleaved "$tmp/$base" "AHC_WORKERS=0" "AHC_WORKERS=2" "AHC_WORKERS=4"
  b0=${IL_RESULT[1]}; b2=${IL_RESULT[2]}; b4=${IL_RESULT[3]}
  s2=$(python3 -c "print(f'{$b0/$b2:.2f}')")
  s4=$(python3 -c "print(f'{$b0/$b4:.2f}')")
  echo "$base: seq ${b0}ms | 2w ${b2}ms (${s2}x) | 4w ${b4}ms (${s4}x)"
  python3 -c "exit(0 if $b0/$b2 >= 1.6 and $b0/$b4 >= 2.5 else 1)" || par_ok=0
done

if [ $seq_ok = 1 ] && [ $par_ok = 1 ]; then
  echo "C3 GATE: PASS"
else
  echo "C3 GATE: FAIL (seq_ok=$seq_ok par_ok=$par_ok)"
fi
exit 0
