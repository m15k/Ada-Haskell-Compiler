# AHC Changelog

## Unreleased

The floor is a genuine conflict (M118). Both gates re-run after a
verified cooldown attempt, correcting two claims from M117.

The cooldown FAILED: 36 minutes of idling never brought the
calibration probe (Boehm b_sort, ~1500ms in the morning) below
1943ms against a 1650ms target, and it swung non-monotonically to
3008ms and back. That is not thermal decay - something else on
this machine competes - so absolute timings from it are currently
worthless. Interleaved ratios remain sound.

b_parmap did NOT recover: 2.60x at 4 workers in M112, now 2.33x
hot and 2.33x cool. M117's guess that the drop was thermal is
WITHDRAWN; the regression is real, and an interleaved floor
comparison finds the cause. At a 16.8MB floor parmap runs
52281ms/20644ms = 2.53x; at 12MB it runs 53270ms/22640ms = 2.35x.
The sequential arm loses 1.9%, the 4-worker arm 9.7% - only
parallel runs pay for stop-the-world rendezvous frequency. So
M114's clamp removal, a correctness fix and still right, is what
pushed parmap below the 2.5x bar.

Which makes M117's other claim wrong too: the C2/C3 floor tension
is a GENUINE CONFLICT, not "a solvable tuning question". C2 passes
only at <= ~8MB (1.80x at 4MB), the parallel half only at >=
~16.8MB (2.53x), and no floor satisfies both. M117 looked at what
lowering the floor did to RSS without checking what it did to
parallelism.

The shape of the conflict names the fix, though: the gates do not
want different constants, they want different behaviour for
different programs - small heaps need frequent collection for RSS,
allocation-heavy parallel programs need infrequent STW for
throughput. A fixed floor cannot express that. A growth-aware
trigger can, and this is the first non-hand-waving evidence for
it. Unbuilt; the natural next collector milestone beside the Linux
port.

Gate verdicts on the fixed collector, and a rounding bug (M117).
Both gates re-run after M115 - the first numbers in this campaign
from a collector that does not lose live data.

C3 sequential PASSES at geometric mean 0.844: own is 16% faster
than Boehm and faster on five of six workloads. That settles two
open questions - M115's fourteen construction-order fixes are
performance-neutral, and unclamping the trigger floor did not cost
the sequential margin.

C3 parallel FAILS and is not currently decidable. b_parmap, which
had cleared both bars at 2.60x, reads 2.31x - but the machine
degraded 30-55% across the session (the same gate measured Boehm's
b_map at 7015ms against 4466ms earlier the same day, unchanged
code), and thermal throttling penalises high-worker
configurations asymmetrically in a way rotation cannot correct.
The sequential half is immune because both builds are
single-threaded and interleaved. Re-measure on a cool machine.

C2 reported PASS at 2.00x and had actually FAILED at 2.00408x: the
harness printed the geometric mean to two decimals and then
compared THE PRINTED STRING to the bar, so "2.00" <= 2.0 passed a
value 0.20% over it. Both gates now decide on full precision and
display rounded. This is the third harness defect of the campaign
after non-interleaved timing (M112) and single-sample RSS (M113),
and all three share a shape: the measuring apparatus quietly
deciding something the numbers did not support. A gate that can
report PASS on a failing value is worse than no gate, because it
is trusted.

Worth recording beside the failure: C2 has gone 2.31x -> 2.00408x
purely from unclamping the floor, missing now by 0.2% rather than
15%, with 0.844 against a 1.00 bar on the sequential side to pay
for a further reduction. Section 13's C2/C3 floor tension looks
solvable rather than genuine - a change of view resting on
measurements from a degraded machine, so confirm before acting.

The collector gets a CI job, and the runtime gets Linux back
(M116). M115 argued that an invariant enforced by remembering is a
habit, and that the checker is what makes it real. This wires that
conclusion in.

scripts/run_own_soak.sh now sets AHC_OWN_VERIFY on every run, so
each one proves the mark set is CLOSED under points-to rather than
only that the output happened to come out right - output equality
notices a lost object once it changes an answer, closure notices
the missed EDGE at the collection that missed it. It costs 20-50%
of run time, which is cheap for what it proves.

.github/workflows/ci.yml gains a `collector` job running the soak,
the whole exec suite under AHC_GC=own with AHC_OWN_VERIFY=1 and
collections forced every 4MB, and the thread sanitiser. None of
these had ever been in CI - the own collector had no automated
coverage at all, which is the process half of why M114's bug
survived five milestones.

The job runs on macOS because AHC_GC=own is Darwin-only today: it
reads thread stack bounds with pthread_get_stackaddr_np and the
data segment through dyld. Both have Linux equivalents and neither
is written, because writing them untested from a Mac is how this
project acquires bugs. The Linux port of the collector is its own
piece of work and is named as such in the workflow.

Found while checking that: the runtime had not compiled on Linux
AT ALL since M105. worker_main's idle nap used
pthread_cond_timedwait_relative_np, a Darwin-only call, outside
any guard - so the parked CI would have been entirely red, on the
default Boehm build too, and nobody noticed because it is parked.
Replaced with plain POSIX pthread_cond_timedwait on an absolute
deadline, which works on both platforms and is tested here.

The fourteen sites (M115). M114's live-data-loss bug is FIXED, and
its cause was this project's own declared invariant, half-applied.

Finding it took a new diagnostic: the mark set must be CLOSED
under points-to, so any marked object pointing at an unmarked heap
object is a missed edge by definition. AHC_OWN_VERIFY=1 walks
every allocated object after marking and reports violations with
both ends' kind and tag. On the reproducer it printed one line - a
live env array pointing at an unmarked Int - which says the edge
was created after its source had already been marked.

That is the generational hazard M108 already wrote down as THE
invariant: allocate components BEFORE their owner, because a
collection landing between the two marks the half-built owner
sticky-old while the child allocated a moment later is young and
reachable only from an old object no minor re-traces. M108
declared the rule and applied it to two sites. Fourteen others
were violating it the whole time - most consequentially the one
every list literal flows through, enum_from_code, which built the
cons cell and then allocated both of its children into it. All
fourteen fixed by hoisting the child allocations above their
container.

Generated code was checked and is clean: codegen only reads
constructor fields and fills environments from values that already
exist, never allocating into a container it has just built. That
is why re-ordering is a complete fix and no compiler-side write
barrier was needed.

Verified: foldl (+) 0 [1..2000000] correct at every trigger floor
(2/4/8/12/16/20/32MB - previously wrong at all but one); the mark
set verifies closed on reproducer and full benchmark; run_own_soak
passes at five floors in both cadences; Boehm regression green.

The lesson is about the rule's shape. An invariant that must hold
at every allocation site, enforced by remembering, is a habit
rather than an invariant - and it failed within one milestone of
being declared. What fixed it was a mechanical CHECKER, which
found in one run what five milestones of soaks missed.

**THE OWN COLLECTOR LOSES LIVE DATA (M114).** `AHC_GC=own`
produces WRONG ANSWERS on deep lazy chains at most collection
cadences: `foldl (+) 0 [1..2000000]` returns a different wrong sum
at each trigger floor (2MB, 8MB, 16MB, 32MB all wrong; 4MB dies
<<loop>>; 12MB happens to be right). It is pre-existing across
M107-M113, not a regression - the committed M113 runtime does the
same at any floor above the clamp described below. The default
build is Boehm and is unaffected; do not use AHC_GC=own for
anything but collector work.

Marking is not the problem, reclamation is: with the tracer
untouched and the sweep made to reclaim nothing, every answer is
correct at every floor. The tracer misses live objects and the
sweep then threads free-list pointers through them. The root scan
is not the gap (the deep case scans a verified 213MB stack range).
Reproducer, sub-second: foldl (+) 0 [1..100000] with
AHC_OWN_MIN=2000000.

The reason this survived a five-milestone campaign is the process
failure, not the bug: every soak, gate and exec run used ONE
collection cadence, because a clamp pinned them all to it. A
collector is not correct at one trigger setting. New harness
scripts/run_own_soak.sh runs deep-chain programs at five floors
and both cadences against the Boehm build and requires identical
output; it fails today on deep_foldl, as it should. Every
correctness claim previously recorded for this collector - "exec
suite green", "soak clean", "TSan clean" - should be read as "at
one trigger setting".

Where b_fib's 22MB was, and the clamp that hid it (M114). M113
closed by asking the next attempt to profile before building
anything. Profiling took one command and found the memory in the
collector's own heap: b_fib commits 32MB with ~0MB live across 32
collections, 22.9MB of it resident. Not the mark bitmap, the
block-state table, thread stacks, or the binary - garbage the
collector had not got round to reclaiming.

