# Design note: The collector campaign

**Status:** C1-C3 IMPLEMENTED (M107, M108); **C4 MEASURED AND
DECLINED**; **both perf gates currently FAIL** (M109 re-ran them
end-to-end - see section 9 for the verdicts and the livelock they
uncovered). The own collector is correct and sequentially faster
than Boehm; it is not yet ready to become the default. What
landed, with errata where the implementation corrected the
design:

- **C1 (allocator)**: as designed, plus per-thread CHUNK carving
  (the pool lock plus the mprotect inside it convoyed at 4
  workers; now paid once per 16MB). Sequential geometric mean
  0.778x of Boehm - own is 22% FASTER. A second fix, spin-HELPING,
  was added here and REMOVED in M109: it livelocks (section 9).
- **C2 (STW mark-sweep)**: as designed, with three corrections.
  (1) Roots use a conservative data-segment scan (one dyld call)
  instead of codegen root arrays - covers prims, registries,
  funptr slots, and every generated global with zero codegen
  changes; precise arrays deferred. (2) Sweep is OBJECT-grain
  within blocks, not block-grain: pure block-grain ratcheted
  b_map's RSS to 52x Boehm (churn leaves one survivor per block),
  object-grain free-slot lists brought it to 1.7x. (3) The
  register-spill jmp_buf must be INSIDE the collector's own scan
  floor - a worker soak caught register-held pointers escaping
  the scan. TSan found three more: a worker reading main's
  own_in_gc, and mixed atomic/plain accesses on the pool head.
- **C3 (generational)**: sticky mark bits with per-block epochs;
  minor collections sweep only blocks allocated into this cycle,
  majors clear the whole bitmap and re-mark. The write barrier is
  the single hot site requirement 4 promised (the thunk IND
  update, twice) plus one cold one (channel tail append), feeding
  per-thread sequential store buffers. Bounded runtime structures
  (tasks, scopes, chans, protected values) are re-walked every
  cycle instead of barriered - the remembered set for everything
  that is not the pure graph. Two errata: `live` is a MAJOR-only
  measurement (letting minors count undirty blocks wholesale fed
  the trigger a runaway threshold - 832MB committed on b_map
  before that line existed), and see the construction-order
  invariant below, which is the campaign's sharpest lesson.
- **C4 (parallel mark)**: NOT BUILT. Section 4 admitted it "ONLY
  if a measured profile shows mark time dominating after C3."
  The collector was taught to time its own phases; mark is 4-21%
  of wall time (45-89% of GC time, but GC is only 5-24% of wall).
  A perfect 4-way parallel mark could return at most 3-16% of
  wall before its own costs - CAS'd mark bits instead of plain
  ORs, work-stealing mark stacks, termination detection. The bar
  is not met, so the stage does not land. See the profile section
  below for what the same measurement DID find.

Trigger policy: collect when bytes-since-GC exceed max(12MB,
2x live); a major every 4 minors or when live triples.
AHC_OWN_MIN / AHC_OWN_MAJOR_EVERY override; AHC_OWN_STATS prints
the phase breakdown; AHC_OWN_PARANOID=1 verifies the generational
invariant (=2 hunts referrers); AHC_OWN_MADVISE=1 trades speed
for RSS.

## 0. The C4 profile: what measuring for one thing found

Two bugs, both found because C4's precondition demanded a
phase-level profile that had never been taken:

1. **`madvise` cost 24% of wall time and bought nothing.** Freed
   blocks were handed back with MADV_FREE_REUSABLE - a syscall
   PER BLOCK. Removing it took parfib from 4.72s to 3.58s at 4
   workers. Peak RSS changed by 0-1MB, because the pool recycles
   those blocks immediately anyway: the high-water mark never
   noticed. Now off by default, behind AHC_OWN_MADVISE.
2. **The sweep walked every slot of blocks that were entirely
   garbage.** A block's mark bits are one contiguous 1KB bitmap
   slice; if every word is zero the block is free, and no slot
   needs touching. On low-survival programs that is nearly every
   block. Sweep time on parfib: 2.35s -> 0.17s.

Together: parfib 16.7s -> 11.5s sequential and 6.19s -> 3.41s at
4 workers. **CORRECTION (M109):** that 4-worker figure was
measured with spin-helping enabled, which the C3 gate later
proved unsafe (it livelocks - see section 9); with helping
removed parfib reaches 2.06-2.26x at 4 workers and the original
B1 parallel bar (2.5x at 4) remains UNCLEARED. The sequential
gains stand. The lesson is the
M74 rule with a sharper edge: *profile the phase you are about
to optimize, because it may not be the phase that is costing
you.* C4 was the question; the answer was in the sweep.

