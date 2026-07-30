# concurrency — the four models, and which parts AHC has

Four runnable programs, one per language whose concurrency model
AHC borrowed from, rejected, or replaced — plus a fifth that
measures what AHC does **not** have:

    scripts/ahc-build.sh examples/concurrency/go_csp.hs        ./go_csp
    scripts/ahc-build.sh examples/concurrency/ghc_sparks.hs    ./ghc_sparks
    scripts/ahc-build.sh examples/concurrency/ada_protected.hs ./ada_protected
    scripts/ahc-build.sh examples/concurrency/rust_aliasing.hs ./rust_aliasing
    scripts/ahc-build.sh examples/concurrency/b2_smp.hs        ./b2_smp

Three run under GHC too (`runghc -itests/shim`), which is how their
goldens were produced. Two cannot have a GHC oracle, for a reason
that is the whole point — see below.

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
| SMP for *task*-shaped work | yes | yes | yes | yes | **no** — B2 unbuilt (`b2_smp.hs` measures it) |
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

### `b2_smp.hs` — what is missing, as a number

Phase B shipped in two stages and only the first is built. **B1**
(sparks) lets worker OS threads evaluate pure thunks, so `par` uses
every core. **B2** (SMP scheduling) would let green tasks run on
several OS threads, so IO-bearing concurrency could use more than
one core. B2 is not built, so every green task shares one OS
thread.

The consequence is precise: AHC has real *concurrency* (tasks
interleave, block, communicate, and are joined) and real
*parallelism for pure code*, but **no parallelism for anything
expressed as tasks**. Three modes make that concrete:

    ./b2_smp par         [n]   pure parallelism  - scales
    ./b2_smp spawn       [n]   task parallelism  - does not
    ./b2_smp interleave        concurrency       - works fine

Measured, 6-core box, four `fib 29`s, interleaved runs:

    workers:            1        2        4
    own   par        7.61s    4.14s    1.85s    4.1x   B1 works
    own   spawn      7.02s    6.53s    6.64s    flat   B2 MISSING
    boehm par        7.05s   10.10s   12.83s    0.55x  (!)
    boehm spawn      6.80s    6.63s    6.57s    flat

**There are two findings in that table, not one.**

*The B2 gap.* `own/par` scales 4.1×; `own/spawn` is flat. Same
answer, same total work, same machine — the only difference is
which mechanism carries the work, and one of them has nowhere to
put a second core.

*Why the collector campaign happened.* Under the **default** build,
`par` does not merely fail to scale — it gets **worse** with every
worker added, 7.05s → 12.83s. A graph reducer allocates on every
reduction, and Boehm anti-scales under parallel allocation storms.
That is why B1's own gate came back at 0.46–0.70×, why the honest
default is `AHC_WORKERS=0` under Boehm, and ultimately why AHC grew
its own collector. Build with `AHC_GC=own` to see B1 work at all.

Reproduce:

    AHC_GC=own scripts/ahc-build.sh examples/concurrency/b2_smp.hs ./b2_own
    for w in 1 2 4; do
      /usr/bin/time -p env AHC_WORKERS=$w ./b2_own par   29
      /usr/bin/time -p env AHC_WORKERS=$w ./b2_own spawn 29
    done

That timing table is deliberately **not** a test. This box cannot
produce clean absolute timings, and three separate harness defects
during the collector campaign had the same shape — apparatus
deciding what the numbers did not support. The suite therefore
asserts only what is stable: that both mechanisms compute the same
answer, and keep computing it at every worker count.

**Why B2 is not built, so this reads as a decision and not a TODO.**
The reproducible schedule is the project's headline, and a second
scheduler thread is exactly what it costs. `--deterministic` stays
the default profile; B2 would have to be an opt-in mode carrying a
weaker guarantee, and that is a design commitment nobody has paid
for. The `interleave` mode is in the program to keep the gap from
being overstated — concurrency is not what is missing, only the
ability to spend more than one core on it.

Like `go_csp`, this example has no GHC oracle: its `interleave`
mode printed two distinct orders in 10 GHC runs and one in 10 AHC
runs.

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
