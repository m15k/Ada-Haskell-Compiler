#!/usr/bin/env bash
# Dogfood example tests: build examples/lisp with AHC, run each
# tests/*.scm (file mode) and tests/*.in (REPL mode, via stdin), and
# compare stdout byte-for-byte against the checked-in .golden.
#
# --oracle regenerates the goldens by running the SAME Haskell source
# under GHC (runghc): the interpreter must behave identically compiled
# by either compiler, so the goldens are GHC's behavior, per house
# rules.
set -u
cd "$(dirname "$0")/.."

GHC="$HOME/.ghcup/bin/runghc"

if [ "${1:-}" = "--oracle" ]; then
  for scm in examples/lisp/tests/*.scm; do
    (cd examples/lisp && "$GHC" Main.hs "tests/$(basename "$scm")") \
      > "${scm%.scm}.golden"
    echo "oracle ${scm%.scm}.golden"
  done
  for inp in examples/lisp/tests/*.in; do
    (cd examples/lisp && "$GHC" Main.hs < "tests/$(basename "$inp")") \
      > "${inp%.in}.golden"
    echo "oracle ${inp%.in}.golden"
  done
  exit 0
fi

scripts/ahc-build.sh examples/lisp/Main.hs examples/lisp/minilisp \
  >/dev/null || { echo "FAIL build examples/lisp"; exit 2; }

fail=0
for scm in examples/lisp/tests/*.scm; do
  if ./examples/lisp/minilisp "$scm" \
       | diff -q - "${scm%.scm}.golden" >/dev/null 2>&1; then
    echo "ok   $scm"
  else
    echo "FAIL $scm"
    fail=1
  fi
done
for inp in examples/lisp/tests/*.in; do
  if ./examples/lisp/minilisp < "$inp" \
       | diff -q - "${inp%.in}.golden" >/dev/null 2>&1; then
    echo "ok   $inp"
  else
    echo "FAIL $inp"
    fail=1
  fi
done
exit $fail
