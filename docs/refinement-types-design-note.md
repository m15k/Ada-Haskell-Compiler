# Design Note: Ada-Style Refinement Types as an AHC Extension

**Status:** stages 1-4 IMPLEMENTED (July 2026) — integer and Double
range refinements, arbitrary boolean predicate refinements on any
nullary base type (all lazily-checked contracts), and modular types
with wraparound arithmetic (a boundary coercion, not a check); see
"As built" below. Stage 4 also brought up the Double runtime itself
(Num/Fractional/Show dictionaries over C doubles).
**Date:** July 2026.
**Prompted by:** the observation that Ada can define types GHC cannot,
and that an Ada-implemented Haskell compiler is uniquely positioned to
offer them at the Haskell surface.

## 1. The observation

Ada's type system is organized around **value constraint**; GHC's is
organized around **parametric and higher-kinded polymorphism**. Neither
subsumes the other:

| Capability | Ada 2022 | GHC (Haskell 2010) | GHC (extensions) |
|---|---|---|---|
| Range-constrained scalars (`range 0 .. 100`) | native, checked on every assignment | none | emulation via smart constructors or type-level Nats; loses transparent arithmetic |
| Arbitrary subtype predicates (`Dynamic_Predicate`, `Static_Predicate`) | native | none | Liquid Haskell (external SMT tool) |
| Modular (wraparound) integer types of any modulus | native | fixed sizes only (`Word8`...) | same |
| Fixed-point / decimal types with declared delta | native | none | libraries, unchecked |
| Value-dependent record shapes (discriminants) | native | none | GADTs + singletons approximate, with proof burden |
| Higher-kinded types, type classes, inference | none | native | native |
| GADTs, type families | none | none | native |

The key nuance: Ada's constraints are **dynamically checked contracts**
(statically provable only with SPARK), while GHC's types are wholly
static. So the gap is not "Ada types are impossible in GHC" but "the
refinement axis is unoccupied in GHC" — a `newtype` plus smart
constructor enforces nothing internally and forfeits arithmetic;
Liquid Haskell occupies the axis but as a separate tool with a separate
ecosystem.

An Ada-implemented compiler collapses the distance: the checking
machinery (constraint propagation, check insertion, an assertion policy
to disable checks in release builds) is the same machinery the compiler
already uses on itself.

## 2. Where AHC already lives on this axis

Phase 1 uses exactly these types for the compiler's own integrity, per
PRD 4.2:

- `AHC.Names.Real_Name_Id` — a range subtype making "absent name" and
  "real name" distinct at the type level (`src/ahc-names.ads`).
- `Prec : Natural range 0 .. 9` on fixity declarations
  (`src/ahc-syntax.ads`).
- `Dynamic_Predicate => Stop >= Start` on source spans
  (`src/ahc-diagnostics.ads`).
- `Type_Invariant => Balanced (...)` on the layout stream
  (`src/ahc-layout.ads`).

The extension proposal is to let *Haskell programs compiled by AHC* say
the same kinds of things.

## 2a. Stages 1-4 as built

Shipped with the refinement-types milestones (M23-M25), directly on
the two Phase 2 design rules (the reserved `Refine` slot on Core
`TCon_T`; erased-head unification):

- **Syntax:** `Int in LO .. HI` in any type position, integer-literal
  bounds with optional `-`. A one-token lookahead (literal after
  `in`) keeps `let ... in` unambiguous. Synonyms work
  (`type Percent = Int in 0 .. 100`).
- **Bases:** `Int` and `Integer` only; anything else, an empty range,
  or a refined data-constructor field is a kind error (a refined
  field would be an unenforced promise until constructor-site checks
  land in a later stage).
- **Semantics:** coercive subtyping by erasure — refined and
  unrefined types unify freely, all arithmetic transparent. AHC.Refine
  eta-wraps every signatured/annotated binder whose type spine
  mentions a refined TCon, applying `ahc_prim_check_range` to refined
  arguments and results (dictionary parameters threaded through). The
  check is a thunk: it fires when the refined value is first
  demanded, so unforced values are never checked and a violation
  inside a lazy structure surfaces exactly at demand time
  (`refinement violation: 151 not in 0 .. 100`, exit 1).
- **Policy toggle:** `ahc emit ... --unchecked` /
  `AHC_UNCHECKED=1 scripts/ahc-build.sh` compiles the checks out —
  Ada's release-mode contract story.