Two causes, both policy rather than physics. Committed address
space grows a whole OWN_CHUNK at a time, so a program needing
slightly more than one chunk commits two (at 1-4MB chunks b_fib
commits 16MB instead of 32MB, RSS 22.9 -> 18.6MB, no measurable
time cost). And the collection trigger carried

    if (floor_bytes < (long)OWN_CHUNK) floor_bytes = OWN_CHUNK;

which raised any floor below the 16MB chunk size up to it. A chunk
is a unit of address space; a collection trigger is a budget for
garbage. Tying them together was a category error, and it hid
three things: the documented 12MB default was really 16MB, every
AHC_OWN_MIN below 16MB was silently ignored - including the 8MB
used by the C2 gate's "forced collection" soak and this campaign's
ad-hoc soak loops, which therefore ran coarser than their labels
claimed (they still passed) - and M113's own conclusion that "the
trigger floor is not the lever" was measured with the lever
disconnected. THAT CONCLUSION IS WITHDRAWN: with the clamp gone
the floor is the strongest lever available, moving b_fib from
22.2MB to 7.7MB across a 2-16MB sweep, against Boehm's 5MB.

The sweep also exposes something the campaign had been missing:
the two gates pull on this one knob in OPPOSITE directions. C2
bounds peak RSS and wants a low floor; C3's sequential half
requires own to be no slower than Boehm and wants a high one. They
had been read as independent verdicts. Collector note section 13
records the trade and says plainly that whatever floor ships is a
declared position on it - not something to inherit from a clamp,
which is how the current value was in fact chosen.

