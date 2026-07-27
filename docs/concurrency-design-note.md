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
keeps the GHC shim (tests/shim) a direct wrapper. Protected
values are designed and implemented in section 6 (M103). Phase B
(SMP) is designed in section 7 (PROPOSED, measurement-gated, two
stages: sparks first - they trade nothing observable - then
opt-in SMP scheduling, which may never clear its gate).

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
in this project. Designed in section 6 (M103); lands now that
Phase A has stabilized.

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

Superseded by section 7, which designs the campaign. The one-line
version stands: determinism survives as the default profile, SMP
is the opt-in, and every step lands only with a benchmark that
justifies it, per the M74 rule.

## 5. What this is not

No STM (GHC's crown; out of scope until a design note argues
otherwise). No async exceptions. No preemption of pure loops in
Phase A. Each absence is an EXCLUSIONS row, not a silence.

## 6. Protected values: contracts reach shared state (M103)

**Status: IMPLEMENTED** (runtime + lib + shim + five prot_* exec
goldens; see 6.3 for the one claim the implementation corrected).
Section 2.3's promise, designed. This is
the milestone where the two halves of the project's identity -
the contract machinery (refinements M60s, Pre/Post M73, discharge
M80s) and the deterministic scheduler (M102) - meet in one
feature, and the design's job is mostly to arrange that they
compose with ZERO new contract machinery.

### 6.1 The Ada original, and the one improvement available

An Ada protected object is state + three operation kinds:
protected functions (read-only), protected procedures (exclusive
read-write), and entries (exclusive read-write behind a BARRIER, a
boolean guard over the state; callers queue until it holds).
Bodies must not block - but Ada enforces that with a RUNTIME check
(Program_Error on a blocking call inside a protected action).

The transplant gets to do better, and this is the design's center:
**operations are pure state transitions, so the no-blocking rule
is a TYPE, not a check.**

    read    :: s -> a           -- protected function
    update  :: s -> (s, a)      -- protected procedure
    barrier :: s -> Bool        -- entry guard

A pure function cannot send, recv, await, or open a file. What Ada
polices at runtime, the type system rules unrepresentable - Rust's
row of the synthesis table (safety checkable before running),
delivered with machinery AHC already owns. And on Phase A's single
OS thread, pure evaluation contains no scheduling points, so
mutual exclusion costs NOTHING: a protected action is atomic by
construction. Phase B adds one mutex per protected value and the
semantics carry over unchanged.

### 6.2 Surface

    data Protected s                      -- abstract (registry index)

    newProtected :: s -> IO (Protected s)
    reading  :: Protected s -> (s -> a) -> IO a
    updating :: Protected s -> (s -> (s, a)) -> IO a
    entry    :: Protected s -> (s -> Bool) -> (s -> (s, a)) -> IO a

`Control.Concurrent.Protected`, a plain lib/ module over four
prims, Handle discipline as always. `entry` parks the caller until
the barrier holds, then runs the body atomically.

