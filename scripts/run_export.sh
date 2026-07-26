#!/usr/bin/env bash
# The foreign-export round trip: build tests/export/MathLib.hs as a
# static library, compile tests/export/main.c against the generated
# ahc_exports.h, run it, and diff against expected.out.
set -eu
cd "$(dirname "$0")/.."

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

gc_ldflags=""
if prefix=$(brew --prefix bdw-gc 2>/dev/null) && [ -d "$prefix" ]; then
  gc_ldflags="-L$prefix/lib -lgc"
fi

scripts/ahc-build.sh --lib tests/export/MathLib.hs "$tmp/mathlib.a" \
  >/dev/null
# shellcheck disable=SC2086
clang -O1 -o "$tmp/cmain" -I "$tmp/mathlib.a.build" \
  tests/export/main.c "$tmp/mathlib.a" $gc_ldflags

if "$tmp/cmain" | diff -u tests/export/expected.out -; then
  echo "ok   tests/export (C main against AHC library)"
else
  echo "FAIL tests/export"
  exit 1
fi
