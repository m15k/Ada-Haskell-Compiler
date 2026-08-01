#!/usr/bin/env bash
# Compatibility shim: the build lives in the compiler now.
#   scripts/ahc-build.sh [--lib] FILE.hs [OUT]
# is exactly
#   ahc build [--lib] FILE.hs [OUT]
# (M124; see `ahc build`'s usage for the flag spellings). Kept so
# every harness, golden, and finger memory continues to work, and
# because it pins the historical env-var interface:
#   AHC_UNCHECKED=1  compiles refinement/contract checks out
#   AHC_NOOPT=1      skips the Core simplifier
#   AHC_GC           boehm (default) | own | none
#   AHC_CFLAGS / AHC_LDFLAGS  extra C flags (cache-keyed / link)
set -eu
cd "$(dirname "$0")/.."
[ -x ./bin/ahc ] || { echo "build first: alr build --validation" >&2; exit 2; }
exec ./bin/ahc build "$@" ${AHC_UNCHECKED:+--unchecked} ${AHC_NOOPT:+--no-opt}
