# M148 The second extension round - Implementation Plan

**Goal:** TupleSections, MultiWayIf, `\cases`, EmptyCase, the layout
operator rule, RecordWildCards/NamedFieldPuns, stock
DeriveFunctor/Foldable/Traversable and overlapping-instance pragmas, as
GHC 9.4.8, always on. FlexibleContexts, which already works, gets its
tests.

**Architecture:**

- **Syntax** is rewritten in the parser over unspellable `$` binders
  (M147's `\case` pattern).
- **Record puns** are a parser rewrite. **Wildcards** go into a renamer
  side table that desugar consults.
- **Stock deriving of Functor/Foldable/Traversable** is a new Core pass
  after desugar (`AHC.Derive_Functor`). It synthesizes the method
  bindings (`fmap`, `foldr`, `traverse`) as ordinary Core and marks the
  instance source-like. The typechecker then checks the synthesized code,
  and elaborate builds the dictionary with superclasses, class defaults
  and `traverse`'s Applicative parameter, through the existing machinery.
- **Overlap pragmas** are matched to instance declarations by span in
  the driver. They travel through `Instance_Info.Overlap`, and one new
  `Inst_Match.Pick` applies GHC's most-specific rule wherever instances
  are selected.

Spec: `docs/specs/2026-10-10-m148-extension-round-two.md`.

## Global constraints

- **Oracle:** GHC 9.4.8 (`~/.ghcup/bin/runghc`, default language
  GHC2021). Conformance is stdout byte-identical; exec tests compare
  `2>&1` with AHC's `ahc:` banner (EXCLUSIONS row 9).
- **Test programs** carry GHC's `LANGUAGE` pragmas. AHC ignores them,
  except that `OverlappingInstances` marks a module's instances.
- **Gate inputs:** `prelude/`, `lib/` and `runtime/ahc_rts.c` are gate
  inputs, and so is `bin/ahc`. Never edit or rebuild them while a suite
  or a reviewer agent runs.
- **Gate:** `./scripts/run_gate.sh` in the background with a 2-hour
  limit. Goldens on both builds, after the binding-name check
  (`names()` in M146's plan).
- **No unordered actuals:** never pass two id-minting calls as actuals
  of one call (memory: ada-actual-evaluation-order).
- **Identity:** classes and instances are found by identity (Env holds
  only builtins and the Prelude, so a name lookup in Env yields the
  Prelude's entity). Foldable and Traversable have no `Env.*_Cl` field:
  resolve them once through `Env.Classes`.
- **Commits:** conventional prefix, lowercase prose subject, trailer
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## File map

| File | Change |
|---|---|
| `src/ahc-parser.adb` | tuple sections (`Parse_Paren_Exp` 1079-1193); multi-way if (`Parse_LExp` 950); `\cases` (890); empty case (980, 898); record puns and `..` (`Parse_Record_Suffix` 781, `Parse_APat` 605); the operator layout hook (`Parse_Stmt_Block` 1360, `Parse_Alt_Block` 1396, `Parse_Decl_Block` 2223) |
| `src/ahc-layout.adb` | open a block after `if` when `\|` follows |
| `src/ahc-syntax.ads` | `Rec_Dotdot : Boolean` on `Rec_Con_E`/`Rec_Update_E`/`Rec_P`; `Overlap_Pragmas` map and `Lang_Overlapping` on `Module_Arena` |
| `src/ahc-rename.ads/.adb` | `Resolutions.Wild_Res`; `..` in patterns and expressions; `Stock_Derivable` + Functor/Foldable/Traversable instance shape; Overlap copied into Instance_Info |
| `src/ahc-desugar.adb` | consult `Wild_Res` in record construction (1341) and patterns (686, 270, 332) |
| `src/ahc-derive_functor.ads/.adb` (new) | synthesize `fmap`/`foldr`/`traverse` Core method bindings |
| `src/ahc_main.adb` | call `Derive_Functor` after desugar; `Detect_Overlap` pragma pass |
| `src/ahc-core.ads` | `Overlap_Kind`, `Instance_Info.Overlap`, `Instance_Info.Stock_Derive` |
| `src/ahc-inst_match.ads/.adb` | `More_Specific`, `Pick` |
| `src/ahc-typechecker.adb`, `src/ahc-elaborate.adb` | use `Pick` in Solve, Solve_Ev, Resolve_GND's Reduce |
| `scripts/scout_repos.sh` | accept the new extensions |
| tests | see each task |

---

## Phase A - syntax

### Task A1: TupleSections

- [ ] **Test:** `tests/conformance/ext_tuple_sections.hs`, oracled.

  ```haskell
  {-# LANGUAGE TupleSections #-}
  main :: IO ()
  main = do
    print (map (,True) [1, 2 :: Int], map (1 :: Int,) "ab")
    print (zipWith3 (,,) [1 :: Int] "x" [True], map (,"x",) [1 :: Int, 2] <*> [False])
    print ((, 'b', ) 'a' 'c', fmap (0 :: Int,) (Just "j"))
  ```
- [ ] **Parser.** In `Parse_Paren_Exp`, the comma branch (1094) currently
  takes `(` followed by commas as a tuple constructor only. If the token
  after the commas is not `)`, it starts a section with leading holes.
  Generalize the tuple loop (1174-1188) to a list of items, each either
  an expression or a hole (`Comma` or `Right_Paren` where an expression
  was expected). With k > 0 holes, build:

  ```ada
  --  (e1, , e3, ) -> \ts1$ ts2$ -> (e1, ts1$, e3, ts2$)  (TupleSections,
  --  M148): one unspellable binder per hole, numbered left to right.
  ```

  Each binder is a `Var_P` / `Var_E` of `Table.Intern ("ts" & Img (I) & "$")`.
  The binders go into a `Lambda_E` whose body is the `Tuple_E`.
  `Check_Tuple_Width` still applies.
- [ ] **Verify** with the test and `run_differential.sh`.

### Task A2: MultiWayIf

- [ ] **Test:** `tests/conformance/ext_multiway_if.hs`, oracled. Cover:
  guards across several lines; a nested multi-way if; guards with `,`
  (pattern guards); multi-way if inside a `do` and in a `where`. Also
  `tests/exec/multiway_if_fail.hs`, with no true guard: AHC's banner plus
  a message naming "multi-way if".
- [ ] **Layout.** In ahc-layout.adb's ordinary-token `case`, `Kw_If`
  followed by `Pipe` opens an implicit block, so the guards can sit on
  their own lines. That is GHC's MultiWayIf layout:

  ```ada
                  when Kw_If =>
                     Enqueue (S, T);
                     --  MultiWayIf (M148): `if |` opens a layout block
                     --  for its guards, as GHC's does.
                     if S.Input (S.I + 1).Kind = Pipe then
                        S.Await_Open := True;
                     end if;
  ```
- [ ] **Parser.** In `Parse_LExp`'s `Kw_If` branch, right after
  `Advance`, test for `V_Left_Brace`, `Left_Brace` or `Pipe`:
  - Parse guard alternatives: loop on `Pipe`, read qualifiers with the
    `Parse_Guarded` body, `->`, then an expression.
  - Skip `;`/`V_Semicolon` between guards, and close on
    `V_Right_Brace`/`Right_Brace`. Use `Try_Layout_Close` for a
    same-line close.
  - Build `Case_E (Scrutinee => Con_E "()", Alts => [Alt (Wild_P, Rhs'(Guarded => True, ...))])`.
  - For the failure text, add a `Multi_Way_If` flag to the alternative
    (or desugar's `Case_E` failure message), so the error says
    "non-exhaustive guards in multi-way if".

### Task A3: `\cases` and EmptyCase

- [ ] **Tests:**
  - `tests/conformance/ext_lambda_cases.hs`: two and three patterns,
    guards, `where`, nested `\cases`, wildcards, laziness (an unused
    `undefined` argument).
  - `tests/conformance/ext_empty_case.hs`: `absurd` over a `Void`-like
    type through `try`/`evaluate`, printing GHC's caught message prefix.
    If AHC's text differs, use an exec test instead.
  - `tests/corpus-types/bad_cases_arity.hs`, rejected by GHC.
- [ ] **Parser `\cases`.** Replace the rejection (883-889).
  - Parse alternatives with `Parse_Alt_Block`'s structure, but each
    alternative is `apat+` followed by `Parse_Guarded (Right_Arrow)` and
    `where`.
  - Check that the counts are equal. A mismatch is "\cases alternatives
    have different numbers of patterns".
  - Build `\c1$ .. cn$ -> case (c1$, .., cn$) of (p1, .., pn) ...`. For
    n = 1, no tuple: `\c1$ -> case c1$ of p1 ...`.
- [ ] **EmptyCase.** Replace the empty-block errors (980, 898) with a
  `Case_E` whose `Alts` is empty. In desugar's `Case_E` branch, empty
  `Alts` becomes ``seq scrut (error "empty case")``:
  `App2 (Global (Env.Seq_V ...), S, Error_Call ("empty case", Span))`.
  Find the seq global as desugar finds `>>`, through `Env.Values`.
  - Check every `Alts.Length >= 1` assumption: `ahc-syntax.adb:81`'s
    `Case_E` well-formedness predicate requires `N.Alts.Length >= 1`.
    Relax it, and check `Exhaustive.Check_Match` with zero rows.

### Task A4: the operator layout rule

- [ ] **Test:** `tests/conformance/ext_layout_operator.hs`. Cover:
  - `do`-block alternation with `<|>` at the statement column (a small
    Maybe-based parser);
  - a `where` binding followed by `++` at its column;
  - a ``​`mappend`​`` backquoted operator;
  - a `-` at the column, which must still start a new statement.
- [ ] **Parser.** In `Parse_Stmt_Block` (1360), extend the existing hook:

  ```ada
            if not Explicit
              and then (Tok.Kind in Kw_Where | Kw_In | Kw_Then | Kw_Else
                                     | Right_Paren | Right_Bracket | Comma
                        or else Op_Closes_Block)
              and then Try_Layout_Close
            then
  ```

  `Op_Closes_Block` is `At_Op and then not Tok_Is ("-") and then not
  Tok_Is ("!") and then Tok.Kind /= Tilde`, where `Tok_Is` compares
  `Tok_QName.Name` with an interned constant.
  - Make the same change in `Parse_Alt_Block` (1396-1401) and
    `Parse_Decl_Block` (2223-2241).
  - Check that `Try_Layout_Close` refuses a pending first-on-line token
    (115). The `<|>` here IS first on its line, so read that guard and
    widen it for this case if needed. Document why.

**Gate (Phase A):** `run_gate.sh` → `GATE ok`, `run_differential.sh`,
`run_differential_types.sh`, `run_repl.sh`, goldens on both builds.

---

## Phase B - RecordWildCards and NamedFieldPuns

### Task B1: puns (parser)

- [ ] **Test:** `tests/conformance/ext_record_puns_wildcards.hs`. Cover:
  - patterns `C{..}`, `C{x, ..}`, `C{x = 1, ..}`;
  - construction `C{..}` from `let`- and argument-bound variables, with
    one field missing (GHC fills bottom: never forced in the test);
  - puns in update `r{x}`;
  - nested records;
  - a wildcard field shadowing a top-level function of the same name.
- [ ] **Parser.** In `Parse_Record_Suffix` (781) and `Parse_APat` (605):
  - A field not followed by `=` is a pun. Append
    `Field_Assign'(F, Var_E F.Name)` or `Field_Pat'(F, Var_P F.Name)`. A
    qualified pun is an error, as in GHC.
  - `Dot_Dot` sets the new `Rec_Dotdot` and must be the last item.

### Task B2: wildcards (renamer and desugar)

- [ ] **Syntax:** `Rec_Dotdot : Boolean := False` on the
  `Rec_Con_E | Rec_Update_E` and `Rec_P` variants.
- [ ] **Renamer.** Add `Wild_Res : Wild_Maps.Map` to `Resolutions`,
  mapping a node id to a vector of `(Field_Index, Var_Id)`.
  - **`Rec_P` with `..`:** for each field of the constructor
    (`DataCon_Info.Field_Names`) not mentioned explicitly, mint a local
    named after the field. Do it the way `Bind_Pattern_Var` does, so it
    shadows exactly like a pattern variable. Record it.
  - **`Rec_Con_E` with `..`:** for each unmentioned field, look up a
    VALUE (not the field's own selector) with
    `Lookup_Value (Field_Name, Quiet => True)`. If found and not the
    selector, record it. Otherwise leave the field missing, as GHC does.
  - **`Rec_Update_E` with `..`** is an error: "record update cannot use
    '..'".
- [ ] **Desugar:**
  - Construction (1341-1375): a field with no explicit assignment takes
    its `Wild_Res` variable when present.
  - Patterns (686-730): the wildcard fields join the field sub-patterns
    as variable patterns.
  - Pattern-variable collection (270-290, 332) must include them.
- [ ] **Verify:** the test, `run_separate.sh` (records across modules),
  and a corpus-types reject `bad_update_dotdot.hs`.

**Gate (Phase B):** gate, both differential suites, `run_separate`,
`run_repl`, goldens on both builds.

---

## Phase C - stock DeriveFunctor / Foldable / Traversable

### Task C1: instance shape (renamer)

- [ ] **Tests**, oracled:
  - `ext_derive_functor.hs`: a sum type; a record; a field `[a]`; a
    field `Maybe (f a)` with a `Functor f` parameter; a tuple
    `(Int, a)`; a function `Int -> a`; a recursive tree; a phantom
    parameter.
  - `ext_derive_foldable.hs`: `sum`, `length`, `foldr (:) []` order,
    `maximum`, `elem`, `null` on the same shapes.
  - `ext_derive_traversable.hs`: `traverse` with Maybe (short circuit),
    with a list (the cartesian effect order), with IO printing (effect
    order), and `sequenceA`.
  - Rejects `bad_derive_functor_contra.hs` (`a -> Int`) and
    `bad_derive_foldable_fun.hs` (a function field).
- [ ] **Renamer `Stock_Derivable`.** Accept Functor (`Env.Functor_Cl`
  identity), Foldable and Traversable (`Env.Classes` identity). Accept
  them for `data` types. For newtypes, keep GND when its eta-reduction
  check would pass (the representation ends in the last variable, which
  is decided syntactically here: the field type is an `App_T` whose last
  argument is the last type variable, not occurring elsewhere).
  Otherwise use the stock path.
- [ ] **Instance shape.** Mint the instance with:
  - `Head_Vars` = the data's variables except the last (the wired spine
    rule);
  - `Stock_Derive` = `Derive_Functor | Derive_Foldable | Derive_Traversable`
    (new `Core.Stock_Derive_Kind`);
  - `From_Source => True`, so elaborate builds it from method bindings;
  - `Context` computed syntactically: for every field type `App_T`
    whose head is a type VARIABLE `f` (not the last variable) applied
    with the last variable in its last argument, add `Cl f`. GHC infers
    the same context. Constructor heads (Maybe, [], user types) resolve
    as wanteds when the synthesized code is typechecked.

### Task C2: the synthesis pass

**Files:** new `src/ahc-derive_functor.ads/.adb`; call it in
`src/ahc_main.adb` after desugar, before the typechecker, on every
instance with `Stock_Derive /= None`.

- [ ] **Algorithm,** GHC User's Guide "Deriving Functor instances". It
  works on Core types from each constructor's `Con_Scheme` (field types
  `t1 -> .. -> tk -> T v1 .. vn`).
  - `Map (T, F, X)` builds `fmap`'s per-field expression:

    | Field type `T` | Result |
    |---|---|
    | `TVar vn` | `F X` |
    | no `vn` | `X` |
    | `TApp (G, U)`, `vn` only in `U` | `fmap (\y -> Map (U, F, y)) X` |
    | a tuple | `case X of (y1..yk) -> (Map (t1, F, y1), ..)` |
    | `TFun (A, B)`, `vn` not in `A` | `\z -> Map (B, F, X z)` |
    | anything else | contravariant: an error at the instance span |

    (`fmap` is the Env global.)
  - `Fold (T, F, X, Acc)` builds `foldr`'s:

    | Field type `T` | Result |
    |---|---|
    | `vn` | `F X Acc` |
    | no `vn` | `Acc` |
    | `G .. U` | `foldr (\y acc' -> Fold (U, F, y, acc')) Acc X` |
    | a tuple | componentwise, right to left |
    | a function | an error |
  - `Trav (T, F, X)` builds `traverse`'s:

    | Field type `T` | Result |
    |---|---|
    | `vn` | `F X` |
    | no `vn` | `pure X` |
    | `G .. U` | `traverse (\y -> Trav (U, F, y)) X` |
    | a tuple | `liftA*` |
    | a function | an error |

    A constructor becomes `pure (\y1 .. yk -> K y1 .. yk) <*> e1 <*> ..`,
    in field order, which is GHC's effect order. A nullary constructor
    is `pure K`.
  - Each method is a `Lam` over F and the value, then a `Case_C` with one
    `Con_Alt` per constructor in declaration order. Newtype constructors
    take the same path, and codegen erasure makes their case free.
- [ ] **Method bindings.** Append `Bind_Pair (Binder => a fresh local
  named "fmap" / "foldr" / "traverse", Rhs => ...)` to
  `M.Instances (II).Method_Binds`. Read how desugar builds `Instance_D`
  method binds and copy that binder convention exactly (elaborate
  matches `M.Info (B.Binder).Name = Mth.Name`).
  - Foldable's other 11 methods come from the class defaults, which
    elaborate already applies to source instances. `traverse`'s
    `Applicative f` dictionary parameter is added by the typechecker,
    which checks the method against its scheme.
- [ ] **Errors:** "cannot derive 'Functor' for 'T': the last type
  variable occurs in a contravariant position", and so on (the Class_Gnd
  code, or a new Class_Derive code).
- [ ] **Verify:** the three conformance tests, the two rejects, and
  `run_userlib` (Data.Map's own Functor/Foldable instances must be
  untouched).

**Gate (Phase C):** gate in both GC modes, both differential suites,
`run_userlib`, `run_separate`, goldens on both builds, fuzz 100.

---

## Phase D - overlapping instances

### Task D1: pragmas to Instance_Info

- [ ] **Test:** `tests/conformance/ext_overlap_pragmas.hs`. Cover:
  - `OVERLAPPABLE C [a]` with `C [Char]`;
  - `OVERLAPPING C (Maybe Int)` with `C (Maybe a)`;
  - `OVERLAPS` three deep (`C a`, `C [a]`, `C [Int]`);
  - a separate module that uses `{-# LANGUAGE OverlappingInstances #-}`.
  - The existing `bad_overlap_use.hs` (no pragmas) stays rejected.
- [ ] **Core:**

  ```ada
     type Overlap_Kind is (No_Overlap, Overlapping, Overlappable,
                           Overlaps, Incoherent);
  ```

  Add `Overlap : Overlap_Kind := No_Overlap` to `Instance_Info`, and the
  new component to the three `Mint_Instance` aggregates.
- [ ] **Driver.** Add `Detect_Overlap (Arena, Source, Pragmas)` beside
  `Detect_Shadow`.
  - For each top-level `Instance_D`, a pragma whose span starts after
    the `instance` keyword's span (`Decl.Span.Stop`) and ends before the
    head type's span start, with text `OVERLAPPING`, `OVERLAPPABLE`,
    `OVERLAPS` or `INCOHERENT`, is recorded in
    `Arena.Overlap_Pragmas (Decl_Id) := kind`.
  - A `LANGUAGE` pragma naming `OverlappingInstances` sets
    `Arena.Lang_Overlapping`.
  - Call it where `Detect_Shadow` is called (ahc_main.adb 522-525,
    687-691).
- [ ] **Renamer `Declare_Instance`:** set `Overlap` from the map, or
  `Overlaps` when `Arena.Lang_Overlapping`.

### Task D2: the most-specific rule

- [ ] **`Inst_Match`:**

  ```ada
     --  A is more specific than B: B's head matches A's head (A's type
     --  variables rigid) and A's does not match B's.
     function More_Specific (M : in out Core_Module; Env : Builtins.Global_Env;
                             A, B : Instance_Info) return Boolean;

     --  GHC's overlap resolution among the Matched candidates: the one
     --  more specific than all others, legal when every other is
     --  overlappable or it is overlapping. 0 = no legal choice.
     function Pick (M : in out Core_Module; Env : Builtins.Global_Env;
                    Cands : Instance_Id_Vectors.Vector) return Natural;
  ```

  - `More_Specific` uses `Match_Head` with an identity `Norm` (the heads
    hold no metas) and M147's rigid-variable rule (structure against a
    TVar is `Undecided`, not `Matched`).
  - Overlappable means `Overlappable | Overlaps | Incoherent`;
    overlapping means `Overlapping | Overlaps | Incoherent`.
- [ ] **Callers:** where `Hits > 1` is an overlap error today, call
  `Pick`, and commit when it returns a candidate:
  - the typechecker's `Solve`;
  - elaborate's `Solve_Ev` (its first-Matched loop must collect every
    candidate and call `Pick` too, so the two passes cannot disagree);
  - Resolve_GND's `Reduce`.

  An `Undecided` from an `Incoherent` instance is ignored; any other
  keeps the wanted residual, as now.
