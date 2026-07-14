# Design Note: Ada-Style Refinement Types as an AHC Extension

**Status:** exploratory — captured for consideration after Phase 4.
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
