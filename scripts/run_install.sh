#!/usr/bin/env bash
# Install/dist harness (M131): the claim is that an installed AHC is
# a COMPLETE, RELOCATABLE compiler - it needs no checkout, no
# environment variables, and no fixed location.
#
#   1. install.sh lays down the prefix shape (bin/ahc +
#      share/ahc/{prelude,lib,runtime}) and nothing outside it;
#   2. the installed compiler builds a stdlib-and-concurrency program
#      from an unrelated directory, and NO path it uses points back
#      into this checkout - the real test of standalone-ness;
#   3. mkdist.sh produces a tarball whose unpacked tree works IN
#      PLACE, with no install step at all;
#   4. the tarball's own install.sh relocates it to a second prefix
#      and that copy works too;
#   5. --uninstall removes everything it installed.
set -u
cd "$(dirname "$0")/.."
root=$(pwd)
[ -x ./bin/ahc ] || { echo "build first: alr build --validation" >&2; exit 2; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
step()  { echo "ok   $1"; }
flunk() { echo "FAIL $1"; fail=1; }

prefix="$tmp/prefix"
scripts/install.sh --prefix "$prefix" --quiet 2>/dev/null

if [ -x "$prefix/bin/ahc" ] \
   && [ -f "$prefix/share/ahc/prelude/Prelude.hs" ] \
   && [ -f "$prefix/share/ahc/runtime/ahc_rts.c" ] \
   && [ -f "$prefix/share/ahc/lib/Data/Map.hs" ] \
   && [ -f "$prefix/share/ahc/LICENSE" ]
then step "install: prefix shape (bin + share/ahc/{prelude,lib,runtime})"
else flunk "install: prefix shape"; fi

# Nothing outside the prefix: the only writable thing install.sh
# touches is $prefix, so the tmp dir holds exactly one entry so far.
if [ "$(ls "$tmp" | wc -l | tr -d ' ')" = "1" ]
then step "install: writes nothing outside the prefix"
else flunk "install: stray files in $tmp"; fi

# A program that needs the Prelude, the stdlib (Data.Map), the
# concurrency library, and the runtime - built from a directory with
# no relationship to the checkout.
work="$tmp/work"; mkdir -p "$work"
cat > "$work/Main.hs" <<'PROG'
import qualified Data.Map as M
import Control.Concurrent.Scoped

main :: IO ()
main = do
  print (M.toList (M.fromList [(2 :: Int, "b"), (1, "a")]))
  scope (\sc -> do
    ch <- newChan
    _ <- spawn sc (send ch (product [1 .. 25] :: Integer))
    v <- recv ch
    print v)
PROG
expected='[(1,"a"),(2,"b")]
15511210043330985984000000'
got=$( cd "$work" && "$prefix/bin/ahc" build Main.hs >/dev/null 2>&1 \
       && ./Main 2>&1 )
if [ "$got" = "$expected" ]
then step "installed compiler builds+runs off-checkout (stdlib, concurrency)"
else flunk "installed compiler off-checkout: got [$got]"; fi

# The strong form: no path it touches points back into this checkout.
rm -rf "$work/Main.build" "$work/Main"
if ( cd "$work" && "$prefix/bin/ahc" build Main.hs -v 2>&1 ) \
     | grep -q "$root/"
then flunk "installed compiler still reaches into the checkout"
else step "installed compiler references nothing in the checkout"; fi

# Dist tarball: unpacked tree works in place.
scripts/mkdist.sh --out "$tmp/dist" >/dev/null 2>&1
tarball=$(ls "$tmp"/dist/ahc-*.tar.gz 2>/dev/null | head -1)
if [ -n "$tarball" ] && tar xzf "$tarball" -C "$tmp/dist"; then
  unpacked=$(ls -d "$tmp"/dist/ahc-*/ | head -1)
  rm -rf "$work/Main.build" "$work/Main"
  if ( cd "$work" && "${unpacked}bin/ahc" build Main.hs >/dev/null 2>&1 \
       && ./Main >/dev/null 2>&1 )
  then step "dist tarball: unpacked tree works in place"
  else flunk "dist tarball in place"; fi

  # And relocates.
  rm -rf "$work/Main.build" "$work/Main"
  if "${unpacked}install.sh" --prefix "$tmp/prefix2" >/dev/null 2>&1 \
     && ( cd "$work" && "$tmp/prefix2/bin/ahc" build Main.hs >/dev/null 2>&1 \
          && ./Main >/dev/null 2>&1 )
  then step "dist tarball: relocates to a second prefix and works"
  else flunk "dist tarball relocation"; fi
else
  flunk "mkdist produced no tarball"
fi

scripts/install.sh --prefix "$prefix" --uninstall --quiet 2>/dev/null
if [ ! -e "$prefix" ]
then step "uninstall: removes everything it installed"
else flunk "uninstall left $(find "$prefix" -type f | wc -l | tr -d ' ') files"; fi

[ $fail -eq 0 ] && echo "install harness: all green"
exit $fail
