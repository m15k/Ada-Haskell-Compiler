#!/usr/bin/env bash
# The spin watchdog and its diagnostic dump, tested by making them
# FIRE ON PURPOSE.
#
# Why this script exists: the watchdog is a trap for a hang that has
# reproduced ONCE in 44 attempts. It runs essentially never, so a
# refactor can break it and nobody would find out until the next
# occurrence - the one time it matters. Both M119 watchdogs were
# wrong on their first attempt, so "it compiles" is not evidence.
#
# The probe sparks a long computation, keeps main busy long enough
# for a worker to CLAIM it, then demands it. With AHC_SPIN_LIMIT=1
# main trips the watchdog while the worker is still legitimately
# computing: a DELIBERATE FALSE POSITIVE, which is the only way to
# exercise the report without reproducing the real bug.
set -u
cd "$(dirname "$0")/.."
[ -x ./bin/ahc ] || { echo "build first: alr build --validation" >&2; exit 2; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
note() { echo "FAIL $*"; fail=1; }

cat > "$tmp/probe.hs" <<'EOF'
import Control.Parallel

slow :: Int -> Int
slow n = if n < 2 then n else slow (n - 1) + slow (n - 2)

main :: IO ()
main = do
  let a = slow 36
      b = slow 27
  a `par` (b `pseq` print (a + b))
EOF

AHC_GC=own scripts/ahc-build.sh "$tmp/probe.hs" "$tmp/probe" >/dev/null 2>&1 \
  || { echo "BUILD-FAIL probe"; exit 1; }

# 1. Armed at 1s: must trip, and the report must IDENTIFY things.
#    A dump that fires but says "UNRECOGNISED" for a known worker
#    would be worse than no dump - it would send the next
#    investigation down a false trail.
out=$(AHC_SPIN_LIMIT=1 AHC_WORKERS=2 "$tmp/probe" 2>&1)
echo "$out" | grep -q "SPIN WATCHDOG"                 || note "armed: no report"
echo "$out" | grep -q "exceeded AHC_SPIN_LIMIT"       || note "armed: did not die"
echo "$out" | grep -q "tag=BLACKHOLE"                 || note "armed: tag not named"
echo "$out" | grep -qE "owner=0x[0-9a-f]+ -> worker #[0-9]+" \
  || note "armed: owner not identified as a worker"
echo "$out" | grep -q "self=.* -> main_task"          || note "armed: self not main"
echo "$out" | grep -q "gc_want="                      || note "armed: no rendezvous state"
echo "$out" | grep -q "sparks: created"               || note "armed: no spark counters"
echo "$out" | grep -qE "deque\[0\] top=[0-9]+"        || note "armed: no deque extents"

# 2 and 3 check that the watchdog does NOT fire on healthy parallel
#    code and that the answer is right. The expected answer is a
#    CONSTANT - slow 36 + slow 27 = fib(36) + fib(27) = 14930352 +
#    196418 - not a second build of the probe: this script used to
#    build and run a Boehm reference silently, and on the arm64 macOS
#    runner that reference was killed (exit 137, out of memory: 30M
#    thunks under a collector the runner cannot afford). Both
#    comparisons then reported a mismatch against an empty string -
#    "got '15126770' want ''" - and four weeks of red CI said nothing
#    about why. A constant cannot be killed, and every other platform
#    checks it too.
ref=15126770

# 2. Default limit (120s): must NOT fire on the same program, and
#    must give the right answer. A watchdog that fires on healthy
#    parallel code is a bug, not a safety net.
got=$(AHC_WORKERS=4 "$tmp/probe" 2>&1)
[ "$got" = "$ref" ] || note "default limit: got '$got' want '$ref'"

# 3. Disabled: must not fire and must still be correct.
got=$(AHC_SPIN_LIMIT=0 AHC_WORKERS=2 "$tmp/probe" 2>&1)
[ "$got" = "$ref" ] || note "limit=0: got '$got' want '$ref'"

# 4. The self-dependency path must still report <<loop>> rather
#    than spinning to the limit - the watchdog must not have
#    swallowed the case the evaluator already diagnosed exactly.
cat > "$tmp/loop.hs" <<'EOF'
main :: IO ()
main = do
  let x = x + (1 :: Int)
  print x
EOF
AHC_GC=own scripts/ahc-build.sh "$tmp/loop.hs" "$tmp/loop" >/dev/null 2>&1 \
  || { echo "BUILD-FAIL loop"; exit 1; }
out=$("$tmp/loop" 2>&1)
echo "$out" | grep -q "<<loop>>" || note "self-loop: no <<loop>> ($out)"

if [ $fail = 0 ]; then echo "WATCHDOG CHECK: PASS"; else echo "WATCHDOG CHECK: FAIL"; fi
exit $fail