Original proposal follows.

**Status as proposed:** PROPOSED (M106 writes this). This is the design note
that `concurrency-design-note.md` section 7.8 said must exist
before anything else in Phase B is touched, and the largest
runtime campaign the project has contemplated - bigger than the
FFI. It should be read after 7.8; the one-line version of that
section is: the spark machinery scales (2.96x on 8 workers over
plain malloc) and the shipped collector is what doesn't (0.46 to
0.70x, every configuration), because **in a graph reducer the
allocator IS the concurrency substrate** - every reduction
allocates, so nothing scales unless allocation does.

## 1. What the runtime actually requires

Requirements first, mechanisms second - each of these is a fact
about AHC as built, with the receipt named.

1. **Conservative roots, forever.** Evaluation is C recursion
   (MANUAL chapter 8); node pointers live in C stack frames and
   callee-saved registers with no stack maps and no way to get
   them. Any collector for this runtime scans thread stacks
   conservatively. The M102 machinery already tracks the live
   extent [sp, top] of every green-thread stack and the M105
   worker stacks are plain pthread stacks - root RANGES are a
   solved problem; only the scanning changes hands.
2. **Non-moving, and this one is permanent.** The v1.5 FFI hands
   node addresses to C: `funptr_reg` keeps `AhcNode **` slots
   alive for wrapper trampolines, and host programs hold handles
   across calls. A moving collector would need a pin set covering
   every pointer that ever crossed the boundary - unknowable by
   construction. Non-moving also keeps Bartlett-style pinning
   complexity out entirely: nothing moves, so nothing pins.
3. **The heap is precisely traceable BY TAG - with one gap.**
   Every node's pointer fields are known from its tag (thunk env,
   fun env, con fields, ind; INT/DOUBLE/CHAR/BIGINT/PTR carry
   none - a PTR payload is foreign and must NOT be traced). The
   gap: env and field ARRAYS have no length header (`ahc_env`
   returns a raw block). The fix is free at the right layer:
   size-segregated pages make an object's size a property of its
   page, so arrays trace precisely with no header added and the
   24-byte node stays 24 bytes.
4. **Mutation is confined, and that is laziness's gift.** The
   heap mutation sites are enumerable: thunk update (the IND
   store - the hot one), protected-value state commits, channel
   queue links, registry slots. A generational write barrier in
   this runtime is ONE hot branch plus a handful of cold ones,
   not a compiler-wide obligation.
5. **Allocation is the design center.** Per-thread, lock-free in
   the fast path, bump-pointer. This is not an optimization to
   apply later; 7.8 established it is the precondition (GHC's
   per-capability nurseries, rediscovered the hard way).
6. **Determinism is not negotiable.** Collection must not create
   scheduling points: green-task switches happen only at IO
   binds, blocking ops, and yield (M102), and a stop-the-world
   pause is invisible to that schedule. The golden discipline
   survives any STW design untouched; it would NOT survive a
   concurrent collector that turned mutator/marker races into
   timing-visible behavior. STW it is.

## 2. The design: block-structured, non-moving, Immix-shaped

A single large virtual reservation carved into 64KB-aligned
blocks (the M102 address-space philosophy, applied to the heap).
Each block has a header: owner kind (node / pointer-array /
atomic), size class, mark bitmap, allocation bitmap. Alignment
makes pointer-to-block-header a mask, and block-header-plus-slot
arithmetic makes pointer-to-object-start O(1) - which is the
whole conservative-filter story:

    candidate word -> in reservation? -> block header (mask)
      -> allocated slot? (bitmap) -> object start (round down)

Round-down handles interior pointers (a C compiler may hold
`&n->u.con.fields` rather than `n`); a PTR node's foreign payload
fails the in-reservation test and is ignored, exactly as today.

**Allocation**: each mutator thread owns one active block per
size class and bumps within it; a spent block is retired and a
fresh one taken from the global pool under a lock paid once per
64KB, not once per node. This is the B1 postmortem's lesson made
structural - and it is deliberately the SAME shape at 1 thread
and at 32.

**Collection v1 (campaign stage C2)**: stop the world; mark from
roots (thread-stack extents conservatively, the generated
`g_Module_*` globals precisely via codegen-emitted root arrays,
runtime registries and prim table explicitly); sweep at block
grain - fully-empty blocks return to the pool, partial blocks
retire from bump service until a later sweep frees them whole.
No free lists inside blocks in v1: bump-only allocation keeps the
fast path three instructions, and block-grain recycling is the
Immix insight minus the evacuation half we are forbidden anyway.

