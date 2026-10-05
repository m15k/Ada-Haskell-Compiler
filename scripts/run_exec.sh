#!/usr/bin/env bash
# End-to-end execution tests: compile tests/exec/*.hs with the full
# AHC pipeline (Haskell -> C -> clang) and compare stdout against the
# checked-in .out goldens. --update regenerates. A tests/exec/NAME.env
# sidecar (VAR=value per line) sets the program's environment - e.g.
# AHC_MAIN_STACK for a constant-stack test (M146).
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
  envs=()
  if [ -f "tests/exec/$base.env" ]; then
    while IFS= read -r kv; do [ -n "$kv" ] && envs+=("$kv"); done < "tests/exec/$base.env"
  fi
  if [ -f "tests/exec/$base.stdin" ]; then
    got=$(env ${envs[@]+"${envs[@]}"} "$tmp/$base" < "tests/exec/$base.stdin" 2>&1)
  else
    got=$(env ${envs[@]+"${envs[@]}"} "$tmp/$base" 2>&1)
  fi
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
