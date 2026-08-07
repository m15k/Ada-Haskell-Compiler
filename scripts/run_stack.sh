#!/usr/bin/env bash
# Main-stack harness (M133): the main thread's depth budget belongs
# to the RUNTIME, not the linker.
#
# Deep lazy chains evaluate by C recursion. Only Darwin's linker
# could ever grow the main stack (GNU ld ignores -z stacksize -
# Linux sizes it from RLIMIT_STACK at exec), so on Linux a
# million-deep thunk chain died at the default 8MB. Since M133,
# ahc_run_main swaps onto a 1GB mmap'd reservation behind a guard
# page - the machinery green threads have used since M102 - on
# EVERY platform, which is also what deleted the per-OS/per-arch
# link flags (and arm64's 512MB linker cap).
#
#   1. a 2M-deep foldl chain evaluates on the default reservation
#      (the b_sumfold shape that sat exactly at the old 512MB edge);
#   2. AHC_MAIN_STACK=2MB shrinks it, and the overflow is a CLEAN
#      one-line report with exit 1 - a guard-page trap, never a
#      silent SIGSEGV (made to fire on purpose, run_watchdog style);
#   3. a sub-floor AHC_MAIN_STACK is ignored (floor 1MB), so a typo
#      cannot produce an unbootable program.
set -u
cd "$(dirname "$0")/.."
[ -x ./bin/ahc ] || { echo "build first: alr build --validation" >&2; exit 2; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
step()  { echo "ok   $1"; }
flunk() { echo "FAIL $1"; fail=1; }

cat > "$tmp/Deep.hs" <<'PROG'
main :: IO ()
main = print (sum [1 .. 2000000 :: Integer])
PROG
./bin/ahc build "$tmp/Deep.hs" "$tmp/deep" >/dev/null 2>&1 \
  || { flunk "build"; exit 1; }

# 1. the default reservation carries a 2M-deep chain
if [ "$("$tmp/deep")" = "2000001000000" ]
then step "2M-deep foldl chain on the default main stack"
else flunk "deep chain on default stack"; fi

# 2. a shrunk stack overflows CLEANLY: one line, exit 1
out=$(AHC_MAIN_STACK=2097152 "$tmp/deep" 2>&1); rc=$?
if [ $rc -eq 1 ] && [ "$out" = "ahc: stack overflow" ]
then step "2MB stack: clean overflow report, exit 1"
else flunk "shrunk stack (rc=$rc, out=[$out])"; fi

# 3. sub-floor values are ignored, not obeyed
if [ "$(AHC_MAIN_STACK=1 "$tmp/deep")" = "2000001000000" ]
then step "sub-floor AHC_MAIN_STACK ignored (floor 1MB)"
else flunk "sub-floor override"; fi

[ $fail -eq 0 ] && echo "main-stack harness: all green"
exit $fail
