#!/usr/bin/env bash
# Differential parser check against GHC (the reference oracle): for
# every tests/corpus/*.hs, AHC and GHC must agree on parse-level
# acceptability. GHC type/scope/package errors are ignored - only
# parse, lexical, layout, and operator-precedence failures count.
#
#   OVER-ACCEPT  = GHC reports a parse-level error but AHC accepted
#   UNDER-ACCEPT = GHC compiles cleanly but AHC rejected
#
# Usage: scripts/run_differential.sh
set -u
cd "$(dirname "$0")/.."

AHC=./bin/ahc
GHC="${GHC:-$HOME/.ghcup/bin/ghc}"
[ -x "$AHC" ] || { echo "build first: alr build --validation" >&2; exit 2; }
[ -x "$GHC" ] || { echo "ghc not found at $GHC (set GHC=...)" >&2; exit 2; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
shopt -s nullglob
for hs in tests/corpus/*.hs; do
  "$AHC" parse "$hs" >/dev/null 2>&1
  ahc_rc=$?
  out=$("$GHC" -XHaskell2010 -fno-code -outputdir "$tmp" "$hs" 2>&1)
  ghc_rc=$?
  if echo "$out" | grep -qiE "parse error|lexical error|cannot mix|precedence parsing"; then
    ghc_parse_bad=1
  else
    ghc_parse_bad=0
  fi

  if [ $ahc_rc -eq 0 ] && [ $ghc_parse_bad -eq 1 ]; then
    echo "OVER-ACCEPT  $hs (GHC parse error, AHC accepted)"
    fail=1
  elif [ $ahc_rc -ne 0 ] && [ $ghc_parse_bad -eq 0 ] && [ $ghc_rc -eq 0 ]; then
    echo "UNDER-ACCEPT $hs (GHC clean, AHC rejected)"
    fail=1
  elif [ $ahc_rc -ne 0 ] && [ $ghc_parse_bad -eq 0 ] && [ $ghc_rc -ne 0 ]; then
    echo "note         $hs: AHC rejects; GHC fails for non-parse reasons"
  else
    echo "ok           $hs"
  fi
done
exit $fail
