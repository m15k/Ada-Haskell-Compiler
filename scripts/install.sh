#!/usr/bin/env bash
# Install AHC into a prefix (M131).
#
#   scripts/install.sh [--prefix DIR] [--uninstall] [--quiet]
#
# Layout (the second shape AHC.Paths knows):
#   PREFIX/bin/ahc
#   PREFIX/share/ahc/prelude/Prelude.hs
#   PREFIX/share/ahc/lib/**
#   PREFIX/share/ahc/runtime/ahc_rts.{c,h}
#   PREFIX/share/ahc/{LICENSE,LICENSE-MIT,LICENSE-APACHE,README.md}
#
# The compiler resolves its prelude, stdlib, and runtime relative to
# its own binary, so the installed tree is relocatable: move it,
# rename the prefix, or unpack a dist tarball anywhere and it works.
# Nothing is written outside PREFIX, and no PATH or shell profile is
# touched - that is the user's business.
set -eu
cd "$(dirname "$0")/.."

prefix=/usr/local
mode=install
quiet=false
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) prefix="${2:?--prefix needs a directory}"; shift 2;;
    --prefix=*) prefix="${1#--prefix=}"; shift;;
    --uninstall) mode=uninstall; shift;;
    --quiet) quiet=true; shift;;
    -h|--help) sed -n '2,20p' "$0"; exit 0;;
    *) echo "install.sh: unknown argument '$1'" >&2; exit 2;;
  esac
done

say() { $quiet || echo "$@"; }
share="$prefix/share/ahc"

if [ "$mode" = uninstall ]; then
  rm -f "$prefix/bin/ahc"
  rm -rf "$share"
  # Only remove the directories we may have created, and only when
  # empty: a shared prefix keeps its other tenants.
  rmdir "$prefix/share" "$prefix/bin" "$prefix" 2>/dev/null || true
  say "uninstalled from $prefix"
  exit 0
fi

[ -x ./bin/ahc ] || {
  echo "install.sh: ./bin/ahc not built (run: alr build --release)" >&2
  exit 2
}

mkdir -p "$prefix/bin" "$share/prelude" "$share/runtime"
install -m 755 ./bin/ahc "$prefix/bin/ahc"
install -m 644 prelude/Prelude.hs "$share/prelude/Prelude.hs"
install -m 644 runtime/ahc_rts.c runtime/ahc_rts.h "$share/runtime/"

# The stdlib keeps its directory shape - module A.B.C lives in
# A/B/C.hs and the resolver walks that path.
rm -rf "$share/lib"
mkdir -p "$share/lib"
( cd lib && find . -name '*.hs' -print0 ) \
  | ( cd lib && xargs -0 -I{} sh -c '
        mkdir -p "$1/$(dirname "{}")" && install -m 644 "{}" "$1/{}"
      ' _ "$share/lib" )

for f in LICENSE LICENSE-MIT LICENSE-APACHE README.md; do
  [ -f "$f" ] && install -m 644 "$f" "$share/$f"
done

say "installed $("$prefix/bin/ahc" --version) to $prefix"
say "  binary:  $prefix/bin/ahc"
say "  support: $share"
$quiet || case ":$PATH:" in
  *":$prefix/bin:"*) ;;
  *) echo "  note: $prefix/bin is not on your PATH";;
esac
