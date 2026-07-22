# AHC Changelog

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
