#!/usr/bin/env bash
# Haskell 2010 conformance subset (the PRD success metric).
#
# Each tests/conformance/*.hs is a plain Haskell 2010 program pinned
# to a Report section. Its .out golden is GHC'S OUTPUT (the oracle),
# regenerated with --oracle; the normal run compiles every program
# with the full AHC pipeline and requires byte-for-byte agreement.
# Report features AHC does not yet cover are listed (with reasons) in
# tests/conformance/EXCLUSIONS.md rather than watered down here.
#
# Usage: scripts/run_conformance.sh [--oracle]
set -u
cd "$(dirname "$0")/.."

GHC="${GHC:-$HOME/.ghcup/bin/runghc}"
mode="${1:-}"

AHC=./bin/ahc
[ -x "$AHC" ] || { echo "build first: alr build --validation" >&2; exit 2; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0; n=0
shopt -s nullglob
for hs in tests/conformance/*.hs; do
  base=$(basename "$hs" .hs)
  exp="tests/conformance/$base.out"
  n=$((n+1))
  if [ "$mode" = "--oracle" ]; then
    [ -x "$GHC" ] || { echo "no GHC oracle at $GHC" >&2; exit 2; }
    if "$GHC" "$hs" > "$tmp/oracle" 2>/dev/null; then
      mv "$tmp/oracle" "$exp"; echo "oracle $exp"
    else
      echo "ORACLE-FAIL $hs"; sed 's/^/  /' "$tmp/oracle" | head -5; fail=1
    fi
    continue
  fi
  if ! scripts/ahc-build.sh "$hs" "$tmp/$base" >/dev/null 2>"$tmp/err"; then
    echo "BUILD-FAIL $hs"; sed 's/^/  /' "$tmp/err" | head -5; fail=1; continue
  fi
  got=$("$tmp/$base" 2>/dev/null)
  if [ ! -f "$exp" ]; then
    echo "MISSING $exp (run with --oracle)"; fail=1
  elif ! diff -u "$exp" <(printf '%s\n' "$got") > "$tmp/diff"; then
    echo "FAIL $hs"; head -12 "$tmp/diff"; fail=1
  else
    echo "ok   $hs"
  fi
done
echo "$n conformance programs"
exit $fail
