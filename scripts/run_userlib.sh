#!/usr/bin/env bash
# Which Prelude a module sees depends on WHICH file it is (M144b): a file
# under the compiler's own lib/ or $AHC_LIB is base's internals and sees
# the whole Prelude, anything else - a project's ./lib included, however
# it was found - sees GHC's export list.
set -u
cd "$(dirname "$0")/.."
[ -x bin/ahc ] || { echo "build first: alr build --validation" >&2; exit 2; }
ROOT=$(pwd)
AHC=$ROOT/bin/ahc
fail=0
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# expect_reject NAME DIR FILE WANT [ENV=VAL...]
expect_reject() {
  local name=$1 dir=$2 file=$3 want=$4; shift 4
  if (cd "$dir" && env "$@" "$AHC" check "$file" >"$tmp/out" 2>&1); then
    echo "FAIL $name: accepted"; fail=1
  elif grep -Fq -- "$want" "$tmp/out"; then echo "ok   $name"
  else echo "FAIL $name: wrong error"; head -3 "$tmp/out"; fail=1; fi
}

# 1. a project's own ./lib is in the cascade, but its files are USER modules
expect_reject "cwd ./lib is a user module" tests/userlib/cwdlib Main.hs \
  "variable not in scope: foldrList_" X=1

# 2. a library module re-exporting `module Prelude` exports the PUBLIC one
expect_reject "re-exported Prelude is public" tests/userlib/reexport Leak.hs \
  "variable not in scope: fromMaybe" AHC_LIB="$ROOT/tests/userlib/reexport/stdlib"
if (cd tests/userlib/reexport && AHC_LIB="$ROOT/tests/userlib/reexport/stdlib" \
      "$AHC" check Fine.hs >"$tmp/out" 2>&1); then echo "ok   re-exported Prelude keeps map"
else echo "FAIL re-exported Prelude lost map"; head -3 "$tmp/out"; fail=1; fi

# 3. a real stdlib module reached through AHC_PATH is still a library module
if (cd tests/userlib/apath && AHC_PATH="$ROOT/lib" "$AHC" build Main.hs "$tmp/apath" \
      >"$tmp/out" 2>&1) && [ "$("$tmp/apath")" = "3" ]
then echo "ok   stdlib via AHC_PATH"
else echo "FAIL stdlib via AHC_PATH"; head -3 "$tmp/out"; fail=1; fi
exit $fail
