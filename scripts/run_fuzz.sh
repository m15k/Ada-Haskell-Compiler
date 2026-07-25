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
#   SLOW-ORACLE  - GHC exceeded its time budget: the seed is SKIPPED
#                  (an expensive program, not a compiler fault)
#   SLOW-AHC     - GHC finished but the AHC-compiled program (or the
#                  build) blew its budget: a finding worth eyeballing
#
# Every external step runs under a time limit, so no generated
# program can wedge a campaign (one 3^n recursion once held three
# oracle processes at 100% CPU for six hours). Budgets in seconds,
# overridable: T_GEN, T_ORACLE, T_BUILD, T_RUN.
set -u
cd "$(dirname "$0")/.."
COUNT="${1:-50}"; START="${2:-1}"
RUNGHC="${RUNGHC:-$HOME/.ghcup/bin/runghc}"
# GEN_BIN: a ghc-compiled Gen binary (see run_fuzz_par.sh) makes
# generation ~20x faster than runghc interpretation.
GEN="${GEN_BIN:-}"
T_GEN="${T_GEN:-60}"; T_ORACLE="${T_ORACLE:-60}"
T_BUILD="${T_BUILD:-180}"; T_RUN="${T_RUN:-120}"

# macOS has no timeout(1); perl's alarm is portable. A process
# killed by SIGALRM exits 142.
lim () { local secs="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$secs" "$@"; }
TIMED_OUT=142
[ -x bin/ahc ] || { echo "build first: alr build --validation" >&2; exit 2; }
[ -x "$RUNGHC" ] || { echo "runghc not found at $RUNGHC" >&2; exit 2; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
found=0

save () {  # $1 seed  $2 kind
  mkdir -p tests/fuzz-failures
  local base="tests/fuzz-failures/seed_$1"
  cp "$tmp/prog.hs" "$base.hs"
  # Provenance stamp: a saved failure is only meaningful against
  # the compiler that produced it (a resumed orphan job once left
  # a ghost artifact from a mid-milestone binary).
  { ./bin/ahc --version; git rev-parse HEAD 2>/dev/null; date; } \
    > "$base.info"
  [ -f "$tmp/ghc.out" ] && cp "$tmp/ghc.out" "$base.ghc.out"
  [ -f "$tmp/ahc.out" ] && cp "$tmp/ahc.out" "$base.ahc.out"
  [ -s "$tmp/ahc.err" ] && cp "$tmp/ahc.err" "$base.ahc.err"
  python3 scripts/shrink_fuzz.py "$base.hs" "$2" >/dev/null \
    && echo "             shrunk: $base.min.hs"
}

for ((seed=START; seed<START+COUNT; seed++)); do
  rm -f "$tmp/ghc.out" "$tmp/ahc.out"; : > "$tmp/ahc.err"
  if ! lim "$T_GEN" ${GEN:-"$RUNGHC" tests/fuzz/Gen.hs} "$seed" \
       > "$tmp/prog.hs" 2>"$tmp/gen.err"; then
    echo "GEN-FAIL     seed $seed"; found=1; continue
  fi
  lim "$T_ORACLE" "$RUNGHC" "$tmp/prog.hs" > "$tmp/ghc.out" 2>"$tmp/ghc.err"
  grc=$?
  if [ $grc -eq $TIMED_OUT ]; then
    echo "SLOW-ORACLE  seed $seed (skipped)"; continue
  elif [ $grc -ne 0 ]; then
    echo "GEN-ILLTYPED seed $seed"; save "$seed" illtyped; found=1; continue
  fi
  lim "$T_BUILD" scripts/ahc-build.sh "$tmp/prog.hs" "$tmp/prog" \
    >/dev/null 2>"$tmp/ahc.err"
  brc=$?
  if [ $brc -eq $TIMED_OUT ]; then
    echo "SLOW-AHC     seed $seed (build)"; save "$seed" slow; found=1; continue
  elif [ $brc -ne 0 ]; then
    echo "AHC-REJECT   seed $seed"; save "$seed" reject; found=1; continue
  fi
  lim "$T_RUN" "$tmp/prog" > "$tmp/ahc.out" 2>&1; arc=$?
  if [ $arc -eq $TIMED_OUT ]; then
    echo "SLOW-AHC     seed $seed (run)"; save "$seed" slow; found=1; continue
  fi
  if [ $arc -ne 0 ] || ! cmp -s "$tmp/ghc.out" "$tmp/ahc.out"; then
    echo "MISMATCH     seed $seed"; save "$seed" mismatch; found=1; continue
  fi
  echo "ok           seed $seed"
done
exit $found
