# ahttpd — an HTTP server in AHC-Haskell

A working HTTP server over the raw libc socket API through the FFI —
no framework, no hidden runtime support, ~200 lines across two
modules. `scripts/run_httpd.sh` keeps it green.

    cd examples/httpd && ahc build    # ahc.toml names the rest
    ./ahttpd 8080
    curl http://127.0.0.1:8080/

Routes: `/` (index), `/fact/N` (exact bignum — `/fact/25` is
15511210043330985984000000, every digit), `/par/N` (the concurrency
demo), `/json` (a Data.Map rendered as JSON), `/quit` (clean
shutdown; the harness never needs `kill`).

## What it demonstrates

- **The FFI carrying a real protocol**: `socket`/`bind`/`listen`/
  `accept`/`read`/`write`/`close`/`fcntl`/`setsockopt` imported
  directly; `sockaddr_in` built byte-by-byte with the marshal
  surface (`mallocBytes`, `pokeWord8`/`pokeInt64`); request bytes in
  via `peekCStringLen`, responses out via the String marshal.
- **Deterministic concurrency as an observable**: `/par/N` answers
  by `scope`/`spawn`/`send`/`recv` fan-out, and the golden asserts
  the workers' **arrival order**, not just the total. The FIFO
  scheduler makes an interleaving a testable output — run it five
  times, get five identical bodies. GHC could compute this sum; it
  could never pin this order.
- **Refinements guarding a boundary**: the listen port's type is
  `Int in 1 .. 65535`. `./ahttpd 70000` dies with
  `refinement violation: 70000 not in 1 .. 65535` — at the type
  boundary, before `bind` ever runs. `Http.response`'s status code
  is a `Status = Int in 100 .. 599`, and its POST relates the
  rendered response to its body.
- **Scheduler-integrated IO** (M127): the accept loop *parks* on
  the listen fd — `waitReadOr lfd quitCh`, Ada's
  accept-or-terminate — and each connection's handler parks on its
  own fd (`waitRead`) while the client dawdles — and parks again on
  `waitWrite` if a response cannot be written in one go, since these
  sockets are nonblocking in both directions. An idle server
  costs ~zero CPU (the harness asserts it), and connections
  overlap: the harness opens a silent connection, serves another
  client meanwhile, then completes the first. Both answers are
  asserted; their *order* is not. Which of two independent TCP
  clients the kernel delivers first is not AHC's schedule to
  determine — the determinism claim is per program **given its
  inputs**, and `/par/N`'s worker arrival order is where that claim
  is actually pinned. An earlier version of this harness asserted
  the cross-client order too, passed on the machine that recorded
  the golden, and failed on a faster one.
- **Byte-exact sessions**: responses carry no Date header, so an
  entire client session — headers included — is one golden file.

Like `examples/cal`, this example is AHC-only by construction: the
refinement surface is not GHC syntax. Its goldens are AHC's own
output. Since M140 the server runs over `Network.Socket` - the
runtime owns the constants and the `sockaddr` layout, so the example
carries nothing platform-specific and the harness runs on Linux CI
too (the first version poked Darwin's `sockaddr_in` byte by byte
through the FFI, and was honest about being Darwin-only).

## The findings — surfaced, then closed

Dogfood programs exist to find the next milestone. The first
version of this server (M125) surfaced two runtime gaps in its
first hour:

1. **Blocking IO blocked every green thread** — so M125 ran its
   sockets nonblocking and busy-polled with `yield`, burning a CPU
   while idle.
2. **Channels could not be polled** — no way to watch a socket
   *and* a quit signal, so M125 handled requests sequentially and
   `/quit` was a route hack.

Both closed in M127 (`docs/io-design-note.md`): the scheduler now
parks tasks on file descriptors and blocks in `poll(2)` when the
run queue drains, waking ready waiters in registration order; and
`tryRecv`/`selectRecv`/`waitReadOr` give channels a select — with
the choice rule pinned, the select Ravenscar could not keep. M128
rewrote this server on those prims: the harness pins the idle-CPU
claim, the concurrent-handler overlap, and the same byte-exact
session goldens as before. Finding to fix to proof, three
milestones — the dogfood tradition working as intended.

## The arm64 delivery gap — closed by M140

From August until v1.13 this section documented an open finding: when
one connection's handler was **parked** mid-request, a second,
independent connection's response was served and logged (`200 OK`) but
its bytes never reached that client — deterministically on Apple
silicon, never on x86_64.

The M140 rewrite over `Network.Socket` closed it. The old code drove
libc directly: `readRequest` treated *every* negative `read` as "would
block" and parked, and `writeAll` did the same for `write`, so an
`EINTR` — which arm64's timing produced and x86_64's did not — parked
a handler on an fd that was already readable or writable, with no
event left to wake it. The library distinguishes: `EAGAIN`/
`EWOULDBLOCK`/`EINTR` come back as "would block" only where the fd
genuinely is not ready, every other errno raises an `IOError`, and the
retry is the library's, not the program's. `scripts/run_httpd.sh`'s
concurrent-handlers check has been fatal on every platform since, and
the arm64 CI job runs the whole harness green.

The harness still runs the server under `AHC_SOCKET_DEBUG=1` and dumps
its socket trace when that check fails: the evidence that was missing
for four months costs nothing to keep.

