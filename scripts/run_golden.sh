#!/usr/bin/env bash
# Golden tests: for every tests/golden/*.hs, compare `ahc lex` output
# (stdout+stderr) against the checked-in .tokens file. Milestone 5 adds
# .ast expectations via `ahc parse`.
#
# Usage: scripts/run_golden.sh [--update]
set -u
cd "$(dirname "$0")/.."

AHC=./bin/ahc
[ -x "$AHC" ] || { echo "build first: alr build --validation" >&2; exit 2; }

update=false
[ "${1:-}" = "--update" ] && update=true

fail=0
shopt -s nullglob
for hs in tests/golden/*.hs; do
  base="${hs%.hs}"
  exp="$base.tokens"
  got="$("$AHC" lex "$hs" 2>&1)"
  if $update; then
    printf '%s\n' "$got" > "$exp"
    echo "updated $exp"
  elif [ ! -f "$exp" ]; then
    echo "MISSING $exp (run with --update)"
    fail=1
  elif ! diff -u "$exp" <(printf '%s\n' "$got"); then
    echo "FAIL $hs"
    fail=1
  else
    echo "ok   $hs"
  fi
done
exit $fail
