# AHC — Ada Haskell Compiler

A ground-up compiler for [Haskell 2010](https://www.haskell.org/onlinereport/haskell2010/)
written in Ada 2022, built around Design-by-Contract: preconditions,
postconditions, and type invariants verify the compiler's own internal
consistency in every development build. See `docs/adahc PRD.rtf` for the
full product requirements.

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
that violated contracts actually raise `Assert_Failure`.

## Status

All four phases are complete: AHC compiles and runs Haskell programs
against a Prelude written in Haskell and compiled by AHC itself, and
adds an Ada-style refinement-types extension.

```sh
scripts/ahc-build.sh Foo.hs   # Haskell -> C -> native executable
./Foo
```

Backend: `ahc emit` generates C over the AHC runtime
(`runtime/ahc_rts.{h,c}`) - call-by-need graph reduction with
update-in-place thunks, curried closures, generic constructor workers,
dictionary field selectors, and IO as world-passing actions - linked
against the Boehm-Demers-Weiser GC (plain malloc fallback). Covered at
runtime today: Int arithmetic/comparison, Bool/Char/String/list Show,
user ADTs with derived Eq/Ord (generic structural prims), user classes
with default methods, lazy infinite structures, do-notation IO.

Standard library: `prelude/Prelude.hs` is compiled through the full
pipeline ahead of every user module - list/tuple/Maybe/Either
functions with signatures, the Either type, and Show instances for
tuples, Maybe and Either as ordinary context-parametrized Haskell
instances, elaborated to dictionary functions like any user code.
The class hierarchy, numeric primitives and IO remain wired in
AHC.Builtins / AHC.Prelude_Core.

Extension - Ada-style refinement types
(`docs/refinement-types-design-note.md`): ranges `type Percent = Int
in 0 .. 100`, predicates `type Nat = Int satisfying (\n -> n >= 0)`
/ `Color satisfying isWarm` (any nullary base type; predicates are
ordinary typechecked Haskell compiled to hidden top-level functions,
so class-constrained predicates like `even` just work), and modular
types `type Clock = Int mod 12` with Ada-style wraparound - values
crossing a declared boundary normalize into `[0, N)`, so
`(25 :: Clock)` is 1 and incrementing a `Byte` past 255 wraps to 0.
Ranges also work on Double (`type Latitude = Double in -90.0 ..
90.0`), backed by a now-working Double runtime: Num/Fractional/Show
at Double are real (`print (7 / 2 :: Double)` prints 3.5), with
Rational and the Floating class still open. Refined types are legal
in data/newtype fields (`data Port = Port (Int in 1 .. 65535)`) -
every construction site checks (or, for `mod` fields, normalizes)
the stored value; reads trust the constructor-established invariant.
Refined types are erased for unification (transparent arithmetic, no
smart constructors); ranges and predicates are lazily-fired checks
at signature and annotation boundaries, and `ahc emit --unchecked`
(or `AHC_UNCHECKED=1 scripts/ahc-build.sh`) compiles the checks out,
mirroring Ada's release-mode contract policy - modular wrapping is
arithmetic semantics, not a check, so it is always applied.

Show is Report-complete where it counts: showsPrec/showList are real
methods, strings print as escaped string literals ("show \"ab\"" and
friends match GHC exactly), negative arguments parenthesize, and
`deriving Show` generates showsPrec per constructor - positional,
record syntax, and parametric types included. Enum at Int is
complete (stepped ranges [1,3..9], succ/pred, to/fromEnum), and the
Prelude gained span/break/splitAt/unzip/foldr1/foldl1/words/lines.

The Floating/RealFrac vocabulary works at Double (sqrt, pi, exp/log,
**, logBase, trig, hyperbolics, floor/ceiling/round/truncate with
round-to-even, fromIntegral), and Double's show now produces GHC's
exact output: shortest round-trip digits with the fixed-vs-scientific
switch (0.1 + 0.2 prints 0.30000000000000004; 1.0e7 stays
scientific). Guards are full Report 3.13 qualifier sequences: boolean
tests, pattern guards (Just v <- lookup k m), and let, in any
comma-separated combination, in equations and case alternatives.

Integer is arbitrary-precision: a hand-rolled sign+magnitude bignum
(uint32 limbs) lives in the runtime, and every integer primitive
takes the C-long fast path until overflow promotes - product
[1 .. 25], 2^100 and 30-digit literals print exactly what GHC
prints, including floored div/mod on negative bignums. Values are
canonical (anything that fits a long stays a plain int node), so
comparisons, Show and the structural Eq/Ord see mixed
representations transparently. Int overflow promotes rather than
wrapping - behavior the Report leaves undefined.

Multi-module programs work: the driver discovers imports from the
root file (module A.B.C in A/B/C.hs beside it), topologically orders
the graph (cycles rejected), and compiles each module through the
frontend into the shared Core - imports support qualified / as /
hiding / import lists, export lists support f, T(..) and C(..), and
abstract types (a type exported without its constructors) hold.
Instances flow program-wide as the Report requires. Compilation is
whole-program: no interface files.

AHC.Optimizer (the PRD stretch goal) simplifies Core before code
generation: atom inlining, beta-to-let, dead-binding elimination,
case-of-known-constructor and default-only-case elision - each
exactly sharing- and laziness-preserving - iterated to a bounded
fixpoint. On a fib/sum/factorial bench it cuts the generated C ~7%
and wall time ~25%; `ahc emit --no-opt` / AHC_NOOPT=1 disables it.
Generated executables link with a 512MB stack so million-element
thunk chains evaluate instead of overflowing.

Remaining gaps: Rational arithmetic and Floating/RealFrac as proper
classes (the vocabulary is monomorphic at Double), the Integral
class proper, exhaustiveness warnings, class defaults for builtin
classes, `module M` re-exports, and separate compilation.

Frontend: lexer with the full literal grammar, Report 10.3 layout
engine, recursive-descent parser for the whole Haskell 2010 surface,
Report 10.6 fixity resolution (`ahc parse`).

Middle end: renamer over a wired-in Prelude signature, kind inference,
desugaring to a System-FC-like Core (`ahc core`), Hindley-Milner
typechecking with type classes, the monomorphism restriction and
Report 4.3.4 defaulting (`ahc check`), and instance-dictionary
elaboration through the contract-checked Mk_Dict constructor.
Call-site dictionary application lands with Phase 3 code generation,
along with the C backend and Boehm GC runtime.

```sh
scripts/run_golden.sh              # golden lex/layout/parse/core/check
scripts/run_differential.sh        # parse-level GHC agreement
scripts/run_differential_types.sh  # type-level GHC agreement
scripts/run_exec.sh                # compile-and-run output goldens
scripts/run_conformance.sh         # Haskell 2010 conformance subset
```

Conformance (the PRD success metric): `tests/conformance/` holds 30
programs pinned to Haskell 2010 Report sections - lexical structure
and layout, every expression form, declarations and classes, the
predefined types, the Prelude subset, and non-strict semantics. Their
goldens are GHC'S OUTPUT (regenerate with `--oracle`); AHC must
reproduce them byte-for-byte. Report features AHC does not implement
are documented in `tests/conformance/EXCLUSIONS.md` rather than
tested weakly. Building the suite immediately caught and fixed five
real bugs: record field selectors had no bodies, record update
dropped unmentioned fields' sharing, a shared join-point node made
the evidence rewriter apply dictionaries twice on nested-constructor
matches, single-line nested `let .. in` failed under parser
lookahead, and `(op) = e` bindings did not parse.

## Layout

```
src/          AHC.* packages (one spec/body pair per package)
src/ahc_main.adb   CLI driver (builds as ./bin/ahc)
tests/        nested Alire crate with the unit test runner
tests/golden/ golden lex/parse expectations
tests/corpus/ realistic modules for GHC-differential checks
scripts/      test harness scripts
```
