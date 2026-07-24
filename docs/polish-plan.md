# Plan: Polish and Depth (v1.2)

**Status:** COMPLETE - every milestone below shipped; v1.2 was
tagged on this plan. v1.1 closed the architecture: all four PRD
phases, the refinement extension, the full stdlib, exhaustiveness
warnings, the numeric tower as classes, and separate compilation.
Nothing structural remains; what follows is chosen polish, ordered
by value. House rules unchanged: GHC 9.4.8 is the oracle, every
milestone lands with the full suite green, EXCLUSIONS.md never
weakens, the MANUAL keeps up.

## Track A - correctness debt first

### M64 - cross-module diagnostic spans (DONE)
The one known wrong behavior: a diagnostic raised while compiling a
non-root module prints against the ROOT module's source text, so
"Main.hs:38:30" can really mean a line in lib/Data/Ratio.hs. Seen
repeatedly during dogfooding (the Data.Map port, the fromRational
warning). Fix: diagnostics carry their originating module; the
driver prints each against its own Source_Text. Medium (Bag record
+ driver plumbing).

### M65 - `fail` at Maybe and [] (DONE - the dicts were already complete; testing found and fixed a real join-point sharing bug instead)
Refutable pattern binds in do-blocks desugar to `fail` per Report
3.14, but only IO has a fail runtime; Maybe/[] are an EXCLUSIONS
row. Give Maybe (fail = Nothing) and [] (fail = []) real Monad
dict entries. Small; unlocks idiomatic `Just x <- lookup k m`
in Maybe do-blocks.

## Track B - GHC-compat breadth

### M66 - Applicative (DONE)
Haskell 2010 predates the Applicative-Monad Proposal, but the
oracle's base has it, so every modern GHC program uses `pure` and
`<*>` freely - the single biggest remaining source-compat gap.
Wire class Applicative (super Functor; pure, <*>, liftA2, *>, <*)
with instances at IO/[]/Maybe, like Monad's dicts. `return = pure`
alias question documented. Medium.

### M67 - Enum at Char (and Double) (DONE - plus Bool/Ordering via the derive branch)
`['a' .. 'z']`, succ/pred at Char - ord/chr prims exist, this is
dictionary work. Enum Double with the Report's odd half-step rule
([1.0, 1.5 ..] stops at limit + 1/2 step), documented carefully.
Small.

### M68 - deriving Enum, Bounded, Ix, Read (DONE for enumerations - incl. Read via maximal-munch token matching; non-nullary shapes documented in EXCLUSIONS)
Enum/Bounded/Ix derive for nullary-constructor types is mechanical
(tags already exist). deriving Read is the big one - inverse of
deriving Show against the Text.Read machinery; monomorphic subset
consistent with the existing Read class. Medium.

### M69 - properFraction + RealFloat (DONE - Track B complete)
properFraction :: RealFrac a => a -> (Integer, a) (tuple-returning
method - a new dict-field shape worth having); RealFloat as a
small real class at Double (isNaN, isInfinite, atan2 moves home).
Small-medium.

## Track C - architectural payoffs

### M70 - polymorphic Ratio a and Complex a (DONE)
The last monomorphic subsets. Now EXPRESSIBLE because M62 made the
tower real: `data Ratio a = a :% a` with
`Integral a => Num (Ratio a)`, `type Rational = Ratio Integer`;
`data Complex a = a :+ a` with `Floating a => Num (Complex a)`.
Pure library work against machinery that already exists; removes
the GHC-side annotation gotchas from the conformance tests.
Medium-large, high satisfaction.

### M71 - Data.Set + Map rounding (DONE - Track C complete)
Data.Set reuses the weight-balanced tree almost verbatim (member/
insert/delete/union/toList); Map gains foldlWithKey, filter,
keysSet. Small, immediate library value.

## Track D - the contracts extension (Ada Pre/Post as pragmas)

### M72 - design note (DONE); M73 - implementation (DONE - Track D complete)
Bring Ada's function-level contracts over as pragmas, completing
the refinement story. See docs/contracts-design-note.md (M72
writes it; the position in brief):

- **What refinements already cover**: per-VALUE predicates at type
  boundaries (`Int satisfying even`). What they cannot say:
  relations BETWEEN a function's arguments, or between arguments
  and its result - Ada's `Pre => X > Y` and `Post => Result >= X`.
- **Proposed form**: pragmas attached to a signature, predicates
  as ordinary typechecked Haskell (reusing the entire hidden
  `$pred` machinery from `satisfying`):

      {-# ANN pre  clamp (\lo hi x -> lo <= hi) #-}
      {-# ANN post clamp (\lo hi x r -> lo <= r && r <= hi) #-}
      clamp :: Int -> Int -> Int -> Int

  (exact pragma spelling decided in M72; GHC ignores unknown
  pragmas, so conformance sources stay oracle-clean).
- **Purity dividend**: Ada needs 'Old because of mutation; Haskell
  post-conditions just NAME the arguments - they cannot have
  changed. Simpler than Ada.
- **Laziness cost**: "check on entry" is meaningless when
  arguments are unevaluated thunks; forcing them would change
  program semantics. Contracts therefore fire DEMAND-TIME like
  every existing refinement check: the pre-predicate wraps each
  argument's use, the post-predicate wraps the result. A
  post-condition that mentions an argument the function never
  forced does force it - contracts observe, and that is
  documented.
- **Policy**: stripped by `--unchecked`, exactly Ada's assertion
  policy, exactly like ranges and `satisfying`.

## Track E - performance and leftovers

### M74 - measurement-driven optimizer round (DONE)
Benchmark harness first (the bignum/fib/sort programs, wall+alloc),
then the profitable next transforms (case-of-case, single-use
inlining across let). Only what measurement justifies.
(Shipped: scripts/run_bench.sh + tests/bench/, and used-once let
inlining barred under lambdas - sumfold 1.58x->2.10x, sort
1.19x->1.91x, map 1.11x->1.28x, fib/bignum flat. Case-of-case was
NOT shipped: nothing in the measured profile justified it.)

### M75 - module-system corners (DONE - plan complete)
The two EXCLUSIONS stragglers: restricting the implicit Prelude
import (`import Prelude hiding (...)`, `import Prelude ()`), and
same-named type synonyms in two modules (the flat Env.Synonyms map
is keyed by bare name - give it per-module keys).
(Shipped: Prelude restriction per Report 5.6.1, all four forms,
qualified-view filtering, builtin syntax unhideable; 3 conformance
+ 3 both-reject differential tests. Synonym/constructor collisions
stay clean compile errors - per-module keys would re-plumb the
kinds-level expansion tables for a corner qualified imports rarely
hit; documented honestly in EXCLUSIONS row 5.)

## Sequencing

A (correctness) -> B in order -> C. D whenever the appetite is
there - M72's design note can happen any time. E last. Every
milestone independently shippable, full suite green, docs current -
house law since M0.
