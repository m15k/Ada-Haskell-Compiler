#!/usr/bin/env bash
# Separate-compilation harness: proves that per-unit code generation
# is deterministic and the object cache is minimal.
#
# Works on a COPY of examples/lisp in a temp dir. Asserts:
#   1. the cold build runs and matches the checked-in golden;
#   2. a no-change rebuild compiles zero objects;
#   3. a comment-only edit compiles zero objects (content-addressed
#      at the generated-C level, not mtimes);
#   4. a semantic edit to the ROOT recompiles exactly one unit;
#   5. a semantic edit to a LIBRARY module recompiles exactly one
#      unit;
#   and behavior stays golden-identical throughout.
set -u
cd "$(dirname "$0")/.."
[ -x ./bin/ahc ] || { echo "build first: alr build --validation" >&2; exit 2; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cp -R examples/lisp "$tmp/lisp"
# The copied root must resolve Lisp.* beside itself; lib/ modules
# still come from the repo's lib/ (cwd-relative), which we do NOT
# touch - the library probe copies the one module it edits.
mkdir -p "$tmp/lisp/Data"
cp lib/Data/Map.hs "$tmp/lisp/Data/Map.hs"

out="$tmp/lisp/app"
fail=0
step() { echo "ok   $1"; }
flunk() { echo "FAIL $1"; fail=1; }

nobj() { ls "$out.build/cache" 2>/dev/null | wc -l | tr -d ' '; }

run_golden() {
  if "$out" "$tmp/lisp/tests/programs.scm" \
       | diff -q - examples/lisp/tests/programs.golden >/dev/null
  then return 0; else return 1; fi
}

# 1. cold build
if scripts/ahc-build.sh "$tmp/lisp/Main.hs" "$out" >/dev/null 2>&1 \
   && run_golden
then step "cold build + golden output"
else flunk "cold build"; fi
n0=$(nobj)

# 2. no-change rebuild
scripts/ahc-build.sh "$tmp/lisp/Main.hs" "$out" >/dev/null 2>&1
n1=$(nobj)
if [ "$n1" -eq "$n0" ]; then step "no-change rebuild: 0 objects"
else flunk "no-change rebuild compiled $((n1-n0)) objects"; fi

# 3. comment-only edit
printf '\n-- cache probe\n' >> "$tmp/lisp/Main.hs"
scripts/ahc-build.sh "$tmp/lisp/Main.hs" "$out" >/dev/null 2>&1
n2=$(nobj)
if [ "$n2" -eq "$n1" ]; then step "comment edit: 0 objects"
else flunk "comment edit compiled $((n2-n1)) objects"; fi

# 4. semantic root edit
perl -pi -e 's/mini-lisp \(an AHC example\)/mini-lisp probe/' \
  "$tmp/lisp/Main.hs"
scripts/ahc-build.sh "$tmp/lisp/Main.hs" "$out" >/dev/null 2>&1
n3=$(nobj)
if [ $((n3 - n2)) -eq 1 ] && run_golden
then step "semantic root edit: exactly 1 object"
else flunk "semantic root edit compiled $((n3-n2)) objects"; fi

# 5. semantic library edit (the copied Data.Map shadows lib/'s)
perl -pi -e \
  's/notMember k m = not \(member k m\)/notMember k m = if member k m then False else True/' \
  "$tmp/lisp/Data/Map.hs"
scripts/ahc-build.sh "$tmp/lisp/Main.hs" "$out" >/dev/null 2>&1
n4=$(nobj)
if [ $((n4 - n3)) -eq 1 ] && run_golden
then step "semantic library edit: exactly 1 object"
else flunk "semantic library edit compiled $((n4-n3)) objects"; fi

exit $fail
