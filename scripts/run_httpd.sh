#!/usr/bin/env bash
# ahttpd harness: the concurrent-server dogfood, pinned.
#
#   1. build examples/httpd (multi-module: Http.hs beside the root)
#      with `ahc build`;
#   2. run a fixed client session against it - bodies for every
#      route plus one full-header response - and byte-compare
#      against the golden. /par/8's worker ARRIVAL ORDER is in the
#      golden: the deterministic scheduler makes an interleaving a
#      testable output;
#   3. the server's own request log is a second golden;
#   4. /quit must end the process (no kill needed);
#   5. a port outside 1..65535 must die at the Port refinement
#      boundary, before bind().
#
# Goldens are AHC's own output (the refinement surface is not GHC
# syntax, so like examples/cal this example is AHC-only).
set -u
cd "$(dirname "$0")/.."
[ -x ./bin/ahc ] || { echo "build first: alr build --validation" >&2; exit 2; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"; kill $spid 2>/dev/null' EXIT
fail=0
spid=""
step()  { echo "ok   $1"; }
flunk() { echo "FAIL $1"; fail=1; }

./bin/ahc build examples/httpd/ahttpd.hs "$tmp/ahttpd" >/dev/null 2>&1 \
  || { flunk "build"; exit 1; }

# A port that is free right now; retry a few candidates.
port=""
for cand in 18731 18747 18763 18779; do
  "$tmp/ahttpd" "$cand" > "$tmp/log" 2>&1 &
  spid=$!
  ok=""
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$cand/"; then
      ok=1; break
    fi
    sleep 0.2
  done
  if [ -n "$ok" ]; then port=$cand; break; fi
  kill $spid 2>/dev/null; wait $spid 2>/dev/null
done
[ -n "$port" ] || { flunk "server never came up"; exit 1; }
step "server up (multi-module ahc build, nonblocking accept)"

base="http://127.0.0.1:$port"
{
  curl -s "$base/fact/25"
  curl -s "$base/par/8"
  curl -s "$base/json"
  curl -s -i "$base/nope"
  curl -s "$base/quit"
} > "$tmp/client.out"

# 4. /quit ends the process on its own (watchdog, not kill)
( sleep 5 && kill $spid 2>/dev/null ) & watchdog=$!
disown $watchdog
if wait $spid 2>/dev/null; then step "/quit shuts the server down"
else flunk "/quit did not end the server"; fi
kill $watchdog 2>/dev/null
spid=""

# 2. the client session, byte-exact (the readiness "/" probe is not
#    in the golden; the log golden accounts for it)
if diff -q "$tmp/client.out" examples/httpd/tests/client.golden >/dev/null
then step "client session byte-identical (incl. /par/8 arrival order)"
else flunk "client session diverged"; diff "$tmp/client.out" examples/httpd/tests/client.golden | head; fi

# 3. the server's request log
if diff -q "$tmp/log" examples/httpd/tests/server.golden >/dev/null
then step "server log byte-identical"
else flunk "server log diverged"; diff "$tmp/log" examples/httpd/tests/server.golden | head; fi

# 5. the Port refinement fires before any socket call
msg=$("$tmp/ahttpd" 70000 2>&1)
if [ "$msg" = "refinement violation: 70000 not in 1 .. 65535" ]
then step "port 70000 dies at the Port boundary"
else flunk "port refinement (got: $msg)"; fi

[ $fail -eq 0 ] && echo "ahttpd harness: all green"
exit $fail
