# M148 - the second extension round

**Status:** approved design, 2026-10-10.
**Oracle:** GHC 9.4.8 (`~/.ghcup/bin/runghc`). Its default language,
GHC2021, already enables NamedFieldPuns, FlexibleContexts, EmptyCase,
DeriveFunctor, DeriveFoldable and DeriveTraversable. Test programs carry
GHC's pragmas anyway.
**Policy:** every extension is **always on**. AHC ignores `LANGUAGE`
pragmas, with one exception: a module's `{-# LANGUAGE
OverlappingInstances #-}` marks its instances overlapping (Unit 4).

## Why

M147's scout tried 203 small repositories and found 38 using M147's
extensions. Almost every one of those also needed something AHC still
lacks. In order:

- TemplateHaskell;
- FlexibleContexts;
- OverlappingInstances;
- TupleSections, RecordWildCards and MultiWayIf;
- DeriveFunctor / DeriveGeneric;
- Parsec.

This round covers all of them except TemplateHaskell, DeriveGeneric and
Parsec, which are a compile-time evaluator, a type-level generics
encoding and a library port respectively. It also adds M147's leftovers:
`\cases`, EmptyCase, and the layout rule for an operator at a statement
column.

Probed against GHC 9.4.8 during design:

| Program | GHC | AHC v1.18 |
|---|---|---|
| `map (,True) [1, 2]` | `[(1,True),(2,True)]` | parse error |
| `if \| x < 0 -> "neg" \| otherwise -> "pos"` | `pos` | parse error |
| `(\cases (Just x) y \| y > 0 -> x + y; _ _ -> 0) (Just 1) 2` | `3` | "\cases is not supported" |
| `mk px py = let name = "pt" in P{..}` | `P {px = 3, ...}` | parse error |
| `case v of {}` | forces `v` | parse error |
| `instance {-# OVERLAPPABLE #-} C [a]` + `instance C [Char]`, use `c "s"` | `string` | overlapping instances |
| `data T a = ... deriving Functor` | derives | not derivable |
| `(Show (f Int), Functor f) => f Int -> String` | works | works already |

## Unit 1 - syntax rewrites in the parser

Each construct follows M147's `\case` pattern: the parser rewrites it
into existing syntax over binders no source program can spell (they all
contain `$`). No later pass changes.

- **TupleSections.** `( e1 , , e3 , )` with k holes becomes `\ts1$ .. tsk$
  -> (e1, ts1$, e3, tsk$)`, with holes numbered left to right. A
  section with no holes is an ordinary tuple.
- **MultiWayIf.** `if | g1 -> e1 | g2 -> e2 ...` becomes `case () of _ |
  g1 -> e1 | g2 -> e2`.
  - The guards are subject to layout, as GHC's multi-way if is: the
    layout pass opens an implicit block after `if` when the next token
    is `|`.
  - When no guard holds, the failure message names "multi-way if".
    Stderr text is AHC's (EXCLUSIONS row 9).
- **`\cases`.** `\cases alt; ...`, where each alternative is `apat1 ..
  apatn [| guard] -> e` with the same n in every alternative, becomes
  `\c1$ .. cn$ -> case (c1$, .., cn$) of (apat1, .., apatn) ...`. With n
  = 1 there is no tuple.
  - Unequal arities are a parse error, as in GHC.
  - Matching is left to right, as in a multi-clause function. Tuple
    construction forces nothing, so the strictness is the same.
- **EmptyCase.** `case e of {}` and `\case {}` are accepted. Both force
  the scrutinee, then raise "empty case" if it returns. That can only
  happen for a type with values, which GHC would warn about.
- **Layout parse-error(t) for operators.** In a statement, binding or
  alternative block, an operator token (varsym/consym or a backquoted
  identifier) at the block's column cannot begin an item. The parser
  closes the implicit block there, through `AHC.Layout.Pop_On_Parse_Error`,
  and continues the enclosing expression. This covers
  `do { ...; pure x` / `<|>` / `pure [] }` (cnyegun/json-haskell).
  - `-`, `!` and `~` are excluded: they can start an expression or a
    bang/lazy pattern.

## Unit 2 - RecordWildCards and NamedFieldPuns (renamer)

- **In patterns:**
  - `C{x}` is `C{x = x}`.
  - `C{f1 = p, ..}` binds every field of `C` not mentioned explicitly
    to a variable of the field's name.
- **In expressions:**
  - `C{x}` is `C{x = x}`.
  - `C{f1 = e, ..}` fills each remaining field from the variable of that
    name in scope. A field with no such variable stays undefined, as in
    GHC (a warning there, a missing-field error when evaluated).
- **Record update** `r{x}` is `r{x = x}`. `..` is not allowed in an
  update, as in GHC.
- Fields are found by identity (`DataCon_Info.Field_Sels`, M75). The
  variables a pattern wildcard binds are ordinary pattern variables,
  shadowing as any pattern does.

## Unit 3 - stock DeriveFunctor, DeriveFoldable, DeriveTraversable

