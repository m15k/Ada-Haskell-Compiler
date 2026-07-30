# concurrency — the four models, and which parts AHC has

Four runnable programs, one per language whose concurrency model
AHC borrowed from, rejected, or replaced:

    scripts/ahc-build.sh examples/concurrency/go_csp.hs        ./go_csp
    scripts/ahc-build.sh examples/concurrency/ghc_sparks.hs    ./ghc_sparks
    scripts/ahc-build.sh examples/concurrency/ada_protected.hs ./ada_protected
    scripts/ahc-build.sh examples/concurrency/rust_aliasing.hs ./rust_aliasing

Three of the four also run under GHC (`runghc -itests/shim`), which
is how the goldens were produced. The fourth cannot have a GHC
oracle, for a reason that is the whole point — see below.

## What AHC actually has

| Capability | Go | GHC | Rust | Ada | **AHC** |
|---|---|---|---|---|---|
| Lightweight threads | goroutines | forkIO | async tasks | tasks | **yes** — green, `ucontext` |
| Channels | core | `Chan` | `mpsc` | rendezvous | **yes** — unbounded FIFO |
| Structured lifetime (no leaks) | no | no | scoped threads | master rule | **yes** — `scope` joins |
| **Reproducible schedule** | no | no | no | Ravenscar-ish | **yes — the headline** |
| Deadlock is a *reported outcome* | panic on all-asleep | `BlockedIndefinitely` | hangs | hangs | **yes** |
| Protected objects / monitors | `sync.Mutex` | `MVar`/STM | `Mutex<T>` | **protected** | **yes**, pure transitions |
| No-blocking-in-critical-section | convention | convention | convention | rule | **a *type*** |
| Contracts on shared state | no | no | no | Pre/Post | **yes** — fire inside the action |
| Deterministic pure parallelism | no | `par`/`pseq` | rayon (no purity) | no | **yes** — B1 sparks |
| Compile-time data-race freedom | no | n/a | **ownership** | no | by immutability, not aliasing |
| Zero-cost in-place mutation | yes | no | **yes** | yes | **no** — the real gap |
| SMP for *IO*-bound concurrency | yes | yes | yes | yes | **no** — B2 unbuilt, deliberate |
| Preemption | yes | yes | OS | yes | **no** — cooperative only |

Read the last three rows as carefully as the rest. AHC is not
better than these four languages; it occupies a corner none of them
do, and pays for it.

## The four programs

### `go_csp.hs` — CSP, with the schedule pinned

Go's bet: the runtime owns the stacks. AHC takes the same shape
(tasks + channels) and changes one thing — the scheduler is
deterministic — and adds one — `scope` cannot return while a child
runs, so a leaked task is not a bug you avoid but a program you
cannot write.

**This program has no GHC oracle, and that is the demonstration.**
It prints a two-producer merge order. Measured, 8 runs each:

    GHC:  7x [2,4,6,1,3,5]   1x [1,3,5,2,4,6]     <- 2 orders
    AHC:  8x [1,3,5,2,4,6]                        <- 1 order

Same sum both ways (21). Go and GHC can assert the sum; only AHC
can assert the *order*, which is why its golden is AHC's own output
(like `examples/cal`) rather than GHC's.

### `ghc_sparks.hs` — the idea AHC copied wholesale

GHC's bet: the runtime owns evaluation. Immutable graph reduction
makes two threads racing on one thunk *harmless* — they compute the
same value — so `par` is advisory and needs no synchronisation in
the source. AHC copies this because it is right, and because it is
the one place determinism costs nothing: workers touch pure thunks
only, IO stays on the main capability in order.

Verified across worker counts — byte-identical every time:

    AHC_WORKERS=0,1,2,4,8  ->  196418 / 17622

`AHC_SPARK_STATS=1` prints created/converted/fizzled. Watch the
fizzle rate, not the clock.

### `ada_protected.hs` — Ada's good idea, with one improvement

Ada's bet: the language owns the tasks, so the compiler can enforce
rules about them. The protected object is the good idea; AHC makes
transitions **pure functions**, so Ada's "a protected body must not
block" stops being a rule and becomes a type:

    updating :: Protected s -> (s -> (s, a)) -> IO a

There is nowhere in `s -> (s, a)` to put an IO action. Verified —
this is a type error, not a runtime check:

    updating acc (\n -> do putStrLn "peek"; return (n+1, ()))
    error: couldn't match type '(,) ?' with 'IO'

A Rust `Mutex` guard cannot say this: a Rust critical section can
block, do IO, or take a second lock in the wrong order. The program
also shows `entry` barriers in both directions (a bounded buffer
where producer and consumer must both park) and PRE/POST contracts
that fire *inside* the protected action, so no task can observe a
state that violated its invariant.

### `rust_aliasing.hs` — the honest one

Rust's bet is the sharpest of the four: data races need aliasing,
mutation, and concurrency, and Rust statically forbids the first two
from co-occurring. AHC gets a comparable guarantee by deleting a
different ingredient — values are immutable, so aliasing is free and
unlimited, and the only mutable state is a `Protected` whose
transitions are pure.

**The trade, stated in both directions.** Rust wins where mutation
is the point: an in-place parallel sort of a large vector is safe
*and* allocation-free in Rust, whereas here it copies and the
collector pays. AHC has no way to say "this thread has exclusive
access to this buffer, mutate it freely" — the guarantee comes from
the absence of the feature, not from mastering it. What AHC wins is
what the guarantee costs to *use*: in this program a shared
structure reaches two concurrent readers with no `Arc`, no clone,
no lifetime, and no `Sync` bound, and is still race-free.

## Regenerating the goldens

    scripts/run_examples.sh --oracle       # GHC, for the three portable ones
    scripts/run_examples.sh --update-conc  # AHC, for go_csp's merge order
