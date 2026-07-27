# Design note: Concurrency and parallelism for AHC

**Status:** Phase A LANDED (M102). Written at M98; sections 1-2
are as proposed. Two implementation notes from the landing: green
stacks became 64MB mmap'd virtual reservations behind a PROT_NONE
guard page with live-extent-only GC registration (GC_add_roots of
[sp, top] at switch-out; GC_set_stackbottom retargets the running
stack) - the GC_MALLOC'd-stack idea scanned too much and guarded
nothing; and Darwin's ucontext_t compiles as a 56-byte stub unless
_XOPEN_SOURCE precedes every include (MANUAL chapter 16, both).
Channels landed as unbounded FIFO (GHC's Chan semantics), which
keeps the GHC shim (tests/shim) a direct wrapper. Contracts on
shared state (section 2.3) and Phase B remain future milestones.

AHC has zero concurrency at every layer, and until now deliberately:
Haskell 2010 has none (Control.Concurrent is GHC library territory,
which is why it is not even an EXCLUSIONS row), the runtime's thunk
update is two plain stores, blackholing is only a `<<loop>>`
detector, Boehm scans one stack, and the v1.5 FFI embedding
contract is one honest sentence about one thread. This note designs
what comes next - and, unusually for this project, it starts a
comparative survey away from AHC entirely, because the design brief
was explicit: understand what Go, GHC Haskell, Rust, and Ada each
do well AS A CONSEQUENCE OF THEIR INFRASTRUCTURE, keep GHC's
surface idioms where they are convenient, and break with GHC where
AHC's infrastructure lets it be superior.

The conclusion up front: AHC will not out-GHC GHC at throughput,
thread count, or STM. It can beat GHC at three things GHC
structurally cannot offer - **reproducible schedules**,
**leak-free structure**, and **contracts on shared state** - and
those three are exactly this project's identity.

## 1. Four languages, infrastructure-up

The instructive question for each language is not "what API does it
offer" but "what does its runtime OWN, and what does its type
system KNOW" - because every strength below is downstream of one of
those two facts.

### 1.1 Go: the runtime owns the stacks

Go's scheduler is M:N (the G-M-P model: goroutines multiplexed onto
OS threads via per-processor run queues with work stealing).
Goroutines start at ~2-8KB because the runtime owns stack layout
end to end: stacks are relocatable and grow by copying, which is
only possible because the compiler emits stack maps and every
pointer is known. Channels are the blessed primitive - CSP with
first-class syntax (`select`), unbuffered rendezvous or buffered
queues. Preemption evolved from cooperative (function-prologue
checks) to asynchronous (signal-based, Go 1.14) because tight loops
starved the scheduler - a lesson worth remembering for any
cooperative design.

- **Strength:** ergonomics. `go f()` is one keyword; a million
  goroutines is normal; channels + select make most coordination
  patterns short.
- **Weakness:** safety is dynamic. Nothing stops two goroutines
  mutating one map; the race detector is a test-time tool, not a
  guarantee. Scheduling is intentionally nondeterministic, and
  `select` is SPECIFIED to choose randomly among ready cases -
  reproducibility was traded away on purpose.
- **What it is downstream of:** a runtime that owns stacks and
  scheduling completely, and a type system that owns nothing about
  aliasing.

### 1.2 GHC: the runtime owns evaluation itself

