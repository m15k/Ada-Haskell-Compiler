# AHC Changelog

## Unreleased

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
- Conformance suite grown 39 -> 47 programs, all byte-identical to
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
