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

# Every floor here used to be at least 2MB, and that was itself a
# single-cadence blind spot of the kind this script exists to catch:
# the M142 stale-mark bug (a recycled slot handed out still carrying
# a conservative mark) reproduces at 64KB, 256KB and 512KB and at NO
# floor of 1MB or above. A trigger floor below one BLOCK (64KB) is
# clamped by the runtime, so 65536 is the smallest cadence that
# exists - a soak that claims "every trigger setting" has to start
# at the boundary value, not at a comfortable one.
FLOORS="65536 524288 2000000 4000000 8000000 16000000 32000000"
[ "${1:-}" = "--quick" ] && FLOORS="65536 8000000"

# printf a floor the way a human says it
floor_label() {
  if [ "$1" -lt 1048576 ]; then echo "$(($1/1024))KB"; else
    echo "$(($1/1000000))MB"; fi
}

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

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

# Block RECYCLING under a deep stack - the shape the two chains
# above do not reach. Each iteration builds and forces a 20000-deep
# chain, so a collection lands mid-recursion with thousands of dead
# frames still inside the scanned extent; their stale words mark
# free slots on blocks a minor does not sweep, and the next
# adoption hands one of those slots to the mutator. That is the
# M142 bug, and this is the smallest program that reaches it
# reliably (10/10 at the 64KB floor; 100 iterations misses, 120
# catches, so the 200 here is deliberate margin, not decoration).
# It is the slowest program in the soak at ~8s a run: the cost is
# scanning a 20000-frame stack at every one of ~550 collections.
cat > "$tmp/deep_recycle.hs" <<'EOF'
nest :: Int -> Int -> Int
nest 0 seed = seed
nest n seed = 1 + nest (n - 1) seed

loop :: Int -> Int -> IO Int
loop 0 acc = return acc
loop k acc = do
  let v = nest 20000 k
  r <- return $! v
  r2 <- return $! v
  loop (k - 1) (acc + r + r2)

main :: IO ()
main = loop 200 0 >>= print
EOF

# gc_scope_retire.hs retires 400 scopes and their protected-value
# waiters. The runtime structs behind them are re-walked rather than
# barriered, which hid two M150 bugs: a struct registered after its
# registry table aged was never marked, and a retired struct kept
# dangling pointers to young objects (every run failed verification
# before the fix).
progs="$tmp/deep_foldl.hs $tmp/deep_nest.hs $tmp/deep_recycle.hs"
for p in tests/exec/lazy.hs tests/exec/numbers.hs tests/exec/prelude4.hs \
         tests/exec/gc_scope_retire.hs; do
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
  # AHC_OWN_VERIFY makes each run prove that the mark set is CLOSED
  # under points-to, rather than only that the output happened to
  # come out right. Output equality catches a lost object once it
  # changes an answer; closure catches the missed EDGE at the
  # collection that missed it, which is how M115's bug was found.
  # Costs 20-50% of run time - cheap for what it proves.
  for fl in $FLOORS; do
    got=$(AHC_OWN_VERIFY=1 AHC_OWN_MIN=$fl "$tmp/${base}_o" 2>&1)
    [ "$got" = "$ref" ] || bad="$bad $(floor_label $fl)"
    got=$(AHC_OWN_VERIFY=1 AHC_OWN_MIN=$fl AHC_OWN_MAJOR_EVERY=1 \
          "$tmp/${base}_o" 2>&1)
    [ "$got" = "$ref" ] || bad="$bad $(floor_label $fl)/major"
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