- **Printing:** `ahc check` shows `clamp :: Int -> Int in 0 .. 100`.
- **Stage 2 — predicate refinements (M26-M28):**
  `BASE satisfying P` in any type position, with `satisfying` a
  contextual keyword (still a legal varid elsewhere) and `P` an
  atomic expression - a named function or a parenthesized lambda /
  section:

  ```haskell
  type Nat  = Int satisfying (\n -> n >= 0)
  type Warm = Color satisfying isWarm      -- user ADTs work
  evenOnly :: Int satisfying even -> Int
  ```

  The base may be ANY nullary type constructor (`Int`, `Char`,
  `Bool`, user enums, ...). Each predicate occurrence compiles to a
  hidden top-level binding `$pred :: BASE -> Bool` whose body is the
  predicate expression, materialized by the desugarer and pushed
  through the ordinary typechecker - so class-constrained predicates
  (`even`'s `Integral`) get their dictionaries by the normal
  elaboration path, and the fixity resolver handles operator chains
  inside predicates. Checks fire through `ahc_prim_check_pred` with
  the same demand-time laziness as ranges; `ahc check` prints
  `Int satisfying even` (or `satisfying (...)` for a lambda).
  Stacking two refinements on one type is rejected. The predicate is
  assumed total and effect-free (its `BASE -> Bool` type rules out
  IO but not divergence) - the same obligation Ada places on
  `Dynamic_Predicate`.
- **Stage 3 — modular types (M29-M30):** `Int mod N` (Int/Integer,
  literal modulus >= 1), Ada's wraparound arithmetic recast for the
  erasure design: a modular refinement is a COERCION, not a
  contract - every value crossing a declared `Int mod N` boundary is
  normalized into `[0, N)` with mathematical mod (never negative:
  `shift 3 (-7) :: Int mod 12` is 8), via `ahc_prim_wrap_mod` at the
  same eta-wrapper positions as checks. Intermediate arithmetic is
  plain Int; annotate the boundary and the result wraps -
  `(25 :: Int mod 12)` is 1, and a `Byte -> Byte` increment of 255
  is 0. Because wrapping is semantics rather than validation, it
  SURVIVES `--unchecked` (exactly as Ada's release mode keeps
  modular arithmetic while dropping contracts). `mod` is contextual
  only when an integer literal follows, so `m mod` remains a valid
  type application and value-level `\`mod\`` is untouched. Stacking
  with ranges/predicates is rejected.
- **Stage 4 — Double ranges (M31-M32):** the note's original
  `Latitude` example, verbatim:

  ```haskell
  type Latitude = Double in -90.0 .. 90.0
  type Unit     = Double in 0 .. 1      -- integer bounds allowed
  ```

  Bounds may be float or integer lexemes (integer bounds on an Int
  range stay integer-only); the lexemes are preserved through the
  refinement arena, so both the printed type and the generated C
  reproduce the user's literals exactly - including scientific
  notation (`Double in 0.0 .. 3.0e2`). Checks fire through
  `ahc_prim_check_range_d` with the usual demand-time laziness and
  are compiled out by `--unchecked`. Prerequisite shipped alongside:
  Double now RUNS - Num/Fractional dictionaries over C doubles
  (fromInteger converts, fromRational is identity because float
  literals are already double nodes), Show Double with `.0`
  normalization for whole values, Eq/Ord via the structural
  comparator. `print 1.5` defaults Fractional to Double per Report
  4.3.4 and just works.
- **Constructor-site checks (M33):** refined types are now legal in
  data and newtype fields - the note's `newtype Port = Port (Int in
  1 .. 65535)` example works. Every occurrence of a constructor
  whose fields carry refinements is eta-wrapped by AHC.Refine, so
  the check (or, for `mod` fields, the normalization) rides each
  refined field's thunk: saturated construction, partial application
  (`map Port ports`), record syntax and record update all route
  through the same rewrite. Field READS are not re-checked - the
  invariant is established at construction; a `Volume (Int mod 256)`
  field stores normalized. Checks fire when the field is first
  demanded, and `--unchecked` drops field contracts while keeping
  modular field normalization, exactly as at signature boundaries.
- **Limits (all stages):** enforcement only at the direct
  argument/result positions of declared signatures, `::`
  annotations, and constructor fields; refinements nested under
  other constructors (`[Int in 0 .. 9]`, a refined type inside a
  field's list) or on class-method signatures typecheck but are not
  runtime-checked; unused (never-demanded) values are never
  checked - that IS the lazy semantics; no compile-time constant
  checking yet.

## 3. Sketch of the extension (`{-# LANGUAGE AdaRefinements #-}`, working name)

### 3.1 Surface syntax

Refined base types in type positions, introduced by `in` on a scalar
type (bikeshed freely):

```haskell
type Percent   = Int in 0 .. 100
type Latitude  = Double in -90.0 .. 90.0
newtype Port   = Port (Int in 1 .. 65535)

clamp :: Int -> Percent
angle :: Latitude -> Latitude -> Double
```

Possible later additions, in increasing order of ambition:

1. predicate refinements: `Int in even`, `Int satisfying (\n -> n `mod` 3 /= 0)`
   (the predicate must be a total, effect-free expression);
2. modular types: `Word mod 10` with wraparound arithmetic;
3. refinements over ADT fields in `data` declarations, giving
   discriminant-style records.

Stage 1 (ranges on `Int`/`Double`/`Char`) already delivers most of the
practical value and nearly all of the safety-critical story.

### 3.2 Semantics

- A refined type is a **subtype**, not a new type: `Percent` values are
  `Int`s, all `Int` operations apply, no wrapping/unwrapping. This is
  the decisive ergonomic difference from `newtype` + smart constructor.
- Subtyping is coercive with checks: `Int -> Percent` inserts a range
  check; `Percent -> Int` is free. Checks raise a runtime error
  carrying the source position (Ada's `Constraint_Error`, in spirit).
- Check placement follows Ada's assignment model: at construction,
  pattern binding against a refined-annotated binder, function entry
  (arguments), and function return.
- Like the compiler's own contracts, checks obey a build policy:
  enabled in debug/test builds, removable in release builds
  (`-fno-refinement-checks`), mirroring PRD 8's mitigation.

### 3.3 Pipeline impact (why we prepare now, build later)

- **Lexer/parser:** trivial — `in`/`mod` in type position parse as an
  annotation node. No layout interaction.
- **AST (`AHC.Syntax`):** one additional `Type_Kind` (e.g.
  `Refined_T (Base : Type_Id; Constraint : Expr_Id)`). The arena
  design absorbs this without disturbance.
- **Typechecker (Phase 2 — the preparation point):** Algorithm W
  unifies on the *erasure* of refined types (a `Percent` unifies where
  an `Int` does); refinements ride along as annotations, never as
  unification variables. **Design rule for Phase 2: the Core type
  representation must keep an optional refinement annotation slot on
  base types, and unification must be written against erased types.**
  This costs nothing now and avoids surgery later.
- **Desugarer:** inserts the checks as ordinary Core (a
  `checkRange# lo hi pos e` primitive), so downstream phases need no
  knowledge of refinements at all.
- **Optimizer:** range information enables check elimination
  (`x + 0` on `Int in 0..100` stays in range for `0..200` targets) —
  a natural, incremental payoff.
- **Backend:** nothing; checks are already ordinary Core by then.

### 3.4 The long game: SPARK-flavored proofs

Ada's story is contracts first, proofs when it matters (SPARK). The
same gradient applies here: dynamic checks by default, and later a
proof mode that discharges checks statically (abstract interpretation
over ranges first; SMT via the Liquid-Haskell playbook if ever
warranted). Modules whose checks all discharge get refinements *for
free at runtime* — the avionics-grade configuration. This is a
research-sized effort and is explicitly not scheduled; the note exists
so nothing in Phases 2-4 forecloses it.

## 4. Fit with the PRD

PRD section 2 names "Safety-Critical Functional Programming" as a
goal and PRD 3.2 keeps GHC extension parity out of scope. This
extension advances the stated goal precisely *because* it is not GHC
parity: it is the one feature where an Ada implementation has a
structural advantage rather than a compatibility deficit, and it gives
AHC a reason to exist beyond pedagogy.

## 5. Sequencing and non-goals

- **Nothing changes in Phases 2-4** except the two Phase 2 design
  rules above (refinement slot in Core types; unification over
  erasures). Haskell 2010 conformance remains the acceptance bar.
- Non-goals: full dependent types, GADTs, type families, and any
  refinement whose check is not a total effect-free expression.
- Revisit after Phase 4 (Prelude + conformance suite) with a concrete
  proposal for stage 1 (scalar ranges).

## 6. Open questions

1. Syntax: `Int in 0 .. 100` reads well but `in` is a keyword with
   layout meaning; confirm no grammar ambiguity in type contexts
   (none known: `in` cannot begin or continue a btype today).
2. How refinements interact with polymorphism: is `[Percent]` just
   `[Int]` with element checks at construction sites? (Erasure says
   yes; confirm against laziness — a thunk's check fires on WHNF
   evaluation, which is observably later than Ada's assignment-time
   check. Likely the right lazy-language semantics, but it must be
   documented.)
3. Defaulting and literals: `95 :: Percent` should check at compile
   time (constant folding makes it free); negative-literal patterns
   already exist in the AST and compose.
4. `Read`/`Show`/`Enum` instances for refined types — derive from the
   base type with checks at the boundary?
