# ahttpd — an HTTP server in AHC-Haskell

A working HTTP server over the raw libc socket API through the FFI —
no framework, no hidden runtime support, ~200 lines across two
modules. `scripts/run_httpd.sh` keeps it green.

    ahc build examples/httpd/ahttpd.hs ahttpd
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
- **Nonblocking IO cooperating with the green scheduler**: the
  listen socket is `O_NONBLOCK`; `accept` and `read` poll with
  `yield`, so waiting for a client never blocks the OS thread and
  spawned green threads keep making progress.
- **Byte-exact sessions**: responses carry no Date header, so an
  entire client session — headers included — is one golden file.

Like `examples/cal`, this example is AHC-only by construction: the
refinement surface is not GHC syntax, and direct `String`
marshalling is an AHC convenience beyond GHC's FFI. Its goldens are
AHC's own output. The socket constants are Darwin's
(`SOL_SOCKET`/`SO_REUSEADDR`/`O_NONBLOCK` and the `sin_len` byte
differ on Linux; the source notes the values).

## What it honestly cannot do yet — the findings

Dogfood programs exist to find the next milestone, and this one
found two runtime gaps:

1. **Blocking IO blocks every green thread.** The scheduler's only
   scheduling points are IO binds, blocking *channel* operations,
   and `yield` — a blocking `accept(2)` would stall the whole
   program, which is why ahttpd runs its sockets nonblocking and
   polls with `yield`. That works, but an idle server busy-polls
   the CPU. The honest fix is scheduler-integrated IO: park a green
   thread on a file descriptor and let `kqueue`/`epoll` wake it —
   the same move every green-thread runtime (Go's netpoller, GHC's
   IO manager) eventually made.
2. **There is no way to poll a channel.** `recv` blocks and nothing
   else exists, so a loop cannot watch a socket *and* a quit signal
   at once — ahttpd handles requests sequentially and `/quit` is a
   route, not a signal. A `tryRecv` (or a `select` over channels —
   Ada's own `select` is the obvious model) would let the accept
   loop fan out handlers concurrently while staying quittable.

Neither gap needed guessing at design time; the program surfaced
both in its first hour. That is the dogfood tradition working as
intended.
