#!/usr/bin/env bash
# Differential fuzzer: seeded random well-typed Haskell 2010 programs
# (tests/fuzz/Gen.hs), compiled by AHC and interpreted by GHC, stdout
# compared byte for byte. Every divergence is saved with both outputs
# to tests/fuzz-failures/ and auto-shrunk (scripts/shrink_fuzz.py).
#
#   scripts/run_fuzz.sh [COUNT] [START_SEED]     (default 50, from 1)
#
# Outcomes per seed:
#   ok           - both ran, byte-identical stdout
#   MISMATCH     - both compiled; stdout differs or AHC exit nonzero
#   AHC-REJECT   - GHC accepts the program, AHC does not (a real
#                  finding: the generator emits only verified-subset
#                  constructs)
#   GEN-ILLTYPED - GHC rejects the generated program (generator bug)
#   GEN-FAIL     - the generator itself crashed (generator bug)
set -u
cd "$(dirname "$0")/.."
COUNT="${1:-50}"; START="${2:-1}"
RUNGHC="${RUNGHC:-$HOME/.ghcup/bin/runghc}"
[ -x bin/ahc ] || { echo "build first: alr build --validation" >&2; exit 2; }
[ -x "$RUNGHC" ] || { echo "runghc not found at $RUNGHC" >&2; exit 2; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
found=0

save () {  # $1 seed  $2 kind
  mkdir -p tests/fuzz-failures
  local base="tests/fuzz-failures/seed_$1"
  cp "$tmp/prog.hs" "$base.hs"
  [ -f "$tmp/ghc.out" ] && cp "$tmp/ghc.out" "$base.ghc.out"
  [ -f "$tmp/ahc.out" ] && cp "$tmp/ahc.out" "$base.ahc.out"
  [ -s "$tmp/ahc.err" ] && cp "$tmp/ahc.err" "$base.ahc.err"
  python3 scripts/shrink_fuzz.py "$base.hs" "$2" >/dev/null \
    && echo "             shrunk: $base.min.hs"
}

for ((seed=START; seed<START+COUNT; seed++)); do
  rm -f "$tmp/ghc.out" "$tmp/ahc.out"; : > "$tmp/ahc.err"
  if ! "$RUNGHC" tests/fuzz/Gen.hs "$seed" > "$tmp/prog.hs" 2>"$tmp/gen.err"; then
    echo "GEN-FAIL     seed $seed"; found=1; continue
  fi
  if ! "$RUNGHC" "$tmp/prog.hs" > "$tmp/ghc.out" 2>"$tmp/ghc.err"; then
    echo "GEN-ILLTYPED seed $seed"; save "$seed" illtyped; found=1; continue
  fi
  if ! scripts/ahc-build.sh "$tmp/prog.hs" "$tmp/prog" >/dev/null 2>"$tmp/ahc.err"; then
    echo "AHC-REJECT   seed $seed"; save "$seed" reject; found=1; continue
  fi
  "$tmp/prog" > "$tmp/ahc.out" 2>&1; arc=$?
  if [ $arc -ne 0 ] || ! cmp -s "$tmp/ghc.out" "$tmp/ahc.out"; then
    echo "MISMATCH     seed $seed"; save "$seed" mismatch; found=1; continue
  fi
  echo "ok           seed $seed"
done
exit $found
