#!/usr/bin/env bash
# The foreign-export round trip: build tests/export/MathLib.hs as a
# static library, compile tests/export/main.c against the generated
# ahc_exports.h, run it, and diff against expected.out.
set -eu
cd "$(dirname "$0")/.."

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# The --lib build PRINTS the flags a host must link with ("built ...
# link with: ..."), decided by the same probe that compiled the
# archive - brew on macOS, pkg-config elsewhere. Consume that line
# instead of re-deriving it: this harness used to run its own
# brew-only probe, which linked fine on macOS and left GC_malloc
# undefined on Linux, where the collector arrives via pkg-config.
# Whatever way the archive was built, the printed flags match it by
# construction (AHC_GC=none prints none and the archive needs none).
built_line=$(scripts/ahc-build.sh --lib tests/export/MathLib.hs \
               "$tmp/mathlib.a")
link_flags=$(printf '%s' "$built_line" \
               | sed -n 's/.*link with: \(.*\))$/\1/p')

# shellcheck disable=SC2086
clang -O1 -o "$tmp/cmain" -I "$tmp/mathlib.a.build" \
  tests/export/main.c "$tmp/mathlib.a" $link_flags

if "$tmp/cmain" | diff -u tests/export/expected.out -; then
  echo "ok   tests/export (C main against AHC library)"
else
  echo "FAIL tests/export"
  exit 1
fi
