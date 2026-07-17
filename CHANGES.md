# AHC Changelog

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