- [ ] **Verify:** the test, `bad_overlap_use.hs` still rejected, and the
  M147 m147r_* tests unchanged.

**Gate (Phase D):** gate, both differential suites, `run_separate`,
`run_repl`, goldens on both builds, fuzz 100.

---

## Phase E - FlexibleContexts tests, scout, milestone gate

- [ ] `tests/conformance/ext_flexible_contexts.hs` (the design probe's
  four shapes plus an instance context `instance Show (f a) => Show
  (Wrap f a)`), oracled.
- [ ] `scripts/scout_repos.sh`: add FlexibleContexts, TupleSections,
  MultiWayIf, RecordWildCards, NamedFieldPuns, EmptyCase, DeriveFunctor,
  DeriveFoldable, DeriveTraversable and OverlappingInstances to
  `ok_ext`.
- [ ] **Milestone gate:** release build; goldens on both builds; full
  gate in both GC modes; both differential suites; repl, examples,
  bindgen, separate, export, userlib, TSan; own soak with
  `AHC_OWN_VERIFY=1`; fuzz 300.
- [ ] **Bench:** A/B against v1.18 (rebuild the
  `/private/tmp/claude-501/ahc-v117` worktree at v1.18), with
  instructions retired where wall time is noisy.
- [ ] **Scout:** re-run the M147 candidate list
  (`scratchpad/scout147_hits.txt`) and record which repos now agree.

**Gate:** all of the above green; bench and scout recorded in the
verdict.

## Phase F - review, write-up, release

- [ ] **Adversarial review,** one reviewer per area:
  - syntax and layout;
  - records;
  - deriving;
  - overlap;
  - a claims audit.

  Then a verification pass. Fixes land as `fix: N defects an adversarial
  review of M148 found`.
- [ ] **Write-up:** CHANGES v1.19; MANUAL (the extensions section);
  EXCLUSIONS (the ext row); repos-to-try (the extensions bullet); memory.
- [ ] **Release v1.19,** with the user's go-ahead.
