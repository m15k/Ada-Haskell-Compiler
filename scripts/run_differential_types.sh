#!/usr/bin/env bash
# Type-level differential check against GHC over tests/corpus-types:
#   AHC accepts  => GHC must report no type/parse error (OVER-ACCEPT)
#   AHC rejects while GHC compiles cleanly => UNDER-ACCEPT
# Corpus modules must stick to the wired-in Prelude subset.
set -u
cd "$(dirname "$0")/.."
AHC=./bin/ahc
GHC="${GHC:-$HOME/.ghcup/bin/ghc}"
[ -x "$AHC" ] || { echo "build first: alr build --validation" >&2; exit 2; }
[ -x "$GHC" ] || { echo "ghc not found at $GHC (set GHC=...)" >&2; exit 2; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
shopt -s nullglob
for hs in tests/corpus-types/*.hs; do
  "$AHC" check "$hs" >/dev/null 2>&1; ahc_rc=$?
  "$GHC" -XHaskell2010 -fno-code -outputdir "$tmp" "$hs" >/dev/null 2>&1
  ghc_rc=$?
  if [ $ahc_rc -eq 0 ] && [ $ghc_rc -ne 0 ]; then
    echo "OVER-ACCEPT  $hs (GHC rejects, AHC accepted)"; fail=1
  elif [ $ahc_rc -ne 0 ] && [ $ghc_rc -eq 0 ]; then
    echo "UNDER-ACCEPT $hs (GHC clean, AHC rejected)"; fail=1
  else
    echo "ok           $hs"
  fi
done
exit $fail
