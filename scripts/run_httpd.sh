#!/usr/bin/env bash
# ahttpd harness: the concurrent-server dogfood, pinned.
#
#   1. build examples/httpd (multi-module: Http.hs beside the root)
#      with `ahc build`;
#   2. an IDLE server costs ~zero CPU - the accept loop PARKS on
#      the listen fd (M127's poll integration); the old busy-poll
#      would burn the whole idle window;
#   3. a fixed client session, byte-compared against the golden.
#      /par/8's worker ARRIVAL ORDER is in the golden;
#   4. CONCURRENT HANDLERS: connection A opens and stays silent
#      (its handler parks on the fd), B is served meanwhile, then
#      A's request completes. Both are asserted by RESULT, not by
#      order: which of two independent TCP clients the kernel
#      delivers first is not AHC's schedule to determine, and
#      pinning it in the log golden is what made this harness fail
#      on a machine faster than the one that recorded it. AHC's
#      determinism claim is per program given its inputs - /par/8's
#      worker arrival order (check 3) is the real thing;
#   5. the server's own request log is a second golden, with the two
#      overlap requests filtered out and asserted separately;
#   6. /quit - a channel signal since M128 - must end the process
#      (no kill needed);
#   7. a port outside 1..65535 must die at the Port refinement
#      boundary, before bind().
#
# Goldens are AHC's own output (the refinement surface is not GHC
# syntax, so like examples/cal this example is AHC-only).
set -u
cd "$(dirname "$0")/.."
[ -x ./bin/ahc ] || { echo "build first: alr build --validation" >&2; exit 2; }

# ahttpd hard-codes Darwin's SOL_SOCKET/SO_REUSEADDR/O_NONBLOCK and
# the sockaddr_in sin_len byte (examples/httpd/README.md says so).
# Porting the example is its own piece of work; until then this
# harness is honest about where it applies.
if [ "$(uname -s)" != "Darwin" ]; then
  echo "skip ahttpd harness: the example's socket constants are Darwin's"
  exit 0
fi

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
step "server up (multi-module ahc build, parked accept)"

# 2. an idle server parks in poll: ~zero CPU
sleep 2
cpu=$(ps -o time= -p $spid | tr -d ' ')
case "$cpu" in
  0:00*) step "idle server: ~zero CPU ($cpu after 2s)";;
  *)     flunk "idle server burned CPU ($cpu after 2s)";;
esac

base="http://127.0.0.1:$port"
{
  curl -s --max-time 10 "$base/fact/25"
  curl -s --max-time 10 "$base/par/8"
  curl -s --max-time 10 "$base/json"
  curl -s -i --max-time 10 "$base/nope"
} > "$tmp/client.out"

# 4. concurrent handlers: A connects and stays silent (its handler
#    parks in readRequest), B is served meanwhile, then A completes.
#    Retried as a unit up to five times with a generous client
#    timeout, because which of two independent TCP clients the
#    loopback delivers - and how fast it delivers the RESPONSE bytes
#    back to curl - is the kernel's business, not AHC's schedule.
#    The rigorous concurrency proof is /par/8's pinned worker
#    arrival order (check 3), which holds on every runner including
#    CI's arm64; this check's own unique job is the park-and-resume
#    path (A parks on its fd, wakes when bytes arrive - asserted by
#    aresp). On an oversubscribed runner B's server-side 200 can
#    finish while its response bytes still lag past a tight client
#    deadline, so a first miss is retried and only a server that
#    never serves the concurrent B across every try is a real wedge.
overlap_ok=""
b=""; b_rc=""
for attempt in 1 2 3 4 5; do
  exec 3<>"/dev/tcp/127.0.0.1/$port" || continue
  sleep 0.3
  b=$(curl -sS --max-time 25 "$base/fact/2" 2> "$tmp/b.err"); b_rc=$?
  printf 'GET /fact/10 HTTP/1.0\r\n\r\n' >&3
  #  Bounded read: an unclosed connection would otherwise block until
  #  the CI job's timeout (60 minutes on the first arm64 macOS run).
  aresp=$(perl -e 'alarm 30; local $/; print <STDIN>' <&3 || true)
  exec 3<&-
  if [ "$b" = "2" ] && printf '%s' "$aresp" | grep -q 3628800; then
    overlap_ok=1; break
  fi
  sleep 0.3   # let the raced connection settle before the next try
done
if [ -n "$overlap_ok" ]
then step "concurrent handlers: A parked, B served, A completed (try $attempt)"
else flunk "concurrent handlers (B=[$b] rc=${b_rc:-?} curl=[$(cat "$tmp/b.err" 2>/dev/null)])"; fi

# 6. quit is a channel signal; the response still says bye
if [ "$(curl -s --max-time 10 "$base/quit")" = "bye" ]
then step "/quit answered"
else flunk "/quit response"; fi

# 4. /quit ends the process on its own (watchdog, not kill)
( sleep 5 && kill $spid 2>/dev/null ) & watchdog=$!
disown $watchdog
if wait $spid 2>/dev/null; then step "/quit shuts the server down"
else flunk "/quit did not end the server"; fi
kill $watchdog 2>/dev/null
spid=""

# 3. the client session, byte-exact (the readiness "/" probe and
#    the overlap requests are not in it; the log golden accounts
#    for every request)
if diff -q "$tmp/client.out" examples/httpd/tests/client.golden >/dev/null
then step "client session byte-identical (incl. /par/8 arrival order)"
else flunk "client session diverged"; diff "$tmp/client.out" examples/httpd/tests/client.golden | head; fi

# 5. the server's request log, minus the two overlap requests -
#    those are asserted by presence, since their relative order is
#    the kernel's to choose, not the scheduler's.
grep -vE '^GET /fact/(2|10) ' "$tmp/log" > "$tmp/log.seq"
if diff -q "$tmp/log.seq" examples/httpd/tests/server.golden >/dev/null
then step "server log byte-identical (sequential session)"
else flunk "server log diverged"; diff "$tmp/log.seq" examples/httpd/tests/server.golden | head; fi

#    (at least once each: the concurrent probe above retries, so a
#    route may be served more than once on a runner that raced the
#    first delivery).
n2=$(grep -c '^GET /fact/2 -> 200 OK$' "$tmp/log")
n10=$(grep -c '^GET /fact/10 -> 200 OK$' "$tmp/log")
if [ "$n2" -ge 1 ] && [ "$n10" -ge 1 ]
then step "both overlapped requests logged, order unasserted"
else flunk "overlap logging (fact/2 x$n2, fact/10 x$n10)"; fi

# 5. the Port refinement fires before any socket call
msg=$(perl -e 'alarm 15; exec @ARGV' "$tmp/ahttpd" 70000 2>&1)
if [ "$msg" = "refinement violation: 70000 not in 1 .. 65535" ]
then step "port 70000 dies at the Port boundary"
else flunk "port refinement (got: $msg)"; fi

[ $fail -eq 0 ] && echo "ahttpd harness: all green"
exit $fail
