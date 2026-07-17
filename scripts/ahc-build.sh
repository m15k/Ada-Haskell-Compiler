#!/usr/bin/env bash
# Compile a Haskell module to a native executable:
#   scripts/ahc-build.sh FILE.hs [OUT]
# Uses ./bin/ahc for Haskell->C, then clang with the AHC runtime and
# the Boehm GC when available (falls back to plain malloc).
set -eu
cd "$(dirname "$0")/.."
src="$1"
out="${2:-${1%.hs}}"
[ -x ./bin/ahc ] || { echo "build first: alr build --validation" >&2; exit 2; }
# AHC_UNCHECKED=1 compiles refinement checks out (release policy).
# AHC_NOOPT=1 skips the Core simplifier.
./bin/ahc emit "$src" "$out" ${AHC_UNCHECKED:+--unchecked} ${AHC_NOOPT:+--no-opt} >/dev/null
gcflags=""
if prefix=$(brew --prefix bdw-gc 2>/dev/null) && [ -d "$prefix" ]; then
  gcflags="-I$prefix/include -DAHC_USE_BOEHM -L$prefix/lib -lgc"
fi
# shellcheck disable=SC2086
# Graph reduction evaluates long thunk chains (a 1M-element foldl)
# by C recursion; give the main thread a 512MB stack so depth limits
# match practical programs rather than the 8MB default.
clang -O1 -o "$out" -I runtime -Wl,-stack_size,0x20000000 \
  "$out.c" runtime/ahc_rts.c $gcflags
echo "built $out"