**Generational v2 (stage C3)**: sticky mark bits - a minor
collection marks only blocks allocated since the last cycle,
plus a remembered set fed by the write barrier at the enumerated
mutation sites (requirement 4). Sequential store buffers per
thread; no card table needed at this heap organization, because
the barrier sites are few and already funnel through runtime
functions (the IND store lives in exactly two places after M105:
`ahc_eval`'s update and `run_spark`'s).

## 3. What happens to Boehm

Nothing, for a long time. `AHC_GC=boehm|own|none` selects at
build; Boehm stays the DEFAULT through the whole campaign, and
the M102/M103/M105 Boehm-specific protocols (stackbottom
retargeting, live-extent add/remove, malloc_many batching) remain
untouched on that path. The own-collector path reuses the same
live-extent bookkeeping with its own scanner. The default flips
only when section 5's gates have held for a full release cycle -
and if they never hold, the project keeps a working collector and
this note keeps its honesty.

## 4. Staging (each stage lands alone, M74 discipline)

- **C1 - the allocator, leak mode.** Blocks, size classes,
  per-thread bump, no collection (exactly what the plain-malloc
  control measured, minus malloc). Proves the parallel and
  sequential allocation story before a single mark bit exists.
- **C2 - STW mark-sweep.** The precise-by-tag tracer, the
  conservative filter, codegen root arrays, block-grain sweep.
  Correctness stage: every harness, plus a fuzz soak under
  AHC_GC=own.
- **C3 - generational.** Sticky marks, the thunk-update barrier,
  remembered sets. Throughput stage.
- **C4 - parallel mark.** ONLY if a measured profile shows mark
  time dominating after C3, and B1's workers make natural
  markers. May never be needed; may never land.

## 5. The gates, as numbers

- **C1 gate**: parfib/parsort at 2/4 workers >= 1.8x/2.4x versus
  own-build sequential (the plain-malloc control measured
  2.06x/2.58x - the allocator may cost a little, not a lot), AND
  sequential run_bench geometric mean within 5% of the Boehm
  build. Leak mode is fine for benchmarks; that is what it is
  for.
- **C2 gate**: all thirteen harnesses green under AHC_GC=own,
  fuzz soak clean, TSan clean (run_tsan grows an own-GC arm),
  peak RSS on the bench suite within 2x of Boehm's.
- **C3 gate**: the ORIGINAL B1 gate, at last - >= 1.6x on 2
  workers, >= 2.5x on 4, workers defaulting ON in the own-GC
  build - plus sequential run_bench at parity or better with
  Boehm (the write barrier must earn its branch).
- **Default flip**: C2 + C3 gates held across one full release.

## 6. What this is not

