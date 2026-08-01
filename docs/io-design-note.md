# Scheduler-integrated IO: a design note

M126. Follow-on to `docs/concurrency-design-note.md`; the brief was
written by a program. `examples/httpd` (M125) put the green-thread
runtime in front of real sockets and surfaced two gaps in its first
hour:

1. **Blocking IO blocks every green thread.** The scheduler's only
   points are IO binds, blocking channel operations, and `yield`; a
   blocking `accept(2)` stalls the whole program. ahttpd works
   around it with `O_NONBLOCK` and a yield-poll — correct, but an
   idle server burns a CPU busy-polling.
2. **Channels cannot be polled.** `recv` blocks and nothing else
   exists, so a loop cannot watch a socket *and* a quit signal;
   ahttpd handles requests sequentially and `/quit` is a route.

This note surveys how four runtimes integrated IO with their
schedulers, then designs AHC's answer under the house constraint
the concurrency note established: **the schedule stays
reproducible**.

## Part 1: four runtimes, four answers

**Go: the netpoller.** Every socket the runtime hands out is
secretly nonblocking; a read that would block parks the goroutine
in the netpoller — a kqueue/epoll/IOCP subsystem the scheduler
consults when it runs out of work. User code *looks* blocking; the
integration is invisible, which is the strongest ergonomics on
offer. The costs: the runtime must own every fd (cgo-opened fds
fall off the fast path), wake order is whatever the kernel returns,
and the netpoller is one of Go's most reworked subsystems — the
invisible abstraction is expensive to keep invisible.

**GHC: the IO manager.** `threadWaitRead`, and everything
Handle-shaped above it, routes through GHC.Event: an event manager
(kqueue/epoll) that parks the Haskell thread and wakes it via MVar
when the fd fires. Truly blocking *foreign* calls escape instead to
OS threads (`safe` FFI), a second mechanism for the same problem.
Like Go: transparent at the surface, nondeterministic at wake, and
historically expensive (global manager, then per-capability
managers, each a rework).

**Rust: no runtime, so the executor decides.** mio wraps
kqueue/epoll; tokio parks tasks on wakers; a blocking syscall in
async code is a bug you hand to `spawn_blocking`'s thread pool.
Most telling for this note: tokio's `select!` **randomizes** its
branch choice on purpose — fairness through deliberate
nondeterminism, the exact opposite bet from AHC's. And the
function-coloring split (async fns cannot call blocking fns) shows
what it costs when IO integration is not the runtime's job.

**Ada: select in the language.** The selective wait is the surface
model this note wants: several `accept` alternatives with guards,
optionally `or delay`, `or terminate`, `else`. But the choice among
open alternatives is implementation-defined — nondeterministic —
and **Ravenscar therefore bans select entirely**: the profile that
made Ada analyzable did it by removing the construct. That is the
irony AHC gets to resolve: Ada invented the surface and then its
own high-integrity profile could not keep it. A select whose choice
rule is *pinned* — textual order, always — is the select Ravenscar
could have kept. AHC builds that.

**Synthesis.** Everyone converges on the same mechanism (a kernel
readiness queue consulted when the scheduler idles) and everyone
gave up determinism at the wake. AHC takes the mechanism shape from
Go/GHC (poll when the run queue drains), the surface from Ada
(select over alternatives, plus an fd-or-channel form), and rejects
the nondeterministic wake everywhere: ready fds wake in
**registration order**, select resolves ties in **list order**.

## Part 2: AHC's design

Three principles:

1. **Determinism survives.** Every wake order is pinned. Two ready
   fds wake their tasks in the order the tasks parked; a select
   over channels takes the first non-empty in list order. An
   interleaving remains a golden.
2. **Explicit, not invisible.** AHC does not intercept fds — the
   FFI stays honest (the runtime never secretly owns what user code
   opened), and the surface says where the scheduling points are.
   This is the Ravenscar instinct applied to IO: analyzable beats
   magical.
3. **The smallest honest mechanism: `poll(2)`.** Not kqueue/epoll.
   poll is POSIX-portable (one implementation, no per-OS branches),
   and at dogfood scale — dozens of fds — its O(n) is noise. The
   netpoller and the IO manager are cautionary tales about paying
   the scalable-mechanism cost up front; kqueue/epoll here is a
   measurement-gated upgrade behind an unchanged contract, exactly
   as SMP was staged behind Phase A.

### Surface

