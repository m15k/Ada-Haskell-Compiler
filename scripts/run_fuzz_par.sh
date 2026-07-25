#!/usr/bin/env bash
# Deep fuzz campaign: split a seed range across parallel jobs.
#
#   scripts/run_fuzz_par.sh [TOTAL] [JOBS] [START]   (default 1000 8 1)
#
# Compiles the generator once (GEN_BIN), then runs JOBS instances of
# run_fuzz.sh over disjoint ranges. Divergences land in
# tests/fuzz-failures/ as usual (seed-named, so jobs never collide).
# Exit 0 iff every seed agreed.
set -u
cd "$(dirname "$0")/.."
TOTAL="${1:-1000}"; JOBS="${2:-8}"; START="${3:-1}"
RUNGHC="${RUNGHC:-$HOME/.ghcup/bin/runghc}"
GHC_BIN="${GHC_BIN:-$HOME/.ghcup/bin/ghc}"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

"$GHC_BIN" -O0 -o "$tmp/gen" -outputdir "$tmp/genbuild" \
  tests/fuzz/Gen.hs >/dev/null 2>&1 \
  || { echo "cannot compile Gen.hs" >&2; exit 2; }

per=$(( (TOTAL + JOBS - 1) / JOBS ))
pids=""
for ((j = 0; j < JOBS; j++)); do
  s=$((START + j * per))
  n=$per
  if ((s + n > START + TOTAL)); then n=$((START + TOTAL - s)); fi
  ((n <= 0)) && break
  GEN_BIN="$tmp/gen" scripts/run_fuzz.sh "$n" "$s" \
    > "$tmp/job$j.log" 2>&1 &
  pids="$pids $!"
done

fail=0
for p in $pids; do
  wait "$p" || fail=1
done
cat "$tmp"/job*.log | awk '{print $1}' | sort | uniq -c
cat "$tmp"/job*.log | grep -E "MISMATCH|REJECT|ILLTYPED|GEN-FAIL" || true
exit $fail
