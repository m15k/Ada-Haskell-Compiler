#!/usr/bin/env bash
# Version reconciliation: the four places AHC states its version have
# to agree, and the BUILT compiler has to agree with the source.
#
#   scripts/check_version.sh          check the tree
#   scripts/check_version.sh v1.14    also check a tag matches
#
# The touchpoints are hand-maintained, which is why this exists: v1.14
# was written up in CHANGES.md and docs while src/ahc.ads still said
# 1.13, so `ahc --version` printed the previous release. Nothing
# asserted otherwise. The binary check is the half that matters most -
# bumping the constant without rebuilding leaves a compiler that
# misreports itself, and a tag cut on that is wrong after the fact.
set -u
cd "$(dirname "$0")/.."

fail=0
note() { printf '  %s\n' "$1"; fail=1; }

#  1. src/ahc.ads is the source of truth.
src=$(sed -n 's/.*Version : constant String := "\([^"]*\)".*/\1/p' src/ahc.ads)
[ -n "$src" ] || { echo "no Version constant in src/ahc.ads" >&2; exit 2; }
echo "src/ahc.ads        $src"

#  2. alire.toml carries a three-component semver; a two-component
#     source version means a .0 patch.
case $src in
  *.*.*) want_alr=$src ;;
  *)     want_alr="$src.0" ;;
esac
alr=$(sed -n 's/^version = "\([^"]*\)".*/\1/p' alire.toml | head -1)
echo "alire.toml         $alr"
[ "$alr" = "$want_alr" ] || note "alire.toml says $alr, expected $want_alr"

#  3. CHANGES.md must have this version's entry, and it must be the
#     FIRST one - a released version is the newest thing in the file.
head_ver=$(grep -m1 '^## v' CHANGES.md | sed 's/^## v\([^ ]*\).*/\1/')
echo "CHANGES.md         $head_ver"
[ "$head_ver" = "$src" ] \
  || note "CHANGES.md's newest entry is v$head_ver, not v$src"

#  4. README's release history.
if grep -q "^- \*\*v$src\*\*" README.md; then
  echo "README.md          v$src"
else
  note "README.md has no '- **v$src**' release-history entry"
fi

#  5. The BUILT compiler. Stale binary = misreporting compiler.
if [ -x ./bin/ahc ]; then
  bin=$(./bin/ahc --version 2>/dev/null | awk '{print $2}')
  echo "bin/ahc --version  $bin"
  [ "$bin" = "$src" ] \
    || note "bin/ahc reports $bin, not $src - rebuild (cd tests && alr build)"
else
  echo "bin/ahc            (not built; skipped)"
fi

#  6. A tag argument, if given.
if [ $# -ge 1 ]; then
  tag=$1
  echo "tag                $tag"
  [ "$tag" = "v$src" ] || note "tag $tag does not match v$src"
fi

if [ $fail -eq 0 ]; then
  echo "VERSION ok ($src)"
else
  echo "VERSION MISMATCH"
fi
exit $fail
