#!/usr/bin/env bash
# Compile a Haskell module to a native executable:
#   scripts/ahc-build.sh FILE.hs [OUT]
# or, with --lib, to a static library plus a C header for its
# foreign exports:
#   scripts/ahc-build.sh --lib FILE.hs OUT.a
#   (header: OUT.a.build/ahc_exports.h; call ahc_lib_init() first,
#    from the one thread that will use the library)
#
# Separate compilation: `ahc emit` writes OUT.build/ containing one C
# file per module (with STABLE symbols - a unit's text depends only on
# its own code) plus a shared header. Each C file is compiled to an
# object cached by content hash in OUT.build/cache/, so an unchanged
# module is never recompiled by the C compiler; the runtime object is
# cached the same way. Then everything links.
set -eu
cd "$(dirname "$0")/.."
lib=false
if [ "${1:-}" = "--lib" ]; then lib=true; shift; fi
src="$1"
out="${2:-${1%.hs}}"
[ -x ./bin/ahc ] || { echo "build first: alr build --validation" >&2; exit 2; }
# AHC_UNCHECKED=1 compiles refinement checks out (release policy).
# AHC_NOOPT=1 skips the Core simplifier.
./bin/ahc emit "$src" "$out" ${AHC_UNCHECKED:+--unchecked} ${AHC_NOOPT:+--no-opt} \
  $($lib && echo --lib) >/dev/null

builddir="$out.build"
cache="$builddir/cache"
mkdir -p "$cache"

gc_cflags=""
gc_ldflags=""
if prefix=$(brew --prefix bdw-gc 2>/dev/null) && [ -d "$prefix" ]; then
  # Green threads need the coroutine API (GC_set_stackbottom,
  # gc >= 8.2); an older collector falls back to no-GC rather than
  # miscompile the runtime.
  if grep -qs GC_set_stackbottom "$prefix/include/gc/gc.h"; then
    gc_cflags="-I$prefix/include -DAHC_USE_BOEHM"
    gc_ldflags="-L$prefix/lib -lgc"
  fi
fi

# FFI plumbing: AHC_CFLAGS/AHC_LDFLAGS come from the environment;
# {-# OPTIONS_AHC_LINK ... #-} pragmas arrive via OUT.build/link_flags.
# A foreign import's Int=long prototype may redeclare a libc builtin
# (e.g. strlen returns size_t); that mismatch is the documented v1
# type model, so silence just that warning.
# -Wno-deprecated-declarations: macOS marks the whole ucontext API
# deprecated; the runtime's green threads use it deliberately.
user_cflags="${AHC_CFLAGS:-} -Wno-incompatible-library-redeclaration -Wno-deprecated-declarations"
user_ldflags="${AHC_LDFLAGS:-}"
if [ -f "$builddir/link_flags" ]; then
  user_ldflags="$user_ldflags $(cat "$builddir/link_flags")"
fi

# Compile flags are part of each object's cache key: a flag change
# must not reuse a stale object.
hash_of() {
  { cat "$@"; printf '%s' "$gc_cflags $user_cflags"; } \
    | shasum -a 256 | cut -d' ' -f1
}

objs=""

# The runtime, cached like any unit.
rh=$(hash_of runtime/ahc_rts.c runtime/ahc_rts.h)
ro="$cache/rts_$rh.o"
if [ ! -f "$ro" ]; then
  # shellcheck disable=SC2086
  clang -O1 -c -o "$ro" -I runtime $gc_cflags $user_cflags runtime/ahc_rts.c
fi
objs="$objs $ro"

# Program units: a unit recompiles only when its generated text (or
# the shared header / runtime header / effective flags) changed.
for c in "$builddir"/*.c; do
  h=$(hash_of "$c" "$builddir/ahc_prog.h" runtime/ahc_rts.h)
  o="$cache/$(basename "${c%.c}")_$h.o"
  if [ ! -f "$o" ]; then
    # shellcheck disable=SC2086
    clang -O1 -c -o "$o" -I runtime -I "$builddir" $gc_cflags $user_cflags "$c"
  fi
  objs="$objs $o"
done

if $lib; then
  # A static archive (runtime object included) plus the generated
  # export header. The host program controls the stack; deep lazy
  # structures may need it raised.
  rm -f "$out"
  # shellcheck disable=SC2086
  ar rcs "$out" $objs
  echo "built $out (header: $builddir/ahc_exports.h;" \
       "link with: $gc_ldflags $user_ldflags)"
  exit 0
fi

# Graph reduction evaluates long thunk chains (a 1M-element foldl)
# by C recursion; give the main thread a 512MB stack so depth limits
# match practical programs rather than the 8MB default. The linker
# spelling is per-OS (Darwin -stack_size; ELF -z stacksize).
case "$(uname)" in
  Darwin) stack_ld="-Wl,-stack_size,0x20000000" ;;
  *)      stack_ld="-Wl,-z,stacksize=0x20000000" ;;
esac
# shellcheck disable=SC2086
clang -O1 -o "$out" $stack_ld $objs $gc_ldflags $user_ldflags
echo "built $out"
