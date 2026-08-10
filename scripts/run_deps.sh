#!/usr/bin/env bash
# Path dependencies harness (M134): the manifest's [dependencies.*]
# contract, end to end.
#
#   1. a path dependency resolves: app -> liba -> libc (a bare
#      module tree with no manifest) -> stdlib, out of tree;
#   2. `ahc check` on a file beside a manifest is dep-aware too
#      (the driver probes the root file's directory);
#   3. one module in two dependencies is an ambiguity error naming
#      both files, not a silent win for manifest order;
#   4. a dependency cycle and a missing dependency directory fail
#      with their own messages;
#   5. editing a dependency module is seen by the next build (the
#      object cache keys on content, not timestamps);
#   6. -j determinism holds with dependency modules in the graph;
#   7. back-compat: the flat manifest in examples/httpd still
#      drives a bare-style build.
set -u
cd "$(dirname "$0")/.."
root=$(pwd)
[ -x ./bin/ahc ] || { echo "build first: alr build --validation" >&2; exit 2; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
step()  { echo "ok   $1"; }
flunk() { echo "FAIL $1"; fail=1; }

cp -R tests/build/pkgs "$tmp/pkgs"

# 1. path dependency, transitive, bare tree, stdlib - build + run
if ( cd "$tmp/pkgs/app" && "$root/bin/ahc" build ) >/dev/null 2>&1 \
   && [ "$("$tmp/pkgs/app/app")" = "HELLO, PACKAGES" ]
then step "path dep + transitive + bare tree: build + run"
else flunk "path dependency build"; fi

# 2. `ahc check` finds the manifest beside the root file
if "$root/bin/ahc" check "$tmp/pkgs/app/Main.hs" >/dev/null 2>&1
then step "ahc check is dep-aware without flags"
else flunk "ahc check with deps"; fi

# 3. ambiguity: the same module from two dependencies
cat > "$tmp/pkgs/app/ahc.toml" <<'MANIFEST'
main = "Main.hs"
[dependencies.liba]
path = "../liba"
[dependencies.libb]
path = "../libb"
MANIFEST
err=$( (cd "$tmp/pkgs/app" && "$root/bin/ahc" build) 2>&1 )
if [ $? -ne 0 ] \
   && printf '%s' "$err" | grep -q "found in two dependencies" \
   && printf '%s' "$err" | grep -q "liba/Data/Greet.hs" \
   && printf '%s' "$err" | grep -q "libb/Data/Greet.hs"
then step "module collision names both dependencies"
else flunk "module collision"; fi

# 4a. dependency cycle
cat > "$tmp/pkgs/app/ahc.toml" <<'MANIFEST'
main = "Main.hs"
[dependencies.one]
path = "../cyc1"
MANIFEST
if ( cd "$tmp/pkgs/app" && "$root/bin/ahc" build ) 2>&1 \
   | grep -q "dependency cycle through"
then step "dependency cycle is its own error"
else flunk "dependency cycle"; fi

# 4b. missing dependency directory
cat > "$tmp/pkgs/app/ahc.toml" <<'MANIFEST'
main = "Main.hs"
[dependencies.ghost]
path = "../nowhere"
MANIFEST
if ( cd "$tmp/pkgs/app" && "$root/bin/ahc" build ) 2>&1 \
   | grep -q "no such directory"
then step "missing dependency directory is its own error"
else flunk "missing dependency directory"; fi

# 5. a dependency edit reaches the next build
cat > "$tmp/pkgs/app/ahc.toml" <<'MANIFEST'
main = "Main.hs"
output = "app"
[dependencies.liba]
path = "../liba"
MANIFEST
sed -i.bak 's/hello, /goodbye, /' "$tmp/pkgs/liba/Data/Greet.hs"
if ( cd "$tmp/pkgs/app" && "$root/bin/ahc" build ) >/dev/null 2>&1 \
   && [ "$("$tmp/pkgs/app/app")" = "GOODBYE, PACKAGES" ]
then step "editing a dependency reaches the next build"
else flunk "dependency edit"; fi

# 6. -j determinism with dependency modules in the graph
rm -rf "$tmp/pkgs/app/app.build" "$tmp/pkgs/app/app"
( cd "$tmp/pkgs/app" && "$root/bin/ahc" build -j1 ) >/dev/null 2>&1
cp "$tmp/pkgs/app/app" "$tmp/app.j1" 2>/dev/null
rm -rf "$tmp/pkgs/app/app.build" "$tmp/pkgs/app/app"
( cd "$tmp/pkgs/app" && "$root/bin/ahc" build -j4 ) >/dev/null 2>&1
if cmp -s "$tmp/pkgs/app/app" "$tmp/app.j1"
then step "-j1 and -j4 cold builds byte-identical with deps"
else flunk "-j determinism with deps"; fi

# 7. back-compat: examples/httpd's flat manifest still builds
#    (main from the manifest, output redirected out of tree)
if ( cd examples/httpd && "$root/bin/ahc" build -o "$tmp/ahttpd" ) \
     >/dev/null 2>&1 && [ -x "$tmp/ahttpd" ]
then step "flat manifest (examples/httpd) still builds bare"
else flunk "flat manifest back-compat"; fi

[ $fail -eq 0 ] && echo "path deps harness: all green"
exit $fail
