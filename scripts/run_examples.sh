#!/usr/bin/env bash
# Dogfood example tests: build examples/lisp and examples/json with
# AHC, run their tests/ inputs (file mode, stdin mode, and json's
# --stats mode), and compare stdout byte-for-byte against the
# checked-in .golden.
#
# --oracle regenerates the goldens by running the SAME Haskell source
# under GHC (runghc): the programs must behave identically compiled
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
  for js in examples/json/tests/*.json; do
    (cd examples/json && "$GHC" Main.hs "tests/$(basename "$js")") \
      > "${js%.json}.golden"
    (cd examples/json && "$GHC" Main.hs --stats \
       "tests/$(basename "$js")") > "${js%.json}.stats.golden"
    echo "oracle ${js%.json}.golden (+stats)"
  done
  for inp in examples/json/tests/*.in; do
    (cd examples/json && "$GHC" Main.hs < "tests/$(basename "$inp")") \
      > "${inp%.in}.golden"
    echo "oracle ${inp%.in}.golden"
  done
  for inp in examples/hm/tests/*.in; do
    (cd examples/hm && "$GHC" Main.hs < "tests/$(basename "$inp")") \
      > "${inp%.in}.golden"
    echo "oracle ${inp%.in}.golden"
  done
  for inp in examples/fibs/tests/*.in; do
    (cd examples/fibs && "$GHC" fastfibinwest.hs \
       < "tests/$(basename "$inp")") > "${inp%.in}.golden"
    echo "oracle ${inp%.in}.golden"
  done
  (cd examples/fibs && "$GHC" fastfibinwest.hs 0 1 92 93 100) \
    > examples/fibs/tests/args.golden
  echo "oracle examples/fibs/tests/args.golden"
  # examples/cal is AHC-only by construction: the contract pragmas are
  # portable, but the refinement surface (Int in 1 .. 31, Int mod 7,
  # Int satisfying isLeapYear) is an extension GHC cannot parse. Its
  # goldens are AHC's own output; regenerate with --update-cal.
  echo "skip   examples/cal (refinement surface has no GHC oracle)"
  exit 0
fi

if [ "${1:-}" = "--update-cal" ]; then
  scripts/ahc-build.sh examples/cal/Main.hs examples/cal/ahccal \
    >/dev/null || { echo "FAIL build examples/cal"; exit 2; }
  for inp in examples/cal/tests/*.in; do
    ./examples/cal/ahccal < "$inp" > "${inp%.in}.golden"
    echo "updated ${inp%.in}.golden"
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

scripts/ahc-build.sh examples/json/Main.hs examples/json/ajson \
  >/dev/null || { echo "FAIL build examples/json"; exit 2; }

for js in examples/json/tests/*.json; do
  if ./examples/json/ajson "$js" \
       | diff -q - "${js%.json}.golden" >/dev/null 2>&1; then
    echo "ok   $js"
  else
    echo "FAIL $js"
    fail=1
  fi
  if ./examples/json/ajson --stats "$js" \
       | diff -q - "${js%.json}.stats.golden" >/dev/null 2>&1; then
    echo "ok   $js (--stats)"
  else
    echo "FAIL $js (--stats)"
    fail=1
  fi
done
for inp in examples/json/tests/*.in; do
  if ./examples/json/ajson < "$inp" \
       | diff -q - "${inp%.in}.golden" >/dev/null 2>&1; then
    echo "ok   $inp"
  else
    echo "FAIL $inp"
    fail=1
  fi
done

scripts/ahc-build.sh examples/hm/Main.hs examples/hm/microhm \
  >/dev/null || { echo "FAIL build examples/hm"; exit 2; }

for inp in examples/hm/tests/*.in; do
  if ./examples/hm/microhm < "$inp" \
       | diff -q - "${inp%.in}.golden" >/dev/null 2>&1; then
    echo "ok   $inp"
  else
    echo "FAIL $inp"
    fail=1
  fi
done

scripts/ahc-build.sh examples/fibs/fastfibinwest.hs examples/fibs/fastfib \
  >/dev/null || { echo "FAIL build examples/fibs"; exit 2; }

for inp in examples/fibs/tests/*.in; do
  if ./examples/fibs/fastfib < "$inp" \
       | diff -q - "${inp%.in}.golden" >/dev/null 2>&1; then
    echo "ok   $inp"
  else
    echo "FAIL $inp"
    fail=1
  fi
done
if ./examples/fibs/fastfib 0 1 92 93 100 \
     | diff -q - examples/fibs/tests/args.golden >/dev/null 2>&1; then
  echo "ok   examples/fibs (argument mode)"
else
  echo "FAIL examples/fibs (argument mode)"
  fail=1
fi

#  examples/cal - the value-constraint example. AHC-only (see its
#  README), so the goldens are AHC's output; beyond the transcripts
#  this block asserts what no other example can: that declared
#  constraints actually fire, and that --unchecked strips the claims
#  without changing a single answer.
scripts/ahc-build.sh examples/cal/Main.hs examples/cal/ahccal \
  >/dev/null || { echo "FAIL build examples/cal"; exit 2; }

for inp in examples/cal/tests/*.in; do
  if ./examples/cal/ahccal < "$inp" \
       | diff -q - "${inp%.in}.golden" >/dev/null 2>&1; then
    echo "ok   $inp"
  else
    echo "FAIL $inp"
    fail=1
  fi
done

#  Constraint violations: message on stderr, nonzero exit. Each is a
#  different half of the extension.
check_violation() {  # label, expected-fragment, args...
  local label="$1" want="$2"; shift 2
  local got rc
  got=$(./examples/cal/ahccal "$@" 2>&1 >/dev/null); rc=$?
  if [ "$rc" -ne 0 ] && [ "${got#*"$want"}" != "$got" ]; then
    echo "ok   cal violation: $label"
  else
    echo "FAIL cal violation: $label (rc=$rc, got '$got')"
    fail=1
  fi
}
check_violation "year range"   "not in 1900 .. 2400"        2500-01-01
check_violation "predicate"    "predicate rejected 2027"    --leapday 2027
check_violation "offset range" "not in -12 .. 14"           --zone 19.5 2026-07-25 13:30
check_violation "mkDate pre"   "precondition of 'mkDate'"   2026-02-31

#  Ada's assertion policy: --unchecked strips every claim and every
#  check, and answers on valid input are untouched - which also pins
#  that modular normalization SURVIVES, since --zone would otherwise
#  print a negative clock.
unchecked=$(mktemp -d); trap 'rm -rf "$unchecked"' EXIT
if AHC_UNCHECKED=1 scripts/ahc-build.sh examples/cal/Main.hs \
     "$unchecked/ahccal" >/dev/null 2>&1; then
  for inp in examples/cal/tests/*.in; do
    if "$unchecked/ahccal" < "$inp" \
         | diff -q - "${inp%.in}.golden" >/dev/null 2>&1; then
      echo "ok   $inp (--unchecked)"
    else
      echo "FAIL $inp (--unchecked changed an answer)"
      fail=1
    fi
  done
else
  echo "FAIL build examples/cal --unchecked"
  fail=1
fi
exit $fail
