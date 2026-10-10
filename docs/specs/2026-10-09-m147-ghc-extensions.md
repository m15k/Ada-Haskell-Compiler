# M147 - LambdaCase, FlexibleInstances, TypeSynonymInstances, GeneralizedNewtypeDeriving

**Status:** approved design, 2026-10-09.
**Oracle:** GHC 9.4.8 (`~/.ghcup/bin/runghc`; compile with `ghc -O0` for stderr and exit codes).
**Policy:** all four extensions are **always on**, as `OverloadedStrings` already is.
- AHC keeps ignoring `LANGUAGE` pragmas.
- Every program GHC accepts behaves identically.
- AHC also accepts the few programs GHC rejects only because a pragma is missing.

## Why

`docs/repos-to-try.md`'s list of what blocks real repositories puts extensions
second, after Hackage dependencies. The leaders are `LambdaCase` and
`TemplateHaskell`, then `FlexibleInstances`, `TypeSynonymInstances`,
`InstanceSigs` and `GeneralizedNewtypeDeriving`. `InstanceSigs` already works
(probed during M146's design). Template Haskell is far out of reach. The other
four fail today:

| Program fragment | AHC v1.17 |
|---|---|
| `f = \case Just n -> n; _ -> 0` | parse error: expected a pattern (found 'case') |
| `instance Pretty [Char] where ...` | couldn't match type '[?7169]' with '[]' |
| `instance Pretty String where ...` | type not in scope: String |
| `newtype Age = Age Int deriving (Num)` | cannot derive 'Num': not a stock derivable class |
| `newtype W a = W (Maybe a) deriving (Functor)` | cannot derive 'Functor': not a stock derivable class |

There is also an older wrong-output bug in the same area. **Newtypes are boxed
at run time**, so `N undefined `seq` x` returns `x`. GHC and Report 4.2.3 give
bottom, because a newtype adds no run-time box.

## Unit 1 - LambdaCase

- **Tokens and layout.** `\case` already lexes as `Backslash Kw_Case`
  (src/ahc-tokens.ads). The layout pass (src/ahc-layout.adb:197-201) opens an
  implicit block after `Kw_Case` when the previous token is `Backslash`, exactly
  as it does after `of`. Explicit braces (`\case { ... }`) work too.
- **Parser.** In `Parse_LExp`'s `Backslash` branch (src/ahc-parser.adb:871),
  a following `Kw_Case` reads `Parse_Alt_Block` (:1338) into a new
  `Lambda_Case_E` expression kind (src/ahc-syntax.ads). The parser cannot mint
  binders.
- **Renamer and desugar.** The renamer resolves the alternatives like a
  `case`'s. Desugar mints a fresh binder `$lc` and produces `\$lc -> case $lc of
  alts`, reusing the case path: guards, `where`, nested patterns and
  non-exhaustive-match failure behave exactly as in `case`.
- **Type checking.** It follows from the desugared form, or from a dedicated
  rule if the typechecker runs before desugaring: a function from the
  scrutinee's type to the alternatives' type.

## Unit 2 - FlexibleInstances and TypeSynonymInstances

### Today

- The renamer (`Instance_Head`, src/ahc-rename.adb:1852-1889) reduces an
  instance head to one type constructor, looked up with `Mod_Find_TyCon`. It
  never consults synonyms, hence "type not in scope: String".
- Kinds (`Do_Instance`, src/ahc-kinds.adb:1150-1188) converts the head type and
  then discards it, keeping only its type variables (`Head_Vars`).
- Instance resolution is keyed by (class, head TyCon) in three places:
  - the typechecker's `Solve` (src/ahc-typechecker.adb:681-783);
  - the elaborator's `Solve_Ev` (src/ahc-elaborate.adb:166-287);
  - the duplicate check in `Declare_Instance` (src/ahc-rename.adb:1916).
- Dictionary globals are named `$d<Class><TyCon>`.

### Design

- **Store the head type.** `Instance_Info` (src/ahc-core.ads:285-308) gains
  `Head_Type`: the converted head, with synonyms expanded (`String` becomes
  `[Char]`). `Head` (the TyCon) stays and is derived from `Head_Type`, so code
  that only needs the constructor keeps working. `Head_Vars` stays: the type
  variables of `Head_Type`, in order of first appearance.
  - The renamer resolves the head through the same path as ordinary types
    (`Resolve_Ty`), so synonyms in heads resolve.
  - A head that is a bare type variable (`instance C a`) is accepted: GHC 9.4.8
    accepts it even without a pragma (oracled). Its `Head` is `No_TyCon`, it
    matches every type, and so it overlaps every other instance of its class.
    Code that reads `Head` must handle `No_TyCon`; the plan finds every reader.
- **One-way matching.** A single `Match_Head (Head_Type, Wanted) return
  Subst-or-fail` binds only the instance's variables, never the wanted's. All
  three places use it:
  - The typechecker solves a wanted `C t` by matching every instance of `C`
    against `t`. Exactly one match commits it, and its context is instantiated
    through the match substitution instead of by position.
  - If no instance matches but one *could* once a metavariable in `t` is
    resolved, the constraint stays deferred.
  - If two or more match, it is an error (see Overlap).
  - The elaborator resolves dictionaries with the same function on the zonked
    types, so the two passes can never disagree.
  - Declarations overlap when their heads unify. Overlap alone is accepted.
    Two declarations whose heads are equal up to renaming of variables are a
    duplicate-instance error, as today.
- **The method and superclass checks** (typechecker.adb:1789-1798, :1863-1874)
  build the instance type from `Head_Type` instead of `TCon Head` applied to
  `Head_Vars`. That is the source of today's `[?]` vs `[]` error.
- **Dictionary names** become `$d<Class><TyCon>` for the first instance per
  (class, TyCon) and `$d<Class><TyCon>$<n>` after that. They are internal names,
  so nothing user-visible changes. The by-identity rule from M75 still holds:
  dictionaries are found through `Instance_Id`, never by name.
- **The IsString/[Char] special case** in `Solve` (typechecker.adb:723-749) is
  re-expressed as an ordinary `IsString [Char]` instance head if that falls out
  naturally; otherwise it stays, and the plan records why.

### Overlap, as GHC does it

GHC accepts overlapping instance declarations. A use that matches more than
one is an error:

```
Overlapping instances for C String arising from a use of 'c'
  Matching instances: instance C [a] ... instance C [Char] ...
```

A use that matches only one (`c [True]` with both `C [Char]` and `C [a]` in
scope) compiles and runs. AHC does the same. The error text follows AHC's
diagnostic style: it names the class, the type and both instance heads, but is
not byte-identical to GHC's, because diagnostics are not conformance output.
`OverlappingInstances` and the per-instance `{-# OVERLAPPING #-}` pragmas are
out of scope.

## Unit 3 - newtype erasure, then GeneralizedNewtypeDeriving

### 3a. Erasure

- **Desugar** (src/ahc-desugar.adb) applies three rules:
  - Applying a newtype constructor `N e` becomes `e`.
  - The bare constructor `N` becomes the identity function.
  - Matching `N p` becomes matching `p` against the scrutinee itself. The
    existing `Newtype_Projection`/`Newtype_Field_Match` paths (:403-476) become
    the identity, and the match stays irrefutable.
- **Results:**
  - Report 4.2.3 semantics: `N undefined `seq` x` is bottom.
  - `case undefined of N _ -> 1` is `1`, as today.
  - Wrapping and unwrapping cost nothing at run time.
- **Audit:** everything that inspects constructor nodes at run time must still
  give GHC's answer for newtypes. The plan enumerates and tests each one:
  - derived `Eq`/`Ord` (the structural `P_EqP` primitive), and derived
    `Show`/`Read`, which must still print and parse `Age 7`;
  - derived `Enum`/`Bounded`/`Ix` on newtypes;
  - record newtypes (`newtype R = R { unR :: Int }`), including field selection
    and record update;
  - newtypes in the FFI (Haskell 2010 FFI allows a newtype of a marshallable
    type as an argument or result);
  - newtypes in `Data.Map` keys and other library code;
  - `show` of a newtype nested in a data type;
  - pattern-match failure messages;
  - separate compilation (`run_separate.sh`) and export interfaces.
- Core keeps the newtype `TyCon_Info.Is_Newtype` flag. Only desugar's output
  changes, so the typechecker is untouched.

### 3b. GeneralizedNewtypeDeriving

- **Which classes.** `deriving (C)` on a newtype accepts any class `C` whose
  instance at the representation type exists, except `Show` and `Read`. Those
  stay stock, as in GHC, printing the constructor (`Age 7`). The newtype
  strategy applies to every other class, including the stock-derivable `Eq`,
  `Ord`, `Bounded`, `Ix` and `Enum`, whose results agree with stock deriving.
  `Enum` on a non-enumeration newtype becomes possible, as in GHC.
- **Head shape.** For `newtype T v1 .. vn = K (R ...)`:
  - **Kind-`*` class** (`Num`, `Eq`, ...): the instance head is
    `T v1 .. vn`, and the dictionary is the representation type's dictionary
    for `R`. If `R` mentions the `vi`, the instance takes the context `R`'s
    instance needs, instantiated.
  - **Kind-`* -> *` class** (`Functor`, `Applicative`, `Monad`, ...): the last
    type variable `vn` is eta-reduced away. The representation must have the
    form `R' vn`, with `vn` occurring only as that final argument. The head is
    `T v1 .. vn-1`, and the dictionary is `R'`'s. `newtype W a = W (Maybe a)
    deriving Functor` reuses `Functor Maybe`.
- **Precondition, checked when the instance is declared.** The representation
  (eta-reduced for constructor classes) must have a matching instance, under
  Unit 2's matching. Otherwise it is a compile error naming the class, the
  newtype and the representation type. For example, GHC rejects
  `newtype Parser a = Parser (String -> [(a, String)]) deriving Functor`,
  because `(->) String` composed with a list is not an instance head. AHC
  rejects it too.
- **Implementation.** Because of 3a, the dictionary is literally the
  representation's dictionary: the derived instance's dictionary global is
  bound to the representation instance's dictionary, applied to the derived
  instance's context dictionaries when it has any. No method wrappers.
  - Rename's `Stock_Derivable` (src/ahc-rename.adb:1472-1492) still governs
    `data` types.
  - For newtypes the renamer defers the class check to the GND precondition.
  - The derived instance's `Head_Vars` and context are computed from the
    representation, not from the "every tyvar at kind `*`" shape
    (rename.adb:1668-1707).

## Error handling

- New errors, each pinned in `tests/corpus-types/`:
  - an ambiguous overlapping use;
  - a duplicate instance;
  - a failed GND precondition;
  - a constructor-class derivation whose representation cannot be
    eta-reduced.
- `\case` with no alternatives (`\case {}`) is a parse error. GHC accepts it
  only under `EmptyCase`.

## Gates

- **Conformance**, oracled against GHC 9.4.8:
  - `ext_lambda_case`: in expressions, in `where`, inside `do`, with guards,
    with nested layout, and with explicit braces;
  - `ext_flexible_instances`: `C [Char]`, `C String`, `C (Maybe Int)` beside
    `C (Maybe Bool)`, instances with contexts over a partially concrete head,
    the overlapping pair `C [Char]`/`C [a]` used only at `[Bool]`, and a
    bare-variable head `instance C a`;
  - `ext_gnd`: `Num`/`Real`/`Enum`/`Integral`/`Bounded`/`Eq`/`Ord` on `Age`,
    `Functor`/`Applicative`/`Monad` on a wrapped `Maybe` and a wrapped `State`,
    stock `Show`/`Read` alongside;
  - `ch04_02_newtype_seq`: Report 4.2.3's newtype semantics, including `seq`,
    lazy patterns and `case undefined of N _`.
- **Corpus-types** rejects for each new error; the M146 probe programs pass.
- **Suites:**
  - the full gate in both GC modes;
  - goldens on the validation and release builds (erasure changes Core, so a
    golden diff here is expected; the binding-name check still applies);
  - both differential suites, repl, examples, bindgen, export, separate and
    userlib;
  - the own-collector soak with `AHC_OWN_VERIFY=1`;
  - fuzz 300.
- **FFI:** any change to how a newtype is marshalled gets the security pass
  (`/security-review`).
- **Bench** against v1.17, interleaved best of 5, with instructions retired
  where wall time is noisy.
- **Release process:** adversarial review, write-up (CHANGES, MANUAL,
  repos-to-try's Extensions bullet), release v1.18.

## Out of scope

- `\cases`, `MultiWayIf`, `TupleSections`, `EmptyCase`;
- `DeriveFunctor` (stock `Functor` for `data` types), `DerivingVia`,
  `StandaloneDeriving`, and deriving strategies syntax;
- `OverlappingInstances`/`OVERLAPPING` pragmas and `IncoherentInstances`;
- multi-parameter type classes and `FlexibleContexts` beyond what Haskell 2010
  contexts already allow;
- `TemplateHaskell`;
- gating extensions on `LANGUAGE` pragmas.

## Errata (after implementation and the adversarial review)

- **Default language.** GHC 9.4.8's default language is GHC2021, which enables
  FlexibleInstances, TypeSynonymInstances, GeneralizedNewtypeDeriving,
  FlexibleContexts, DeriveFunctor and EmptyCase. Only LambdaCase needs a
  pragma under `runghc`.
- **`Parser` example.** GHC accepts `newtype Parser a = Parser (String ->
  [(a, String)]) deriving Functor` through stock DeriveFunctor. AHC rejects it
  (no stock DeriveFunctor; EXCLUSIONS). The GND precondition test uses a
  contravariant field instead.
- **`\case {}`.** It is accepted by `runghc` (EmptyCase is in GHC2021).
  Rejecting it is a documented gap, as is `\cases`.
- **Where things landed.**
  - Unit 1's `Lambda_Case_E` became a parser rewrite over an unspellable binder.
  - Unit 3a's desugar erasure became codegen erasure: one place covers every
    Core producer.
- **Tests.**
  - The "wrapped State" GND test landed as `m147r_gnd_function_rep` (a reader
    over `e -> a`), once the review made function representations eta-reduce.
  - Newtype keys in `Data.Map` were probed by the review and agree with GHC.
  - Newtypes in FFI signatures are rejected ("not marshallable"), which is
    recorded in EXCLUSIONS rather than tested.