C2 re-measured; the RSS failure is real (M113). With the timing
gates found unsound (M112), the C2 gate's own methodology was
tightened - peak RSS sampled three times per binary, alternating
the two builds so memory-pressure drift lands on both, minimum
kept. The geometric mean moved from 2.31x to 2.29x against a 2.0x
bar, which is the informative part: peak RSS does not drift with
temperature the way wall time does, so that failure is a genuine
property of the collector rather than an artifact, and the two
failing gates are different in kind. Large heaps are at parity
(b_sumfold 1.08x, b_strictfold 1.20x); small and medium heaps are
not (b_fib 4.47x at 22MB vs 5MB, b_sort 4.27x, b_map 2.54x).
Correctness halves pass every run. (This entry was written at M113
but never reached the file - the release commit had renamed the
section it was anchored to, and the edit silently matched nothing.
Recorded here with M114's corrections folded in.)

## v1.6 (2026-07-29)

The embedding release, and the runtime campaign behind it
(M98-M112). Two arcs since v1.5.

**The FFI grows up.** v1.5 shipped the interface; v1.6 makes it
something to build on. A runtime error inside an exported entry no
longer kills the host process - it unwinds to the boundary and
arrives as std::runtime_error, Err, error, or IOError in whichever
language is embedding. A Foreign.Marshal surface (mallocBytes,
peek/poke at every width, pointer arithmetic, C strings) opens the
APIs that traffic in arrays and out-parameters - proved by libc's
qsort sorting through a Haskell comparator, and by ahcsql, a real
sqlite3 binding in ~80 lines. examples/ffi is now one Haskell
engine - infinite lazy sieve, exact bignums, an expression parser,
word frequencies - embedded five ways, each running traffic in
BOTH directions through a host_log symbol the library imports and
every host defines in its own language.

**The runtime learns concurrency, and a collector.** Deterministic
structured concurrency (scope/spawn/await, channels, green threads,
one reproducible schedule per program), protected values carrying
contracts into shared state, opt-in SMP sparks, and AHC's own
block-structured generational collector. All of it is OPT-IN: the
default build is still Boehm with zero workers, and its output is
byte-identical to v1.5's. The campaign reports its bars as
measured, including the two it did not clear - C2 peak RSS at 2.31x
against a 2.0x bar, and the B1 parallel speedup, whose earlier
3.37x reading M109 withdrew when it removed the unsafe spin-helping
that produced it - and the stage that measured itself out of
existence (C4 parallel marking, declined on its own profile).

The harness lies, and a governor that did not pay (M112). A
reported "4 workers slower than 2" sent this milestone looking for
a bad default; it found a bad measurement instead. The three
collector gate scripts timed each configuration to completion in
turn, which lets a thermally drifting machine masquerade as a
difference between configurations - precisely the failure M74
added interleaving to run_bench.sh to prevent, reproduced because
these scripts were written without it. run_c3_gate.sh now
interleaves AND rotates the starting configuration, since
interleaving alone still penalises whichever config runs last on
the hottest machine; run_c1_gate.sh (subsumed by C2's) carries a
warning instead.

Re-measured, the 47% gap becomes ~6% and is specific to b_parfib,
whose sparked value is demanded almost immediately after being
sparked; on b_parsort and b_parmap four workers are clearly
better. The default worker count is unchanged and no fix was
needed.

A measurement-driven worker governor was built anyway and is a
NEGATIVE RESULT, kept on experiment/worker-governor. It hill
climbs the active worker count on allocation rate (useful work in
a graph reducer is ~proportional to allocation, and a thread
spinning on a blackhole allocates nothing, so contention shows up
as a rate drop). It is correct - exec suite, soak at an 11-worker
pool, TSan, and sequential programs untouched because workers only
start on the first `par` - but interleaved A/B puts it 4-10%
BEHIND the fixed default on all three benchmarks: probing parks
and wakes workers, rebalances deques, and spends time at
suboptimal counts.

New benchmark b_parmap (embarrassingly parallel, no cross-task
dependencies) joins the gate as a third parallel shape - and
refutes the assumption that such workloads want maximum workers:
it peaks at 4 on 6 physical cores. It is also the FIRST workload
ever to clear both B1 bars (2.12x at 2 workers, 2.60x at 4). The
C3 parallel gate still fails overall, because b_parfib and
b_parsort miss the 4-worker bar for reasons visible in their own
source (tight spark-then-demand dependency; a sequential merge
phase). Collector note section 11 records the shape and proposes
- without acting on - a per-workload bar, since changing a
threshold because you failed it deserves more care than changing
code.

The spokes grow up (M111): examples/ffi is now one real Haskell
library - engine/Engine.hs, an infinite lazy sieve, exact bignum
factorials, a recursive-descent expression parser whose failures
cross the boundary, and ranked word frequencies - embedded by five
programs in C, C++, Rust, Go, and GHC. A new C spoke joins the four
generated ones (the emitted ahc_exports.h is already the C
binding). Every example runs the traffic BOTH ways: Engine.hs
imports host_log and never defines it, so each host supplies that
symbol in its own language (a C function, an extern "C" C++ one, a
Rust #[no_mangle] extern "C" fn, a cgo //export, a GHC foreign
export) and the library calls back out into its embedder while
computing - in the GHC case, two Haskell runtimes importing from
and exporting to each other in one process. The library performs no
I/O of its own, so all output has a single writer and the goldens
stay deterministic across five runtimes' buffering. Each example
also provokes a parse failure and shows it arriving as that
language's own error type before carrying on.

Both collector gates re-run end-to-end, and a livelock removed
(M109). The C2 and C3 gate scripts had not been run to completion
against the M108 runtime; running them produced two failures and
one real bug, all recorded in collector-design-note.md section 9.

The bug: spin-HELPING, added in C1 to close a scaling gap, can
livelock. b_parsort at 2 workers hung at 98% CPU for 45 minutes -
main spinning on a blackhole in ahc_eval while a worker spun on a
different blackhole inside run_spark. **A thread that is WAITING
must not ACQUIRE**: the spark a spinner helps with blackholes
fresh thunks that the thread it waits for may then demand, which
is a dependency cycle the program never contained. Plain spinning
is safe for the mirror-image reason - ownership follows the
program's own dependency graph, so a cycle there really is a
<<loop>>. C1's own comment had dismissed this case as a program
bug; b_parsort is a correct program. Helping is removed.

C3 sequential gate: PASS - geometric mean 0.892x of Boehm across
six workloads (bar <= 1.00); the generational write barrier did
not eat the allocator's margin.

C3 parallel gate: FAIL - parfib 2.22x/2.06x and parsort
1.54x/2.08x at 2/4 workers against 1.6x/2.5x bars, so the B1 bar
remains uncleared and the earlier 3.37x reading is withdrawn (it
depended on the unsafe helping). (A further claim here, that four
workers are slower than two on parfib, was qualified in M112: the
47% magnitude was a harness artifact, the residual difference is
~6% and parfib-specific.) The exit
is structural - let a blocked thread re-evaluate the claimed
thunk and race to update (safe by purity, never blocks), which
requires the node layout to stop overwriting u.thunk.code/env at
claim time.

C2 gate: FAIL on peak RSS - geometric mean 2.31x of Boehm against
a 2.0x bar, though every correctness half passes (exec suite,
forced-collection soak at 0/2/4 workers, TSan). Two hypotheses
were measured and rejected: madvise is RSS-neutral even on large
heaps, and the trigger floor is not the lever. Peak RSS *is* the
committed high-water mark, so it can only be lowered by
collecting earlier - a growth-aware trigger, plus size-class
fragmentation work.

Generational collection, and a stage that measured itself out of
existence (M108, campaign stages C3+C4):

C3 makes the own collector generational. Sticky mark bits plus a
per-block epoch mean a minor collection sweeps only the blocks
allocated into this cycle; a major clears the bitmap and re-marks
everything. The write barrier is the single hot site the design
note promised - the thunk IND update - plus one cold one, feeding
per-thread sequential store buffers; bounded runtime structures
(tasks, scopes, channels, protected values) are re-walked each
cycle instead, which is the remembered set for everything that is
not the pure graph. Workers default ON under AHC_GC=own.

C3 also produced the campaign's sharpest lesson, now an invariant
with a tool to enforce it: **in a generational collector,
allocation order is a correctness property**. ahc_mk_con had
allocated the owner before its fields for a hundred milestones; a
collection landing between those two allocations marks the
half-built owner sticky-old, and the young fields array it then
receives is invisible to the next minor - freed while referenced.
AHC_OWN_PARANOID=1 shadow-marks after every minor and names any
object the sticky view would lose (=2 hunts the referrer that
holds the edge, which is what found this one); the exec suite
runs clean under it.

C4 (parallel marking) was MEASURED AND DECLINED. The design note
admitted it only if a profile showed mark time dominating after
C3, so the collector was taught to time its own phases - and mark
is 4-21% of wall (45-89% of GC time, but GC is only 5-24% of
wall). The bar is not met and the stage does not land. The same
profile, however, found two real defects: MADV_FREE_REUSABLE was
costing a syscall per freed block - 24% of parfib's wall time -
while moving peak RSS by 0-1MB (now opt-in via AHC_OWN_MADVISE),
and the sweep walked every slot of blocks that were entirely
garbage when their mark-bitmap slice is one contiguous 1KB read
(sweep on parfib: 2.35s -> 0.17s). Together: parfib 16.7s ->
11.5s sequential and 6.19s -> 3.41s at 4 workers. (The 4-worker
figure was measured with spin-helping, which M109 then removed as
unsafe; see below - the B1 parallel bar is NOT cleared. The
sequential gains stand.) Profile the phase you are about to
optimize; it may not be the one costing you.

The own collector arrives (M107, campaign stages C1+C2): AHC_GC=
own builds against the project's own memory manager - a
block-structured, non-moving, Immix-shaped allocator-plus-
collector designed in docs/collector-design-note.md. C1: 64KB
blocks from one 64GB virtual reservation, per-thread bump
allocation per size class and kind (node / pointer-array / misc),
per-thread chunk carving (global lock once per 16MB), and
spin-helping (a blackhole spinner runs another spark, capped at
depth 4 - the cap is a war story). C2: stop-the-world mark-sweep
with cooperative rendezvous at three safepoint families, live-
extent conservative stack scanning (the M102 bookkeeping,
rescanned by our own tracer), a conservative data-segment root
scan (zero codegen changes; precise root arrays deferred to C3),
by-tag precise heap tracing with misc structs scanned
conservatively, and OBJECT-grain sweep via per-block free-slot
lists - block-grain alone ratcheted b_map to 52x Boehm's RSS;
object-grain brought the bench-suite geometric mean to 1.96x
(gate: 2.0x). Sequential wall time beats the Boehm build (0.778x
geometric mean at C1; still ahead with collections on). Every
exec golden byte-identical under AHC_GC=own at 0/2/4 workers
with collections forced every 8MB; TSan audits the rendezvous
and found five real bugs across the campaign (a recursing
safepoint, a register spill outside the scan floor, a worker
reading the collector's private flag, mixed-atomicity pool
accesses, and the help-depth frame exhaustion). Boehm remains
the default until C3 and a full green release, per the note.

Sparks land opt-in; the gate returns a finding (M105, Phase B1):
Control.Parallel (par/pseq) over a multi-threaded thunk protocol -
CAS claim via a transient tag, release/acquire IND updates, worker
OS threads with Chase-Lev spark deques that never park on
blackholes, and sparked errors captured into re-raising thunks so
error programs stay byte-identical at every worker count. TSan is
an acceptance harness (scripts/run_tsan.sh) and found two real
races in the first draft of the protocol. Workers are OPT-IN
(AHC_WORKERS=N; default 0): the benchmark gate (>= 1.6x on 2
workers, scripts/run_parbench.sh) recorded 0.46-0.70x under the
shipped collector, and the control experiments isolated the cause
- Boehm anti-scales under parallel allocation-storm mutation in
every configuration tried (stock, tuned, thread-local-alloc
source build, collections disabled), while the identical runtime
over plain malloc scales 2.06x/2.58x/2.96x at 2/4/8 workers. The
allocator is the sixth hot subsystem the Phase B inventory
missed; the postmortem and the collector-campaign prerequisite
are design note section 7.8. Shipped regardless: sequential
allocation now batches through GC_malloc_many per-thread free
lists (measurably faster), worker stacks get the 512MB
virtual-reservation treatment, and the main stack reservation
doubles to 1GB (the new eval locals nudged a 2M-deep thunk chain
over the old 512MB edge - caught by the bench harness's
output-verification step).

Protected values (M103): Control.Concurrent.Protected - Ada's
protected object with the no-blocking rule made a type. Shared
state accessed only through pure transitions: reading (atomic
snapshot), updating (s -> (s, r)), and entry behind a pure
barrier (s -> Bool) with callers parked FIFO and the queue
rescanned from the head after every commit (Ada's eggshell
epilogue, order pinned - wake order is a testable golden).
Commits force the new state to WHNF inside the protected action,
so a named transition's {-# PRE/POST #-} contracts fire before
any other task can see the state, with zero new contract
machinery; refined state fields keep their demand rule and die at
first observation. GHC shim: a TVar with the barrier spelled
retry. Four prims, five prot_* exec goldens, design note
section 6.

Deterministic structured concurrency, Phase A (M102):
Control.Concurrent.Scoped - scope/spawn/await, unbounded FIFO
channels (newChan/send/recv), and yield, over green threads on one
OS thread with a strictly deterministic FIFO round-robin scheduler
whose only scheduling points are the IO bind boundaries, blocking
operations, and yield. Same program, same input, same schedule,
same bytes - an interleaving is now a testable golden
(tests/exec/conc_interleave.hs), a deadlock is a reported outcome,
and a failed child nobody awaited fails its scope at the join
point (Ada's master rule as the primitive; there is no forkIO).
Runtime: ucontext coroutines with 64MB virtual guard-paged stacks,
live-extent GC registration (GC_set_stackbottom + GC_add_roots per
switch), per-task error frames, blackholes that park a foreign
forcer and still die <<loop>> on self-dependency, and Scope/Task/
Chan as registry indices per the Handle discipline. Six exec
goldens; schedule-independent programs differential-tested against
GHC via tests/shim (runghc -i tests/shim). Design and the
four-language survey behind it: docs/concurrency-design-note.md.
War stories: the 56-byte ucontext stub and the silent 8MB stack
overflow (MANUAL chapter 16).

The dogfood binding (M101): examples/sqlite - ahcsql binds the
OS-shipped sqlite3 in ~80 lines and runs a full session against an
in-memory database: an out-parameter open (mallocBytes/peekPtr),
SQL strings in and column values out, CInt result codes, a Haskell
lambda as sqlite3_exec's row callback walking char** arrays
NULL-safely, and the C library's own error message peeked back on a
bad query. scripts/run_sqlite.sh keeps it green. This is the proof
the FFI plan aimed at: binding a real C library is now an
afternoon, not a compiler feature.

The classic lands (M100): tests/exec/ffi_qsort.hs - libc's qsort
sorting a C Int64 array with a Haskell comparator, exercising the
wrapper callback, the marshal surface, and the fixed-width types in
one golden. The whole-FFI smoke test the plan aimed at from the
start.

The marshal surface (M99): raw memory for C interop, all through
the existing prims boundary - mallocBytes/free, plusPtr/castPtr,
peek/poke at every fixed width plus Double and Ptr (byte offsets,
memcpy'd so alignment never bites, poke values range-checked),
newCString (malloc'd, released with free), and peekCStringLen.
peek/poke move primitive values only; the memory is not scanned by
the collector. This unlocks C APIs that traffic in arrays, structs,
and out-parameters. Exec goldens cover the full round trip and the
poke range death.

Boundary errors respect the embedding (M98): while a foreign-export
entry function is on the stack, a runtime error - error, a
pattern-match failure, an FFI range death, a contract or refinement
violation - unwinds (setjmp/longjmp, 8-deep frame stack) to that
entry instead of killing the host process; the entry returns 0/NULL
and ahc_last_error() carries the message until the next call.
Ordinary AHC programs are untouched: outside an armed entry ahc_die
prints and exits as before, and every exit path in the runtime
(error, contract claims, openFile, closed handles, refinement
violations) now routes through the same choke point with its
message format preserved byte-for-byte. The generated bindings
speak each language's idiom: C++ throws std::runtime_error, Rust
returns Result<T, String>, Go returns (T, error), GHC raises
IOError. tests/export gains a `boom` export; every spoke example
now errors, catches, and keeps computing.

## v1.5 (2026-07-26)

The FFI release (M89-M97): a complete bidirectional foreign
function interface built as a C-ABI hub with generated per-language
spokes. `foreign import ccall` and `foreign export ccall` (Report
chapter 8), library mode with a generated C header, Haskell
closures as C function pointers, fixed-width C types, and
`ahc bindgen` producing idiomatic C++, Rust, Go, and GHC bindings -
one AHC-compiled library demonstrably embedded from all four, plus
plain C. The milestone entries below tell the story newest-first.

The spokes (M96-M97): `ahc bindgen cpp|rust|go|ghc Lib.hs OUT`
generates idiomatic host-language bindings next to ahc_exports.h -
a C++ RAII class, a Rust module of safe wrappers over a raw extern
block, a cgo package that funnels every call onto one locked OS
thread, and a GHC foreign-import module (two Haskell runtimes in
one process). examples/ffi/ holds a working consumer per language
over the shared tests/export/MathLib.hs; scripts/run_bindgen.sh
builds and runs whichever spokes have their toolchain installed -
all four (clang++, rustc, go, ghc) verified end to end. MANUAL
ch. 9 closes with the hub-and-spoke story.

Fixed-width C types (M95): Int8/16/32/64 and Word8/16/32/64 as
builtin tycons, with CChar/CInt/CUInt/CLong/CULong/CSize as wired
synonyms (LP64 widths). `int abs(int)` is now honestly
`CInt -> CInt` - closing the Int=long caveat that made
int-returning libc functions undeclarable. Runtime nodes are plain
AHC_INT sharing Int's Num/Integral/Eq/Ord/Show dictionaries
(arithmetic stays exact and promoting; the width is enforced only
at the FFI boundary, where out-of-range values die with the width
in the message instead of truncating). Word64 results above 2^63-1
box as bignums via the new ahc_mk_ulong; the reverse direction
accepts 0..2^63-1 in v1. Marshalling covers imports, exports, and
callback trampolines uniformly; exec goldens cover abs/toupper
round trips and the Int32 range death.

Callbacks (M94): `FunPtr a` (phantom C function pointer with
Eq/Ord, `nullFunPtr`) and `foreign import ccall "wrapper"` - a
Haskell closure becomes a real C function pointer. The type must be
`ft -> IO (FunPtr ft)`, checked structurally. Each wrapper-import
site gets a static pool of 32 statically-typed C trampolines plus a
closure-slot array (static data, so the Boehm collector sees the
closures; no libffi dependency); a runtime registry maps trampoline
addresses back to slots so `freeHaskellFunPtr` can clear them, and
a C call through a freed pointer dies cleanly. `"dynamic"` imports
are rejected with a clear message. Exec tests drive callbacks
through libc itself: a signal handler invoked by raise(SIGINT) and
an atexit hook that fires after main returns; a second test goldens
the use-after-free death. FunPtr marshals as a pointer in ordinary
imports/exports (e.g. signal's second argument).

The FFI goes bidirectional (M93): `foreign export ccall` and
library mode. An export names one of the module's own bindings; its
type rides the same signature channel (installed when the binding
has none, superseded by the binding's own signature otherwise, so
the C prototype always reflects the real type). Codegen emits a
C-ABI entry function per export in the root unit - marshal C
arguments to nodes, build the spine, `ahc_eval` or the new
`ahc_run_io`, unbox - and generates ahc_exports.h with
extern-"C"-guarded prototypes. Exported String results come back as
malloc'd `char *` the caller frees; a bignum-promoted Int result
dies cleanly. C names are validated in the frontend (exporting
Haskell's `double` without a "c_name" impent is an AHC diagnostic,
not a clang error).

`ahc emit --lib` plus `ahc-build.sh --lib OUT.a` produce a static
archive (runtime included) whose root unit carries
`ahc_lib_init(void)` - RTS init plus every unit initializer in
dependency order - instead of main(). The embedding contract: call
ahc_lib_init once, then call exports from that same thread. New
round-trip harness scripts/run_export.sh builds tests/export's
library, compiles a C main against the generated header, and diffs
the output; golden negatives cover export-of-undefined and
C-keyword names.

The FFI arrives (M89-M92): `foreign import ccall` end to end -
Report chapter 8's import half, restricted to the ccall convention
and plain symbol impents. A foreign declaration is a bodiless
global: the renamer feeds its type through the ordinary signature
channel (kinds and the typechecker have no FFI special cases), the
desugarer derives a marshalling spec from the scheme, and codegen
emits an extern prototype plus a wrapper in the owning module's C
unit - evaluate and unbox each argument, call, box the result.
IO-typed imports get the world-passing shape, so effect ordering is
exactly the built-in primitives'; pure imports call at saturation;
nullary pure imports are CAFs.

The v1 marshallable universe is Int (=long; a bignum-promoted value
dies cleanly at the boundary rather than truncating), Double, Char,
Bool, `()` (results), String (copied each way), and the new
`Ptr a` - a phantom-typed raw C pointer with wired Eq/Ord,
`nullPtr`, and `peekCString :: Ptr Char -> IO String` for nullable
C results like getenv. Runtime groundwork: an `AHC_PTR` node tag,
`ahc_mk_primn` (a general curried collector that removes the old
arity-3 prim ceiling), and `ahc_marshal_cstring`/`ahc_free_cstring`.

Build plumbing: `AHC_CFLAGS`/`AHC_LDFLAGS` pass through
scripts/ahc-build.sh, `{-# OPTIONS_AHC_LINK -lfoo #-}` collects
link flags from the source into OUT.build/link_flags (GHC only
warns on the unknown pragma), and compile flags join the
object-cache key so a flag change can never reuse a stale object.
New tests: ffi_libc, ffi_io, ffi_bigint_err exec goldens, a parse
golden, and a marshallability-diagnostic golden. MANUAL chapter 9
gains an FFI section with the type table and the two honesty rules
(match the C definition under Int=long; bignum dies at the
boundary).

## v1.4.2 (2026-07-26)

The value-constraint patch (M87-M88): two example programs, no
compiler changes. ahccal (examples/cal) - a civil calendar built
entirely out of declared constraints, the worked tour of refinement
types and Pre/Post contracts working together, and the first
example that is AHC-only by construction. fastfibinwest
(examples/fibs) - a stray broken file turned into a working
bignum Fibonacci CLI. The examples harness grows from 13 tests to
28 across five programs, and learns to assert that constraints
actually fire and that --unchecked changes no answer.

examples/fibs repaired and promoted: fastfibinwest.hs was a stray
broken file (`Main = do` bound a nonexistent constructor, so both
compilers rejected it) and is now a working CLI - fib by fast
doubling, reading indices from arguments or stdin, one result per
line, with per-word error reporting. The only real gap behind it
was `Data.Bits.bitSize`, deprecated in base and absent from AHC's
Data.Bits; rather than add it, the program derives the bit width
from its own argument, because an AHC Int promotes to bignum on
overflow and therefore has no fixed width to report honestly.
Everything else in the original already worked (an
MR-restricted `foldl_ = foldl'`, a `let` inside a list-comprehension
generator, descending stepped enumeration, bignum arithmetic). It
carries a `{-# PRE fib \n -> n >= 0 #-}` that main's boundary check
guarantees can never fire, and it is oracle-verified: goldens are
GHC 9.4.8's output, crossing the fib 92/93 machine-word boundary
where AHC's hand-rolled limbs meet GMP. fib 1000000 (208988
digits) takes ~1.1s.

The value-constraint example (M87): examples/cal - ahccal, a civil
calendar utility and the worked tour of the Ada extension's two
halves working together. Four refinement kinds carry the values
(Int ranges for Year/Month/Day/DayOfYear, a `satisfying` predicate
for LeapYear, `Int mod 7` and `Int mod 1440` for weekdays and
clocks, `Double in -12.0 .. 14.0` for real UTC offsets, all of them
inside constructor fields on Date), and Pre/Post contracts carry
the relations no per-value constraint can state - February 31st is
a `mkDate` precondition, not a `Day` bound. The date/integer
isomorphism is fully specified: dayNumber and dateOf are declared
to invert each other, addDays and daysBetween are specified in
terms of them, and every call in the test suite checks all of it at
demand time. The program contains no hand-written validation
whatsoever; every failure message it can produce comes from a check
the compiler inserted.

The examples harness grows from 13 tests to 25, and gains two
assertions no other example could make: the four constraint kinds
each fail with the right message and a nonzero exit, and the
`--unchecked` build agrees with the checked build on every valid
input - which also pins that modular normalization survives the
release policy while the claims do not. ahccal is the first example
that is AHC-only by construction (contract pragmas are portable,
the refinement surface is not), so its goldens are AHC's output and
`run_examples.sh --oracle` skips it, with `--update-cal` to
regenerate.

Two things the build found, both recorded in examples/cal/README.md:
refined type synonyms work in constructor fields (`data Date = Date
Year Month Day` checks every construction) - previously only
inline field refinements were pinned; and a contract on a function
whose signature carries refinements is never discharged even when
its claim is argument-free, which is why the one argument-free
claim in the program lives on an unrefined helper. Incompleteness,
not unsoundness - but a real limit on the discharge evaluator's
reach, measured on a real program for the first time.

## v1.4.1 (2026-07-25)

The dogfood patch (M85-M86): two new example programs, no
compiler changes. ajson (examples/json) - a JSON parser and
pretty-printer with a Data.Map --stats mode, leaning on v1.4's
exact-literal and Burger-Dybvig show machinery. microhm
(examples/hm) - a miniature Hindley-Milner inferencer, the
compiler's typechecker in ~350-line miniature with the real
Bind_Meta occurs-check obligation restated as a live contract;
the STUDY-GUIDE's Station 6 companion. BOTH came up
byte-identical under AHC and GHC on their first builds - the
first dogfood programs in the project's history to do so. The
examples harness now runs 13 tests across three programs.

The third dogfood program (M86): examples/hm - microhm, a
miniature Hindley-Milner inferencer (Algorithm W,
let-polymorphism, occurs check, Data.Map substitution
composition) - the compiler's typechecker in ~350-line miniature,
compiled by that machinery, byte-identical under both compilers
on the first AHC build (the second program in a row). The unifier
states the REAL typechecker's obligations as contracts: bindVar
carries the Bind_Meta occurs-check precondition as a {-# PRE #-},
live and demanded on every unification in the test suite. Doubles
as the STUDY-GUIDE's Station 6 companion. Exercises previously
un-dogfooded ground: map-valued Data.Map workloads, deep mutual
recursion, threaded fresh-name supplies.

The second dogfood program (M85): examples/json - ajson, a JSON
parser and pretty-printer in the AHC subset, byte-identical
compiled by AHC or interpreted by GHC across parse/pretty, error
reporting, and a Data.Map --stats mode (goldens in the examples
harness). It leans on everything v1.4 built: numbers are
fromRational of the exact decimal ratio, output goes through the
Burger-Dybvig show, \uXXXX escapes round-trip as code points with
ASCII-only IO. First dogfood in the project's history to come up
byte-identical on the FIRST build - the exactness release doing
its job.

## v1.4 (2026-07-25)

The exactness release (M82-M83). Float literals became exact
decimal ratios end to end - `0.1 :: Rational` is `1 % 10`, every
Double literal keeps its strtod-exact value through one correctly
rounded conversion, and the oldest EXCLUSIONS entry fell.
Non-nullary deriving is rejected at compile time instead of
compiling to runtime stubs. Double's show now generates shortest
round-trip digits by GHC's exact Burger-Dybvig algorithm, not
printf rounding. The fuzzer's menu grew seven type families and
its first 10,000-seed campaign ran - after teaching two hard
lessons (a harness must time-limit every subprocess; a generator
must emit TRACTABLE programs, not merely terminating ones) it
found four compiler bugs down to a floored-mod overflow that
surfaced three layers up as a mis-reduced Rational. All fixed,
all pinned. Conformance suite: 69 -> 74 programs, byte-identical
to GHC 9.4.8. A CI workflow exists but is parked pending GitHub
billing (workflow_dispatch only). docs/fuzzer-guide.md documents
campaign practice; docs/STUDY-GUIDE.md gives newcomers the
guided path through the codebase.

Fuzzer menu expansion + the first deep campaign (M83):

- **The menu grew** (docs/fuzzer-guide.md documents usage, triage
  and the menu rule): records (construction, update, selectors), a
  fielded ADT exercising the pattern matrix and derived Eq/Ord/Show
  with negative fields, Either, Rational (exact literals, %,
  numerator/denominator, guarded / and recip, fromRational),
  exponent-form Double literals, sin/cos/log/exp, and
  multi-binding let. Every construct was pinned byte-identical on
  both compilers before entering the menu, per the standing rule.
- **The harness can no longer be wedged.** Every external step
  (generate, oracle, build, run) runs under a time limit, with two
  new outcomes: SLOW-ORACLE (skip - an expensive program) and
  SLOW-AHC (a finding). This was not theoretical: the first deep
  campaign was discovered six hours in with three ORACLE processes
  pegged at 100% CPU, the harness patiently waiting on programs
  that would never finish. scripts/run_fuzz_par.sh splits a range
  across parallel jobs over a compiled generator (~20x faster than
  interpreting it per seed).
- **The generator now emits TRACTABLE programs**, not merely
  terminating ones - two disciplines, both learned from that
  wedge. The recursive call is let-bound and the generator hands
  out the variable, so k uses share one thunk (inlining "(f xs)"
  at k sites is k^depth; a 3^n body was the hang). And any
  construct whose cost depends on a value's MAGNITUDE is clamped:
  a Double range's step falls below one ULP at large magnitudes
  (v + 1.5 == v), making the range an infinite list.
- **Three compiler bugs found, fixed and pinned** (suite: 70 ->
  74 programs):
  - **show, shortest-round-trip digits**: four seeds printed a
    different last digit from GHC on bit-IDENTICAL values. GHC
    picks digits by Burger-Dybvig; AHC derived them from printf's
    correctly-rounded decimal, which agrees except on boundary
    cases where two renderings both round-trip. The runtime now
    implements GHC's floatToDigits exactly, over the existing
    bignum limbs (ch11_04_show_double_digits.hs).
  - **show, denormals**: the new digit generator took the
    asymmetric boundary case at the minimum exponent. A denormal's
    neighbours are evenly spaced - only a power-of-two significand
    ABOVE the minimum exponent is asymmetric - so values below
    2^-1022 printed one digit too many (ch11_04_show_denormal.hs).
  - **mod, large positives**: the textbook floored-mod idiom
    ((x`rem`y)+y)`rem`y OVERFLOWS when both operands are large
    positives, wrapping negative. 7.4e18 `mod` 8.2e18 surfaced as
    a wrong gcd and a mis-reduced Rational, layers above the
    arithmetic (ch06_04_mod_large.hs). div was already correct;
    add/sub/mul use __builtin_*_overflow.

CI + correctness mop-up (M82):

- **Non-nullary deriving Enum/Bounded/Ix/Read is rejected at
  compile time** ("all constructors must be nullary") instead of
  compiling to runtime error stubs - AHC no longer accepts what
  GHC rejects here (bad_derive_nonnullary.hs pins the agreement;
  the single-constructor Bounded/Ix products GHC additionally
  accepts stay honestly unimplemented).
- **Float literals are exact decimal ratios** (Report 6.4):
  codegen emits an exact numerator/denominator pair (Ratio-shaped
  node) when Data.Ratio is in the program; the wired Rational
  placeholder expands like a nullary synonym in unification once
  `type Rational` exists; Data.Ratio gains the real source
  fromRational, and Fractional Double's fromRational converts the
  pair with ONE round-to-nearest-even. `0.1 :: Rational` is
  `1 % 10`; every Double literal keeps its strtod-exact value.
  The oldest EXCLUSIONS entry is struck
  (ch06_04_rational_literals.hs, suite: 70).
- **GitHub Actions CI** (.github/workflows/ci.yml): ubuntu runner
  with Alire/GNAT and ghcup GHC 9.4.8, both build profiles, 219
  unit tests, all eleven harnesses, 50 fuzz seeds, on every push
  and PR. First cross-platform dividend arrived before the first
  run: the 512MB-stack link flag was Darwin-only syntax;
  ahc-build.sh now gates it per OS.

## v1.3 (2026-07-24)

The verification-and-tooling release: the five-item post-v1.2
roadmap, complete. A differential fuzzer that generates random
well-typed programs and byte-compares AHC against GHC per seed
(M76); real `seq`, `($!)` and an honest `foldl'` (M77); the full
System.IO file-handle API (M78); `ahc repl`, compile-and-run over
the object cache with no second evaluator (M79-M80); and
compile-time contract discharge - what the compiler can prove,
the runtime need not check (M81). The new tooling immediately paid
its way: the fuzzer and the REPL's first sessions found FIVE real
compiler bugs the hand-written suite had never touched (a
layout-vs-lookahead corner, Integer->Double rounding drift,
negative-zero show, wired-body theft by name shadowing, and
implicit-Prelude qualified resolution) - every one fixed and
pinned. Conformance suite: 62 -> 69 programs, all byte-identical
to GHC 9.4.8; eleven test harnesses; 300-seed fuzz campaigns
green.

Compile-time contract discharge (M81 - the roadmap's last item):

- **What the compiler can prove, the runtime need not check** -
  Ada's policy, transplanted. AHC.Discharge is a fuel-bounded
  constant evaluator over elaborated Core (closures over the
  existing arena, eager arguments, lazy branches, two-pass letrec
  for dictionary globals, selector projection through known
  dictionaries, Int primitive folding). Every contract claim is
  evaluated once at compile time with its parameters OPAQUE:
  proved True -> the claim is dropped before the wrapper is built
  (both dropped means no wrapper, zero overhead); proved False ->
  "this precondition can never hold" warning, check kept; Unknown
  -> check kept. Opaque parameters poison every consuming path, so
  argument-dependent predicates can never discharge by mistake -
  incompleteness is possible, unsoundness is not.
- Install_Bodies now runs BEFORE Insert_Checks (the evaluator
  reduces through the wired dictionaries, which must exist).
- Proved three ways: scripts/run_discharge.sh greps the generated
  C (trivially-true claims absent, argument-dependent present,
  provably-false warns and stays); ext_contracts_discharge.hs
  pins unchanged observable behavior under the GHC oracle
  (suite: 69); tests/exec/contract_never.hs pins that a
  never-holding contract still fails at demand time with the
  standard message.

The REPL (M79 design note, M80 implementation):

- **`ahc repl`**: compile-and-run over the M63 object cache
  (docs/repl-design-note.md). The REPL adds NO second evaluator -
  every entry becomes a real program built by the real pipeline
  and run by the real runtime, so every conformance guarantee
  carries over. Session state is two generated modules: Repl
  (accumulated imports + declarations, validated and rolled back
  on error - a bad entry never poisons the session) and Main
  (`it = <expr>` plus a runner chosen by the inferred type: IO
  actions run, everything else prints). Line classification uses
  the real parser, not a regex. Commands: :type, :load (GHCi's
  reset-on-load), :reload, :clear, :help, :quit. Pinned
  transcripts in tests/repl/ via scripts/run_repl.sh.
- **The REPL's first session found compiler bug four**: with
  Data.Map imported, `nub` died on a missing global.
  Install_Bodies attached wired Prelude bodies by bare-name
  lookup in the MUTABLE flat env, which any module re-defining
  the name (Data.Map's filter) had clobbered - the wired var was
  left bodiless. Wired bodies now resolve through the Base
  snapshot. The same session's pinning exposed bug five:
  `Prelude.filter` with a local `filter` defined resolved to the
  LOCAL one (the implicit-Prelude qualified path consulted the
  own-module map first); it now goes straight to the Base
  snapshot. Both pinned in ch05_wired_shadowing.hs (suite: 68).

System.IO file handles (M78):

- **The full practical handle API**: openFile/hClose/withFile,
  hPutStr/hPutStrLn/hPutChar/hPrint, hGetLine/hGetChar/
  hGetContents/hIsEOF/hFlush, writeFile/appendFile, and
  stdin/stdout/stderr as first-class handles. IOMode is an
  ordinary source enumeration deriving exactly GHC's instances
  (Eq, Ord, Show, Enum - GHC has no Bounded IOMode, verified the
  hard way).
- **The runtime deals only in integers**: a Handle is an index
  into a small registry of FILE pointers (std streams pre-seeded
  at 0..2), so an operation on a closed handle dies with a clean
  message instead of touching freed memory; the Handle type is
  ABSTRACT in source (constructor unexported), so the only handles
  in circulation come from openFile. Eight new prims; everything
  else - withFile, writeFile, hPutStrLn, hPrint - is ordinary
  Haskell in lib/System/IO.hs.
- Two documented divergences (EXCLUSIONS): hGetContents is strict
  (GHC's lazy semi-closed-handle behavior means portable programs
  must not touch the handle afterward regardless), and hClose on a
  std stream flushes rather than closes. ch07_io_handles.hs pins
  the whole surface byte-identical (suite: 67);
  tests/exec/handle_errors.hs and handle_missing.hs pin the error
  paths.

Real seq + strictness (M77):

- **`seq` is a primitive**: force to WHNF, yield the second
  argument (p_seq in the runtime; wired global with scheme
  `a -> b -> b`; the Report fixity `infixr 0` was already in the
  table waiting). `($!)` is built on it in the wired Prelude.
- **`Data.List.foldl'` is honest**: the accumulator is forced at
  every step (`let z' = f z x in z' `seq` ...`) instead of being a
  renamed `foldl` - the EXCLUSIONS row is gone. WHNF semantics
  pinned: `seq [undefined] x` forces the spine's first constructor
  only.
- Verified three ways: ch06_02_seq.hs (GHC-oracle values),
  tests/exec/seq_strict.hs (the forcing itself: output order and
  the forced error - p_error now flushes stdout before dying so
  effects precede the die message), and the fuzzer's menu grew seq
  and foldl' productions.
- **The extended fuzz campaign found bug three (seed 17): negative
  zero**. `-0.0 == 0.0` is True, so fmt_double's equality-based
  zero fast path printed "0.0" for negative zero; showsPrec's
  parenthesization tested `v < 0`, also blind to -0.0. Show now
  honors the sign bit, and parenthesization keys off the formatted
  leading '-' (covering -0.0 and -Infinity, excluding NaN, exactly
  GHC's behavior). Pinned as ch06_04_negative_zero.hs (suite: 66).
- Measured honestly (scripts/run_bench.sh): foldl' is about
  strictness, not speed - on a 2M-element sum that fits in memory
  the strict fold pays ~30% for the per-element force
  (b_strictfold 2.46s vs b_sumfold 1.86s, optimized); its win is
  the space guarantee, not wall time. Both benches stay in the
  suite so the trade-off remains visible.

Differential fuzzer (M76):

- **scripts/run_fuzz.sh + tests/fuzz/Gen.hs**: a seeded generator
  of random well-typed Haskell 2010 programs (deterministic 64-bit
  LCG; runs under GHC, base-only) whose every construct and library
  function was first pinned byte-identical on both compilers, so a
  divergence is always a real finding. Each seed's program is
  compiled by AHC and interpreted by GHC and the stdout compared
  byte for byte; divergences are saved to tests/fuzz-failures/ and
  auto-shrunk by delta debugging (scripts/shrink_fuzz.py: drop main
  statements and whole definitions while the same divergence
  reproduces). Known-undefined territory is avoided by
  construction: Int arithmetic stays small, text stays ASCII,
  partial functions are never emitted.
- **First blood, seed 3**: a single-line `let ... in` inside an
  explicit-brace case alternative inside a do block produced
  spurious "'}' without matching explicit '{'" errors. Root cause:
  the do-statement bind/expression lookahead (Arrow_Ahead) drained
  tokens through the layout engine WITHOUT the parser's
  parse-error(t) feedback, so the let's implicit context was never
  closed. Fix: the scan now stops at the first token a pattern
  cannot contain (let/case/if/do/lambda/...), which both answers
  the question early and keeps lookahead from opening layout
  contexts at all. Pinned as ch10_03_lookahead_let.hs.
- **Seed 57: Integer->Double rounding**. `fromIntegral` on a
  bignum accumulated per-limb (`v * 2^32 + limb`), rounding at
  every step; values a few bits past 53 drifted by ulps from GHC
  (1.610269053685309e26 vs the correct ...095e26). The runtime now
  takes the top 53 bits and applies ONE round-to-nearest-even with
  a proper round/sticky pair - GHC's integerToDouble semantics.
  Pinned as ch06_04_integer_to_double.hs (suite: 64, including
  2^64±1, 2^53+1, and 10^300).

## v1.2 (2026-07-23)

The polish-and-depth release: every milestone of docs/polish-plan.md
(M64-M75) shipped. Correctness debt first (cross-module diagnostic
spans, a join-point sharing fix found while testing fail-at-Maybe),
then GHC-compat breadth (Applicative, Enum at Char/Double, deriving
Enum/Bounded/Ix/Read for enumerations, properFraction + RealFloat),
the architectural payoffs (polymorphic Ratio a and Complex a,
Data.Set), the contracts extension (Ada's Pre/Post as pragmas -
refinements govern values, contracts govern functions, closing the
Ada story), and finally a measured optimizer round (up to 2.1x) and
the module-system corners. Conformance suite: 51 -> 62 programs,
all byte-identical to GHC 9.4.8. Nothing planned remains unbuilt.

Module-system corners (M75 - the polish plan's last item):

- **Restricting the implicit Prelude import** (Report 5.6.1): an
  explicit `import Prelude ...` now replaces the implicit one.
  `hiding` frees names for local definitions, only-lists narrow,
  `import Prelude ()` empties, `qualified` forces qualification.
  The explicit import reuses the ordinary import-view filter over
  the Base snapshot; the renamer's snapshot fallback switches off
  when one is present. Pinned by conformance (ext_prelude_*.hs -
  suite now 62) and both-reject differentials (bad_prelude_*.hs):
  hiding filters the QUALIFIED view too, and builtin syntax
  (`()`, `[]`, `:`, tuples) can never be hidden - it is grammar.
- **Same-named synonyms/constructors across modules**: both
  namespaces are program-global; a collision is a clean
  compile-time error ("defined more than once") where GHC would
  disambiguate by module. Documented in EXCLUSIONS row 5 - the
  honest remaining flatness, never silent misresolution.

Measurement-driven optimizer round (M74):

- **Benchmark harness** scripts/run_bench.sh: five workloads in
  tests/bench/ (fib, strict fold over 2M ints, Data.List.sort on
  30k LCG-random elements, factorial-2000 bignum, 40k-entry
  Data.Map build-and-fold), each built with and without --no-opt,
  outputs verified identical, then timed with warmup plus
  interleaved best-of-5 so noise hits both sides equally. An
  initial sequential timing "found" a 24% fib regression that the
  interleaved harness dissolved entirely - the harness was
  hardened before the optimizer was touched, which is the point
  of measurement-driven.
- **Used-once let inlining**: a non-recursive let binding whose
  variable occurs exactly once, not under a lambda, is substituted
  at its use site (the rhs MOVES, preserving the tree invariant).
  One occurrence means the thunk was forced at most once anyway -
  sharing-exact; the lambda bar prevents turning one evaluation
  into many. Measured: 2.10x on the fold (was 1.58x), 1.91x on
  sort (was 1.19x), 1.28x on Map (was 1.11x), ~1.0x on
  call-dominated fib and prim-dominated bignum. All 59 conformance
  programs remain byte-identical with the optimizer on.

Function contracts (M72-M73, docs/contracts-design-note.md):

- **Ada's Pre/Post as pragmas**: {-# PRE f expr #-} /
  {-# POST f expr #-}. Each becomes a hidden top-level binding
  parsed from the pragma's own tokens (spans point into the
  pragma, so contract type errors land exactly there), typechecked
  against a signature DERIVED from f's own - tyvars, class
  context, argument spine, Bool. AHC.Refine wraps the function:
  forcing the result forces the precondition, then the body, then
  the postcondition against the let-shared result. Undemanded
  calls check nothing (demand time, like every refinement check);
  polymorphic functions get polymorphic contracts with the
  dictionaries threaded through; --unchecked strips all claims
  (Ada's assertion policy); one new runtime prim (check_claim).
- Compile-time errors: unknown function, duplicate PRE/POST,
  missing type signature, PRE on a value binding, and ordinary
  type errors at pragma spans.
- GHC ignores the pragmas (stderr warning only), so contracted
  source stays portable: ext_contracts.hs runs byte-identical
  under both compilers (suite now 59); tests/exec/contracts.hs
  pins the violation messages and demand-time semantics;
  examples/contracts.hs is the worked tour (clamp, a
  self-specifying integer sqrt, sorted-precondition binary search,
  polymorphic maxOf, laziness demo).

Track C - the architectural payoffs (M70-M71):

- **Polymorphic Ratio a and Complex a** (M70): data Ratio a with
  Integral-context instances and type Rational = Ratio Integer;
  data Complex a with RealFloat-context Num and polar family. The
  last monomorphic library shapes die, expressible only because
  the tower is real classes (M62/M69). Two rename rules extended:
  a type SYNONYM may shadow a builtin TyCon (symmetric with the
  data rule), and a visible synonym outranks the shadowed builtin
  at use sites. Suite entry lib_poly_ratio_complex.hs; existing
  ratio/complex tests unchanged and identical.
- **Data.Set + Map roundout** (M71): the weight-balanced tree
  without values (member/insert/delete/union/difference/
  intersection/filter/map, fromDistinctAscList's comparison-free
  balanced build), byte-identical to real containers (lib_set.hs);
  Map gains filter, foldlWithKey, keysSet, fromDistinctAscList.
  Set's constructors are SBin/STip: the renamer's constructor
  namespace is flat across modules (the M75 item), and Data.Map
  owns Bin/Tip. Suite now 58 programs.

properFraction + RealFloat (M69):

- **properFraction** joins RealFrac (result at Integer, where
  GHC's defaulting lands): truncation toward zero with the exact
  fractional remainder, body as Prelude source (dblPF_). The
  method's type is the tower's first pair-returning dict field.
- **RealFloat** is a real class (superclasses RealFrac, Floating)
  at Double/Float: isNaN, isInfinite, isNegativeZero (three new
  IEEE prims), and atan2 moves home from its monomorphic exile.
  Defaulting extended (print (isNaN (0/0)) just works).
- ch06_04_realfloat.hs byte-identical to GHC (computed NaN/
  Infinity/negative zero, both atan2 quadrant cases, destructured
  properFraction); suite now 56 programs. Track B of the polish
  plan is complete.

Enum at Char/Double + the deriving family (M67-M68):

- **Enum at Char and Double** (M67): real dictionaries with every
  method body as Prelude source. Char rides ord/chr (['a'..'z'],
  stepped, succ/pred, to/fromEnum); Double follows GHC's numeric
  enumeration - +1 chains with the Report 6.3.4 half-step limit,
  and K-INDEXED stepping (n + k*delta) for enumFromThen(To), probed
  empirically: the chained recurrence accumulates rounding where
  GHC's per-element rounding prints 0.4. The Enum Double/Float
  instances had never been registered; now they are.
- **deriving Enum, Bounded, Ix, Read for enumerations** (M68):
  constructor-tag arithmetic end to end - succ/pred/toEnum/
  fromEnum/all four enumFroms, minBound/maxBound, range/index/
  inRange/rangeSize, and Read via a maximal-munch token matcher
  (readsEnum_ in Text.Read) against a generated constructor table.
  Ix and Read derives target SOURCE classes - the deriving
  machinery finds any registered class. Bonus: the wired
  Bool/Ordering Enum instances ride the same branch, so [False ..]
  works. Suite now 55 programs (ch06_03_enum_char_double,
  ch11_01_derives).

Polish track A + Applicative (M64-M66, docs/polish-plan.md):

- **Fixed: cross-module diagnostic spans** (M64). Diagnostics carry
  an origin tag; the driver renders each against its own module's
  source. The fromRational warning now reports
  lib/Data/Ratio.hs:45:1 (the instance) instead of a meaningless
  root-file position; type errors in imported modules report the
  right file.
- **Fixed: refutable do-binds with multi-position patterns** (M65).
  The fail dictionaries were already complete (Maybe -> Nothing,
  [] -> skip), but Ds_Do passed the fail CALL as Match_One's
  failure continuation instead of a let-bound join-point variable -
  so a pattern like (x : y : _) failing at the second cons shared
  one `fail` node between failure positions and the evidence
  rewriter applied the dictionary twice ("applied a non-function").
  The tree invariant's third strike. Pinned by ch03_14_faildo.hs;
  EXCLUSIONS' stale 3.14 row corrected.
- **Applicative** (M66): an ordinary source Prelude class over the
  wired Functor - pure, <*>, liftA2 (with defaults for liftA2/
  *>/<*), plus <$> in the Prelude - instances at Maybe, [] and IO.
  First source class with a SUPERCLASS (the default methods reach
  fmap through sup$Applicative$1) and first []-headed source
  instances; both just worked. ch04_applicative.hs byte-identical
  to GHC. Suite now 53 programs.

## v1.1 (2026-07-21)

Everything after v1.0: the complete standard library (including the
formerly-deferred quartet and Data.Map), the mini-Lisp dogfood
program and the three compiler bugs it found, exhaustiveness and
redundancy warnings, the numeric tower as real classes, and
separate compilation. The deliberately-unbuilt list is empty.

Separate compilation (M63):

- **Per-module code generation with stable symbols**: `ahc emit`
  writes OUT.build/ with one C file per module plus a shared
  header. Globals are mangled from (module, source name) - never
  an arena id - and locals/lifted functions are numbered per unit,
  so a module's generated text depends only on its own code.
  Elaborated instance dictionaries are attributed to the module
  that declared the instance; the wired prelude and prim bodies
  form the Prelude unit. Per-unit init functions run in dependency
  order from main().
- **Content-addressed object cache**: ahc-build.sh compiles each
  unit (and the runtime) to an object keyed by the hash of its
  generated text and reuses it across builds. No-change and
  comment-only rebuilds compile ZERO objects; a semantic edit to
  one module recompiles exactly one. Interpreter rebuilds: ~6s ->
  ~1s (the frontend is ~0.3s; clang on the old monolith was 94% of
  every build).
- **The frontend stays whole-program by design** (no interface
  files): Report program-wide instance coherence holds by
  construction. Documented in EXCLUSIONS.
- New harness scripts/run_separate.sh pins the cache behavior;
  outputs remain byte-identical everywhere (same Core, partitioned
  emission).

The numeric tower as real classes (M62):

- **Integral** (superclasses Num, Ord) with instances at Int and
  Integer: quot/rem/div/mod stop being fake Num-constrained
  globals and become methods; the canonical bignum representation
  means both instances bind the same promoting prims and
  `toInteger` is the identity.
- **Floating** and **RealFrac** (superclass Fractional) with
  instances at Double: the whole vocabulary (pi, exp/log/sqrt,
  `**`, logBase, trig, hyperbolics; truncate/round/ceiling/floor
  at Integer results, where GHC's defaulting lands anyway) moves
  from monomorphic globals into real dictionaries. Same runtime
  prims - sqrt changed type, not behavior. atan2 stays monomorphic
  (RealFloat territory).
- **fromIntegral is ordinary Prelude source** (`fromInteger .
  toInteger`), fully polymorphic at last; **(^)/(^^)** added
  (exact `2 ^ 100` via bignum; the fast-exponentiation helper is a
  constraint-carrying where-binding - the M59 typechecker fix in
  action); even/odd/gcd/lcm generalized to Integral.
- Report 4.3.4 defaulting extended to the new classes
  (`print (floor 2.5)`, `print (sqrt 2)` default as GHC does).
- New conformance program ch06_04_tower.hs (52 lines of
  polymorphic tower use) byte-identical to GHC; suite now 51.

Exhaustiveness warnings (M61) and Data.List lookup (M60):

- **AHC.Exhaustive** - Maranget-style usefulness analysis over
  function equations and case alternatives: "non-exhaustive
  patterns in function 'f'" / "in case expression", and "redundant
  pattern" for clauses that can never fire. Handles constructors
  (incl. tuples, lists, records), literals (never a complete set),
  and guards (a clause counts as covering only when unguarded or
  carrying an otherwise/True alternative; guarded predecessors
  never shadow). Root module only - library and Prelude matches
  are vetted. Agrees line-for-line with GHC's
  -Wincomplete-patterns / -Woverlapping-patterns on the pinned
  corpus (tests/golden/check_matches).
- **Data.List now re-exports lookup**, matching base.

Data.Map (M59):

- **lib/Data/Map.hs** - a weight-balanced binary search tree
  (Adams' algorithm, the same family as GHC's containers):
  insert/delete/lookup/union/unionWith/fromList/adjust and friends,
  Show/Eq instances - observable behavior matches containers
  exactly and the conformance test oracles against the real thing.
  The mini-Lisp interpreter's environments now use it (Map under
  AHC, containers under GHC, still byte-identical).
- **Fixed: qualified type names.** `Map.Map` in a signature never
  consulted the qualifier - the renamer's type lookup now mirrors
  the value path (qualified-through-import resolves only in that
  module's exports, Report 5.3); same for qualified synonyms.
- **Fixed: constraints from where-helpers.** A wanted constraint
  arising inside an inner let - notably the match compiler's join
  points, i.e. ANY multi-equation where-helper - kept the inner
  binder as its owner, so the enclosing group's context never
  claimed it ("ambiguous type variable" on perfectly ordinary
  code). Unsolved wanteds now float to the enclosing binding when
  a group closes. Pinned by conformance where_context.hs (also
  covers superclass discharge: an Eq wanted met by an Ord given).
  The suite is now 50 programs.

Dogfooding (M58):

- **examples/lisp** - a mini-Lisp interpreter (REPL + batch) written
  in Haskell 2010 and compiled by AHC itself: exact numeric tower
  (bignum Integer / Rational / Double), closures, letrec via lazy
  knot-tying, boot prelude written in mini-Lisp. Verified
  byte-identical to the same source compiled by GHC
  (`scripts/run_examples.sh`, GHC-oracle goldens).
- **Fixed: cross-module type synonyms.** A synonym imported from
  another module expanded a syntax-arena id against the importing
  module's arena (garbage; typically "cyclic type synonym"). Kind
  checking now caches each synonym's converted Core rhs at its
  declaration and expansion substitutes into the cached form;
  failed (cyclic) synonyms are poisoned to report exactly once.
  Found by the interpreter's first compile.
- **System.IO.isEOF** - new primitive, needed by the REPL to see
  end-of-file coming (AHC's `getLine` errors at EOF, as does GHC's).
- New multi-module conformance case pinning cross-module synonyms
  (nullary and parametric); the suite is now 48 programs.

The standard library (docs/stdlib-plan.md), complete - every
milestone including everything the plan originally deferred:

- **Library modules** compiled by AHC through its own module system
  (`lib/`, resolved root-dir -> `$AHC_LIB` -> `lib/`): Data.List
  (base's exact production orders), Data.Char, Data.Maybe, Data.Ord,
  Data.Tuple, Data.Bool, Control.Monad + Data.Functor
  (Monad-polymorphic over IO/[]/Maybe), System.IO /
  System.Environment / System.Exit (input at last: getLine,
  getContents, readFile, interact, getArgs), Numeric, Data.Bits at
  Int, Data.Ix as an ordinary source class.
- **The formerly-deferred quartet** (M54-M57): Data.Ratio (exact
  fractions over bignum, GHC's `1 % 2` Show), Data.Complex at Double
  (new atan2 prim), Data.Array (Int-indexed, list-backed), Text.Read
  (a source Read class; GHC's exact `Prelude.read: no parse`).
- **Compiler enablers**: builtin-class default methods (E4 - a Show
  instance defining only `show` gets Report-correct
  showsPrec/showList; Ord defaults reach Eq through the superclass),
  `module M` re-exports (E5), derived Show for infix constructors,
  and a rename rule letting a library type take a builtin TyCon's
  name (how `Rational` claimed its own).
- Conformance suite grown 39 -> 48 programs, all byte-identical to
  GHC 9.4.8.

## v1.0 (2026-07-17)

First release. A Haskell 2010 compiler written in Ada 2022, built
around Design-by-Contract: the compiler's internal consistency is
enforced by preconditions, postconditions and type invariants in
every development build.

Everything in the PRD, including both stretch goals:

- **Full pipeline to native code**: lexer, Report 10.3 layout,
  recursive-descent parser for the whole Haskell 2010 surface,
  fixity resolution, renamer, kind inference, pattern-matrix
  desugarer, Algorithm W with type classes / monomorphism
  restriction / defaulting, dictionary elaboration with call-site
  evidence, Core-to-Core optimizer, C code generation over a
  call-by-need graph-reduction runtime with the Boehm GC.
- **A Prelude written in Haskell and compiled by AHC itself**,
  including Show instances as ordinary context-parametrized code.
- **Report-complete Show** (showsPrec/showList, string literals,
  escapes, GHC-exact Double formatting), **deriving Eq/Ord/Show**,
  pattern guards, stepped enumerations, Floating/RealFrac at Double.
- **Arbitrary-precision Integer**: hand-rolled limb arithmetic with
  a canonical small-int representation; product [1..25] prints what
  GHC prints.
- **Multi-module programs** (Report ch. 5): import/export lists,
  qualified/as/hiding, abstract types, cycle detection - compiled
  whole-program.
- **Ada-style refinement types** (the design-note extension, all
  four stages): ranges on Int and Double, arbitrary boolean
  predicates on any nullary type, modular wraparound arithmetic -
  erased for unification, enforced at signatures, annotations and
  constructor fields, with `--unchecked` mirroring Ada's release
  policy.
- **A 39-program Haskell 2010 conformance suite whose goldens are
  GHC 9.4.8's output** - AHC reproduces them byte-for-byte - plus
  219 unit tests, five golden/differential/execution harnesses, and
  documented exclusions (tests/conformance/EXCLUSIONS.md).