GHC's RTS runs green threads on capabilities (one per core) with
work stealing. Its threads are cheap for a deeper reason than Go's:
the STG machine owns the *evaluation* stack as heap objects, so a
thread's stack starts at ~1KB and grows by chunk-linking - the very
thing AHC's evaluate-by-C-recursion reducer lacks. Laziness forces
the runtime's hand on synchronization: two threads may race to
force one thunk, so updates go through atomic blackholing (claim by
CAS, lose the race, block on the blackhole's queue). On top: MVar
(a one-place lock-carrying cell), STM (composable memory
transactions - the genuinely unmatched piece), `par`/`pseq` sparks
(DETERMINISTIC parallelism for pure code: sparks change wall time,
never results), and async exceptions.

- **Strength:** STM's composability; sparks' determinism; millions
  of threads; decades of production hardening.
- **Weakness:** `forkIO` is unstructured - threads are fire-and-
  forget, leak by default, and die silently unless hand-plumbed
  (the `async` library and structured wrappers exist precisely
  because the primitive is wrong). Schedules are unreproducible:
  a concurrency bug seen once may never be seen again, and the
  golden-output testing discipline this project lives by is
  impossible for concurrent GHC programs. Laziness plus threads
  breeds famous space/behavior surprises.
- **What it is downstream of:** a runtime that owns evaluation
  (growable stacks, safe preemption at allocation points) - and a
  design culture that prized throughput over replay.

### 1.3 Rust: the type system owns aliasing

Rust ships no runtime. `std::thread` is OS threads; what makes Rust
distinctive is `Send`/`Sync`: ownership and borrowing prove at
compile time that no two threads alias mutable state - data races
are a TYPE ERROR, the strongest static concurrency guarantee in any
mainstream language. Async/await is a library affair (executors:
tokio et al.), with the known "function coloring" cost and an
ecosystem split. Rayon gives structured, deterministic-shaped data
parallelism (parallel iterators, join) that feels like Ada 2022's
`parallel` done as a library.

- **Strength:** compile-time freedom from data races, no GC, C-grade
  predictability. Rayon's structured fork-join.
- **Weakness:** no green threads in the language; async is
  fragmented and colors functions; the safety story stops at data
  races (deadlocks and nondeterminism remain yours).
- **What it is downstream of:** a type system that owns aliasing -
  and the refusal to have a runtime at all.

### 1.4 Ada: the language owns the tasks

Ada put concurrency in the LANGUAGE in 1983. Tasks are declared
constructs with a master/dependent rule: a scope cannot be left
until its dependent tasks terminate - structure is not a library
pattern, it is the semantics. Protected objects (Ada 95) are
data-oriented synchronization: state plus operations plus ENTRY
BARRIERS (boolean guards; callers queue until the barrier is true),
i.e. monitors with the conditions moved into declarations, checked
and analyzable. Rendezvous is typed synchronous communication. And
the **Ravenscar profile** is the move nobody else made: a
restricted, statically analyzable subset of the tasking model
(fixed task set, no dynamic priorities, ceiling locking) adopted
for certified real-time systems BECAUSE its schedules can be
reasoned about and reproduced.

- **Strength:** structure by construction; protected objects as the
  best-designed shared-state primitive of the four; determinism as
  a deliberate, certifiable profile.
- **Weakness:** tasks map to OS threads in practice (heavyweight;
  thousands, not millions); no data-parallel story until Ada
  2022's `parallel` blocks; the ergonomics are ceremonious.
- **What it is downstream of:** a language (and certification
  culture) that owns the task model - and is willing to RESTRICT
  it to make it analyzable.

### 1.5 The synthesis table

| Take from | The thing | Into AHC as |
|---|---|---|
| Go | cheap structured spawn, channels as the blessed primitive | `scope`/`spawn` ergonomics; `Chan` with send/recv |
| GHC | surface idioms; sparks (later) | API names Haskell programmers expect; Phase B `par` |
| Rust | safety checkable BEFORE running | no ownership available - so contracts + scope discipline carry the checkable-safety instinct |
| Ada | task masters; protected objects; the Ravenscar bet | `scope` semantics; contract-carrying protected values (follow-on milestone); the deterministic scheduler as the DEFAULT |

One empirical footnote: the v1.5 FFI already embeds one AHC library
inside all four of these languages (`examples/ffi/`), and the Go
spoke is itself a worked example of this note's subject - a
host-side concurrency discipline (one locked OS thread fed by a
channel) compensating for a single-threaded callee. The comparison
above is not abstract; all four runtimes are already linked against
this project's output.

## 2. AHC's design: deterministic structured concurrency

Three decisions, each traceable to the table.

### 2.1 The scheduler is deterministic, and that is the headline

Phase A implements green threads on ONE OS thread with a strictly
deterministic round-robin scheduler whose scheduling points are IO
operations (plus explicit `yield`). Consequences, all deliberate:

- **Same program, same input, same schedule, same bytes - every
  run.** The golden discipline survives concurrency intact: an
  interleaving IS a testable output. GHC cannot pin such a test at
  all; AHC's exec suite will pin dozens.
- Concurrency bugs REPRODUCE. The six-hour-wedge war story taught
  what nondeterministic hangs cost; a deterministic scheduler makes
  every concurrent misbehavior a rerunnable test case.
- The cooperative contract is stated, not hidden: a pure
  non-allocating loop does not preempt (Go's pre-1.14 lesson,
  accepted knowingly - and revisit-able in Phase B exactly as Go
  revisited it).
- This is the Ravenscar move: restrict the model until it is
  analyzable, and make THAT the default profile. Phase B's SMP mode
  will be the opt-in, not the other way round.

### 2.2 Structure is the primitive, forkIO is the compat layer

```haskell
scope   :: (Scope -> IO a) -> IO a     -- joins all children on exit
spawn   :: Scope -> IO a -> IO (Task a)
await   :: Task a -> IO a              -- re-raises the child's death
newChan :: IO (Chan a)
send    :: Chan a -> a -> IO ()
recv    :: Chan a -> IO a
yield   :: IO ()
```

Ada's master rule, verbatim: `scope` cannot return while children
run; a dying child fails its Task; `await` propagates; an
unawaited failed child fails the scope. Threads cannot leak by
construction. A thin GHC-idiom layer (`forkIO` = spawn into an
implicit whole-program scope, `MVar` sugar over `Chan`) exists for
convenience and is documented as the legacy shape, inverting GHC's
priorities on purpose.

**The oracle survives via a shim**: `Control.Concurrent.Scoped` has
a GHC implementation (forkIO/MVar/async underneath, selected by
`-i` path in the harnesses), so concurrent programs whose
observable output is deterministic remain differential-testable
against GHC - the discipline that has caught seven compiler bugs
keeps working. Schedule-SENSITIVE outputs are pinned as AHC-only
exec goldens, meaningful precisely because of 2.1.

### 2.3 Contracts reach shared state (follow-on milestone)

Ada's protected object, transplanted the way refinements and
Pre/Post were: a protected value whose operations carry
`{-# PRE/POST #-}` and whose entries carry barriers. `MVar` gives
you a cell; a protected value gives you a cell with OBLIGATIONS,
checked (or discharged at compile time) like every other contract
in this project. This lands after Phase A stabilizes, as its own
milestone with its own note section.

## 3. Phase A implementation plan (single OS thread)

Why single-threaded first: the shared-state inventory (error-frame
stack, FunPtr registry, handle registry, every CAF thunk, the
two-store IND update) is untouched by green threads on one OS
thread - Phase A builds the semantics, API, scheduler, blackhole
blocking, tests, and docs while dodging every memory-model hazard,
and the v1.5 embedding contract ("call exports from one thread")
remains exactly true. Nothing shipped last week is invalidated.

Runtime work (runtime/ahc_rts.c):

1. **Contexts**: ucontext where sound; Darwin/arm64 gets a ~60-line
   assembly switch (callee-saved regs + sp + lr + d8-d15), probed
   at build time. Per-thread stacks are big VIRTUAL reservations,
   lazily committed (mmap MAP_NORESERVE; the 512MB executable-stack
   trick, generalized per green thread - address space is the cheap
   resource on 64-bit). Each stack extent is registered with Boehm
   (GC_add_roots, or GC_set_stackbottom where the installed
   collector has it - probed in ahc-build.sh).
2. **Scheduler**: one run queue, strict FIFO round-robin.
   `maybe_yield()` in IO-primitive bodies and `yield`; nowhere
   else.
3. **Blackholes become synchronization**: owner field; another
   thread parks on an owned blackhole and wakes on update;
   owner==self still dies `<<loop>>`. The one semantic change to
   `ahc_eval`.
4. **TCB**: per-thread error-frame stack (the FFI's setjmp frames
   must live per green thread); everything else stays global.
5. **Channels**: rendezvous + small queue of nodes; blocked parties
   park on the channel in FIFO order (determinism again).
6. **Prims**: primScope/primSpawn/primAwait/primChan*/primYield,
   wired per the M78 handle-registry template.

## 4. Phase B sketch (SMP), measurement-gated

CAS blackhole claim + blocked queues; IND updates become
payload-store-release then tag-store (readers acquire); Boehm built
with GC_THREADS and per-thread registration; capabilities with work
stealing; `par` sparks for pure parallelism. The determinism
guarantee survives as a profile: `--deterministic` keeps Phase A's
sequential schedule (the certification profile); SMP mode documents
what it trades. Every step lands only with a benchmark that
justifies it, per the M74 rule - and the honest expectation is that
Phase B is a large, separate campaign.

## 5. What this is not

No STM (GHC's crown; out of scope until a design note argues
otherwise). No async exceptions. No preemption of pure loops in
Phase A. Each absence is an EXCLUSIONS row, not a silence.
