#!/usr/bin/env bash
# `ahc build` harness (M124): the native build command's contract.
#
#   1. out-of-tree: a multi-module program with a stdlib import
#      builds and runs from a directory that is NOT the checkout -
#      AHC.Paths' installation-relative resolution at work;
#   2. -j determinism: cold -j1 and cold -j4 builds produce
#      byte-identical binaries (parallelism must not be observable);
#   3. the shim still translates the historical env spellings
#      (AHC_UNCHECKED strips a range claim through it);
#   4. a link-level failure surfaces the C toolchain's own message
#      and a nonzero exit - never a silent half-build.
set -u
cd "$(dirname "$0")/.."
root=$(pwd)
[ -x ./bin/ahc ] || { echo "build first: alr build --validation" >&2; exit 2; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
step()  { echo "ok   $1"; }
flunk() { echo "FAIL $1"; fail=1; }

cp tests/build/Main.hs tests/build/Util.hs "$tmp/"

# 1. out-of-tree build + run
if ( cd "$tmp" && "$root/bin/ahc" build Main.hs -o app ) >/dev/null 2>&1 \
   && [ "$("$tmp/app")" = 'map: [(1,"one"),(2,"two")]' ]
then step "out-of-tree build + run (multi-module, Data.Map)"
else flunk "out-of-tree build"; fi

# 2. -j determinism: two cold builds, different worker counts
rm -rf "$tmp/app.build" "$tmp/app"
( cd "$tmp" && "$root/bin/ahc" build Main.hs -o app -j1 ) >/dev/null 2>&1
cp "$tmp/app" "$tmp/app.j1" 2>/dev/null
rm -rf "$tmp/app.build" "$tmp/app"
( cd "$tmp" && "$root/bin/ahc" build Main.hs -o app -j4 ) >/dev/null 2>&1
if cmp -s "$tmp/app" "$tmp/app.j1"
then step "-j1 and -j4 cold builds byte-identical"
else flunk "-j determinism"; fi

# 3. env spellings through the shim
cp tests/build/Range.hs "$tmp/Range.hs"
scripts/ahc-build.sh "$tmp/Range.hs" "$tmp/range" >/dev/null 2>&1
if "$tmp/range" >/dev/null 2>&1
then flunk "checked build should die at the range boundary"
else step "checked build dies at the range boundary"; fi
rm -rf "$tmp/range.build" "$tmp/range"
AHC_UNCHECKED=1 scripts/ahc-build.sh "$tmp/Range.hs" "$tmp/range" >/dev/null 2>&1
if [ "$("$tmp/range" 2>/dev/null)" = "12" ]
then step "AHC_UNCHECKED=1 strips the claim through the shim"
else flunk "AHC_UNCHECKED through the shim"; fi

# 4. failure surface
err=$(AHC_LDFLAGS="-lnope-no-such-library" \
      scripts/ahc-build.sh tests/exec/hello.hs "$tmp/hello" 2>&1 >/dev/null)
rc=$?
if [ $rc -ne 0 ] && printf '%s' "$err" | grep -q "nope-no-such-library"
then step "link failure: toolchain message + nonzero exit"
else flunk "link failure surface (rc=$rc)"; fi

# 5. ahc.toml: a bare `ahc build` in a project directory reads the
#    manifest; unknown keys are rejected loudly
proj="$tmp/proj"; mkdir -p "$proj"
cp tests/build/Range.hs "$proj/Range.hs"
cat > "$proj/ahc.toml" <<'MANIFEST'
# the smallest honest manifest
main = "Range.hs"
output = "rng"
unchecked = true
MANIFEST
if ( cd "$proj" && "$root/bin/ahc" build ) >/dev/null 2>&1 \
   && [ "$("$proj/rng")" = "12" ]
then step "ahc.toml: bare build, manifest flags applied"
else flunk "ahc.toml build"; fi
printf 'main = "Range.hs"\nbogus = 1\n' > "$proj/ahc.toml"
if ( cd "$proj" && "$root/bin/ahc" build ) 2>&1 \
   | grep -q "unknown key 'bogus'"
then step "ahc.toml: unknown key rejected with a message"
else flunk "ahc.toml unknown key"; fi

[ $fail -eq 0 ] && echo "ahc build harness: all green"
exit $fail
