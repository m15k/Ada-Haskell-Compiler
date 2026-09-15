#!/usr/bin/env bash
# The gate: the four suites every change has to clear, run so that a
# failure is IMPOSSIBLE to miss.
#
#   scripts/run_gate.sh                 all of it
#   scripts/run_gate.sh unit golden     only those
#
# Why this exists rather than a line of shell per suite: running a
# suite through a filter - `run_golden.sh | tail -3` - reports the
# FILTER's exit status, not the suite's, because that is what the
# exit status of a pipeline is. Gates run that way looked green while
# conformance had a BUILD-FAIL scrolled past the tail and the Core
# goldens went two commits stale. Every suite here runs unpiped, its
# rc is captured directly, and only a failing suite prints output.
set -u
cd "$(dirname "$0")/.."
[ -x ./bin/ahc ] || { echo "build first: cd tests && alr build" >&2; exit 2; }
[ -x ./tests/bin/ahc_tests ] \
  || { echo "build first: cd tests && alr build" >&2; exit 2; }

fail=0

#  Run one suite, print its rc, and on failure show the lines that
#  are not per-test "ok" noise.
run_suite() {
  local name=$1; shift
  local out rc
  out=$("$@" 2>&1); rc=$?
  printf '%-16s rc=%s\n' "$name" "$rc"
  if [ $rc -ne 0 ]; then
    #  Truncated at 200 columns: one line of a Core golden diff is
    #  the whole elaborated Prelude on a single line, and dumping it
    #  raw buries every other failure in the run.
    printf '%s\n' "$out" | grep -Ev '^ok ' | cut -c1-200 | head -40
    fail=1
  fi
  return 0
}

#  No arguments means every suite; otherwise only the ones named.
selected=("$@")

has() {
  local w=$1 s
  [ ${#selected[@]} -eq 0 ] && return 0
  for s in "${selected[@]}"; do [ "$s" = "$w" ] && return 0; done
  return 1
}

has unit        && run_suite unit        ./tests/bin/ahc_tests
has conformance && run_suite conformance ./scripts/run_conformance.sh
has exec        && run_suite exec        ./scripts/run_exec.sh
#  Both collectors: an exec test can pass under Boehm and fail under
#  the generational one (a missing write barrier shows up nowhere
#  else), so the own-GC pass is not optional.
has exec-own    && AHC_GC=own run_suite exec-own ./scripts/run_exec.sh
has golden      && run_suite golden      ./scripts/run_golden.sh

if [ $fail -eq 0 ]; then
  echo "GATE ok"
else
  #  The Core goldens are a dump of the whole elaborated Prelude, so
  #  any Prelude change moves them. To tell a legitimate regeneration
  #  from a regression, compare the SETS of top-level binding names:
  #    names() { grep -o '^(bind[a-z]* (\$\?[^ ]*' "$1" \
  #                | sed 's/^(bind[a-z]* (//; s/_[0-9]*$//' | sort -u; }
  #    diff <(names tests/golden/X.core) <(names /tmp/new.core)
  #  Only additions you can name means --update is safe.
  echo "GATE FAILED"
fi
exit $fail