No moving or compaction, ever, on the current FFI (requirement
2). No concurrent marking (requirement 6 - determinism outranks
pause times in this project's identity, and the pause budget of
a batch compiler's runtime is generous). No finalizers, no weak
references - nothing in the language surface asks for them. No
per-object headers: the 24-byte node earned its size across a
hundred milestones and keeps it. No new GC for the COMPILER
itself (it is an Ada program; arenas already won that argument in
chapter 2 of the manual).

## 7. Risks, named

Conservative over-retention is unchanged in kind from Boehm; the
block-grain sweep adds a new flavor (a partial block held by one
survivor) that Immix's own literature bounds and the C2 RSS gate
watches. The two-collector window is a maintenance tax, capped by
making AHC_GC=own a CI job from C1 day one. The conservative
filter's round-down must be fuzzed against forged-pointer
patterns (the corpus fuzzer gains an own-GC arm). And the honest
scheduling risk: this campaign is large, its payoff is gated on
hardware behavior already measured once (the plain-malloc
control), and B1's opt-in machinery loses nothing by waiting -
there is no deadline pressure, only the note's own gates.

## 8. The construction-order invariant (C3's war story)

The sharpest lesson of the campaign, found by a verifier written
for the purpose after b_sumfold started dying with
"non-exhaustive patterns in function" - the classic shape of a
freed-but-referenced object.

**The rule**: *an object must never gain a pointer to something
allocated after it, without a write barrier.*

The violation was in `ahc_mk_con`, which had stood unchanged for
a hundred milestones:

    AhcNode *n = alloc_node();          /* owner FIRST  */
    n->u.con.fields = ahc_env(arity);   /* child SECOND */

Under a non-generational collector this is unimpeachable. Under a
generational one it is a liveness bug, because a collection can
run *between the two allocations*: `ahc_env` reaches the
allocation slow path, the collector runs, conservatively finds
the half-built `n` on the C stack and marks it - and `n` is now
STICKY-marked old. The `fields` array it receives a moment later
is young and unreferenced by anything the next minor collection
traces, because the next minor does not re-trace old objects. It
is swept. The constructor's own child is freed underneath it.

The fix is one line - allocate the components first, then the
owner - applied at `ahc_mk_con` and `mk_sparked_die`:

    AhcNode **fields = arity ? ahc_env(arity) : NULL;
    AhcNode *n = alloc_node();
    n->u.con.fields = fields;           /* stores an OLDER object */

**The tool that found it** is worth as much as the fix, and it
stays: `AHC_OWN_PARANOID=1` runs a full mark into a shadow bitmap
after every minor collection and reports any object the shadow
says is live that the sticky view would free - i.e. exactly the
objects a generational bug is about to lose, named at the moment
of the bug rather than at the crash. `=2` additionally hunts
referrers (an O(heap^2) scan) and prints the object holding the
edge, which is what identified the constructor. The whole exec
suite runs clean under it, and any future runtime code that
allocates a child after its owner will be caught the same way.

The generalizable form, for whoever writes the next runtime
allocation site: **in a generational collector, allocation order
is a correctness property, not a style choice.**


## 9. The gate verdicts, and the livelock helping hid (M109)

Re-running both gates end-to-end against the committed M108
runtime produced two failures and one bug. Recorded here because
the campaign's rule is that gates report, not decorate.

**C3 sequential: PASS.** Geometric mean 0.892x of Boehm across
six workloads (bar <= 1.00) - the generational write barrier did
not eat the allocator's margin. own is faster on every
allocation-heavy program (b_map 0.726, b_sumfold 0.760, b_sort
0.880) and marginally slower on the two that barely allocate.

**C3 parallel: FAIL,** and the failure exposed a livelock in
shipped code. `b_parsort` at 2 workers hung at 98% CPU for 45
minutes; thread stacks showed main spinning on a blackhole in
`ahc_eval` while a worker spun on a different blackhole inside
`run_spark`. The cause was spin-HELPING, added in C1 to close a
scaling gap: **a thread that is WAITING must not ACQUIRE.** The
spark a spinner helps with blackholes fresh thunks, which the
thread it is waiting for may then demand - a dependency cycle the
program never contained. Plain spinning is safe for the
mirror-image reason: ownership follows the program's own
dependency graph, so a cycle there really is a `<<loop>>`. C1's
own code comment had dismissed this as "a genuinely CYCLIC
cross-task dependency", i.e. a program bug; b_parsort is a
correct program, and that dismissal was wrong.

Helping is removed. The cost is the scaling it was buying:

    parfib  2w/4w   with helping 2.21x/3.01x (deadlock-prone)
                    without      2.22x/2.06x
    parsort 2w/4w   with helping  hangs
                    without      1.54x/2.08x

So the B1 parallel bar (1.6x at 2, 2.5x at 4) is not met, and was
only ever "met" by an unsafe mechanism. Note also that four
workers are SLOWER than two on parfib - a spinning waiter burns a
core to no purpose, which is the honest shape of the remaining
problem.

The real fix is structural, not tuning. GHC lets a thread that
blocks on a blackhole suspend its computation; AHC's evaluator is
C recursion and cannot. The promising direction is the other one
purity allows: let the blocked thread simply RE-EVALUATE the
claimed thunk (same answer, by purity) and race to update, which
never blocks and never deadlocks. That is not possible today only
because claiming overwrites `u.thunk.code/env` with the owner and
waiter fields - preserving them is a node-layout question, and
its own milestone.

**C2: FAIL** on peak RSS - geometric mean 2.31x of Boehm against
a 2.0x bar (correctness halves all pass: exec suite, forced-
collection soak at 0/2/4 workers, TSan). The mean is dominated by
small and medium heaps: b_fib 4.48x (22MB vs 5MB - trivial in
absolute terms), b_sort 4.27x (149MB vs 35MB), while the large-
heap programs are at parity (b_sumfold 1.09x, b_strictfold
1.20x). Two hypotheses were measured and REJECTED: `madvise` is
RSS-neutral even on large heaps (797 vs 796MB), and the trigger
floor is not the lever (b_fib and b_sort are unchanged between a
4MB and a 12MB floor). The structural cause is that own's peak
RSS *is* its committed high-water mark, and a peak can only be
lowered by collecting EARLIER - never by releasing later. The fix
is therefore a growth-aware trigger (collect on committed-bytes
velocity, not just a multiple of live), plus size-class
fragmentation work. Also its own milestone.
