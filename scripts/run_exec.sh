#!/usr/bin/env bash
# End-to-end execution tests: compile tests/exec/*.hs with the full
# AHC pipeline (Haskell -> C -> clang) and compare stdout against the
# checked-in .out goldens. --update regenerates.
set -u
cd "$(dirname "$0")/.."
update=false
[ "${1:-}" = "--update" ] && update=true
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
shopt -s nullglob
for hs in tests/exec/*.hs; do
  base=$(basename "$hs" .hs)
  exp="tests/exec/$base.out"
  if ! scripts/ahc-build.sh "$hs" "$tmp/$base" >/dev/null 2>"$tmp/err"; then
    echo "BUILD-FAIL $hs"; sed 's/^/  /' "$tmp/err" | head -5; fail=1; continue
  fi
  got=$("$tmp/$base" 2>&1)
  if $update; then
    printf '%s\n' "$got" > "$exp"; echo "updated $exp"
  elif [ ! -f "$exp" ]; then
    echo "MISSING $exp (run with --update)"; fail=1
  elif ! diff -u "$exp" <(printf '%s\n' "$got"); then
    echo "FAIL $hs"; fail=1
  else
    echo "ok   $hs"
  fi
done
exit $fail