For `data T a1 .. an = ...` or a newtype, deriving `Functor`, `Foldable`
or `Traversable` covers the last parameter `an`, following GHC's
documented algorithm (GHC User's Guide, "Deriving Functor instances"):

- **Field types**, by their shape:
  - a field of type `an` is mapped, folded or traversed;
  - a field whose type does not mention `an` is copied, skipped or
    `pure`d;
  - a field of type `F t1 .. tk an`, with `an` only in the last
    argument, recurses through `F`'s own instance (so the context gains
    `Functor F` when `F` is a variable);
  - a tuple is handled componentwise;
  - a function type `x -> r`, with `an` not in `x`, is post-composed
    (Functor only).
- **Rejected,** with a GHC-shaped error:
  - `an` in a contravariant position (the argument of a function);
  - `an` in a non-last argument of a type application;
  - a function field in a Foldable or Traversable derivation.
- **Order.** `foldr` and `traverse` visit fields left to right,
  constructors in declaration order. That fixes the order of folds and
  effects to GHC's.
- **Newtypes:** GND still applies wherever its eta-reduction succeeds
  (M147). Stock deriving covers the other representations (`newtype
  Parser a = Parser (String -> [(a, String)])`), as GHC2021 does.
- **Implementation:** the derived methods are produced as ordinary Core
  through the existing deriving machinery (prelude_core's derive
  routines), dispatching on the class by identity, never by name (M75).

## Unit 4 - OverlappingInstances

- **Pragmas.** The parser reads `{-# OVERLAPPING #-}`, `{-#
  OVERLAPPABLE #-}`, `{-# OVERLAPS #-}` and `{-# INCOHERENT #-}`
  immediately after `instance` into a new field, `Instance_Info.Overlap`.
  A module carrying `{-# LANGUAGE OverlappingInstances #-}` marks every
  instance it declares `OVERLAPS` (GHC's deprecated meaning).
- **Selection,** GHC's rule. Let the candidates be the instances that
  match the wanted (`Inst_Match.Matched`).
  - If there is more than one, find the most specific: its head is a
    substitution instance of every other candidate's head, and is not
    equal to it.
  - It is chosen when, for every other candidate, either that candidate
    is overlappable (`OVERLAPPABLE`, `OVERLAPS`, `INCOHERENT`) or the
    chosen one is overlapping (`OVERLAPPING`, `OVERLAPS`, `INCOHERENT`).
  - Otherwise it is the existing overlap error.
- **Incoherence:** an `Undecided` instance (one that could match after a
  type variable is instantiated) still leaves the wanted residual, unless
  that instance is `INCOHERENT`, in which case it is ignored.
- **Consistency.** The same decision function serves the typechecker's
  Solve, elaborate's Solve_Ev and Resolve_GND, so they cannot disagree
  (M147's invariant).

## Unit 5 - FlexibleContexts

It already works (probed). Add conformance coverage for constructed
constraints in signatures, instance contexts and inferred types. The
scout's filter accepts FlexibleContexts, TupleSections, MultiWayIf,
RecordWildCards, NamedFieldPuns, EmptyCase, DeriveFunctor,
DeriveFoldable, DeriveTraversable and OverlappingInstances.

## Error handling

New corpus-types rejects, each confirmed rejected by GHC:

- contravariant `deriving Functor`;
- `deriving Foldable` over a function field;
- an overlap with no pragmas (already pinned; kept);
- a `\cases` arity mismatch;
- `..` in a record update;
- a `C{..}` construction with a field and no variable is NOT an error
  (GHC warns), so it gets a conformance program, not a reject.

## Gates

- **Conformance**, oracled against GHC 9.4.8:
  - `ext_tuple_sections`, `ext_multiway_if`, `ext_lambda_cases`,
    `ext_empty_case`, `ext_layout_operator`;
  - `ext_record_wildcards` (patterns, construction, puns, nested
    records, shadowing);
  - `ext_derive_functor`, `ext_derive_foldable`, `ext_derive_traversable`
    (nested functors, tuples, functions, records, multiple constructors,
    effect order);
  - `ext_overlap_pragmas` (OVERLAPPING/OVERLAPPABLE/OVERLAPS, the
    LANGUAGE form, a most-specific choice three deep);
  - `ext_flexible_contexts`.
- **Exec:** the multi-way-if guard failure and the empty-case forcing.
- **Corpus-types:** the rejects above.
- **Suites:**
  - the full gate in both GC modes;
  - goldens on the validation and release builds;
  - both differential suites, repl, separate, examples, userlib;
  - fuzz 300.
- **Bench** against v1.18.
- **Scout:** re-run the M147 candidate list, recording which repos now
  agree with GHC.
- **Then:** adversarial review, write-up (CHANGES, MANUAL, repos-to-try,
  EXCLUSIONS), release v1.19.

## Out of scope

- TemplateHaskell, DeriveGeneric / GHC.Generics, DeriveAnyClass,
  DerivingVia, StandaloneDeriving;
- Parsec and other Hackage ports;
- the structural Eq/Ord divergence (EXCLUSIONS), which gets its own
  milestone;
- gating extensions on LANGUAGE pragmas (except OverlappingInstances'
  instance marking).
