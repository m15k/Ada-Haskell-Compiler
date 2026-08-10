#!/usr/bin/env bash
# Git dependencies harness (M135): fetch, minimal version
# selection, pins, and ahc.sum - against local git repos over
# file:// URLs, with the module cache pointed into the tmpdir.
#
#   1. a git dependency fetches, builds, and runs;
#   2. MVS: two requirers ask for 1.0.0 and 1.1.0 of the same
#      repo - the build gets 1.1.0, the max of the minimums;
#   3. a root pin forces v1.0.0 over the transitive minimums;
#   4. warm cache: a second build does no fetching and survives
#      the upstream repos disappearing entirely;
#   5. `ahc fetch` prefetches into a fresh cache, so the first
#      build afterwards is already offline;
#   6. a tampered cache entry hard-fails against ahc.sum.
set -u
cd "$(dirname "$0")/.."
root=$(pwd)
[ -x ./bin/ahc ] || { echo "build first: alr build --validation" >&2; exit 2; }
command -v git >/dev/null || { echo "git required" >&2; exit 2; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
step()  { echo "ok   $1"; }
flunk() { echo "FAIL $1"; fail=1; }

export AHC_MOD="$tmp/mod"
G="git -c user.email=ahc@test -c user.name=ahc"

# --- upstream repos ---------------------------------------------
# greet: v1.0.0 and v1.1.0, output distinguishes them
mkdir -p "$tmp/repos/greet/Data"
( cd "$tmp/repos/greet"
  git init -q
  printf 'module Data.Greet (greeting) where\ngreeting :: String -> String\ngreeting who = "hello v1, " ++ who\n' > Data/Greet.hs
  $G add -A; $G commit -qm v1; git tag v1.0.0
  printf 'module Data.Greet (greeting) where\ngreeting :: String -> String\ngreeting who = "hello v1.1, " ++ who\n' > Data/Greet.hs
  $G add -A; $G commit -qm v1.1; git tag v1.1.0 )

# mida wants greet >= 1.0.0; midb wants greet >= 1.1.0
for m in a b; do
  v=1.0.0; [ "$m" = b ] && v=1.1.0
  mkdir -p "$tmp/repos/mid$m/Mid"
  ( cd "$tmp/repos/mid$m"
    git init -q
    up=$(echo "$m" | tr '[:lower:]' '[:upper:]')
    printf 'module Mid.%s (line%s) where\nimport Data.Greet (greeting)\nline%s :: String\nline%s = "%s: " ++ greeting "pkg"\n' \
      "$up" "$up" "$up" "$up" "$up" > "Mid/$up.hs"
    printf '[dependencies.greet]\ngit = "file://%s/repos/greet"\nversion = "%s"\n' "$tmp" "$v" > ahc.toml
    $G add -A; $G commit -qm one; git tag v1.0.0 )
done

# --- the consuming project --------------------------------------
mkdir -p "$tmp/app"
printf 'module Main where\nimport Mid.A (lineA)\nimport Mid.B (lineB)\nmain :: IO ()\nmain = do\n  putStrLn lineA\n  putStrLn lineB\n' > "$tmp/app/Main.hs"
manifest() {  # manifest [pin]
  { printf 'main = "Main.hs"\noutput = "app"\n'
    printf '[dependencies.mida]\ngit = "file://%s/repos/mida"\nversion = "1.0.0"\n' "$tmp"
    printf '[dependencies.midb]\ngit = "file://%s/repos/midb"\nversion = "1.0.0"\n' "$tmp"
    [ $# -gt 0 ] && printf '[dependencies.greet]\ngit = "file://%s/repos/greet"\npin = "%s"\n' "$tmp" "$1"
  } > "$tmp/app/ahc.toml"
}
rebuild() { rm -rf "$tmp/app/app" "$tmp/app/app.build"
            ( cd "$tmp/app" && "$root/bin/ahc" build ); }

# 1+2. fetch + build + run, and MVS picks 1.1.0 (midb's minimum)
manifest
if rebuild >/dev/null 2>&1 \
   && [ "$("$tmp/app/app")" = 'A: hello v1.1, pkg
B: hello v1.1, pkg' ]
then step "git deps build + run; MVS selects the max of minimums"
else flunk "git dependency build / MVS"; fi

# 3. a root pin forces v1.0.0 over both transitive minimums
manifest v1.0.0
if rebuild >/dev/null 2>&1 \
   && [ "$("$tmp/app/app")" = 'A: hello v1, pkg
B: hello v1, pkg' ]
then step "root pin overrides transitive minimums"
else flunk "root pin"; fi

# 4. warm cache: upstream disappears, build still works, silently
manifest
rebuild >/dev/null 2>&1
mv "$tmp/repos" "$tmp/repos.away"
out=$(rebuild 2>&1)
if [ $? -eq 0 ] && ! printf '%s' "$out" | grep -q fetching \
   && [ "$("$tmp/app/app")" = 'A: hello v1.1, pkg
B: hello v1.1, pkg' ]
then step "warm cache builds offline, no fetching"
else flunk "offline warm cache"; fi
mv "$tmp/repos.away" "$tmp/repos"

# 5. ahc fetch prefetches into a fresh cache
rm -rf "$AHC_MOD"
if ( cd "$tmp/app" && "$root/bin/ahc" fetch ) >/dev/null 2>&1; then
  mv "$tmp/repos" "$tmp/repos.away"
  if rebuild >/dev/null 2>&1
  then step "ahc fetch prefetches; first build is offline"
  else flunk "ahc fetch prefetch"; fi
  mv "$tmp/repos.away" "$tmp/repos"
else flunk "ahc fetch"; fi

# 6. a tampered cache entry hard-fails against ahc.sum
tampered=$(find "$AHC_MOD" -type d -name 'greet@1.1.0' | head -1)
echo '-- tampered' >> "$tampered/Data/Greet.hs"
err=$(rebuild 2>&1); rc=$?
if [ $rc -ne 0 ] && printf '%s' "$err" | grep -q "does not match"
then step "tampered cache entry fails against ahc.sum"
else flunk "ahc.sum mismatch (rc=$rc)"; fi

# 7. adversarial review: a pin with '..' is refused before any
#    filesystem operation can escape the module cache
manifest v1.0.0
sed -i.bak 's#pin = "v1.0.0"#pin = "../../../../../../tmp/ahc_escape"#' "$tmp/app/ahc.toml"
rm -f "$tmp/app/ahc.toml.bak"
err=$(rebuild 2>&1)
if [ $? -ne 0 ] && printf '%s' "$err" | grep -q "escape the module cache" \
   && [ ! -e /tmp/ahc_escape ] && [ ! -e /tmp/ahc_escape.fetch ]
then step "a '..' pin is refused, nothing created outside the cache"
else flunk "path-traversal refusal"; fi

# 8. adversarial review: a repo carrying a symlink loop and an
#    escape-to-/etc symlink hashes and builds without hang or crash
mkdir -p "$tmp/repos/greet/Sub"
( cd "$tmp/repos/greet"
  ln -s . Sub/loop 2>/dev/null
  ln -s /etc/passwd Sub/escape 2>/dev/null
  $G add -A; $G commit -qm links; git tag v1.2.0 )
rm -rf "$AHC_MOD"
manifest
sed -i.bak 's/version = "1.0.0"/version = "1.2.0"/g' "$tmp/repos/mida/ahc.toml" 2>/dev/null
# depend on greet 1.2.0 directly so the symlinked tree is fetched
{ printf 'main = "Main.hs"\noutput = "app"\n'
  printf '[dependencies.greet]\ngit = "file://%s/repos/greet"\nversion = "1.2.0"\n' "$tmp"
} > "$tmp/app/ahc.toml"
printf 'module Main where\nmain :: IO ()\nmain = putStrLn "ok"\n' > "$tmp/app/Main.hs"
if rebuild >/dev/null 2>&1 && [ "$("$tmp/app/app")" = ok ]
then step "a repo with symlink loop + escape hashes and builds safely"
else flunk "symlink-bearing repo"; fi

# 9. security review: a git URL that is really a git option
#    (--upload-pack=<cmd>) plus a colon-bearing pin was a
#    supply-chain RCE - it must be refused, and nothing run
rm -f "$tmp/PWNED"
{ printf 'main = "Main.hs"\n'
  printf '[dependencies.evil]\n'
  printf 'git = "--upload-pack=touch${IFS}%s/PWNED"\n' "$tmp"
  printf 'pin = "x:y"\n'
} > "$tmp/app/ahc.toml"
err=$(rebuild 2>&1)
if [ $? -ne 0 ] && [ ! -e "$tmp/PWNED" ] \
   && printf '%s' "$err" | grep -q "may not begin with '-'"
then step "an --upload-pack git URL is refused (no RCE)"
else flunk "git option-injection RCE not closed"; fi

[ $fail -eq 0 ] && echo "git deps harness: all green"
exit $fail
