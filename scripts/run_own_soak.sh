#!/usr/bin/env bash
# Own-collector correctness soak ACROSS COLLECTION CADENCES.
#
# The gap this closes: every soak in the collector campaign ran at a
# single trigger floor, and a clamp (removed in M114) silently pinned
# that floor to one value for all of them. A live-data-loss bug in the
# tracer survived the whole campaign because the one cadence everyone
# tested happened to be a cadence where it does not bite.
#
# A collector is not correct at one trigger setting; it is correct at
# every trigger setting or it is broken. This runs each program under
# AHC_GC=own at several floors and against the Boehm build, and
# requires byte-identical output from all of them.
#
# Usage: scripts/run_own_soak.sh [--quick]
set -u
cd "$(dirname "$0")/.."
[ -x ./bin/ahc ] || { echo "build first: alr build --validation" >&2; exit 2; }

FLOORS="2000000 4000000 8000000 16000000 32000000"
[ "${1:-}" = "--quick" ] && FLOORS="2000000 8000000"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

# Deep lazy chains are the shape that finds tracer bugs: a long
# spine of live thunks, most of it reachable only from a very deep
# conservative C stack.
cat > "$tmp/deep_foldl.hs" <<'EOF'
main :: IO ()
main = print (foldl (+) 0 [1 .. 100000 :: Int])
EOF
cat > "$tmp/deep_nest.hs" <<'EOF'
build :: Int -> [Int] -> [Int]
build 0 acc = acc
build n acc = build (n - 1) (n : acc)

main :: IO ()
main = print (sum (build 80000 []))
EOF

progs="$tmp/deep_foldl.hs $tmp/deep_nest.hs"
for p in tests/exec/lazy.hs tests/exec/numbers.hs tests/exec/prelude4.hs; do
  [ -f "$p" ] && progs="$progs $p"
done

for hs in $progs; do
  base=$(basename "$hs" .hs)
  AHC_GC=boehm scripts/ahc-build.sh "$hs" "$tmp/${base}_b" >/dev/null 2>&1 \
    || { echo "BUILD-FAIL boehm $base"; fail=1; continue; }
  AHC_GC=own scripts/ahc-build.sh "$hs" "$tmp/${base}_o" >/dev/null 2>&1 \
    || { echo "BUILD-FAIL own $base"; fail=1; continue; }
  ref=$("$tmp/${base}_b" 2>&1)
  bad=""
  for fl in $FLOORS; do
    got=$(AHC_OWN_MIN=$fl "$tmp/${base}_o" 2>&1)
    [ "$got" = "$ref" ] || bad="$bad $((fl/1000000))MB"
    got=$(AHC_OWN_MIN=$fl AHC_OWN_MAJOR_EVERY=1 "$tmp/${base}_o" 2>&1)
    [ "$got" = "$ref" ] || bad="$bad $((fl/1000000))MB/major"
  done
  if [ -n "$bad" ]; then
    echo "FAIL $base: output differs from Boehm at floors:$bad"
    fail=1
  else
    echo "ok   $base (all floors, minor and major cadences)"
  fi
done

if [ $fail = 0 ]; then echo "OWN SOAK: PASS"; else echo "OWN SOAK: FAIL"; fi
exit $fail
