# M150 - the correctness round

**Status:** design approved in brainstorming, 2026-10-15; this spec is
awaiting review.
**Oracle:** GHC 9.4.8 (`~/.ghcup/bin/runghc`; compiled `ghc -O0` where
an exception's rendering differs). Its default language is GHC2021.
**Scope:** seven places where AHC rejects or misreads a program GHC
accepts, plus the error-text follow-ups M149 recorded in EXCLUSIONS.

## Why

Each item below was probed against both compilers on 2026-10-14
(programs in the brainstorming scratch; each becomes a conformance case).

| # | Program | GHC 9.4.8 | AHC v1.20 |
|---|---|---|---|
| 1 | `sumTo !acc 0 = acc` | `5050` | parse error: `expected '='` |
| 2 | `mapM f (Just 3)`, `sequence (Just [1,2])`, `mapM` over a user `Traversable` | works | type error: `couldn't match type '[]' with 'Maybe'` |
| 3 | `data P = P Ci Int deriving (Eq, Ord)`, `Ci` with a case-insensitive `instance Eq` | `True` | **`False`, silently** |
| 3b | `[Ci "A"] == [Ci "a"]`, also through `Maybe` and tuples | `True` | **`False`, silently** |
| 4 | `data T = T F deriving Show`, no `Show F` | compile error `No instance for (Show F)` | runs, then `deriving Show: unsupported field type` |
| 4b | `data Ph a = Ph Int deriving Eq`; `Ph 1 == (Ph 1 :: Ph (Int -> Int))` | `True` | `no instance for 'Eq Int -> Int'` |
| 5 | `f x = x + 1 where x = 10` | `11` | `'x' is bound more than once` |
| 6 | `(case n of` / alternatives / `)` at the alternatives' column | `(1,2)` | `expected a pattern (found ')')` |
| 7 | `let ñ = 1; café = ñ + 1` | `(1,2)` | `invalid character` |

Items 3 and 3b are the reason this milestone exists: valid programs get
wrong answers with no diagnostic. Item 3b means any container of a type
with a hand-written `Eq`/`Ord` compares wrongly today.

The M149 follow-ups (EXCLUSIONS, Exceptions row): library modules raise
their own texts without GHC's call stacks (`Data.Map`, `Data.Set`,
`Data.Array`, `Numeric`, `digitToInt`, `maximumBy`), `Word`'s errors
name `Word64`, and derived `Enum` errors lack the call stack GHC prints
at the `deriving` clause.

## Phases

Phases A, B and E are independent. C precedes D (derived `Traversable`
and the new `mapM` interact through the class hierarchy).

### A. Lexer and parser

