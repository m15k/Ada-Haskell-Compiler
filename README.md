# AHC — Ada Haskell Compiler

A ground-up compiler for [Haskell 2010](https://www.haskell.org/onlinereport/haskell2010/)
written in Ada 2022, built around Design-by-Contract: preconditions,
postconditions, and type invariants verify the compiler's own internal
consistency in every development build. AHC compiles Haskell to C over
its own graph-reduction runtime, runs it against a Prelude written in
Haskell and compiled by AHC itself, and holds itself to one standard
of correctness: **byte-identical output to GHC 9.4.8** on a pinned
conformance suite. On top of Haskell 2010 it adds an Ada-flavored
extension family — refinement types, function contracts, deterministic
structured concurrency — and a complete bidirectional FFI with binding
generators for C++, Rust, Go, and GHC.

```sh
./bin/ahc build Foo.hs        # Haskell -> C -> native executable
./Foo
./bin/ahc repl                # interactive (docs/repl-design-note.md)
```

New here? **`docs/STUDY-GUIDE.md`** is the guided path through the
codebase: eight stations from tokens to graph reduction, each with the
source to read, the stage dumps to run, and a test question — plus an
exercise ladder from "add a Prelude function" to "strike an EXCLUSIONS
row". **`docs/MANUAL.md`** is the complete manual — every design
decision and the theory behind it, written for a reader who is not a
compiler engineer. `docs/adahc-PRD.md` holds the full product
requirements (`docs/adahc PRD.rtf` is the original).

## Building

Requires [Alire](https://alire.ada.dev/) with a GNAT ≥ 13 toolchain
(`alr toolchain --select gnat_native gprbuild`).

```sh
alr build --validation   # all contracts enabled (default for development)
alr build --release      # contracts compiled out
./bin/ahc --version
```

## Testing

```sh
cd tests
alr build --validation
./bin/ahc_tests
```

The tests crate always builds with contracts enabled; some tests assert
that violated contracts actually raise `Assert_Failure`. The end-to-end
harnesses live in `scripts/` — see [Verification](#verification).

## The compiler

**Frontend**: lexer with the full literal grammar, Report 10.3 layout
engine, recursive-descent parser for the whole Haskell 2010 surface,
Report 10.6 fixity resolution (`ahc parse`).

**Middle end**: renamer over a wired-in Prelude signature, kind
inference, desugaring to a System-FC-like Core (`ahc core`),
Hindley-Milner typechecking with type classes, the monomorphism
restriction and Report 4.3.4 defaulting (`ahc check`), and
instance-dictionary elaboration through the contract-checked Mk_Dict
constructor, with call-site dictionary application in code generation.

**Optimizer** (the PRD stretch goal): AHC.Optimizer simplifies Core
before code generation — atom inlining, beta-to-let, dead-binding
elimination, case-of-known-constructor and default-only-case elision,
each exactly sharing- and laziness-preserving, iterated to a bounded
fixpoint. On a fib/sum/factorial bench it cuts the generated C ~7% and
wall time ~25% (a later measured round reached up to 2.1x on the
benchmark suite, `scripts/run_bench.sh`); `ahc emit --no-opt` /
`AHC_NOOPT=1` disables it.

**Backend**: `ahc emit` generates C over the AHC runtime
(`runtime/ahc_rts.{h,c}`) — call-by-need graph reduction with
update-in-place thunks, curried closures, generic constructor workers,
dictionary field selectors, and IO as world-passing actions. The
default build links the Boehm-Demers-Weiser GC (plain malloc
fallback); `AHC_GC=own` selects AHC's own block-structured
generational collector, which runs 16% faster than Boehm on the
sequential bench via a growth-aware collection trigger. Generated
executables link with a 1GB (virtual, lazily committed) stack so
million-element thunk chains evaluate instead of overflowing. The runtime covers the full language
as shipped: all numeric types including arbitrary-precision Integer,
user ADTs with the derive family, user classes and dictionaries, lazy
infinite structures, `seq`/`($!)`, do-notation IO with stdin/stdout
and file handles, command-line arguments, and the refinement/contract
check primitives (compiled out under `--unchecked`; provably-true
contract claims never reach the runtime at all).

**Separate compilation**: `ahc emit` writes one C file per module with
STABLE symbols (globals mangled from module+name, locals and lifted
functions numbered per unit), so a module's generated text depends
only on its own code; `ahc build` compiles each unit to an
object cached by content hash and links. An edit to one module
recompiles exactly one object — proven by `scripts/run_separate.sh`
(no-change and comment-only rebuilds compile ZERO objects; the cache
is content-addressed, not mtime-based). Rebuilds of the mini-Lisp
interpreter drop from ~6s to ~1s. The frontend (parse-through-Core,
~0.3s for the whole interpreter) deliberately stays whole-program:
that is what makes the Report's program-wide instance coherence hold
by construction, with no orphan-instance or interface-consistency
machinery.

**Multi-module programs**: the driver discovers imports from the root
file (module A.B.C in A/B/C.hs beside it), topologically orders the
graph (cycles rejected), and compiles each module through the frontend
into the shared Core — imports support qualified / as / hiding /
import lists, export lists support `f`, `T(..)`, `C(..)`, and `module
M` re-exports (facade modules, `module Prelude`), and abstract types
(a type exported without its constructors) hold. Instances flow
program-wide as the Report requires.

**REPL**: `ahc repl` is compile-and-run over the object cache — no
second evaluator, so the REPL cannot disagree with the compiler
(docs/repl-design-note.md).

## Language coverage highlights

**The numeric tower is real classes**: Integral (instances at Int and
Integer — the canonical bignum representation lets both bind the same
promoting prims, with toInteger the identity), Floating and RealFrac
(instances at Double: sqrt, pi, exp/log, `**`, logBase, trig,
hyperbolics, floor/ceiling/round/truncate with round-to-even, results
at Integer), plus RealFloat and properFraction. fromIntegral is
ordinary Prelude source (`fromInteger . toInteger`, fully
polymorphic), `(^)`/`(^^)` exist (exact 2^100 via bignum),
even/odd/gcd/lcm are Integral-constrained, and defaulting covers the
new classes (`print (floor 2.5)` just works).

**Exactness end to end**: float literals are carried as exact decimal
ratios through the whole pipeline, and Double's show produces GHC's
exact output — shortest round-trip digits (Burger-Dybvig) with the
fixed-vs-scientific switch (`0.1 + 0.2` prints 0.30000000000000004;
`1.0e7` stays scientific). Exact Rational arithmetic lives in
Data.Ratio, printed GHC-style as `1 % 2`.

**Integer is arbitrary-precision**: a hand-rolled sign+magnitude
bignum (uint32 limbs) lives in the runtime, and every integer
primitive takes the C-long fast path until overflow promotes —
`product [1 .. 25]`, 2^100 and 30-digit literals print exactly what
GHC prints, including floored div/mod on negative bignums. Values are
canonical (anything that fits a long stays a plain int node), so
comparisons, Show and the structural Eq/Ord see mixed representations
transparently. Int overflow promotes rather than wrapping — behavior
the Report leaves undefined.

**Show is Report-complete where it counts**: showsPrec/showList are
real methods, strings print as escaped string literals (`show "ab"`
and friends match GHC exactly), negative arguments parenthesize, and
`deriving Show` generates showsPrec per constructor — positional,
record syntax, and parametric types included. `deriving` also covers
Enum, Bounded, Ix, and Read for enumerations, and underivable shapes
are rejected at compile time. Builtin-class default methods work (a
Show instance defining only `show` gets Report-correct
`showsPrec`/`showList`; an Ord instance can define just `compare` — or
just `<=`, with `compare` defaulting through the superclass Eq).

**Guards are full Report 3.13** qualifier sequences: boolean tests,
pattern guards (`Just v <- lookup k m`), and let, in any
comma-separated combination, in equations and case alternatives. Enum
is complete at Int, Char and Double (stepped ranges `[1,3..9]`,
succ/pred, to/fromEnum). `seq` and `($!)` are real (an honest
`foldl'`).

**Warnings are real**: exhaustiveness and redundancy via
Maranget-style usefulness analysis over function equations and case
alternatives (for the root module) — agrees line-for-line with GHC's
`-Wincomplete-patterns` / `-Woverlapping-patterns` on the pinned
corpus. Cross-module diagnostics carry proper source spans.

Remaining monomorphic subsets: Data.Array (Int indices) and Text.Read's
instance set. `Ratio a` and `Complex a` are fully polymorphic.

## The Ada extension

### Refinement types

(docs/refinement-types-design-note.md) Ranges `type Percent = Int in
0 .. 100`, predicates `type Nat = Int satisfying (\n -> n >= 0)` /
`Color satisfying isWarm` (any nullary base type; predicates are
ordinary typechecked Haskell compiled to hidden top-level functions,
so class-constrained predicates like `even` just work), and modular
types `type Clock = Int mod 12` with Ada-style wraparound — values
crossing a declared boundary normalize into `[0, N)`, so `(25 ::
Clock)` is 1 and incrementing a `Byte` past 255 wraps to 0. Ranges
also work on Double (`type Latitude = Double in -90.0 .. 90.0`).
Refined types are legal in data/newtype fields (`data Port = Port
(Int in 1 .. 65535)`) — every construction site checks (or, for `mod`
fields, normalizes) the stored value; reads trust the
constructor-established invariant. Refined types are erased for
unification (transparent arithmetic, no smart constructors); ranges
and predicates are lazily-fired checks at signature and annotation
boundaries, and `ahc emit --unchecked` (or `AHC_UNCHECKED=1
scripts/ahc-build.sh`, the shim over `ahc build`) compiles the checks out, mirroring Ada's
release-mode contract policy — modular wrapping is arithmetic
semantics, not a check, so it is always applied.

### Function contracts

(docs/contracts-design-note.md, examples/contracts.hs) Ada's Pre/Post
as pragmas:

    {-# PRE  clamp \lo hi x -> lo <= hi             #-}
    {-# POST clamp \lo hi x r -> lo <= r && r <= hi #-}

Predicates are ordinary typechecked Haskell (checked against a
signature derived from the function's own, class context included;
contract type errors land on the pragma), and the checks fire at
demand time — forcing the result checks pre, body, then post against
the shared result; an undemanded call checks nothing. Purity removes
Ada's `'Old`; `--unchecked` strips claims; GHC ignores the pragmas, so
contracted programs remain portable Haskell (the conformance suite
runs them byte-identical under both compilers).

**Compile-time contract discharge** closes the loop: a fuel-bounded
evaluator proves claims at compile time where it can — provably-true
claims vanish from the generated code; provably-false ones warn at
compile time (`scripts/run_discharge.sh`).

### Deterministic structured concurrency

(docs/concurrency-design-note.md — a four-language comparison of
Go, GHC, Rust, and Ada, then AHC's answer) `Control.Concurrent.Scoped`
provides scope/spawn/await, channels, and yield over green threads
whose strict round-robin scheduler makes every run of a program
reproduce the same schedule byte for byte: an interleaving is a golden
test, a deadlock is a reported outcome, and a scope joins its children
by construction (Ada's master rule; there is deliberately no
`forkIO`). `Control.Concurrent.Protected` adds protected values —
shared state with Ada-protected-object discipline. Opt-in SMP sparks
provide pure parallelism; `examples/concurrency` states the remaining
gap as a number: pure parallelism scales 4.1x while task parallelism
stays flat, because SMP *task* scheduling is unbuilt. All runtime
concurrency additions are opt-in; the default build is still Boehm
with zero workers, and every pre-existing program's behavior is
unchanged.

## FFI and embedding

A complete bidirectional foreign function interface (Report chapter
8):

```haskell
foreign import ccall "sin" c_sin :: Double -> Double  -- call C
foreign export ccall square :: Int -> Int             -- be called
```

```sh
./bin/ahc build --lib MathLib.hs mathlib.a        # + ahc_exports.h
./bin/ahc bindgen rust MathLib.hs mathlib.a       # + safe wrappers
```

Library mode produces a static archive plus a generated C header;
Haskell closures pass as C function pointers (no libffi); fixed-width
C types have boundary-enforced widths; and `ahc bindgen` generates
idiomatic C++, Rust, Go, and GHC bindings. The embedding story is
built to lean on: an error inside an exported entry unwinds to the
boundary and arrives as the host language's own failure type instead
of killing the process, and a marshalling surface (allocation,
peek/poke at every width, pointer arithmetic, C strings) opens the
APIs that traffic in arrays and out-parameters — libc's `qsort` sorts
through a Haskell comparator, and `examples/sqlite` binds real sqlite3
in ~80 lines. `examples/ffi` is one Haskell engine (lazy sieve, exact
bignums, an expression parser, word frequencies) embedded five ways —
C, C++, Rust, Go, GHC — each running traffic in *both* directions
through a symbol the library imports and every host defines. The GHC
host means two Haskell runtimes in one process, talking through C.

## Standard library

`prelude/Prelude.hs` is compiled through the full pipeline ahead of
every user module — list/tuple/Maybe/Either functions with signatures,
and Show instances for tuples, Maybe and Either as ordinary
context-parametrized Haskell instances, elaborated to dictionary
functions like any user code. The class hierarchy, numeric primitives
and IO remain wired in AHC.Builtins / AHC.Prelude_Core.

`lib/` holds the Haskell 2010 library subset (docs/stdlib-plan.md):
Data.List (sort and friends with base's exact production orders),
Data.Char, Data.Maybe, Data.Ord (with Down), Data.Tuple, Data.Bool,
Control.Monad and Data.Functor (Monad-polymorphic over IO, [] and
Maybe — the Maybe Monad and all three Functor dictionaries are real),
System.IO (file handles: openFile/hClose/hPutStr/hGetLine and
friends) / System.Environment / System.Exit (getLine, getContents,
readFile, interact, getArgs, exit codes), Numeric (showHex and
friends), Data.Bits at Int, Data.Ix as an ordinary source class,
Data.Map and Data.Set (a weight-balanced search tree matching the
containers library's observable behavior exactly — toList order, Show
format, union bias — and oracled against the real thing), Data.Ratio
(exact fractions over bignum Integer), Data.Complex, Data.Array
(Int-indexed), Text.Read (a source Read class covering
Int/Integer/Bool/lists/pairs), and the concurrency modules
Control.Concurrent.Scoped / Protected — all ordinary Haskell modules
compiled by AHC through its own module system. The driver resolves
imports beside the root file, then `$AHC_LIB`, then `lib/`.
Conformance oracles run the same programs under GHC's real base
library, so AHC's implementations are tested against the canonical
ones.

## Examples — the dogfood programs

All under `examples/`, exercised by `scripts/run_examples.sh` (28
example tests); unless noted, the same source runs under GHC and the
harness requires the two builds byte-identical (goldens are GHC's
output, `--oracle` regenerates).

- **`lisp/`** — a Scheme-flavored mini-Lisp interpreter: a REPL and
  batch evaluator with an exact numeric tower (bignum Integer,
  Rational, Double), closures, `letrec` knot-tied through laziness,
  and a boot prelude written in mini-Lisp. Its first compile
  immediately found and fixed a real compiler bug (cross-module type
  synonyms read the defining module's syntax arena through an
  importing module's ids) and drove the first need-based stdlib
  addition (`isEOF`).
- **`json/`** — ajson, a JSON parser and pretty-printer over the
  exact-literal machinery, with a Data.Map `--stats` mode.
- **`hm/`** — microhm, Algorithm W in ~350 lines: the compiler's own
  typechecker in miniature, with its occurs-check obligation restated
  as a live contract. Byte-identical under either compiler on its
  first build, like ajson.
- **`fibs/`** — Fibonacci by fast doubling over bignum Integer,
  reading indices from arguments or stdin, with goldens that straddle
  the fib 92/93 machine-word boundary where AHC's hand-rolled limbs
  meet GMP (fib 1000000, 208988 digits, in about a second).
- **`cal/`** — ahccal, a civil-calendar utility, the odd one out and
  the reason to read it: the worked tour of the Ada extension's two
  halves together, and the only example that is AHC-only by
  construction. Ranges, a `satisfying` predicate, two modular types, a
  Double range and refined constructor fields carry the values;
  Pre/Post contracts carry the relations no per-value constraint can
  express (February 31st is a `mkDate` precondition, not a `Day`
  bound), up to a full specification of the date/integer isomorphism.
  The program contains no hand-written validation at all — every
  failure message comes from a check the compiler inserted. The
  harness additionally pins that the four constraint kinds actually
  fire, and that `--unchecked` strips every claim without changing a
  single answer while modular normalization survives. Contract pragmas
  are portable; the refinement surface is not, so its goldens are
  AHC's own output and `--oracle` skips it (`examples/cal/README.md`
  says why, in full).
- **`ffi/`** and **`sqlite/`** — the embedding examples (see [FFI and
  embedding](#ffi-and-embedding)).
- **`httpd/`** — ahttpd, an HTTP server over the raw libc socket
  FFI: nonblocking accept/read cooperating with the green
  scheduler, a `/par/N` route whose scope/spawn/channel fan-out has
  its worker ARRIVAL ORDER pinned in the golden (deterministic
  scheduling as an observable), exact-bignum `/fact/N`, and a
  listen port whose type is `Int in 1 .. 65535`. AHC-only like cal.
  The two runtime gaps its first version surfaced (blocking IO vs
  the scheduler, no channel poll) became M127's
  scheduler-integrated IO — fd parking via poll(2) with
  registration-order wakes, tryRecv/selectRecv/waitReadOr — and
  the server now parks its accept loop, overlaps handlers, and
  idles at zero CPU, all pinned by its harness. Dogfood as
  roadmap, roadmap as dogfood.
- **`concurrency/`** — the four concurrency models from the design
  note, each restated as a runnable AHC program (`go_csp`,
  `ghc_sparks`, `rust_aliasing`, `ada_protected`), plus `b2_smp`
  measuring which parts of the SMP story exist.
- **`contracts.hs`** — the function-contract walkthrough.

## Verification

The house rule is that claims are tested, and the oracle is GHC.

**Conformance** (the PRD success metric): `tests/conformance/` holds
74 programs (including multi-module cases) pinned to Haskell 2010
Report sections — lexical structure and layout, every expression form,
declarations and classes, the predefined types, the Prelude subset,
and non-strict semantics. Their goldens are GHC'S OUTPUT (regenerate
with `--oracle`); AHC must reproduce them byte-for-byte. Report
features AHC does not implement are documented in
`tests/conformance/EXCLUSIONS.md` rather than tested weakly. Building
the suite immediately caught and fixed five real bugs: record field
selectors had no bodies, record update dropped unmentioned fields'
sharing, a shared join-point node made the evidence rewriter apply
dictionaries twice on nested-constructor matches, single-line nested
`let .. in` failed under parser lookahead, and `(op) = e` bindings did
not parse.

**The differential fuzzer** (docs/fuzzer-guide.md) generates random
well-typed programs and byte-compares AHC against GHC per seed, with
an automatic shrinker for failures. The fuzzer and the REPL have found
seven real compiler bugs the hand-written suite had missed — all fixed
and pinned, several of them only reachable at campaign scale (10,000
seeds); the hardened deep campaign found four more, including a
floored-mod overflow.

The harnesses (`scripts/`):

```sh
scripts/run_golden.sh              # golden lex/layout/parse/core/check
scripts/run_differential.sh        # parse-level GHC agreement
scripts/run_differential_types.sh  # type-level GHC agreement
scripts/run_exec.sh                # compile-and-run output goldens
scripts/run_conformance.sh         # Haskell 2010 conformance suite
scripts/run_separate.sh            # separate-compilation cache proofs
scripts/run_examples.sh            # the dogfood programs, oracled
scripts/run_fuzz.sh                # differential fuzzing (run_fuzz_par.sh: parallel)
scripts/run_repl.sh                # REPL session goldens
scripts/run_discharge.sh           # compile-time contract discharge
scripts/run_export.sh              # FFI exports (run_bindgen.sh: four hosts)
scripts/run_sqlite.sh              # the sqlite3 binding
scripts/run_httpd.sh               # ahttpd: live HTTP session goldens
scripts/run_build.sh               # ahc build: out-of-tree, -j determinism, failure surface
scripts/run_bench.sh               # benchmark suite (run_parbench.sh: SMP gate)
scripts/run_c1_gate.sh             # own-collector gates: allocator...
scripts/run_c2_gate.sh             #   ...collection correctness/footprint...
scripts/run_c3_gate.sh             #   ...generational parity + speed
scripts/run_own_soak.sh            # collector soak across collection cadences
scripts/run_tsan.sh                # ThreadSanitizer acceptance (thunk protocol, allocator locks)
scripts/run_watchdog_check.sh      # the spin watchdog, made to fire on purpose
```

## Release history

- **v1.0–v1.1** — the four PRD phases: frontend, middle end, C
  backend + runtime, self-hosted Prelude; then the refinement-types
  extension.
- **v1.2** — the polish plan (docs/polish-plan.md, M64–M75):
  cross-module diagnostic spans, Applicative, Enum at Char/Double,
  deriving Enum/Bounded/Ix/Read, properFraction/RealFloat, polymorphic
  `Ratio a`/`Complex a`, Data.Set, function contracts, a measured
  optimizer round, Report 5.6.1 Prelude-restriction imports.
- **v1.3** — verification and tooling (M76–M81): the differential
  fuzzer, real `seq`/`($!)`/`foldl'`, System.IO file handles, `ahc
  repl`, compile-time contract discharge.
- **v1.4** — the exactness release (M82–M83): float literals as exact
  decimal ratios end to end, compile-time rejection of underivable
  shapes, Burger-Dybvig show digits, a floored-mod overflow fix, the
  hardened deep-campaign fuzzer that found them. v1.4.1/v1.4.2
  (M85–M88) added the ajson, microhm, fibs, and cal examples.
- **v1.5** — the FFI release (M89–M97): bidirectional `foreign
  import`/`export ccall`, library mode, closures as C function
  pointers, fixed-width types, `ahc bindgen` for C++/Rust/Go/GHC.
- **v1.6** — the embedding release (M98–M112): errors crossing the
  boundary as host failure types, the marshalling surface, the sqlite
  binding, the five-host examples/ffi; deterministic structured
  concurrency (Scoped, Protected, SMP sparks); AHC's own generational
  collector (`AHC_GC=own`).
- **v1.7** — the builder release (M124–M125): `ahc build` replaces
  the build script (native, parallel `-j`, byte-identical to a
  serial build, works from any directory via installation-relative
  path resolution; the script survives as a shim), and the ahttpd
  dogfood — an HTTP server over the socket FFI whose goldens pin a
  deterministic concurrent schedule, and whose README records the
  two runtime gaps it surfaced.
- **v1.6.1** — the collector patch (M113–M123): `AHC_GC=own` lost
  live data on deep lazy chains and no longer does — a pre-existing
  defect never reachable from the default build, fixed at fourteen
  sites and now enforced by a verifier rather than by habit — after
  which both collector gates pass on a correct collector (own 16%
  faster than Boehm sequentially, via a growth-aware trigger that
  cleared a conflict no fixed constant could).

Full details per release in `CHANGES.md`.

## Documentation

- `docs/MANUAL.md` — the complete manual
- `docs/STUDY-GUIDE.md` — the guided path for newcomers
- `docs/adahc-PRD.md` — product requirements (the original: `docs/adahc PRD.rtf`)
- Design notes: refinement types, contracts, REPL, concurrency,
  collector (`docs/*-design-note.md`), the fuzzer guide
  (`docs/fuzzer-guide.md`), and the stdlib plan (`docs/stdlib-plan.md`)
- `tests/conformance/EXCLUSIONS.md` — what is deliberately absent, and why

## Layout

```
src/          AHC.* packages (one spec/body pair per package)
src/ahc_main.adb   CLI driver (builds as ./bin/ahc)
runtime/      ahc_rts.{h,c} — the graph-reduction runtime
prelude/      Prelude.hs, compiled ahead of every user module
lib/          the Haskell 2010 library subset + concurrency modules
tests/        nested Alire crate with the unit test runner
tests/golden/ golden lex/parse expectations
tests/corpus/ realistic modules for GHC-differential checks
tests/conformance/  the Report-pinned suite + EXCLUSIONS.md
examples/     the dogfood programs
scripts/      build + harness scripts
docs/         manual, study guide, PRD, design notes
```
