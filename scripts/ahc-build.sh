#!/usr/bin/env bash
# Compile a Haskell module to a native executable:
#   scripts/ahc-build.sh FILE.hs [OUT]
#
# Separate compilation: `ahc emit` writes OUT.build/ containing one C
# file per module (with STABLE symbols - a unit's text depends only on
# its own code) plus a shared header. Each C file is compiled to an
# object cached by content hash in OUT.build/cache/, so an unchanged
# module is never recompiled by the C compiler; the runtime object is
# cached the same way. Then everything links.
set -eu
cd "$(dirname "$0")/.."
src="$1"
out="${2:-${1%.hs}}"
[ -x ./bin/ahc ] || { echo "build first: alr build --validation" >&2; exit 2; }
# AHC_UNCHECKED=1 compiles refinement checks out (release policy).
# AHC_NOOPT=1 skips the Core simplifier.
./bin/ahc emit "$src" "$out" ${AHC_UNCHECKED:+--unchecked} ${AHC_NOOPT:+--no-opt} >/dev/null

builddir="$out.build"
cache="$builddir/cache"
mkdir -p "$cache"

gc_cflags=""
gc_ldflags=""
if prefix=$(brew --prefix bdw-gc 2>/dev/null) && [ -d "$prefix" ]; then
  gc_cflags="-I$prefix/include -DAHC_USE_BOEHM"
  gc_ldflags="-L$prefix/lib -lgc"
fi

hash_of() {
  cat "$@" | shasum -a 256 | cut -d' ' -f1
}

objs=""

# The runtime, cached like any unit.
rh=$(hash_of runtime/ahc_rts.c runtime/ahc_rts.h)
ro="$cache/rts_$rh.o"
if [ ! -f "$ro" ]; then
  # shellcheck disable=SC2086
  clang -O1 -c -o "$ro" -I runtime $gc_cflags runtime/ahc_rts.c
fi
objs="$objs $ro"

# Program units: a unit recompiles only when its generated text (or
# the shared header / runtime header) changed.
for c in "$builddir"/*.c; do
  h=$(hash_of "$c" "$builddir/ahc_prog.h" runtime/ahc_rts.h)
  o="$cache/$(basename "${c%.c}")_$h.o"
  if [ ! -f "$o" ]; then
    # shellcheck disable=SC2086
    clang -O1 -c -o "$o" -I runtime -I "$builddir" $gc_cflags "$c"
  fi
  objs="$objs $o"
done

# Graph reduction evaluates long thunk chains (a 1M-element foldl)
# by C recursion; give the main thread a 512MB stack so depth limits
# match practical programs rather than the 8MB default.
# shellcheck disable=SC2086
clang -O1 -o "$out" -Wl,-stack_size,0x20000000 $objs $gc_ldflags
echo "built $out"
