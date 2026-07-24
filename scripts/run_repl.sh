#!/usr/bin/env bash
# REPL transcript tests: feed each tests/repl/*.in to `ahc repl` in
# a fresh fixed scratch directory (fixed so diagnostic paths are
# deterministic) and byte-compare the full stdout+stderr against
# the .out golden. --update regenerates.
set -u
cd "$(dirname "$0")/.."
update=false
[ "${1:-}" = "--update" ] && update=true
[ -x bin/ahc ] || { echo "build first: alr build --validation" >&2; exit 2; }
fail=0
shopt -s nullglob
for tin in tests/repl/*.in; do
  base=$(basename "$tin" .in)
  exp="tests/repl/$base.out"
  dir="/tmp/ahc-repl-test-$base"
  rm -rf "$dir"; mkdir -p "$dir"
  got=$(AHC_REPL_DIR="$dir" ./bin/ahc repl < "$tin" 2>&1)
  rm -rf "$dir"
  if $update; then
    printf '%s\n' "$got" > "$exp"; echo "updated $exp"
  elif [ ! -f "$exp" ]; then
    echo "MISSING $exp (run with --update)"; fail=1
  elif ! diff -u "$exp" <(printf '%s\n' "$got"); then
    echo "FAIL $tin"; fail=1
  else
    echo "ok   $tin"
  fi
done
exit $fail
