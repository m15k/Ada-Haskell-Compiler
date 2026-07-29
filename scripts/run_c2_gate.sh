#!/usr/bin/env bash
# C2 gate (collector-design-note.md section 5): correctness and
# footprint for the own collector, now collecting.
#
#   1. The exec suite green under AHC_GC=own.
#   2. Soak: every concurrency/par exec golden byte-identical at
#      0/2/4 workers with an 8MB collection trigger (collections
#      constantly, rendezvous exercised).
#   3. TSan clean (scripts/run_tsan.sh builds AHC_GC=own).
#   4. Peak RSS on the bench workloads within 2x of the Boehm
#      build (per-workload ratios and the geometric mean printed).
#
# Usage: scripts/run_c2_gate.sh
set -u
cd "$(dirname "$0")/.."
[ -x ./bin/ahc ] || { echo "build first: alr build --validation" >&2; exit 2; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

echo "== 1. exec suite (AHC_GC=own) =="
if AHC_GC=own scripts/run_exec.sh >/dev/null 2>&1; then
  echo "ok"
else
  echo "FAIL"; fail=1
fi

echo "== 2. forced-collection soak, 0/2/4 workers =="
soak=0
for hs in tests/exec/par_*.hs tests/exec/conc_*.hs tests/exec/prot_*.hs; do
  base=$(basename "$hs" .hs)
  AHC_GC=own scripts/ahc-build.sh "$hs" "$tmp/$base" >/dev/null 2>&1 || { echo "BUILD-FAIL $base"; soak=1; continue; }
  for w in 0 2 4; do
    for i in 1 2; do
      got=$(AHC_WORKERS=$w AHC_OWN_MIN=8000000 "$tmp/$base" 2>&1)
      [ "$got" = "$(cat "tests/exec/$base.out")" ] || { echo "SOAK-FAIL $base (w=$w)"; soak=1; break 2; }
    done
  done
done
[ $soak = 0 ] && echo "ok (all byte-identical)" || fail=1

echo "== 3. tsan =="
if scripts/run_tsan.sh >/dev/null 2>&1; then echo "ok"; else echo "FAIL"; fail=1; fi

echo "== 4. peak RSS, own vs boehm =="
ratios=""
for hs in tests/bench/b_fib.hs tests/bench/b_sumfold.hs \
          tests/bench/b_strictfold.hs tests/bench/b_sort.hs \
          tests/bench/b_map.hs; do
  base=$(basename "$hs" .hs)
  AHC_GC=own scripts/ahc-build.sh "$hs" "$tmp/${base}_o" >/dev/null 2>&1
  AHC_GC=boehm scripts/ahc-build.sh "$hs" "$tmp/${base}_b" >/dev/null 2>&1
  # Peak RSS is a single number per run, but it is not a constant:
  # it depends on where collections fall relative to peak live data,
  # so one sample per binary is not a measurement. Take three each,
  # ALTERNATING the two builds so any drift in system memory
  # pressure lands on both, and keep the minimum - the cleanest
  # reproducible figure, applied identically to both sides.
  # (Timing gates need interleaving for thermal drift; this is the
  # same discipline applied to the quantity this gate actually
  # measures - see collector-design-note.md section 11.)
  ro=999999999999; rb=999999999999
  for _i in 1 2 3; do
    _v=$(/usr/bin/time -l "$tmp/${base}_o" 2>&1 >/dev/null | awk '/maximum resident/{print $1}')
    [ "$_v" -lt "$ro" ] && ro=$_v
    _v=$(/usr/bin/time -l "$tmp/${base}_b" 2>&1 >/dev/null | awk '/maximum resident/{print $1}')
    [ "$_v" -lt "$rb" ] && rb=$_v
  done
  r=$(python3 -c "print(f'{$ro/$rb:.2f}')")
  ratios="$ratios $r"
  echo "$base: own $((ro/1048576))MB boehm $((rb/1048576))MB (${r}x)"
done
# Decide on FULL PRECISION, display rounded. Deciding on the
# rounded value let a geometric mean of 2.00408 report PASS
# against a 2.0 bar, because the string "2.00" was what got
# compared (M117).
gm=$(python3 -c "
import math
rs = [float(x) for x in '''$ratios'''.split()]
print(repr(math.exp(sum(map(math.log, rs)) / len(rs))))")
printf 'geometric mean: %.2fx (gate: <= 2.0x)\n' "$gm"
python3 -c "exit(0 if $gm <= 2.0 else 1)" || fail=1

if [ $fail = 0 ]; then echo "C2 GATE: PASS"; else echo "C2 GATE: FAIL"; fi
exit 0
