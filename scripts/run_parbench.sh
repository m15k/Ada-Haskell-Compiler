#!/usr/bin/env bash
# B1 gate benchmark (design note 7.6): wall time for the par
# workloads at AHC_WORKERS=0 / 2 / 4, outputs verified identical
# across settings first, interleaved best-of-3 per setting so noise
# hits every arm equally, spark stats alongside - a speedup number
# without a fizzle rate is how spark pools rot.
#
# Gate: >= 1.6x on 2 workers and >= 2.5x on 4, both workloads.
# Usage: scripts/run_parbench.sh
set -u
cd "$(dirname "$0")/.."
[ -x ./bin/ahc ] || { echo "build first: alr build --validation" >&2; exit 2; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
now_ms() { python3 -c 'import time; print(int(time.time()*1000))'; }

gate_ok=1
for hs in tests/bench/b_parfib.hs tests/bench/b_parsort.hs; do
  base=$(basename "$hs" .hs)
  scripts/ahc-build.sh "$hs" "$tmp/$base" >/dev/null 2>&1 || { echo "BUILD-FAIL $hs"; exit 1; }

  AHC_WORKERS=0 "$tmp/$base" > "$tmp/ref.txt"
  for w in 2 4; do
    AHC_WORKERS=$w "$tmp/$base" > "$tmp/w.txt"
    cmp -s "$tmp/ref.txt" "$tmp/w.txt" || { echo "OUTPUT DIFFERS at $w workers: $hs"; exit 1; }
  done

  b0=999999999; b2=999999999; b4=999999999
  for i in 1 2 3; do
    for w in 0 2 4; do
      t0=$(now_ms); AHC_WORKERS=$w "$tmp/$base" >/dev/null; t1=$(now_ms)
      dt=$((t1 - t0))
      case $w in
        0) [ $dt -lt $b0 ] && b0=$dt ;;
        2) [ $dt -lt $b2 ] && b2=$dt ;;
        4) [ $dt -lt $b4 ] && b4=$dt ;;
      esac
    done
  done

  s2=$(python3 -c "print(f'{$b0/$b2:.2f}')")
  s4=$(python3 -c "print(f'{$b0/$b4:.2f}')")
  stats=$(AHC_SPARK_STATS=1 AHC_WORKERS=4 "$tmp/$base" 2>&1 >/dev/null | tail -1)
  echo "$base: seq ${b0}ms | 2w ${b2}ms (${s2}x) | 4w ${b4}ms (${s4}x)"
  echo "  $stats"
  python3 -c "exit(0 if $b0/$b2 >= 1.6 and $b0/$b4 >= 2.5 else 1)" || gate_ok=0
done

if [ $gate_ok = 1 ]; then
  echo "B1 GATE: PASS (>= 1.6x on 2 workers, >= 2.5x on 4)"
else
  echo "B1 GATE: FAIL"
fi
exit 0
