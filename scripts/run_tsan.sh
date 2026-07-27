#!/usr/bin/env bash
# ThreadSanitizer acceptance for the B1 thunk protocol (design note
# 7.3): the memory model gets a sanitizer, not just a benchmark.
# Builds the par exec tests WITHOUT the collector (TSan and Boehm's
# stop-the-world do not mix) and with -fsanitize=thread, runs each
# several times under a full worker pool, and fails on any TSan
# report. The par tests never switch green contexts, so TSan's
# non-understanding of ucontext never comes up.
set -u
cd "$(dirname "$0")/.."
[ -x ./bin/ahc ] || { echo "build first: alr build --validation" >&2; exit 2; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
for hs in tests/exec/par_fib.hs tests/exec/par_shared.hs \
          tests/exec/par_error.hs; do
  base=$(basename "$hs" .hs)
  ./bin/ahc emit "$hs" "$tmp/$base" >/dev/null || { echo "EMIT-FAIL $hs"; fail=1; continue; }
  clang -O1 -g -fsanitize=thread \
    -Wno-incompatible-library-redeclaration -Wno-deprecated-declarations \
    -I runtime -I "$tmp/$base.build" \
    runtime/ahc_rts.c "$tmp/$base.build"/*.c -o "$tmp/$base" \
    || { echo "CC-FAIL $hs"; fail=1; continue; }
  clean=1
  for i in 1 2 3; do
    AHC_WORKERS=4 "$tmp/$base" > "$tmp/out.txt" 2>&1
    if grep -q "WARNING: ThreadSanitizer" "$tmp/out.txt"; then
      clean=0
      echo "TSAN $hs (run $i):"
      grep -m1 -A6 "WARNING: ThreadSanitizer" "$tmp/out.txt" | sed 's/^/  /'
      break
    fi
  done
  if [ $clean = 1 ]; then echo "ok   $hs (3 runs, tsan clean)"; else fail=1; fi
done
exit $fail
