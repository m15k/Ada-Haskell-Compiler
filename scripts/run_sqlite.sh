#!/usr/bin/env bash
# The dogfood binding: build examples/sqlite/ahcsql.hs against the
# system sqlite3 (linked via its OPTIONS_AHC_LINK pragma), run it,
# and diff against expected.out.
set -eu
cd "$(dirname "$0")/.."

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

scripts/ahc-build.sh examples/sqlite/ahcsql.hs "$tmp/ahcsql" \
  >/dev/null 2>&1

if "$tmp/ahcsql" | diff -u examples/sqlite/expected.out -; then
  echo "ok   examples/sqlite (Haskell callback over sqlite3_exec)"
else
  echo "FAIL examples/sqlite"
  exit 1
fi