**A1. Bang patterns** (always on, the convention for AHC's extensions;
GHC2021 enables them).
- A `!` is a bang when whitespace or an opening bracket precedes it and
  no whitespace follows it (GHC 9's rule); otherwise it is the operator
  `!`. `f !x = e` is strict in `x`; `arr ! i = e` defines `(!)`.
- New `Bang_P` pattern node beside `Lazy_P`, handled in every pass that
  handles `Lazy_P`: rename, fixity, exhaustiveness (a bang is
  transparent there), the printer, desugar. Allowed wherever an apat
  is: equations, lambdas, `\case`, `\cases`, case alternatives, nested
  (`(!a, b)`, `Just !x`), under `~`.
- Meaning: matching `!p` against `v` forces `v` to WHNF, then matches
  `p`. Desugar: `seq v (match p)`, finding `seq` as EmptyCase does.
- Strict bindings: `let !x = e in b` and `where !x = e` force `x`
  before the body (before the guards, for `where`); `!x <- m` in `do`
  forces the bound result.
- A bang on a top-level binding is a compile error, as in GHC.

**A2. A closing token ends a layout block.** The do-block loop's
start-of-item check (a token that cannot start an item - `)`, `]`, `,`,
`then`, `else`, `of`, `in`, `where`, or an operator that closes a block
- triggers `Try_Layout_Close`) is applied at the start of each item in
`Parse_Alt_Block`, `Parse_Cases_Block` and `Parse_Decl_Block`: the
Report's parse-error(t) rule, applied consistently.

**A3. Unicode identifiers and operators**, per the Report's lexical
syntax (2.2, 2.4):
- variable start: a lowercase letter or other letter (Unicode Ll, Lo)
  or `_`; constructor start: uppercase or titlecase (Lu, Lt);
  continuation: any letter (L*), a decimal digit (Nd), `'`, `_`;
- operator characters: Unicode symbols and punctuation (S*, P*) other
  than the Report's special characters, so `(∘)` can be defined.
- Category data: `tests/gen_unicode.hs` also emits
  `src/ahc-unicode.ads`, a two-level table of GHC 9.4.8's
  `generalCategory` - exact by construction, as the runtime's
  `Data.Char` tables are.
- The lexer decodes UTF-8 for identifiers and operators (today only in
  character literals). Columns count code points, so layout under
  non-ASCII identifiers matches GHC (check `Source_Text.Column_Of`;
  fix it if it counts bytes).
- Out of scope: `UnicodeSyntax` (`→`, `∀` as keywords; off in GHC2021).

**Gate A:** conformance (oracled) - bang patterns in every position,
strict `let`/`where`/`do`, a bang forcing `undefined`, `)` closing after
`case`/`\cases`/`where`, identifiers in Spanish, Greek, Cyrillic and
CJK, Unicode operators, layout aligned under multi-byte identifiers;
negative corpus - a top-level bang; parse goldens regenerated and
audited; differential parse green; 300-seed fuzz.

### B. Renamer: `where` shadows the arguments

In `Rename_Value_Decl`'s `Fun_D` arm the argument patterns and the
`where` group get separate scopes (a second `Push_Scope` before
`Declare_Group`), so `where x = ...` shadows argument `x` over the
guards and right-hand side. The same split for a case alternative's
pattern and its `where` (`ahc-rename.adb` ~1334). Duplicates within one
`where` group or one pattern (`f x x`) stay errors.

**Gate B:** conformance - shadowing in equations, guards and case
alternatives; negative corpus - a duplicate inside one `where`; full
suites.

### C. The class hierarchy: Applicative above Monad

GHC 7.10's Applicative-Monad Proposal and Foldable/Traversable in the
Prelude, which GHC 9.4.8 has.

- **Wiring.** `Applicative` moves from Prelude source into
  `src/ahc-builtins.adb` beside the wired `Functor` and `Monad`, with
  all five methods (`pure`, `<*>`, `liftA2`, `*>`, `<*`) and `Functor`
  as superclass. `Monad` gains `Applicative` as superclass. The
  defaults of `liftA2`, `*>`, `<*` stay Haskell in the Prelude,
  attached the way the wired `Monad`'s `>>` default is. `Monad` stays
  wired: do-notation desugars to the wired `>>=`/`>>`.
- **Defaults and entailment.** `return` defaults to `pure` (replacing
  the M141 head-solving trick). A given `Monad m` yields `Applicative
  m` and `Functor m` by ordinary superclass extraction, so
  `Monad_Entails_In_GHC` (`ahc-typechecker.adb` ~665) is deleted.
- **Traversable**, base's shape: `class (Functor t, Foldable t) =>
  Traversable t` with methods `traverse`, `sequenceA`, `mapM`,
  `sequence`; defaults `sequenceA = traverse id`, `mapM = traverse`,
  `sequence = sequenceA`. The list-only top-level `mapM`/`sequence` are
  removed; the `[]` instance keeps a direct monadic `mapM` if the bench
  asks for it.
- **New module and instances.** `lib/Data/Traversable.hs`
  (`Traversable(..)`, `for`, `forM`, `mapAccumL`, `mapAccumR`);
  `Control.Monad`'s `forM`/`forM_` become general. New instances as in
  base: `Traversable` for `Set`, `Identity`, `((,) a)`, `Array i`;
  `Functor`/`Foldable` for `((,) a)`. The Prelude export list stays
  GHC's (`check_prelude_exports.sh`).
- **User-visible change.** A `Monad` instance without an `Applicative`
  instance is rejected, as in GHC. The error carries a hint:

  ```
  error: no instance for 'Applicative Parser', required by the
    superclasses of an instance declaration
    hint: add  instance Applicative Parser where
                 pure = return; (<*>) = ap
  ```

  and likewise `Functor` (`fmap = liftM`). Every Monad instance in the
  Prelude, `lib/` and the tests already has its Applicative instance
  (audited 2026-10-15).
- EXCLUSIONS loses the "Monad does NOT have Applicative as superclass"
  clause and the "`mapM`/`sequence` are list-only" clause.

**Gate C:** full suites both GC modes; differential parse + types;
conformance (oracled) - `mapM`/`sequence`/`traverse` over `Maybe`,
`Either`, `Map`, a user `Traversable`, tuples, `Array`; `pure`/`<*>`/
`fmap` used under `Monad m =>` alone; `forM` over `Maybe`; negative
corpus - a Monad without Applicative (pins the hint); Core golden diffs
explained line by line (the Monad dictionary shape changes, so the diff
is not renumber-only); bench delta, 2% budget on the sequential
benchmarks.

### D. Deriving and structural equality

**D1. Structural dictionaries.** One structural primitive
(`poly_cmp`, `ahc_rts.c` ~2499) serves every wired and derived
`Eq`/`Ord` instance; it is correct only when every type it reaches
compares structurally.
- A dictionary is *structural* when its `==`/`compare` agrees with the
  primitive on every value of its type. Base instances are structural:
  `Int`, `Integer`, `Char`, `Double`, `Float`, the fixed-width types,
  `Word`, `Bool`, `()`, `Ordering`.
- An instance for a type constructor (list, `Maybe`, `Either`, tuples,
  every derived instance) is structural exactly when every dictionary
  it is applied to - the context's, and each concrete field type's - is
  structural.
- Decided when the dictionary is built, not per comparison: a
  structural dictionary's methods are the primitives, as today (strings,
  `[Int]` and derived records keep their speed; contract discharge
  keeps seeing the primitives it special-cases); any other gets
  field-wise code calling each field's instance, constructors compared
  in declaration order for `Ord` (Report 11.1).
- New `Derive_Eq`/`Derive_Ord` in `ahc-prelude_core.adb` build the
  field-wise bodies with `Dict_For_Class`, as `Derive_Show` does; the
  list, `Maybe`, `Either` and tuple instances get the same treatment.
  This also closes the EXCLUSIONS gap where a user's overlapping
  `Eq [Bool]` was ignored.

**D2. Inferred derived contexts.** Stock `Eq`, `Ord`, `Show`, `Read`
stop using one `C a` per type variable; they reuse the derived-context
reducer GND already uses (`Reduce`, `ahc-typechecker.adb` ~2041), which
walks the constructor fields:
- phantom parameters need nothing: `Ph (Int -> Int)` compares;
- a missing field instance is a compile error at the deriving clause's
  class name, never a runtime crash (function fields, existentials and
  missing instances all land here):

  ```
  T.hs:2:23: error: no instance for 'Show F', arising from the first
    field of 'T' (type 'F'), when deriving 'Show T'
  ```

- the type printer parenthesises function types in these messages
  (today: `'Eq Int -> Int'`).

**D3. Deriving clauses keep their spans.** `Parse_Deriving` records a
span per class name; the renamer copies it onto the instance (today the
instance span is the `data` keyword). Uses: the D2 error position, and
derived `Enum`'s call stack - the renamer precomputes GHC's
`CallStack (from HasCallStack):\n  error, called at F:L:C in
main:Module` at that span, stores it on the instance, and `Derive_Enum`
raises `succ`/`pred`/`toEnum` failures through `primErrorLoc`.

**Gate D:** conformance (oracled) - `Ci` inside lists, `Maybe`,
tuples, `Either`, derived records, nested derived types; `compare`
across constructors; a phantom parameter; derived `Enum` errors in a
single- and a multi-module program; an overlapping `Eq [Bool]`;
negative corpus - missing `Show`/`Eq`/`Ord` field instances and a
function field; `run_discharge.sh` unchanged; bench delta with
`b_sort` and `b_map` checked by name; full suites both GC modes.

### E. Library error texts and `Word`

**E1. Texts recorded from the oracle.** Every reachable `error` site
in `lib/` raises GHC 9.4.8's exact text, recorded by running a probe
(not transcribed from base's source). Fixed call stacks go through the
existing `primErrorLoc` (message + constant location); containers'
functions are not `HasCallStack`, so their stacks have no user frame.

| Site | Today | Disposition |
|---|---|---|
| `Data.Map`: `!`, `findIndex`, `elemAt`, `deleteAt`, `findMin`, `findMax`, `deleteFindMin`, `deleteFindMax`, Foldable `maximum`/`minimum` | message only | GHC text + containers call stack |
| `Data.Set`: `elemAt`, `findIndex`, `deleteFindMin` | message only | GHC text + call stack |
| `Data.Array` `!` | `(Array.!): index out of range` | through the index's `Ix` instance: `Ix{Int}.index: Index (5) out of range ((0,2))`, per-type texts recorded for `Char`, `Integer`, tuples, derived `Ix` |
| `Data.Array` undefined element | `(Array.!): undefined array element` | GHC text |
| `Numeric.showIntAtBase` | `negative` | `applied to negative number -1` |
| `digitToInt` / `intToDigit` | no value | `not a digit 'z'` / `not a digit 20` |
| `maximumBy` / `minimumBy` | list-only, `List.maximumBy: empty list` | `Foldable`-general, `maximumBy: empty structure` |
| `Map.fromDistinctAscList`, `balance*`, `formatRealFloat`, `roundTo` | internal | unchanged: unreachable from valid input |

**E2. `Word` is its own type.** A wired `Word_TC` with `Word64`'s
representation and the full fixed-width instance set (`Eq`, `Ord`,
`Show`, `Read`, `Num`, `Real`, `Enum`, `Bounded`, `Integral`, `Bits`,
`FiniteBits`, `Ix`, `PrintfArg`), conversions through `fromIntegral`,
FFI marshalling as `uint64_t`, and `bindgen` mapping `size_t`/
`uintptr_t` to it where it does today. Its texts name `Word`; mixing
`Word` and `Word64` without a conversion is a type error, as in GHC.

**Gate E:** conformance (oracled) - a probe per changed site (caught
`show`), a `Word` program (arithmetic, `show`/`read`, `Enum` errors,
`Bits`, conversions); negative corpus - `Word` used as `Word64`;
`run_export.sh` and `run_bindgen.sh`; full suites both GC modes.
EXCLUSIONS loses the library-text clause.

## Milestone gate

Full suites in both builds and both GC modes; own soak with
`AHC_OWN_VERIFY=1` (from the 64KB floor); TSan; 300-seed fuzz;
differential parse + types; bench delta against v1.20 within 2%, with
`b_sort` and `b_map` named; then the adversarial review and the
write-up (CHANGES, README, MANUAL, EXCLUSIONS, the memory notes).

## Out of scope

`MonadFail` (GHC 8.8's split of `fail`); GHC2021 extensions beyond
`BangPatterns`; `UnicodeSyntax`; `show (e :: ErrorCall)`'s missing
call stack (needs pattern synonyms).