The operations passed in are ORDINARY NAMED TOP-LEVEL FUNCTIONS at
the call sites that matter - and that single sentence is the whole
contract story. A named `s -> (s, a)` function takes `{-# PRE #-}`
and `{-# POST #-}` pragmas TODAY, with M73's demand-time wrapper,
M73's typing rules, and the discharge pass, none of them modified:

    data Buf = MkBuf { items :: [Int]
                     , cap :: Int satisfying (\n -> n > 0) }

    {-# PRE  push \x s -> length (items s) < cap s          #-}
    {-# POST push \x s (s', _) -> length (items s') <= cap s' #-}
    push :: Int -> Buf -> (Buf, ())
    push x s = (s { items = items s ++ [x] }, ())

    notFull :: Buf -> Bool
    notFull s = length (items s) < cap s

    ... entry buf notFull (push x) ...

`MVar` gives you a cell; `Protected Buf` gives you a cell whose
every update carries obligations. A refined STATE TYPE (satisfying
fields, ranges) composes too, under the extension's own rule: a
field's check fires at first OBSERVATION, so no task can ever see
an out-of-range field - while a boundary-checked whole-state
invariant, Ada Type_Invariant style, is spelled POST (on every
transition, checked at commit).

### 6.3 Semantics: where the checks fire (the load-bearing part)

Contracts fire at demand time (M73's rule), so the design must say
WHEN a protected action demands. Decision: **`updating` and
`entry` force the returned pair and the new state to WHNF inside
the protected action.** Consequences, all deliberate:

- The transition's own PRE/POST wrappers fire INSIDE the mutual
  exclusion, before any other task can see the state - Ada's
  boundary, transplanted. A violation names its operation and dies
  (or unwinds to the task's frame, failing the Task, per M102's
  error story). State-wide invariants therefore belong in POST -
  that is the boundary-checked instrument.
- State thunk chains cannot form across updates: each action pays
  for its own transition. This is the hGetContents precedent - a
  documented strictness point where laziness would otherwise let
  one task's debt land in another task's schedule. WHNF only: the
  state's FIELDS stay as lazy as their types allow, and a REFINED
  field keeps the extension's demand rule - its check is part of
  the field, so it fires at first observation, in whichever task
  looks first. No task can observe a violating value; the check
  point is the observation, not the commit. (Tried the stronger
  claim first; the lazily-fired check thunks make it false, and
  demand-time is this project's stated rule anyway.)
- `reading` forces nothing beyond what the projection demands -
  protected functions stay observation-only, Ada's read side.

Barriers are pure `s -> Bool`, evaluated by the runtime during
epilogues (below). A barrier must therefore tolerate being run at
any protected-action boundary - which purity guarantees.

### 6.4 Determinism: the epilogue, made reproducible

Ada's "eggshell" model re-evaluates barriers at the end of every
protected action. The transplant keeps the shape and pins the
order: after each `updating`/`entry` body commits, the runtime
walks that value's entry queue IN ARRIVAL ORDER; each parked entry
whose barrier now holds runs its body immediately (state advances,
its caller is woken with the result) and the walk CONTINUES with
the updated state, since one enabling can disable or enable
others. First-arrived, first-served, every run the same - the
FIFO discipline channels already follow, so an entry queue is a
testable golden like an interleaving. A parked entry whose barrier
never holds again is a deadlock, reported by M102's detector when
no task remains runnable.

### 6.5 Runtime plan (small, by construction)

Registry of `AhcProt { state : AhcNode*, waiters }` where each
waiter carries (barrier closure, body closure, task) - the same
node shapes channels use. Four prims: `primProtNew`,
`primProtRead` (apply, return), `primProtUpdate` (apply, force
pair + state to WHNF, store, epilogue scan), `primProtEntry`
(barrier now, else park; on wake the epilogue has already run the
body - the Ada pattern where the completer executes on behalf of
the queuer, which is also what makes the order deterministic).
Wired per the M78 template; builtins/prelude-core entries mirror
M102's seven.

### 6.6 Testing

The GHC shim is the elegant one: `Protected s` = `TVar s`, and
`entry`'s barrier-wait is LITERALLY `retry` - GHC's STM expresses
in one primitive what the shim exists to emulate, a nice inversion
of section 1.2. Schedule-independent programs (a bounded buffer's
final contents, sums over producers/consumers) stay differential
against the oracle; barrier WAKE ORDER and violation deaths are
AHC-only exec goldens. One conformance-style program with
contracts that hold proves protected source remains
oracle-portable (GHC sees only ignorable pragma warnings). The
discharge harness gets a case where a provably-true barrier
precondition vanishes under the existing prover.

### 6.7 v1 scope, stated up front

No requeue (Ada's own hairiest corner), no timed or conditional
entry calls, no priority queuing (FIFO is the profile - the
Ravenscar simplification again), no `Protected` sharing across
foreign exports. MVar-as-sugar (`Protected (Maybe a)`) is a
worked example in the module documentation, not a shipped compat
layer, until something dogfooded wants it.

## 7. Phase B: SMP, in two stages (the campaign design)

**Status: PROPOSED.** Section 4's sketch, made a plan. The design
brief has not changed since section 2: AHC will not out-GHC GHC at
throughput, and `--deterministic` (Phase A's schedule, byte-for-
byte) remains the DEFAULT profile forever - the Ravenscar bet is
the identity, SMP is the opt-in. What Phase B adds is the ability
to spend cores at all, and the design's first job is to spend them
WITHOUT giving up determinism where that is possible. It is,
for half the problem.

### 7.1 The staging decision: results before schedules

The synthesis table (1.5) already contains the observation this
design turns into staging: GHC's sparks are DETERMINISTIC
parallelism - `par` changes wall time, never results. So Phase B
splits in two, and the halves differ in what they trade:

- **B1 - sparks**: `par :: a -> b -> b` and `pseq`. Worker OS
  threads evaluate PURE thunks only; every IO action still runs
  on the main capability, on Phase A's scheduler, in Phase A's
  order. Results are identical by purity; the IO schedule is
  identical by construction; therefore EVERY EXISTING GOLDEN
  KEEPS PASSING with workers on. B1 is not a profile - it is the
  default, because it trades nothing observable. (This is the one
  place a Haskell runtime gets parallelism Go, Rust, and Ada
  structurally cannot offer this cheaply: purity makes the race
  benign.)
- **B2 - SMP scheduling**: green tasks on N capabilities with
  work stealing; `send`/`recv`/`spawn` interleavings become real
  races. Opt-in (`--smp`, or AHC_RTS=-N4), and the note's rule
  applies: the flag's documentation leads with what it trades -
  schedule goldens hold only under the default profile. B2 exists
  for programs whose IO structure is itself parallel (servers);
  the honest expectation is that B1 delivers most of the value to
  most AHC programs and B2 may never clear its gate.

### 7.2 The shared-state inventory (the audit section 3 dodged)

Phase A was designed so single-OS-thread execution made this list
irrelevant. B1 makes the sublist marked (w) hot - workers touch
it; B2 makes all of it hot.

| Mutable location | B1 disposition | B2 disposition |
|---|---|---|
| thunk update (tag+ind stores) (w) | atomic protocol, 7.3 | same |
| blackhole owner/waiters (w) | CAS claim + CAS push, 7.3 | same |
| CAF thunks (w) | same protocol (they are thunks) | same |
| Boehm allocation (w) | GC_THREADS build, 7.5 | same |
| spark deques (w) | Chase-Lev, owner-push/thief-steal | same |
| run queue | main-only, untouched | per-capability + steal |
| chan queues/waiters | main-only, untouched | per-chan lock |
| protected values | main-only, untouched | per-value lock (6.1 promised) |
| task/scope/chan/prot registries | main-only mutation | lock on grow |
| handle + FunPtr registries | main-only, untouched | lock |
| per-task error frames | already per-task (M102) | same |
| stdout/stderr | main-only, untouched | libc-locked, order honest-nondet |

The (w) rows are five. That is the real content of the B1 gate:
five subsystems made thread-safe buys spendable cores with zero
observable change.

### 7.3 The thunk protocol (the one lock-free part that must be)

Every worker and the main thread race on thunk evaluation; this
path cannot take a lock without erasing the point. The protocol,
GHC's shape adapted to AHC's two-word node:

- **Claim**: CAS tag THUNK -> BLACKHOLE. Loser either parks
  (owner field, M102's machinery - waiter push is a CAS on the
  waiters list) or, for a spark-evaluated thunk, simply moves on
  (B1 workers never park on blackholes: a busy thunk is someone
  else's work already, steal the next spark; only the main task
  parks. Keeps workers deadlock-free by construction).
- **Update**: store u.ind with RELEASE, then store tag IND with
  RELEASE; readers load tag with ACQUIRE and only then u.ind.
  The two-store window where tag says BLACKHOLE and ind is
  written is benign: blackhole readers go to the waiters path,
  which the updater drains after the tag store.
- **Wake**: swap the waiters list to empty with CAS, then push
  each waiter to a locked MPSC inbox its capability drains at its
  own scheduling points. In B1 this stays deterministic for a
  structural reason, not a hopeful one: workers never park, so
  the only possible waiter is the main task - an inbox of size
  at most one, drained at main's next scheduling point, and
  "which worker finished the thunk first" is invisible to the
  schedule because either way main resumes at that same point
  with the same value. B2 gives this up along with everything
  else it gives up.

C11 atomics (`stdatomic.h`), no assembly. The protocol lands with
a stress golden (N workers forcing one shared CAF lattice) run
under ThreadSanitizer in CI as its acceptance test, not just the
benchmark - TSan is the M74-hardening move for memory models.

### 7.4 Sparks and capabilities

`par x y`: allocate a spark (pointer to the unevaluated thunk of
x) onto the current capability's Chase-Lev deque; return y. Spark
pool is advisory - a spark may be evaluated by a worker, by the
demander, or never; purity makes all three the same answer.
Workers loop: pop own deque, else steal FIFO from a victim in
round-robin, else sleep on a condvar the deque push signals.
`pseq` is `seq` with a guaranteed order (evaluate left first) -
it exists so `par`-users can stage demand; the optimizer must
learn it is strict in both arguments but MUST NOT reorder.

Fizzling is the B1 benchmark's core number: a spark whose thunk
the main task forced first did useless bookkeeping. The M74-style
report for parfib prints sparks created / converted / fizzled
alongside wall time, because a speedup number without a fizzle
rate is how spark pools rot.

B2's capabilities generalize the worker loop: each capability owns
a green-task runq + spark deque; stealing takes whole tasks from
the runq tail. Everything section 6 built survives: protected
values get the per-value mutex 6.1 promised (entry queues stay
FIFO per value - wake order within one protected value remains
deterministic even under B2; only cross-object ordering is not),
chans get a lock, and scope join parks exactly as today.

### 7.5 The collector under threads

Boehm built with GC_THREADS; each worker registers
(GC_register_my_thread) and the Phase A coroutine protocol
(set_stackbottom + live-extent roots, M102) applies PER OS THREAD
- a capability switching green tasks retargets its own thread's
stackbottom, and the M102 war-story rule (feature macros on line
one; sizeof-check ABI structs) is already paid for. Collections
stop the world; that is Boehm's model and AHC accepts it (the
alternative is not having a GC). The B1 gate benchmark must
therefore include an allocation-heavy workload, because STW pause
frequency under parallel mutation is where naive spark designs
lose their speedup back.

### 7.6 The gates (M74 discipline, stated as numbers)

Nothing in Phase B lands without its benchmark, and the harness
is hardened FIRST (interleaved A/B, best-of-5, outputs verified
identical - run_bench.sh grows a --workers axis):

- **B1 gate**: parfib and a par-mergesort in tests/bench must
  show >= 1.6x on 2 workers and >= 2.5x on 4, fizzle rate
  reported, all existing suites green with workers ON, TSan
  clean. If pure-eval parallelism cannot clear 1.6x on 2 cores,
  B1 does not land and the design returns here.
- **B2 gate**: a channel-parallel workload (N producers hashing
  into one consumer) >= 1.5x on 2 capabilities vs B1-main-only,
  under --smp, with the deterministic-profile suites still green
  by default. B2 additionally requires a written answer to "what
  broke in the six-hour-wedge class of bugs" - i.e. its own
  war-story section before merge, not after.

### 7.7 What Phase B is not

Still no STM, still no async exceptions, still no preemption of
pure loops (sparks make long pure work a RESOURCE, which removes
most of the pressure that made Go add async preemption). No
NUMA/pinning/affinity vocabulary. No promise that B2 ships: B1 is
designed to be the resting place if the measurements say so, and
the note considers that outcome a success, not a retreat - the
project's identity is the deterministic profile, and B1 is the
largest amount of parallelism obtainable without touching it.
