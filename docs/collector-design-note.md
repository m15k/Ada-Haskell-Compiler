# Design note: The collector campaign

**Status:** PROPOSED (M106 writes this). This is the design note
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