`Control.Concurrent.Scoped` grows five entries:

    waitRead   :: Int -> IO ()             -- park until fd readable
    waitWrite  :: Int -> IO ()             -- park until fd writable
    tryRecv    :: Chan a -> IO (Maybe a)
    selectRecv :: [Chan a] -> IO (Int, a)  -- first ready, ties by
                                           --   list order; 0-based
    waitReadOr :: Int -> Chan a -> IO (Maybe a)
                                           -- Just v: message first
                                           -- Nothing: fd readable

Fds are `Int` (`fromIntegral` away from the FFI's `CInt`; the
runtime never opens or closes them). `selectRecv` takes a
*same-type* channel list because Haskell 2010 has no existentials;
the heterogeneous case is the CSP funnel — many typed channels
forwarded into one sum-typed channel — and the manual documents the
pattern rather than the type system faking it. `waitReadOr` is the
accept-loop shape ahttpd needs (Ada's `accept ... or terminate`,
with the fd playing the entry): wait for a client *or* a quit
message, deterministically preferring the message.

### Semantics

- The new prims are scheduling points like `recv`. Readiness is
  *checked* when the run queue drains: a busy peer delays the poll
  exactly as it already delays every other task — the cooperative
  contract, unchanged and documented.
- Run queue empty + fd waiters: the scheduler blocks in
  `poll(..., -1)`. This is the busy-poll's replacement — an idle
  server now costs 0% CPU and wakes on the first ready fd.
- Run queue empty + **no** fd waiters: the same honest
  "deadlock: all green threads blocked" as today.
- A task parked on an fd inside a failing scope inherits the
  existing scope-join semantics (the join waits for every child;
  a child parked forever is the same deadlock report it is with
  channels today). Nothing new to learn.
- Sparks never park (design note 7.3); the green scheduler — and
  with it all of this — runs on the main OS thread only. No locks.

## Part 3: implementation plan (M127)

Runtime (`ahc_rts.c`):

- TCB grows `wait_fd` (-1 = none), `wait_ev` (POLLIN/POLLOUT),
  `wait_chan` (the dual-wait channel, if any), and `ionext` — a
  second linkage, because a dual-waiter sits in a channel's
  recv_waiters (via `qnext`) *and* the io list at once.
- A global io-wait list in registration order (`ionext`).
- `sched_switch`'s empty-queue branch becomes a loop: poll-and-wake
  or die. `io_poll_block()` builds a `pollfd` array from armed
  waiters in list order, blocks in `poll`, retries EINTR, then
  wakes ready waiters **in registration order** and prunes.
- Wake hygiene for dual waits: a woken dual-waiter unlinks itself
  from the *other* list before proceeding; `io_chan_send`'s waiter
  scan tightens `state < 2` to `state == 1` so an fd-woken (but not
  yet resumed) selector is never handed a second value; the io wake
  path likewise wakes only `state == 1`.
- Prims: `io_wait_read`/`io_wait_write`/`io_try_recv`/
  `io_select_recv`/`io_wait_read_or`. Maybe is tags 1/2, a pair is
  `mk_con(1, 2)` children-first, and the select prim walks the
  evaluated cons cells directly.
- Wiring per the M78 template: schemes in `ahc-builtins.adb`, BPs
  in `ahc-prelude_core.adb`, surface in Scoped.

Tests: exec goldens that build their own plumbing through the FFI
(`pipe(2)` imported by the test program itself) — tryRecv on empty
and full channels, selectRecv order pins including the tie case,
waitReadOr both ways, waitRead parking and waking across a pipe
write from a sibling task; every one schedule-pinned and run x5 for
byte-identity. MANUAL chapter 18 and EXCLUSIONS updated.

## Part 4: the acceptance test (M128)

ahttpd reworked on the new prims is the milestone's proof:

- the accept loop parks on the listen fd (`waitReadOr lfd quitCh`) —
  no busy-poll, idle CPU at zero;
- a handler is `spawn`ed per connection — the server is finally
  concurrent, and a golden pins it;
- `/quit` becomes a message on the quit channel — a signal, not a
  route hack;
- the session goldens stay byte-identical for unchanged routes, and
  the README's "what it honestly cannot do yet" section is rewritten
  to say *how* both findings closed.

## Part 5: non-goals

- **Timeouts** (`or delay`). Wall-clock is nondeterministic by
  nature; a timeout that fires is a schedule change no golden can
  pin. Deferred until there is an honest testing story (virtual
  time), not smuggled in untestable.
- **kqueue/epoll.** Measurement-gated, behind the same surface.
- **Windows/IOCP**, **async exceptions**, **Handle integration**
  (System.IO stays synchronous), **fd ownership** (the runtime
  never closes what it did not open).
