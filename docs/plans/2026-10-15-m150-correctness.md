# M150 The correctness round - Implementation Plan

**Goal:** every program in the spec's probe table compiles and prints
GHC 9.4.8's output: bang patterns, `mapM` over any `Traversable` with
`Applicative` above `Monad`, `Eq`/`Ord` that respect a field's own
instance, derived contexts inferred from the fields, `where` shadowing,
closing tokens ending layout blocks, Unicode identifiers - plus GHC's
exact library error texts and `Word` as its own type.
**Architecture:** five independent-ish phases over the lexer/parser
(A), renamer (B), the wired class hierarchy and Prelude (C), the
dictionary builders in `ahc-prelude_core.adb` plus the typechecker's
derived-context reducer (D), and `lib/` error sites plus a new wired
`Word` type constructor (E). Spec:
`docs/specs/2026-10-15-m150-correctness.md`.

## Global constraints

- Oracle: GHC 9.4.8, `~/.ghcup/bin/runghc` (default language GHC2021).
  Conformance `.out` files are produced FROM THE REPO ROOT:
  `~/.ghcup/bin/runghc tests/conformance/NAME.hs > tests/conformance/NAME.out`.
  Multi-module cases run from their own directory
  (`tests/conformance/multi/NAME/`).
- New tests are named `m150_*`.
- `prelude/`, `lib/`, `runtime/ahc_rts.c`, `bin/ahc` and `scripts/` are
  gate inputs: never edit or rebuild them while a suite runs. Never edit
  `src/` during a gate that ends with a rebuild.
- Core goldens are generated on the RELEASE build
  (`alr build --release`, then `scripts/run_golden.sh --update`) and the
  validation build must reproduce them; a diff that is not
  renumber-only must be explained line by line (phases C, D, E say what
  each expects).
- Ada: never pass two node-minting calls as actuals of one call; hoist
  them into constants (release and validation number Core differently
  otherwise).
- Every phase gate includes the full suites in BOTH GC modes
  (`scripts/run_gate.sh`: unit, conformance, exec, exec-own, golden,
  prelude-exports, userlib).
- Perf budget: bench delta against v1.20 within 2% on the sequential
  benchmarks, `b_sort` and `b_map` named, measured interleaved
  (`scripts/run_bench.sh`; never compare absolute times across runs).
- Commits: conventional prefix, lowercase prose subject, trailer
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Execution order

B1 → A1-A6 → C1-C7 → D1-D8 → E1-E6. B is the smallest change; C must
precede D (both edit `Give_Dict`'s superclass loop and the superclass
check's message - D3 and D5 say how to merge onto C's version); E is
mostly `lib/` and one new type constructor. Anchors in each task are
quoted code, not only line numbers: earlier phases shift lines.

## Where this plan departs from the spec

Found while planning, each recorded in its phase and in the write-up:

- **A3:** operator characters follow GHC, not "S* and P*": GHC excludes
  Ps/Pe/Pi/Pf (`a ⟨ b` is a lexical error); Lm/Mn continue a name but
  cannot start one. `Source_Text.Column_Of` counted bytes; it now
  counts code points.
- **C1 (new prerequisite):** the tuple type constructors `(,)`/`(,,)`
  must parse as prefix types (`instance Functor ((,) a)`).
- **C4/C5:** no `Traversable Set` (base has none; GHC rejects it), and
  the `Array` instances are at `Array` (AHC's `Data.Array` has one type
  parameter).
- **D:** the derived-`Enum` call-stack string is computed in
  `ahc_main` after desugar (the renamer has no file context); a GND
  newtype over a stock-derived type still sees the per-variable context
  (GND resolution runs before inference) - stricter than GHC, recorded
  in EXCLUSIONS. Also fixed: a pre-existing `selector on a
  non-dictionary` crash under an `Ord a` context, and `max`/`min` ties
  (GHC's `max` answers `y`).
- **D, not fixed:** NaN inside a derived or wired `Ord` (`Just nan >
  Just 1` is True in AHC, False in GHC) - recorded in EXCLUSIONS.
- **E:** `Word` is its own `Word_TC` marshalled as `Word64`, not a
  ninth fixed-width kind; no `FiniteBits` (AHC has no such class); no
  `Ix` for triples (no `Ord (a,b,c)`); no bindgen change (nothing maps
  `size_t` to `Word` today; `CSize` stays `Word64` as in GHC). Also
  fixed: `maximumBy` returned the first of equal maxima (GHC: the last)
  and `showIntAtBase` looped on base 1.
- **Found outside scope:** `let x = e :: Int in b` misparses (the
  refinement-type syntax reads `Int in ...` as a range); tests
  parenthesise such annotations. Candidate for M151.

## Phase A - lexer and parser

Spec items A1 (bang patterns), A2 (a closing token ends a layout
block) and A3 (Unicode identifiers) land as six tasks. A1 here is the
spec's A2, which is independent and smallest; the Unicode table and
lexer (A2, A3) come before the bang lexing (A4), whose prefix rule
asks whether a neighbouring character is a Unicode letter.

Every code step below was applied to a scratch copy of the tree at
`23cdddf` and built; with all of Phase A and B applied, the six new
conformance programs printed their oracle output byte for byte and
the unit tests reported `passed: 389, failed: 0` (359 before),
`run_gate.sh` reported `GATE ok` (every suite, both collectors), and
`run_differential.sh` and `run_differential_types.sh` exited 0. The
300-seed fuzz campaign was not run on that copy.

### Phase A/B file map

| File | Change |
|---|---|
| `src/ahc-parser.adb` | `At_Item_Closer` (one parse-error(t) rule for four block loops); `Prefix_Bang` in apats, equation lookahead, the expression-context error |
| `tests/gen_unicode.hs` | `ada` mode emits `src/ahc-unicode.ads` |
| `src/ahc-unicode.ads` (new, generated) | GHC 9.4.8's `generalCategory`, two-level table |
| `src/ahc-lexer.adb` | UTF-8 decoding, GHC's character classes, the prefix-`!` rule |
| `src/ahc-tokens.ads/.adb` | new token kind `Prefix_Bang` |
| `src/ahc-source_text.ads/.adb` | `Column_Of` counts code points |
| `src/ahc-sites.adb` | `Ghc_Column` reuses `Column_Of` |
| `src/ahc-syntax.ads/.adb`, `src/ahc-syntax-printer.adb` | `Bang_P` pattern node |
| `src/ahc-rename.adb` | `Bang_P`; top-level bang error; where-group scope (Phase B) |
| `src/ahc-fixity.adb`, `src/ahc-exhaustive.adb` | `Bang_P` |
| `src/ahc-desugar.adb` | `Seq_E`, `Force_All`; `Bang_P` matching; strict `let`/`where`/`do`/guard/comprehension bindings |
| `tests/src/test_lexer.adb`, `tests/src/test_source_text.adb` | unit tests |
| `tests/conformance/m150_{layout_close,unicode_idents,unicode_layout,bang_patterns,strict_bindings,where_shadows}.hs/.out` | oracled programs |
| `tests/golden/{parse_m150_bang,parse_m150_bang_expr,check_m150_toplevel_bang}.hs` | pinned AST and messages |
| `tests/corpus-types/bad_m150_{toplevel_bang,where_duplicate,args_duplicate}.hs` | negative differential cases |

None of these tasks touch `prelude/`, `lib/` or `runtime/`. The Core
goldens do not change: no builtin is added, and the desugarer mints
new nodes only for bangs, which no existing golden contains.

Helper used below: `scratchpad/one.sh conformance NAME` builds one
conformance program and diffs it with its golden (the M149 helper).

Line numbers are those of `23cdddf`. Earlier tasks shift later lines
in the same file (Task A3 deletes four lines near the top of
`ahc-lexer.adb`, Task A4 adds lines to `ahc-desugar.adb` after line
140), so locate each edit by the code quoted with it.

---

### Task A1: a closing token ends a case, `\cases`, `let` or `where` block (spec A2)

**Files:**
- Modify: `src/ahc-parser.adb:259-266` (add `At_Item_Closer` after
  `Op_Closes_Block`)
- Modify: `src/ahc-parser.adb:1646-1655` (do block),
  `:1696-1699` (`Parse_Cases_Block`), `:1778-1781`
  (`Parse_Alt_Block`), `:2628-2631` (`Parse_Decl_Block`)
- Create: `tests/conformance/m150_layout_close.hs`, `.out`

**Interfaces:**
- Produces: `function At_Item_Closer return Boolean` (parser-local).

- [ ] **Step 1: Failing test first.** Create
  `tests/conformance/m150_layout_close.hs`:

```haskell
{-# LANGUAGE LambdaCase #-}
-- M150: a token that cannot start an item closes an implicit layout
-- block (Report 10.3's parse-error(t)), in case, \cases, let and
-- where blocks as it already did in do blocks.

pairCase :: Int -> (Int, Int)
pairCase n = (case n of
  1 -> 1
  _ -> 2
  , 2)

parenCase :: Int -> Int
parenCase n = (case n of
  0 -> 10
  _ -> 20
  )

listCase :: Int -> [Int]
listCase n = [case n of
  0 -> 1
  _ -> 2
  ]

pick :: Int -> Int -> Int
pick = (\cases
  0 y -> y
  x _ -> x
  )

compLet :: [Int]
compLet = [ x + y | let x = 5
                        y = 6
                        , True ]

whereComma :: Int -> (Int, Int)
whereComma n = (case n of
  m -> j
    where
    j = m * 3
    , 1)

-- Already accepted before M150: `in` at the bindings' column.
letIn :: Int
letIn = let a = 1
            b = 2
            in a + b

main :: IO ()
main = do
  print (pairCase 1)
  print (parenCase 0, parenCase 5)
  print (listCase 3)
  print (pick 0 7, pick 3 7)
  print compLet
  print (whereComma 2)
  print letIn
```

  Oracle it from the repo root:
  `~/.ghcup/bin/runghc tests/conformance/m150_layout_close.hs > tests/conformance/m150_layout_close.out`.
  The `.out` must be exactly:

```
(1,2)
(10,20)
[2]
(7,3)
[11]
(6,1)
3
```

  Confirm it fails today: `scratchpad/one.sh conformance m150_layout_close`
  prints `BUILD-FAIL` with `10:3: error: expected a pattern (found ',')`.
  (Probed on v1.20: `pairCase`, `parenCase`, `listCase` fail in
  `Parse_Alt_Block`, `pick` in `Parse_Cases_Block`, `compLet` and
  `whereComma` in `Parse_Decl_Block`; `letIn` already works.)

- [ ] **Step 2: Implement.** In `src/ahc-parser.adb`, directly after
  `Op_Closes_Block` (line 266), add:

```ada
      --  Report 10.3's parse-error(t) at the start of an item of an
      --  implicit block: a token no statement, alternative or
      --  declaration can start with closes the block, and the
      --  enclosing construct continues - `(case n of` / alts / `, 2)`.
      --  One rule for do, case, \cases, let and where blocks (M150).
      function At_Item_Closer return Boolean
      is (Tok.Kind in Kw_Where | Kw_In | Kw_Then | Kw_Else | Kw_Of
            | Right_Paren | Right_Bracket | Comma
          or else Op_Closes_Block);
```

  In `Parse_Stmt_Block` replace lines 1650-1655

```ada
            if not Explicit
              and then (Tok.Kind in Kw_Where | Kw_In | Kw_Then
                          | Kw_Else | Right_Paren | Right_Bracket
                          | Comma
                        or else Op_Closes_Block)
              and then Try_Layout_Close
            then
```

  with

```ada
            if not Explicit and then At_Item_Closer and then Try_Layout_Close
            then
```

  (the do block gains `of`, as the spec lists). In
  `Parse_Cases_Block` (1696-1699) replace

```ada
            if not Explicit and then Op_Closes_Block and then Try_Layout_Close
            then
               exit;   --  the M148 operator rule, as in Parse_Alt_Block
```

  with

```ada
            if not Explicit and then At_Item_Closer and then Try_Layout_Close
            then
               exit;   --  parse-error(t), as in Parse_Alt_Block (M150)
```

  In `Parse_Alt_Block` (1778-1781) and `Parse_Decl_Block`
  (2628-2631) replace each

```ada
            if not Explicit and then Op_Closes_Block and then Try_Layout_Close
            then
               exit;   --  Tok is the V_Right_Brace (M148 operator rule)
```

  with

```ada
            if not Explicit and then At_Item_Closer and then Try_Layout_Close
            then
               exit;   --  Tok is the V_Right_Brace (parse-error(t), M150)
```

  After this, `grep -n "Op_Closes_Block" src/ahc-parser.adb` shows
  only its definition and its use inside `At_Item_Closer`.

- [ ] **Step 3: Verify.**
  - `alr exec -- gcc -c -gnatc -gnat2022 -gnatwa -Isrc src/ahc-parser.adb -o scratchpad/ck/ahc-parser.o`
    (no errors);
  - `alr build --validation`;
  - `scratchpad/one.sh conformance m150_layout_close` → `ok m150_layout_close`;
  - `./scripts/run_gate.sh golden conformance` → `GATE ok`;
  - `./scripts/run_differential.sh` → exit 0.

- [ ] **Step 4: Commit.**
  `fix(parser): a token that cannot start an alternative or declaration closes the layout block, as in a do block`

  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```

---

### Task A2: GHC 9.4.8's general categories as an Ada table (spec A3)

**Files:**
- Modify: `tests/gen_unicode.hs` (whole file; 90 lines today)
- Create: `src/ahc-unicode.ads` (generated, about 3,200 lines, 153
  distinct pages)
- Test: `tests/src/test_lexer.adb` (category spot checks)

**Interfaces:**
- Produces:

```ada
package AHC.Unicode with Pure is
   type General_Category is
     (Lu, Ll, Lt, Lm, Lo, Mn, Mc, Me, Nd, Nl, No,
      Pc, Pd, Ps, Pe, Pi, Pf, Po, Sm, Sc, Sk, So,
      Zs, Zl, Zp, Cc, Cf, Cs, Co, Cn);   --  GHC's constructor order
   subtype Code_Point is Natural range 0 .. 16#10FFFF#;
   function Category (C : Code_Point) return General_Category;
end AHC.Unicode;
```

- [ ] **Step 1: Extend the generator.** Edit `tests/gen_unicode.hs`.
  The C output must stay byte-identical.
  - Replace the header comment's lines 4-7 with:

```haskell
-- version). With the argument `ada` it emits src/ahc-unicode.ads
-- instead: GHC's generalCategory for the lexer's identifier and
-- operator classes (M150). Regenerate both when the oracle GHC
-- changes:
--
--   runghc tests/gen_unicode.hs > runtime/ahc_unicode.h
--   runghc tests/gen_unicode.hs ada > src/ahc-unicode.ads
```

  - After `import qualified Data.Map as Map` add
    `import System.Environment (getArgs)`.
  - Generalise `dedup` (lines 30-32) so both tables share it:

```haskell
-- (unique pages in first-seen order, per-page index)
dedup :: ([[Int]], [Int])
dedup = dedupPages pages

dedupPages :: [[Int]] -> ([[Int]], [Int])
dedupPages = go Map.empty [] []
  where
```

    (the `go` equations below it are unchanged).
  - Rename the current `main` to `mainC` and put a dispatcher in front:

```haskell
main :: IO ()
main = do
  args <- getArgs
  case args of
    ["ada"] -> mainAda
    _ -> mainC

mainC :: IO ()
mainC = do
  let (uniq, idx) = dedup
```

    (the rest of the old `main` body follows unchanged).
  - Append at the end of the file:

```haskell
-- generalCategory as GHC's constructor index (0 = UppercaseLetter ..
-- 29 = NotAssigned), one 256-entry page per 256 code points.
catPages :: [[Int]]
catPages = [ [ fromEnum (generalCategory (toEnum (pg * 256 + i)))
             | i <- [0 .. 255] ]
           | pg <- [0 .. 0x10FF] ]

chunks :: Int -> [a] -> [[a]]
chunks _ [] = []
chunks n xs = let (a, b) = splitAt n xs in a : chunks n b

-- Ada aggregate rows of 16 numbers, a comma after all but the last.
adaRows :: String -> [Int] -> [String]
adaRows ind xs =
  let rows = map (intercalate ", " . map show) (chunks 16 xs)
      n = length rows
  in zipWith (\i r -> ind ++ r ++ (if i == n then "" else ","))
             [1 :: Int ..] rows

mainAda :: IO ()
mainAda = do
  let (uniq, idx) = dedupPages catPages
      np = length uniq
  mapM_ putStrLn
    [ "--  Generated by tests/gen_unicode.hs from the oracle GHC's"
    , "--  Data.Char.generalCategory - DO NOT EDIT. Regenerate with:"
    , "--    runghc tests/gen_unicode.hs ada > src/ahc-unicode.ads"
    , "--  Two levels: Index maps a 256-point page to one of the"
    , "--  " ++ show np ++ " distinct Pages (M150)."
    , ""
    , "package AHC.Unicode with Pure is"
    , ""
    , "   --  GHC's GeneralCategory, in its constructor order."
    , "   type General_Category is"
    , "     (Lu, Ll, Lt, Lm, Lo, Mn, Mc, Me, Nd, Nl, No,"
    , "      Pc, Pd, Ps, Pe, Pi, Pf, Po, Sm, Sc, Sk, So,"
    , "      Zs, Zl, Zp, Cc, Cf, Cs, Co, Cn);"
    , ""
    , "   subtype Code_Point is Natural range 0 .. 16#10FFFF#;"
    , ""
    , "   function Category (C : Code_Point) return General_Category;"
    , ""
    , "private"
    , ""
    , "   type Cat_Code is range 0 .. 29;"
    , "   type Page_Id is range 0 .. " ++ show (np - 1) ++ ";"
    , "   type Page is array (0 .. 255) of Cat_Code;"
    , ""
    , "   Pages : constant array (Page_Id) of Page :="
    , "     [" ]
  mapM_ (\(i, p) -> do
           putStrLn ("      --  page " ++ show i)
           putStrLn "      ["
           mapM_ putStrLn (adaRows "       " p)
           putStrLn ("      ]" ++ (if i == np - 1 then "" else ",")))
        (zip [0 :: Int ..] uniq)
  mapM_ putStrLn
    [ "     ];"
    , ""
    , "   Index : constant array (0 .. 16#10FF#) of Page_Id :="
    , "     [" ]
  mapM_ putStrLn (adaRows "      " idx)
  mapM_ putStrLn
    [ "     ];"
    , ""
    , "   function Category (C : Code_Point) return General_Category"
    , "   is (General_Category'Val (Pages (Index (C / 256)) (C mod 256)));"
    , ""
    , "end AHC.Unicode;" ]
```

- [ ] **Step 2: Generate.** From the repo root:
  - `~/.ghcup/bin/runghc tests/gen_unicode.hs > runtime/ahc_unicode.h && git diff --exit-code runtime/ahc_unicode.h`
    → exit 0 (the C table is unchanged; `runtime/` is a gate input,
    so no suite may be running);
  - `~/.ghcup/bin/runghc tests/gen_unicode.hs ada > src/ahc-unicode.ads`;
  - `grep -n "Page_Id is" src/ahc-unicode.ads` → `type Page_Id is range 0 .. 152;`;
  - `alr exec -- gcc -c -gnatc -gnat2022 -gnatwa -Isrc src/ahc-unicode.ads -o scratchpad/ck/ahc-unicode.o`
    → no output.

- [ ] **Step 3: Regression test.** In `tests/src/test_lexer.adb` add
  `with AHC.Unicode;` to the context clause, change `procedure Run is`
  to declare `use type AHC.Unicode.General_Category;`, and right after
  `Start_Suite ("Lexer");` add:

```ada
      --  GHC 9.4.8's generalCategory (M150), spot checks.
      Check (AHC.Unicode.Category (16#61#) = AHC.Unicode.Ll, "a is Ll");
      Check (AHC.Unicode.Category (16#394#) = AHC.Unicode.Lu, "Delta is Lu");
      Check (AHC.Unicode.Category (16#1C5#) = AHC.Unicode.Lt, "Dz is Lt");
      Check (AHC.Unicode.Category (16#6570#) = AHC.Unicode.Lo,
             "CJK ideograph is Lo");
      Check (AHC.Unicode.Category (16#2B0#) = AHC.Unicode.Lm,
             "modifier h is Lm");
      Check (AHC.Unicode.Category (16#303#) = AHC.Unicode.Mn,
             "combining tilde is Mn");
      Check (AHC.Unicode.Category (16#2218#) = AHC.Unicode.Sm,
             "ring operator is Sm");
      Check (AHC.Unicode.Category (16#B7#) = AHC.Unicode.Po,
             "middle dot is Po");
      Check (AHC.Unicode.Category (16#27E8#) = AHC.Unicode.Ps,
             "angle bracket is Ps");
      Check (AHC.Unicode.Category (16#D800#) = AHC.Unicode.Cs,
             "surrogate is Cs");
      Check (AHC.Unicode.Category (16#10FFFF#) = AHC.Unicode.Cn,
             "last code point is Cn");
```

- [ ] **Step 4: Verify.** `alr build --validation`, then
  `cd tests && alr build --validation && ./bin/ahc_tests` →
  `passed: 370, failed: 0`.
- [ ] **Step 5: Commit.**
  `feat(unicode): gen_unicode also emits ghc 9.4.8's general categories as an ada table`

  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```

---

### Task A3: Unicode identifiers and operators; columns count code points (spec A3)

**Files:**
- Modify: `src/ahc-lexer.adb`: context clause (line 1);
  `Is_Ident_Char` (25-27, deleted); `Position_Of` (139-154);
  new block before the "Comments and whitespace" banner (198-200);
  `At_Line_Comment` (204-211); `Munch_Ident`/`Munch_Symbols`
  (258-276); `Scan_Large_Ident` chain tests (330, 337, 353); the
  `Scan` dispatch (834-836)
- Modify: `src/ahc-source_text.ads:6-7`, `src/ahc-source_text.adb:101-114`
- Modify: `src/ahc-sites.adb:19-40` (`Ghc_Column`)
- Create: `tests/conformance/m150_unicode_idents.hs`, `m150_unicode_layout.hs` (+ `.out`)
- Test: `tests/src/test_lexer.adb`, `tests/src/test_source_text.adb`

**Interfaces:**
- Consumes: `AHC.Unicode.Category` (Task A2).
- Produces (lexer-local, inside `Scan`, used by Task A4):
  `procedure Decode_At (I : Positive; Code : out Natural; Width : out Natural)`,
  `type Char_Class is (Small, Large, Digit, Modifier, Mark, Symbol, Other)`,
  `function Class_At (I : Positive) return Char_Class`,
  `function Width_At (I : Positive) return Positive`,
  `function Alnum_At (I : Positive) return Boolean`,
  `function Prev_Start (I : Positive) return Positive`.
- Produces: `Source_Text.Column_Of` counts code points.

**Character classes.** GHC 9.4.8's lexer (`Lexer.x`, `adj_c`) is the
oracle, and it is narrower than the spec's "S* and P*": `Ps`, `Pe`,
`Pi`, `Pf` are "other graphic", allowed only in literals and comments
(`a ⟨ b` is a lexical error in GHC), and `Lm`/`Mn` continue a name
but cannot start one (`ʰ = 3` is a lexical error, `aʰ = 3` is fine).
The table:

| Class | Categories (non-ASCII) | ASCII |
|---|---|---|
| Small (varid start) | Ll, Lo | `a`-`z`, `_` |
| Large (conid start) | Lu, Lt | `A`-`Z` |
| Digit (continue only) | Nd, Nl, No | `0`-`9` |
| Modifier (continue only) | Lm | - |
| Mark (continue only) | Mn | `'` |
| Symbol | Pc, Pd, Po, Sm, Sc, Sk, So | `Is_Symbol_Char` |
| Other | everything else, malformed UTF-8 | everything else |

- [ ] **Step 1: Failing tests first.** Create
  `tests/conformance/m150_unicode_idents.hs`:

```haskell
-- M150: Unicode identifiers and operators (Haskell 2010 Report 2.2,
-- 2.4), with GHC's character classes.
module Main where

-- Spanish, Greek, Cyrillic, CJK variables; a Greek constructor.
data Forma = Círculo Double | Δ Double Double
  deriving Show

área :: Forma -> Double
área (Círculo r) = 3 * r * r
área (Δ b h) = b * h / 2

λx :: Int -> Int
λx n = n * 2

привет :: String
привет = "мир"

数 :: Int
数 = 42

-- Letters may continue with marks, modifier letters and primes.
año' :: Int
año' = 2026

x̃, aʰ :: Int
x̃ = 7
aʰ = 8

-- Unicode operators: math symbols and other punctuation.
infixr 9 ∘
(∘) :: (b -> c) -> (a -> b) -> a -> c
f ∘ g = \x -> f (g x)

(⊕) :: Int -> Int -> Int
a ⊕ b = a * 10 + b

(·) :: Int -> Int -> Int
a · b = a * b

data Par = Int :⊗ Int deriving Show

main :: IO ()
main = do
  let ñ = 1 :: Int
      café = ñ + 1
  print (ñ, café)
  print (área (Círculo 1), área (Δ 4 3))
  print (Δ 1 2)
  print (λx 21, привет, 数, año')
  print ((λx ∘ λx) 3, 1 ⊕ 2, 3 :⊗ 4, 6 · 7, x̃ + aʰ)
  print [ x | x <- [ñ .. café] ]
```

  Its oracled `.out`:

```
(1,2)
(3.0,6.0)
Δ 1.0 2.0
(42,"\1084\1080\1088",42,2026)
(12,12,3 :⊗ 4,42,15)
[1,2]
```

  Create `tests/conformance/m150_unicode_layout.hs`. Every block below
  opens after a multi-byte identifier on its line, so a byte-counting
  `Column_Of` misplaces the block's column and the next line closes it:

```haskell
-- M150: layout columns count code points, not bytes, so blocks that
-- open after a multi-byte identifier on the same line align as in GHC.

café :: Int
café = let α = 1
           β = 2
       in α + β

größe :: Int -> Int
größe n = case n of 0 -> 10
                    _ -> 20

über :: IO ()
über = do putStrLn "ü1"
          putStrLn "ü2"

данные :: [Int]
данные = [ x | x <- [1 .. 3] ] where ä = 0
                                     ö = ä

main :: IO ()
main = do
  print café
  print (größe 0, größe 1)
  über
  print данные
```

  Its oracled `.out`:

```
3
(10,20)
ü1
ü2
[1,2,3]
```

  Oracle both from the repo root
  (`~/.ghcup/bin/runghc tests/conformance/X.hs > tests/conformance/X.out`)
  and confirm both are `BUILD-FAIL` today (`invalid character`).

- [ ] **Step 2: Columns count code points.** In
  `src/ahc-source_text.ads` replace lines 6-7 with:

```ada
--  Columns follow Report 10.3: the first column is 1 and tab stops are
--  8 characters apart. A column counts characters - code points of
--  the UTF-8 text, as GHC's columns do - not bytes (M150).
```

  In `src/ahc-source_text.adb`, `Column_Of`'s loop (106-112) becomes:

```ada
      for I in S.Line_Start (S.Line_Of (O)) .. O - 1 loop
         if S.Char_At (I) = ASCII.HT then
            Col := Col + (Tab_Stop - (Col - 1) mod Tab_Stop);
         elsif Character'Pos (S.Char_At (I)) in 16#80# .. 16#BF# then
            null;   --  a UTF-8 continuation byte: the same character
         else
            Col := Col + 1;
         end if;
      end loop;
```

  `src/ahc-sites.adb` `Ghc_Column` (19-40) counted code points on its
  own since M149; make it the same function (its tab rule
  `((Col - 1) / 8 + 1) * 8 + 1` equals `Column_Of`'s):

```ada
   function Ghc_Column
     (Src : Source_Text.Source; O : Source_Text.Byte_Offset) return Positive
   is
   begin
      --  Source_Text counts code points and tab stops, as GHC does
      --  (M150).
      return Positive (Src.Column_Of (O));
   end Ghc_Column;
```

  In `src/ahc-lexer.adb` `Position_Of`, line 152 becomes:

```ada
            --  One past the last character; a trailing continuation
            --  byte is already past it (columns count code points).
            Column := Text.Column_Of (Source_Text.Byte_Offset (Len))
              + (if Character'Pos (At_Offset (Len)) in 16#80# .. 16#BF#
                 then 0 else 1);
```

- [ ] **Step 3: The lexer's character classes.** In
  `src/ahc-lexer.adb`:
  - add `with AHC.Unicode;` after `with Ada.Strings.Unbounded;`;
  - delete `Is_Ident_Char` (lines 25-27; `Munch_Ident` was its only
    user and now classifies through `Class_At`);
  - insert before the `--  Comments and whitespace` banner (line 198):

```ada
      ------------------------------------------------------------------
      --  Characters beyond ASCII (Report 2.2, M150)
      ------------------------------------------------------------------

      --  The code point whose UTF-8 sequence starts at byte I and the
      --  sequence's length in bytes; Width = 0 when the bytes there
      --  are not one well-formed sequence.
      procedure Decode_At
        (I : Positive; Code : out Natural; Width : out Natural)
      is
         Lead : constant Natural :=
           (if I <= Len then Character'Pos (At_Offset (I)) else 0);
         Need : Natural;
      begin
         Code := 0;
         Width := 0;
         if I > Len then
            return;
         elsif Lead < 16#80# then
            Code := Lead;
            Width := 1;
            return;
         elsif Lead in 16#C2# .. 16#DF# then
            Need := 1;
            Code := Lead mod 32;
         elsif Lead in 16#E0# .. 16#EF# then
            Need := 2;
            Code := Lead mod 16;
         elsif Lead in 16#F0# .. 16#F4# then
            Need := 3;
            Code := Lead mod 8;
         else
            return;
         end if;
         for K in 1 .. Need loop
            if I + K > Len
              or else Character'Pos (At_Offset (I + K))
                        not in 16#80# .. 16#BF#
            then
               Code := 0;
               return;
            end if;
            Code := Code * 64 + Character'Pos (At_Offset (I + K)) mod 64;
         end loop;
         if Code > 16#10FFFF#
           or else Code in 16#D800# .. 16#DFFF#
           or else (Need = 2 and then Code < 16#800#)
           or else (Need = 3 and then Code < 16#1_0000#)
         then
            Code := 0;
            return;
         end if;
         Width := Need + 1;
      end Decode_At;

      --  GHC's lexical class of a character (Lexer.x's adj_c, over
      --  GHC 9.4.8's generalCategory): Small and Large start a varid
      --  and a conid; Digit, Modifier and Mark only continue one;
      --  Symbol is an operator character; Other is everything else,
      --  including Ps/Pe/Pi/Pf, whitespace and malformed UTF-8.
      type Char_Class is
        (Small, Large, Digit, Modifier, Mark, Symbol, Other);

      subtype Ident_Class is Char_Class range Small .. Mark;

      function Class_At (I : Positive) return Char_Class is
         C : constant Character := At_Offset (I);
      begin
         if Character'Pos (C) < 16#80# then
            return (if Is_Small (C) then Small
                    elsif Is_Large (C) then Large
                    elsif Is_Digit (C) then Digit
                    elsif C = ''' then Mark
                    elsif Is_Symbol_Char (C) then Symbol
                    else Other);
         end if;
         declare
            Code  : Natural;
            Width : Natural;
         begin
            Decode_At (I, Code, Width);
            if Width = 0 then
               return Other;
            end if;
            case Unicode.Category (Code) is
               when Unicode.Ll | Unicode.Lo => return Small;
               when Unicode.Lu | Unicode.Lt => return Large;
               when Unicode.Nd | Unicode.Nl | Unicode.No => return Digit;
               when Unicode.Lm => return Modifier;
               when Unicode.Mn => return Mark;
               when Unicode.Pc | Unicode.Pd | Unicode.Po | Unicode.Sm
                  | Unicode.Sc | Unicode.Sk | Unicode.So => return Symbol;
               when others => return Other;
            end case;
         end;
      end Class_At;

      --  Bytes in the character at I: its UTF-8 length, 1 for ASCII
      --  and for a malformed byte.
      function Width_At (I : Positive) return Positive is
         Code  : Natural;
         Width : Natural;
      begin
         Decode_At (I, Code, Width);
         return Positive'Max (Width, 1);
      end Width_At;

      --  Data.Char.isAlphaNum of the character at I: a letter (L*) or
      --  a number (N*).
      function Alnum_At (I : Positive) return Boolean
      is (Class_At (I) in Small | Large | Digit | Modifier);

      --  The first byte of the character that ends just before I.
      function Prev_Start (I : Positive) return Positive
        with Pre => I > 1
      is
         J : Positive := I - 1;
      begin
         while J > 1
           and then Character'Pos (At_Offset (J)) in 16#80# .. 16#BF#
         loop
            J := J - 1;
         end loop;
         return J;
      end Prev_Start;
```

    (`Alnum_At` and `Prev_Start` are first used in Task A4; until
    then `-gnatwa` reports them unreferenced, which is a warning.)
  - `At_Line_Comment` (line 210): a run of dashes followed by a
    Unicode symbol is an operator too:

```ada
         return Ahead >= 2
           and then not (Pos + Ahead <= Len
                         and then Class_At (Pos + Ahead) = Symbol);
```

  - `Munch_Ident` and `Munch_Symbols` (258-276) become:

```ada
      function Munch_Ident return Positive is
         Start : constant Positive := Pos;
      begin
         while Pos <= Len and then Class_At (Pos) in Ident_Class loop
            Pos := Pos + Width_At (Pos);
         end loop;
         return Start;
      end Munch_Ident;

      function Munch_Symbols return Positive is
         Start : constant Positive := Pos;
      begin
         while Pos <= Len and then Class_At (Pos) = Symbol loop
            Pos := Pos + Width_At (Pos);
         end loop;
         return Start;
      end Munch_Symbols;
```

  - In `Scan_Large_Ident`'s qualified-name loop: line 330
    `Is_Large (Peek)` → `Class_At (Pos) = Large`; line 337
    `Is_Small (Peek)` → `Class_At (Pos) = Small`; line 353
    `Is_Symbol_Char (Peek)` → `Class_At (Pos) = Symbol` (so
    `Círculo.área` is one qvarid).
  - In `Scan`'s dispatch, between `elsif Is_Symbol_Char (C) then
    Scan_Operator;` (834-835) and the final `else`, add:

```ada
            elsif Character'Pos (C) >= 16#80# then
               --  Unicode letters and symbols (Report 2.2, M150).
               case Class_At (Pos) is
                  when Small => Scan_Small_Ident;
                  when Large => Scan_Large_Ident;
                  when Symbol => Scan_Operator;
                  when others =>
                     declare
                        Start : constant Positive := Pos;
                     begin
                        Pos := Pos + Width_At (Pos);
                        Error (Diagnostics.Lex_Invalid_Character, Start,
                               "invalid character '" & Slice (Start, Pos)
                               & "'");
                        Emit_Plain (Error_Token, Start);
                     end;
               end case;
```

    (the whole UTF-8 sequence goes into the message, never half of
    one).

- [ ] **Step 4: Unit tests.** In `tests/src/test_lexer.adb` add
  `with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;` and, before
  `procedure Run`, the helper (under `-gnatW8` a `String` literal
  holds Latin-1, not UTF-8):

```ada
   --  UTF-8 bytes of S (a String literal holds Latin-1 under -gnatW8).
   function U8 (S : Wide_Wide_String) return String
   is (Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Encode (S));
```

  and after the category checks of Task A2:

```ada
      --  Unicode identifiers and operators (Report 2.2, 2.4; M150)
      Check_Equal (Lex (U8 ("ñ café λx 数")),
                   U8 ("varid ""ñ""|varid ""café""|varid ""λx""|varid ""数"""),
                   "Unicode varids (Ll and Lo start one)");
      Check_Equal (Lex (U8 ("Δ Círculo.área")),
                   U8 ("conid ""Δ""|qvarid ""Círculo.área"""),
                   "Unicode conid and qualified varid");
      Check_Equal (Lex (U8 ("x̃ aʰ año'")),
                   U8 ("varid ""x̃""|varid ""aʰ""|varid ""año'"""),
                   "marks, modifier letters and primes continue a name");
      Check_Equal (Lex (U8 ("f ∘ g · h :⊗ k → m")),
                   U8 ("varid ""f""|varsym ""∘""|varid ""g""|varsym ""·"""
                       & "|varid ""h""|consym "":⊗""|varid ""k"""
                       & "|varsym ""→""|varid ""m"""),
                   "Unicode operators (Sm, Po; no UnicodeSyntax)");
      Check_Equal (Lex (U8 ("ʰ")), "<error>!errors: 1",
                   "a modifier letter cannot start a name");
      Check_Equal (Lex (U8 ("a ⟨ b")),
                   "varid ""a""|<error>|varid ""b""!errors: 1",
                   "open punctuation is not an operator character (GHC)");
```

  In `tests/src/test_source_text.adb` add
  `with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;` and, before the
  empty-source block:

```ada
      --  Columns count code points (M150): 2- and 3-byte characters
      --  are one column each.
      declare
         S : constant Source :=
           Load_String
             ("t.hs",
              Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Encode ("año x"));
      begin
         Check_Equal (Integer (S.Column_Of (6)), 5,
                      "a two-byte letter is one column");
      end;

      declare
         S : constant Source :=
           Load_String
             ("t.hs",
              Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Encode ("λ→x"));
      begin
         Check_Equal (Integer (S.Column_Of (6)), 3,
                      "two- and three-byte characters are one column each");
      end;
```

- [ ] **Step 5: Verify.**
  - semantic checks: `alr exec -- gcc -c -gnatc -gnat2022 -gnatwa -Isrc src/X.adb -o scratchpad/ck/X.o`
    for `ahc-lexer`, `ahc-source_text`, `ahc-sites`;
  - `alr build --validation`; `cd tests && alr build --validation && ./bin/ahc_tests`
    → `passed: 378, failed: 0`;
  - `scratchpad/one.sh conformance m150_unicode_idents` and
    `... m150_unicode_layout` → `ok`;
  - `./scripts/run_gate.sh` → `GATE ok` (exec goldens with M149 site
    columns are unchanged: they were already code-point columns).
- [ ] **Step 6: Commit.**
  `feat(lexer): identifiers and operators may be unicode, classified by ghc's own general categories, and columns count code points`

  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```

---

### Task A4: bang patterns in every apat position (spec A1)

**Files:**
- Modify: `src/ahc-tokens.ads:41-47`, `src/ahc-tokens.adb:96`
- Modify: `src/ahc-lexer.adb` `Scan_Operator` (403-418)
- Modify: `src/ahc-syntax.ads:196-201, 226-227`, `src/ahc-syntax.adb:136-137`,
  `src/ahc-syntax-printer.adb:249`
- Modify: `src/ahc-parser.adb` `Is_Bang` (234-236), `Can_Start_APat`
  (608-611), `Parse_APat_Inner`'s `Tilde` arm (734-738),
  `Can_Start_AExp` (867-870), `Parse_AExp`'s `others` (986-987),
  `Parse_Binding`'s lookahead (2357-2367)
- Modify: `src/ahc-rename.adb:1134-1135`, `src/ahc-fixity.adb:342-343`,
  `src/ahc-exhaustive.adb:102-103`
- Modify: `src/ahc-desugar.adb`: after `Global` (138-140);
  `Pat_TyCon` (668-669); `Add_Handled` (704-706); `Unfailable`
  (1055-1056); `Bound_Vars` (1126-1127); `Match_One` (1354-1355)
- Create: `tests/conformance/m150_bang_patterns.hs` (+ `.out`),
  `tests/golden/parse_m150_bang.hs`, `tests/golden/parse_m150_bang_expr.hs`
- Test: `tests/src/test_lexer.adb`

**Interfaces:**
- Consumes: `Prev_Start`, `Alnum_At`, `Peek`, `Pos`, `Len` in the
  lexer (Task A3).
- Produces: `Tokens.Prefix_Bang` (a `Token_Kind`, `Image` = `"!"`);
  `Syntax.Bang_P` with field `Bang_Pat : Real_Pat_Id`; in
  `AHC.Desugar`'s body
  `function Seq_E (A, B : Core.Real_Expr_Id; Span : Diagnostics.Source_Span) return Core.Real_Expr_Id`
  and
  `function Force_All (Forces : Core.Var_Id_Vectors.Vector; Body_E : Core.Real_Expr_Id; Span : Diagnostics.Source_Span) return Core.Real_Expr_Id`
  (Task A5 uses both).

**The lexical rule** (GHC 9, proposal 229, as GHC 9.4.8's
`Lexer.x` implements it): an operator that is exactly `!` is a bang
when it is *not preceded by a closing token* and *is followed by an
opening token*. A closing token's last character is `)`, `]`, `"`,
`'`, `_`, a letter or number, or a `}` that is not the end of a `-}`
comment. An opening token's first character is `(`, `[`, `"`, `'`,
`_`, a letter or number, or a `{` that does not start a `{-` comment.
So `f !x`, `(!a, b)`, `[!x]`, `T !Int` and `!x` at the start of a
line are bangs; `a ! b`, `a!b`, `a! b`, `(!)`, `(! 0)` and `xs !! 0`
are operators. A bang in an expression is GHC's error
"Bang pattern in expression context".

- [ ] **Step 1: Failing test first.** Create
  `tests/conformance/m150_bang_patterns.hs`:

```haskell
{-# LANGUAGE LambdaCase #-}
-- M150: bang patterns in every pattern position, and `!` still an
-- operator when it is not a prefix occurrence (GHC 9's rule).
import Control.Exception

-- Does evaluating v to WHNF raise? Prints "forced" or the value.
probe :: Show a => String -> a -> IO ()
probe name v = do
  r <- try (evaluate v)
  putStrLn (name ++ ": " ++ case r of
    Left e -> const "forced" (e :: ErrorCall)
    Right x -> show x)

sumTo :: Int -> Int -> Int
sumTo !acc 0 = acc
sumTo !acc n = sumTo (acc + n) (n - 1)

constOne :: Int -> Int
constOne !_ = 1

lazyOne :: Int -> Int
lazyOne _ = 1

firstOf :: (Int, Int) -> Int
firstOf (!a, _) = 7

justBang :: Maybe Int -> Int
justBang (Just !x) = 2
justBang Nothing = 0

underLazy :: Int -> Int
underLazy ~(!x) = 3

guarded :: Int -> String
guarded !n
  | n > 0 = "positive"
  | otherwise = "not positive"

-- `!` as an operator: loose infix defines it, tight infix uses it.
infixl 9 !
(!) :: [a] -> Int -> a
xs ! i = xs !! i

-- A bang under a newtype constructor forces the wrapped value.
newtype Box = Box Int
boxed :: Box -> Int
boxed (Box !_) = 8

main :: IO ()
main = do
  print (sumTo 0 100)
  probe "equation !_" (constOne undefined)
  probe "equation _" (lazyOne undefined)
  probe "tuple (!a, _)" (firstOf (undefined, 2))
  probe "Just !x" (justBang (Just undefined))
  probe "~(!x)" (underLazy undefined)
  probe "lambda" ((\ !x -> 4 :: Int) undefined)
  probe "lambda lazy" ((\x -> 4 :: Int) undefined)
  probe "case !_" (case (undefined :: Int) of !_ -> 5 :: Int)
  probe "case _" (case (undefined :: Int) of _ -> 5 :: Int)
  probe "\\case" ((\case !_ -> 6 :: Int) (undefined :: Int))
  probe "newtype Box !_" (boxed (Box undefined))
  putStrLn (guarded 3)
  print ([10, 20, 30] ! 1, [10, 20, 30]!2, map (! 0) [[1], [2 :: Int]])
  print ((!) "abc" 0)
```

  Its oracled `.out`:

```
5050
equation !_: forced
equation _: 1
tuple (!a, _): forced
Just !x: forced
~(!x): 3
lambda: forced
lambda lazy: 4
case !_: forced
case _: 5
\case: forced
newtype Box !_: forced
positive
(20,30,[1,2])
'a'
```

  Today it is `BUILD-FAIL` (`expected '='` at `sumTo !acc`). With
  every `!` pattern deleted, the same program builds on v1.20 and
  prints the lazy answers, so the harness itself is sound.

- [ ] **Step 2: The token.** In `src/ahc-tokens.ads` the enumeration's
  tail (line 47) becomes:

```ada
      Kw_Cases,

      --  A prefix occurrence of `!` (GHC 9's rule, M150): not preceded
      --  by a closing token, followed by an opening one - `f !x`,
      --  `(!a, b)`, `T !Int`. A bang pattern or a strictness flag;
      --  any other `!` is the operator (varsym).
      Prefix_Bang);
```

  In `src/ahc-tokens.adb` `Image`, after the `Kw_Cases` arm (96):

```ada
         when Prefix_Bang   => return "!";
```

- [ ] **Step 3: The lexer rule.** In `src/ahc-lexer.adb`, replace the
  head of `Scan_Operator` (403-409) so it reads:

```ada
      --  GHC 9's prefix occurrence of an operator (proposal 229): not
      --  preceded by a closing token, and followed by an opening one.
      --  Start is the operator's first byte; Pos is one past its end.
      function Is_Prefix_Occurrence (Start : Positive) return Boolean is
         Closing_Before : Boolean := False;
         Opening_After  : Boolean := False;
      begin
         if Start > 1 then
            declare
               P : constant Positive := Prev_Start (Start);
               C : constant Character := At_Offset (P);
            begin
               Closing_Before :=
                 (case C is
                    when ')' | ']' | '"' | ''' | '_' => True,
                    when '}' => not (P > 1 and then At_Offset (P - 1) = '-'),
                    when others => Alnum_At (P));
            end;
         end if;
         if Pos <= Len then
            Opening_After :=
              (case Peek is
                 when '(' | '[' | '"' | ''' | '_' => True,
                 when '{' => Peek (1) /= '-',
                 when others => Alnum_At (Pos));
         end if;
         return not Closing_Before and then Opening_After;
      end Is_Prefix_Occurrence;

      procedure Scan_Operator is
         Start : constant Positive := Munch_Symbols;
         Sym   : constant String := Slice (Start, Pos);
         Kind  : constant Token_Kind := Symbol_Kind (Sym);
      begin
         if Sym = "!" and then Is_Prefix_Occurrence (Start) then
            Emit_Plain (Prefix_Bang, Start);   --  a bang (M150)
         elsif Kind = Varsym then
```

  (the remaining `Varsym`/`Consym`/`else` arms are unchanged).

- [ ] **Step 4: The node.** `src/ahc-syntax.ads` line 201 becomes
  `As_P, Lazy_P, Bang_P, Rec_P, Sig_P);` and after the `Lazy_P`
  variant (226-227):

```ada
         when Bang_P =>
            --  `!p` (M150): force the value, then match p.
            Bang_Pat : Real_Pat_Id;
```

  `src/ahc-syntax.adb` `Well_Formed`, after the `Lazy_P` arm (137):

```ada
         when Bang_P =>
            return Ok (A, N.Bang_Pat);
```

  `src/ahc-syntax-printer.adb`, after line 249:

```ada
            when Bang_P => return "(pbang " & Pat_S (N.Bang_Pat) & ")";
```

- [ ] **Step 5: The parser.** In `src/ahc-parser.adb`:
  - `Is_Bang` (234-236): a strictness flag is either spelling:

```ada
      --  A strictness flag on a constructor field: the prefix `!` of
      --  `T !Int`, or a loose `T ! Int` (accepted as before M150).
      function Is_Bang return Boolean
      is (Tok.Kind = Prefix_Bang
          or else (Tok.Kind = Varsym and then Tok.Qualifier = Names.No_Name
                   and then Tok.Name = Bang_Name));
```

  - `Can_Start_APat` (608-611): add `| Prefix_Bang` after `Tilde`.
  - `Parse_APat_Inner`, after the `Tilde` arm (738):

```ada
            when Prefix_Bang =>
               --  BangPatterns (M150; GHC2021): `!apat`.
               Advance;
               return Arena.Add
                 (Pat_Node'(Kind => Bang_P, Span => Span,
                            Bang_Pat => Parse_APat));
```

  - `Can_Start_AExp` (867-870): add `| Prefix_Bang` after
    `Left_Bracket`, with the comment
    `--  Prefix_Bang starts no expression; it is listed so that`
    `--  Parse_AExp reports it as GHC does (M150).`
  - `Parse_AExp`, before `when others => Fail ("expected an expression");` (986):

```ada
            when Prefix_Bang =>
               Fail ("bang pattern in expression context (did you mean"
                     & " to add a space after the '!'?)");
```

  - `Parse_Binding`'s prefix-equation lookahead (2357-2367): add
    `| Prefix_Bang` to the first list (after `Tilde`) and to the
    second list (before `Equals`), so `sumTo !acc 0 = acc` and
    `(op) !x y = ...` are equations, not pattern bindings.

- [ ] **Step 6: Rename, fixity, exhaustiveness.**
  `src/ahc-rename.adb` `Rename_Pat`, after the `Lazy_P` arm (1135):

```ada
            when Bang_P =>
               Rename_Pat (N.Bang_Pat, Global_Binders);
```

  `src/ahc-fixity.adb` `Resolve_Pat`, after line 343:

```ada
            when Bang_P =>
               Resolve_Pat (N.Bang_Pat);
```

  `src/ahc-exhaustive.adb` `Norm`, after line 103:

```ada
            when Bang_P =>
               return Norm (Syntax.Pat_Id (N.Bang_Pat));   --  transparent
```

- [ ] **Step 7: Desugar.** In `src/ahc-desugar.adb`:
  - after `Global` (line 140), the two helpers (Task A5 uses
    `Force_All`):

```ada
      --  `seq A B`, the builtin found by name as EmptyCase finds it
      --  (M150: bang patterns and strict bindings).
      function Seq_E
        (A, B : Core.Real_Expr_Id; Span : Diagnostics.Source_Span)
         return Core.Real_Expr_Id
      is
         Seq_C : constant Builtins.Var_Maps.Cursor :=
           Env.Values.Find (Table.Intern ("seq"));
      begin
         return App2
           (Global (Core.Var_Id (Builtins.Var_Maps.Element (Seq_C)), Span),
            A, B, Span);
      end Seq_E;

      --  Body_E under `seq f` for each strict binding F of a group,
      --  first binding outermost (M150): `let !x = e in b` forces x
      --  before b.
      function Force_All
        (Forces : Core.Var_Id_Vectors.Vector;
         Body_E : Core.Real_Expr_Id;
         Span   : Diagnostics.Source_Span) return Core.Real_Expr_Id
      is
         Result : Core.Real_Expr_Id := Body_E;
      begin
         for I in reverse 1 .. Forces.Last_Index loop
            declare
               F_Ref : constant Core.Real_Expr_Id :=
                 VarE (Core.Real_Var_Id (Forces.Element (I)), Span);
            begin
               Result := Seq_E (F_Ref, Result, Span);
            end;
         end loop;
         return Result;
      end Force_All;
```

    (`Forces.Element (I)`, not `Forces (I)`: the indexing form is
    ambiguous inside a conversion.)
  - `Pat_TyCon`, after line 669:

```ada
            when Bang_P =>
               return Pat_TyCon (N.Bang_Pat);
```

  - `Add_Handled`, the `elsif N.Kind = As_P` chain (704-706) gains:

```ada
         elsif N.Kind = Bang_P then
            Add_Handled (N.Bang_Pat, Into);
```

  - `Unfailable`, after the `Sig_P` arm (1056):

```ada
            when Bang_P =>
               --  A bang can diverge but never fails to match.
               return Unfailable (Pat_Id (N.Bang_Pat));
```

  - `Bound_Vars`, after line 1127:

```ada
            when Bang_P =>
               Bound_Vars (N.Bang_Pat, Into);
```

  - `Match_One`, after the `Lazy_P` arm (1355):

```ada
            when Bang_P =>
               --  `!p` (M150): force the scrutinee, then match p.
               declare
                  S_Ref : constant Core.Real_Expr_Id := VarE (Scrut, Span);
                  Rest  : constant Core.Real_Expr_Id :=
                    Match_One (Scrut, N.Bang_Pat, Inner, Fail);
               begin
                  return Seq_E (S_Ref, Rest, Span);
               end;
```

    The two node-minting calls are hoisted into constants (the
    actual-evaluation-order rule). Equations, lambdas, `case`,
    `\case`, `\cases`, constructor fields (`Con_Match` sends a
    non-variable sub-pattern through `Match_Seq`), newtype fields
    (`Newtype_Field_Match`) and `do`/comprehension binds all reach
    this arm through `Match_One`; nothing else needs a change.

- [ ] **Step 8: Lexer unit tests.** In `tests/src/test_lexer.adb`,
  after the Unicode checks of Task A3:

```ada
      --  Bang patterns: GHC 9's prefix-occurrence rule (M150)
      Check_Equal (Lex ("f !x = x"),
                   "varid ""f""|!|varid ""x""|=|varid ""x""",
                   "prefix ! is a bang");
      Check_Equal (Lex ("a ! b"), "varid ""a""|varsym ""!""|varid ""b""",
                   "loose infix ! is the operator");
      Check_Equal (Lex ("a!b"), "varid ""a""|varsym ""!""|varid ""b""",
                   "tight infix ! is the operator");
      Check_Equal (Lex ("a! b"), "varid ""a""|varsym ""!""|varid ""b""",
                   "suffix ! is the operator");
      Check_Equal (Lex ("(!)"), "(|varsym ""!""|)",
                   "! before a closing bracket is the operator");
      Check_Equal (Lex ("(!x,!_)"), "(|!|varid ""x""|,|!|_|)",
                   "! after an opening bracket or a comma is a bang");
      Check_Equal (Lex ("!(a)"), "!|(|varid ""a""|)",
                   "! at the start of input is a bang");
      Check_Equal (Lex ("T !Int"), "conid ""T""|!|conid ""Int""",
                   "a strictness flag is a bang");
      Check_Equal (Lex ("f {- c -}!x"), "varid ""f""|!|varid ""x""",
                   "a block comment's -} is not a closing token");
      Check_Equal (Lex ("x !! y"), "varid ""x""|varsym ""!!""|varid ""y""",
                   "!! stays one operator");
      Check_Equal (Lex (U8 ("ñ!x")), U8 ("varid ""ñ""|varsym ""!""|varid ""x"""),
                   "a Unicode letter before ! is a closing token");
```

- [ ] **Step 9: Parse goldens.** Create
  `tests/golden/parse_m150_bang.hs`:

```haskell
module M where
f !x (!a, b) (Just !y) = x
g = \ !z ~(!w) -> z
h xs = let !n = length xs in n
xs ! i = i
k arr = arr!0
data T = T !Int ! Int
```

  and `tests/golden/parse_m150_bang_expr.hs`:

```haskell
module M where
f xs = xs !1
```

  Run `./scripts/run_golden.sh --update`, then audit:
  `git status --short tests/golden` lists only the four new files
  (no existing golden moved), and the new `.ast` files are exactly:

```
(module M)
(fun f (pats (pbang (pvar x)) (ptuple (pbang (pvar a)) (pvar b)) (pcon Just (pbang (pvar y)))) (var x))
(patbind (pvar g) (lam (pats (pbang (pvar z)) (plazy (pbang (pvar w)))) (var z)))
(fun h (pats (pvar xs)) (let (binds (patbind (pbang (pvar n)) (app (var length) (var xs)))) (var n)))
(fun ! (pats (pvar xs) (pvar i)) (var i))
(fun k (pats (pvar arr)) (app (app (var !) (var arr)) (int 0)))
(data T (vars) (cons (con T !(tcon Int) !(tcon Int))))

```

  (`parse_m150_bang.ast`: `xs ! i` defines `!`, `arr!0` uses it, and
  both strictness spellings still mark the field strict) and

```
(module M)
tests/golden/parse_m150_bang_expr.hs:2:11: error: bang pattern in expression context (did you mean to add a space after the '!'?) (found '!')
```

  (`parse_m150_bang_expr.ast`; GHC 9.4.8 reports the same position:
  `2:11: error: Bang pattern in expression context: !1`).

- [ ] **Step 10: Verify.**
  - semantic checks (`gcc -c -gnatc ...`) of `ahc-lexer`,
    `ahc-tokens`, `ahc-parser`, `ahc-syntax`, `ahc-syntax-printer`,
    `ahc-rename`, `ahc-fixity`, `ahc-exhaustive`, `ahc-desugar`: no
    errors (the `redundant conversion` warnings at desugar's
    `Syntax.Pat_Id (P)` and exhaustive line 69 are pre-existing);
  - `alr build --validation`; `cd tests && alr build --validation && ./bin/ahc_tests`
    → `passed: 389, failed: 0`;
  - `scratchpad/one.sh conformance m150_bang_patterns` → `ok`;
  - `./scripts/run_gate.sh` → `GATE ok` (the strict fields of
    `ch04_02_strict_fields`, `lib/Data/Map/Internal.hs` and
    `System.Random.SplitMix` now lex as `Prefix_Bang` and still
    parse through `Is_Bang`).
- [ ] **Step 11: Commit.**
  `feat(parser): bang patterns, with ghc 9's rule for when a ! is a bang and when it is the operator`

  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```

---

### Task A5: strict `let`, `where` and `do` bindings; no top-level bang (spec A1)

**Files:**
- Modify: `src/ahc-desugar.adb`: `Ds_Group`'s forward declaration
  (981-983); guard `Let_S` (1671-1688); `Ds_Rhs`'s `where`
  (1697-1708); `Ds_Do`'s `Let_S` (1811-1823); `Ds_Comp`'s `Let_S`
  (1878-1891); `Let_E` (2069-2082); `Ds_Group` (2574-2699)
- Modify: `src/ahc-rename.adb` `Declare_Group`'s `Pat_Unit` arm (1526-1532)
- Create: `tests/conformance/m150_strict_bindings.hs` (+ `.out`),
  `tests/golden/check_m150_toplevel_bang.hs` (+ `.types`),
  `tests/corpus-types/bad_m150_toplevel_bang.hs`

**Interfaces:**
- Consumes: `Seq_E`, `Force_All`, `Bang_P`, `Match_One`'s `Bang_P`
  arm (Task A4).
- Produces:

```ada
      procedure Ds_Group
        (Decls  : Syntax.Decl_Id_Vectors.Vector;
         Into   : in out Core.Bind_Vectors.Vector;
         Forces : in out Core.Var_Id_Vectors.Vector);
      procedure Ds_Group   --  top level, instance and class bodies
        (Decls : Syntax.Decl_Id_Vectors.Vector;
         Into  : in out Core.Bind_Vectors.Vector);
```

**Semantics** (GHC's user guide translation): a binding `!p = e` in
a group makes the group's body force it. For `!x = e` the body is
`seq x body`. For any other `!p = e` the selector translation stays
(`$pb = e`, one selector per variable), plus
`$bm = case $pb of !p -> ()`, and the body is `seq $bm body`: forcing
`$bm` evaluates `e` to WHNF and matches `p`, but forces nothing
inside it, so `let !(a, b) = (undefined, 2) in b` is `2`. A `where`
group's forces wrap the guards, so they happen before any guard is
tried. `!x <- m` in `do` needs no new code: the bind's pattern goes
through `Match_One`, whose `Bang_P` arm forces the result.

- [ ] **Step 1: Failing tests first.** Create
  `tests/conformance/m150_strict_bindings.hs`:

```haskell
{-# LANGUAGE LambdaCase #-}
-- M150: strict let / where / do bindings, and \cases with bangs.
import Control.Exception

probe :: Show a => String -> a -> IO ()
probe name v = do
  r <- try (evaluate v)
  putStrLn (name ++ ": " ++ case r of
    Left e -> const "forced" (e :: ErrorCall)
    Right x -> show x)

probeIO :: String -> IO () -> IO ()
probeIO name act = do
  r <- try act
  case r of
    Left e -> putStrLn (name ++ ": " ++ const "forced" (e :: ErrorCall))
    Right () -> return ()

letStrict :: Int
letStrict = let !x = (undefined :: Int) in 1

letLazy :: Int
letLazy = let x = (undefined :: Int) in 1

-- Only the pair is forced, not its components.
letPair :: Int
letPair = let !(a, b) = (undefined, 2 :: Int) in b

letWild :: Int
letWild = let !_ = (undefined :: Int) in 3

-- The where binding is forced before the guards are tried.
whereStrict :: Int -> String
whereStrict n
  | n > 0 = "positive"
  | otherwise = "other"
  where !check = if n == 99 then undefined else n

-- A strict binding's variable is usable in the body.
letUse :: Int
letUse = let !y = 20 + 1 in y * 2

twoArgs :: Int -> Int -> Int
twoArgs = \cases
  !a 0 -> 0
  _ b -> b

main :: IO ()
main = do
  probe "let !x" letStrict
  probe "let x" letLazy
  probe "let !(a, b)" letPair
  probe "let !_" letWild
  probe "where 1" (length (whereStrict 1))
  probe "where 99" (length (whereStrict 99))
  probe "let use" letUse
  probe "\\cases !a 0" (twoArgs undefined 0)
  probe "\\cases _ b" (twoArgs undefined 5)
  probeIO "do !x <-" $ do
    !x <- return (undefined :: Int)
    putStrLn "not reached"
  probeIO "do x <-" $ do
    x <- return (undefined :: Int)
    putStrLn "do x <-: lazy"
  probeIO "do let !x" $ do
    let !x = (undefined :: Int)
    putStrLn "not reached"
```

  Its oracled `.out`:

```
let !x: forced
let x: 1
let !(a, b): 2
let !_: forced
where 1: 8
where 99: forced
let use: 42
\cases !a 0: forced
\cases _ b: forced
do !x <-: forced
do x <-: lazy
do let !x: forced
```

  (`\cases _ b` is `forced` in GHC too: the first alternative's `!a`
  forces the first argument before the second alternative is tried.)
  Keep the parentheses in `let !x = (undefined :: Int) in 1`: AHC's
  refinement-type syntax reads `:: Int in 1 ..` as a range type, so
  `let x = e :: Int in b` without them is a parse error in AHC (a
  pre-existing incompatibility, outside this milestone).
  After Task A4 alone, `scratchpad/one.sh conformance m150_strict_bindings`
  builds but differs on `let !x`, `let !_`, `where 99` and
  `do let !x` (they print the lazy answers).

  Create `tests/corpus-types/bad_m150_toplevel_bang.hs`:

```haskell
{-# LANGUAGE BangPatterns #-}
-- GHC 9.4.8: Top-level strict bindings aren't allowed: !x = 3
!x = (3 :: Int)
main :: IO ()
main = print x
```

  and `tests/golden/check_m150_toplevel_bang.hs`:

```haskell
!x = (3 :: Int)

main :: IO ()
main = print x
```

- [ ] **Step 2: `Ds_Group` collects forces.** In
  `src/ahc-desugar.adb`, the forward declaration (981-983) becomes:

```ada
      --  Forces receives, in order, the variables a strict binding of
      --  the group (`!p = e`, M150) makes the group's body force;
      --  wrap the body with Force_All.
      procedure Ds_Group
        (Decls  : Syntax.Decl_Id_Vectors.Vector;
         Into   : in out Core.Bind_Vectors.Vector;
         Forces : in out Core.Var_Id_Vectors.Vector);
```

  The body's header (2574-2577) takes the same third parameter. In
  the `Pat_Unit` arm, after `PR` (2611-2612) declare:

```ada
                     --  `!p = e` (M150): a strict binding. BN/BR are
                     --  the pattern under the bang (PN/PR otherwise).
                     Strict : constant Boolean := PN.Kind = Bang_P;
                     BN : constant Pat_Node :=
                       (if Strict then Arena.Node (PN.Bang_Pat) else PN);
                     BR : constant Resolution :=
                       (if Strict then Res.Pat_Res (Positive (PN.Bang_Pat))
                        else PR);
```

  The variable-binding branch (2634-2639) becomes:

```ada
                     if BN.Kind = Var_P and then BR.Kind = Var_Res then
                        --  x = e directly; `!x = e` also forces x.
                        M.Vars (BR.Var).From_Pattern_Binding := True;
                        Into.Append
                          (Core.Bind_Pair'(Binder => BR.Var,
                                           Rhs => RHS_E));
                        if Strict then
                           Forces.Append (Core.Var_Id (BR.Var));
                        end if;
                     else
```

  In the selector branch, directly after the selector loop's
  `end loop;` (after line 2688, still inside the block that saved
  `Match_Context`), add:

```ada
                              if Strict then
                                 --  `!p = e`: $bm = case $pb of !p -> ()
                                 --  forces e and matches p when the
                                 --  body forces $bm (GHC's translation).
                                 declare
                                    BM : constant Core.Real_Var_Id :=
                                      Fresh ("$bm", Span);
                                    PB_Ref : constant Core.Real_Expr_Id :=
                                      VarE (PB, Span);
                                    Fail : constant Core.Real_Expr_Id :=
                                      Fail_Match
                                        (Pat_Text (Ext_P (N.Pat)),
                                         Ext_D (D), PB_Ref,
                                         "irrefutable pattern failed",
                                         Handled => Handled_Of_One (N.Pat),
                                         Schema => Pat_Schema (N.Pat));
                                    Unit_R : constant Core.Real_Expr_Id :=
                                      ConE (Core.Real_DataCon_Id
                                              (Env.Unit_DC), Span);
                                    Check : constant Core.Real_Expr_Id :=
                                      Match_One (PB, N.Pat, Unit_R, Fail);
                                 begin
                                    Into.Append
                                      (Core.Bind_Pair'
                                         (Binder => BM, Rhs => Check));
                                    Forces.Append (Core.Var_Id (BM));
                                 end;
                              end if;
```

  (`N.Pat` is the `Bang_P` itself, so `Match_One` forces `$pb` even
  when the inner pattern is irrefutable, as in `!_` or `!~(a, b)`.)
  After `end Ds_Group;` (2699) add the two-argument overload, which
  the module top level (3189) and `Ds_Method_Bodies` (2716) keep
  calling unchanged:

```ada
      --  A group whose bindings cannot be strict: the module's top
      --  level (the renamer rejects a bang there) and instance and
      --  class bodies.
      procedure Ds_Group
        (Decls : Syntax.Decl_Id_Vectors.Vector;
         Into  : in out Core.Bind_Vectors.Vector)
      is
         Ignored : Core.Var_Id_Vectors.Vector;
      begin
         Ds_Group (Decls, Into, Ignored);
      end Ds_Group;
```

- [ ] **Step 3: Every local group's body forces.** Five callers,
  each hoisting `Force_All` into a constant before the `M.Add`:
  - guard `| let ...` in `Ds_Rhs` (1671-1688):

```ada
                              when Let_S =>
                                 declare
                                    Binds : Core.Bind_Vectors.Vector;
                                    Forces : Core.Var_Id_Vectors.Vector;
                                 begin
                                    Ds_Group (QN.Let_Binds, Binds, Forces);
                                    if not Binds.Is_Empty then
                                       declare
                                          Forced : constant
                                            Core.Real_Expr_Id :=
                                              Force_All (Forces, Acc, Span);
                                       begin
                                          Acc := M.Add
                                            (Core.Expr_Node'
                                               (Kind => Core.Let_C,
                                                Span => Span,
                                                Is_Rec => True,
                                                Binds => Binds,
                                                Let_Body => Forced));
                                       end;
                                    end if;
                                 end;
```

  - `where` in `Ds_Rhs` (1697-1708):

```ada
         if not Where_Ds.Is_Empty then
            declare
               Binds : Core.Bind_Vectors.Vector;
               Forces : Core.Var_Id_Vectors.Vector;
            begin
               Ds_Group (Where_Ds, Binds, Forces);
               if not Binds.Is_Empty then
                  declare
                     --  `where !x = e` forces x before the guards.
                     Forced : constant Core.Real_Expr_Id :=
                       Force_All (Forces, Result, Span);
                  begin
                     Result := M.Add (Core.Expr_Node'
                       (Kind => Core.Let_C, Span => Span, Is_Rec => True,
                        Binds => Binds, Let_Body => Forced));
                  end;
               end if;
            end;
         end if;
```

  - `Ds_Do`'s `Let_S` (1811-1823):

```ada
            when Let_S =>
               declare
                  Binds : Core.Bind_Vectors.Vector;
                  Forces : Core.Var_Id_Vectors.Vector;
                  Rest : constant Core.Real_Expr_Id :=
                    Ds_Do (Stmts, From + 1, Span);
               begin
                  Ds_Group (N.Let_Binds, Binds, Forces);
                  if Binds.Is_Empty then
                     return Rest;
                  end if;
                  declare
                     Forced : constant Core.Real_Expr_Id :=
                       Force_All (Forces, Rest, Span);
                  begin
                     return M.Add (Core.Expr_Node'
                       (Kind => Core.Let_C, Span => Span, Is_Rec => True,
                        Binds => Binds, Let_Body => Forced));
                  end;
               end;
```

  - `Ds_Comp`'s `Let_S` (1878-1891):

```ada
               when Let_S =>
                  declare
                     Binds : Core.Bind_Vectors.Vector;
                     Forces : Core.Var_Id_Vectors.Vector;
                     Rest : constant Core.Real_Expr_Id :=
                       Ds_Comp (Quals, From + 1, Head, Span);
                  begin
                     Ds_Group (N.Let_Binds, Binds, Forces);
                     if Binds.Is_Empty then
                        return Rest;
                     end if;
                     declare
                        Forced : constant Core.Real_Expr_Id :=
                          Force_All (Forces, Rest, Span);
                     begin
                        return M.Add (Core.Expr_Node'
                          (Kind => Core.Let_C, Span => Span,
                           Is_Rec => True, Binds => Binds,
                           Let_Body => Forced));
                     end;
                  end;
```

  - `Let_E` in `Ds_Expr` (2069-2082):

```ada
               declare
                  Binds : Core.Bind_Vectors.Vector;
                  Forces : Core.Var_Id_Vectors.Vector;
                  Body_E : constant Core.Real_Expr_Id :=
                    Ds_Expr (N.Let_Body);
               begin
                  Ds_Group (N.Binds, Binds, Forces);
                  if Binds.Is_Empty then
                     return Body_E;
                  end if;
                  declare
                     Forced : constant Core.Real_Expr_Id :=
                       Force_All (Forces, Body_E, Span);
                  begin
                     return M.Add (Core.Expr_Node'
                       (Kind => Core.Let_C, Span => Span, Is_Rec => True,
                        Binds => Binds, Let_Body => Forced));
                  end;
               end;
```

  With no bang in a group, `Forces` is empty and `Force_All` returns
  its argument, so no other program's Core changes.

- [ ] **Step 4: No top-level bang.** In `src/ahc-rename.adb`
  `Declare_Group`, the `Pat_Unit` arm (1526-1532) becomes:

```ada
               when Pat_Unit =>
                  declare
                     D : constant Real_Decl_Id := U.Equations (1);
                     N : constant Decl_Node := Arena.Node (D);
                  begin
                     --  GHC: "Top-level strict bindings aren't allowed".
                     if Global and then Arena.Node (N.Pat).Kind = Bang_P
                     then
                        Bag.Add (Diagnostics.Error,
                                 Diagnostics.Rename_Unsupported, N.Span,
                                 "top-level strict bindings aren't "
                                 & "allowed");
                     end if;
                     Rename_Pat (N.Pat, Global_Binders => Global);
                  end;
```

- [ ] **Step 5: Verify.**
  - semantic checks of `ahc-desugar` and `ahc-rename`; `alr build --validation`;
  - `scratchpad/one.sh conformance m150_strict_bindings` → `ok`;
  - `./bin/ahc check tests/corpus-types/bad_m150_toplevel_bang.hs`
    → rc 1, `3:1: error: top-level strict bindings aren't allowed`;
  - `./scripts/run_golden.sh --update`; `git status --short tests/golden`
    lists only `check_m150_toplevel_bang.hs/.types`, and the
    `.types` file is exactly
    `tests/golden/check_m150_toplevel_bang.hs:1:1: error: top-level strict bindings aren't allowed`;
  - `./scripts/run_gate.sh` → `GATE ok` (in particular the three Core
    goldens are unchanged);
  - `./scripts/run_differential_types.sh` → exit 0
    (`ok tests/corpus-types/bad_m150_toplevel_bang.hs`).
- [ ] **Step 6: Commit.**
  `feat(desugar): a banged let, where or do binding is forced before the body, and a top-level bang is an error as in ghc`

  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```

---

### Task A6: Phase A gate run

**Files:** none changed unless a suite fails; a failure is fixed in
the task that introduced it, with its own regression case.

- [ ] **Step 1:** release build goldens (the evaluation-order rule:
  ids can number differently between builds):
  `alr build --release && ./scripts/run_golden.sh` → every line `ok`;
  then `alr build --validation`.
- [ ] **Step 2:** `./scripts/run_gate.sh` → `GATE ok` (unit,
  conformance, exec, exec-own, golden, prelude-exports, userlib).
- [ ] **Step 3:** `./scripts/run_differential.sh` and
  `./scripts/run_differential_types.sh` → both exit 0.
- [ ] **Step 4:** `./scripts/run_fuzz_par.sh 300 8` → exit 0; no new
  files in `tests/fuzz-failures/` (shrink any with
  `scripts/shrink_fuzz.py` and fix before going on).
- [ ] **Step 5:** `git status --short` shows no stray files from the
  runs.

**Gate (Phase A):** conformance (oracled) -
`m150_bang_patterns` (bangs in equations, tuples, constructor and
newtype fields, under `~`, lambdas, `case`, `\case`, guards, `!` as an
operator), `m150_strict_bindings` (strict `let`/`where`/`do`/guard
bindings, `\cases`, a bang forcing `undefined`), `m150_layout_close`
(`)`/`]`/`,` closing after `case`/`\cases`/`let`/`where`),
`m150_unicode_idents` (Spanish, Greek, Cyrillic, CJK identifiers,
Unicode operators), `m150_unicode_layout` (layout aligned under
multi-byte identifiers); negative corpus - `bad_m150_toplevel_bang`;
parse goldens `parse_m150_bang`, `parse_m150_bang_expr`,
`check_m150_toplevel_bang` regenerated and audited (no existing golden
moves, release build too); unit tests `passed: 389, failed: 0`;
`run_gate.sh` → `GATE ok`; differential parse + types green;
300-seed fuzz green.

---

## Phase B - the renamer: `where` shadows the arguments

### Task B1: a `where` group gets its own scope

**Files:**
- Modify: `src/ahc-rename.adb:1588-1596` (`Rename_Value_Decl`, `Fun_D`)
- Modify: `src/ahc-rename.adb:1333-1339` (`Rename_Expr`, `Case_E`
  alternatives; `\cases` alternatives are `Case_E` alternatives too)
- Create: `tests/conformance/m150_where_shadows.hs` (+ `.out`)
- Create: `tests/corpus-types/bad_m150_where_duplicate.hs`,
  `tests/corpus-types/bad_m150_args_duplicate.hs`

**Interfaces:**
- Consumes: `Push_Scope`, `Pop_Scope`, `Declare_Group`,
  `Bind_In_Scope` (632: a duplicate is an error only within the
  innermost scope, which is what makes the split work).
- Produces: nothing new.

- [ ] **Step 1: Failing test first.** Create
  `tests/conformance/m150_where_shadows.hs`:

```haskell
-- M150: a where binding shadows an argument of the same name over the
-- guards and the right-hand side, in equations and case alternatives.

plain :: Int -> Int
plain x = x + 1
  where x = 10

guarded :: Int -> String
guarded n
  | n > 5 = "big " ++ show n
  | otherwise = "small " ++ show n
  where n = 7

-- The where binding may use other arguments, but not the shadowed one
-- (it would refer to itself).
pairUp :: Int -> Int -> (Int, Int)
pairUp a b = (a, b)
  where b = a * 100

inCase :: Maybe Int -> Int
inCase m = case m of
  Just v -> v
    where v = 42
  Nothing -> 0

-- A where function's own parameter shadows the where-bound name's
-- outer argument as before.
nested :: Int -> Int
nested y = go 3
  where go y = y * 2

-- Several equations, each with its own shadowing where.
multi :: Int -> Int
multi 0 = z where z = -1
multi z = z where z = 5

main :: IO ()
main = do
  print (plain 1)
  putStrLn (guarded 1)
  print (pairUp 2 3)
  print (inCase (Just 1), inCase Nothing)
  print (nested 100)
  print (multi 0, multi 9)
```

  Its oracled `.out`:

```
11
big 7
(2,200)
(42,0)
6
(-1,5)
```

  On v1.20, `./bin/ahc check tests/conformance/m150_where_shadows.hs`
  reports five errors (`6:9: error: 'x' is bound more than once`,
  and the same at 12:9, 18:9, 23:11, 35:19).

  Create `tests/corpus-types/bad_m150_where_duplicate.hs`:

```haskell
-- A where group still may not bind one name twice, even now that it
-- may shadow an argument (GHC 9.4.8: Conflicting definitions for 'y').
f :: Int -> Int
f x = x + y
  where y = 1
        y = 2
main :: IO ()
main = print (f 0)
```

  and `tests/corpus-types/bad_m150_args_duplicate.hs`:

```haskell
-- One equation's patterns still may not bind one name twice (GHC
-- 9.4.8: Conflicting definitions for 'x').
f :: Int -> Int -> Int
f x x = x
main :: IO ()
main = print (f 1 2)
```

- [ ] **Step 2: Implement.** `Rename_Value_Decl`'s `Fun_D` arm
  (1588-1596) becomes:

```ada
            when Fun_D =>
               Push_Scope;
               for P of N.Fun_Pats loop
                  Rename_Pat (P);
               end loop;
               --  The where group's own scope: `f x = x where x = 10`
               --  shadows the argument over guards and body (M150).
               --  Duplicates within the patterns, or within the group,
               --  are still errors - each is one scope.
               Push_Scope;
               Declare_Group (N.Fun_Where, Global => False);
               Rename_Rhs (N.Fun_Rhs);
               Rename_Group_Bodies (N.Fun_Where);
               Pop_Scope;
               Pop_Scope;
```

  `Rename_Expr`'s `Case_E` alternative (1334-1339) becomes:

```ada
                     Push_Scope;
                     Rename_Pat (Alt.Pat);
                     --  The where group's own scope: its bindings
                     --  shadow the pattern's (M150, as in GHC).
                     Push_Scope;
                     Declare_Group (Alt.Where_Ds, Global => False);
                     Rename_Rhs (Alt.Alt_Rhs);
                     Rename_Group_Bodies (Alt.Where_Ds);
                     Pop_Scope;
                     Pop_Scope;
```

  `Pat_D` (1597-1603) already has one scope for its `where` (its
  pattern is declared in the enclosing group), so it is unchanged.
  Desugar needs nothing: shadowing is resolved to distinct Core
  variables here.

- [ ] **Step 3: Verify.**
  - `alr exec -- gcc -c -gnatc -gnat2022 -gnatwa -Isrc src/ahc-rename.adb -o scratchpad/ck/ahc-rename.o`;
    `alr build --validation`;
  - `scratchpad/one.sh conformance m150_where_shadows` → `ok`;
  - `./bin/ahc check tests/corpus-types/bad_m150_where_duplicate.hs`
    → rc 1, `6:9: error: 'y' is bound more than once`;
    `./bin/ahc check tests/corpus-types/bad_m150_args_duplicate.hs`
    → rc 1, `4:5: error: 'x' is bound more than once`;
  - `./scripts/run_differential_types.sh` → exit 0.
- [ ] **Step 4: Commit.**
  `fix(rename): a where binding shadows an argument of the same name, in equations and case alternatives`

  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```

- [ ] **Step 5: Phase B gate run.** `./scripts/run_gate.sh` →
  `GATE ok` (both collectors: the gate's `exec-own` suite runs
  `AHC_GC=own`); `AHC_GC=own ./scripts/run_conformance.sh` → exit 0;
  `./scripts/run_differential.sh` and
  `./scripts/run_differential_types.sh` → exit 0;
  `./scripts/run_examples.sh` and `./scripts/run_separate.sh` → exit 0
  (larger programs whose `where` clauses now get a scope of their
  own).

**Gate (Phase B):** conformance - `m150_where_shadows` (shadowing in
equations, guards and case alternatives); negative corpus -
`bad_m150_where_duplicate` (a duplicate inside one `where`) and
`bad_m150_args_duplicate`; full suites: `run_gate.sh` → `GATE ok`
with both GC modes, differential parse + types, examples, separate
compilation.

## Phase C - Applicative above Monad, Traversable in full

Spec section C (`docs/specs/2026-10-15-m150-correctness.md`). Phase C
precedes D. Every line number below is the CURRENT source at
`23cdddf`; tasks earlier in this phase shift later line numbers, so
each step also quotes the text it replaces.

**Phase-C-wide notes (read before any task):**

- `SCRATCH` is the executing session's scratchpad directory. Nothing
  under it is committed.
- **Gate inputs:** C3, C4 and C5 edit `prelude/Prelude.hs` and `lib/`.
  Don't start a background suite while those files are changing.
- **Goldens:** C3 and C4 change the Core goldens beyond renumbering,
  because the Monad and Traversable dictionaries change shape.
  Regenerate them on the RELEASE build. Audit them with
  `$SCRATCH/golden_audit.py` (written in C3, step 6), then confirm the
  VALIDATION build reproduces them byte for byte. A difference between
  the two builds is the actual-evaluation-order hazard: hoist the
  id-minting calls.
- **Ada semantic check before every build:**
  `alr exec -- gcc -c -gnatc -gnat2022 -gnatwa -Isrc src/X.adb -o $SCRATCH/ck/X.o`
  (after `mkdir -p $SCRATCH/ck`). Treat any new warning as a defect,
  for example an unreferenced `Same_Tv_Arg` after C3.

**Spec deviations decided while planning** (record them in the
write-up):

1. **No `Traversable Set`.** base has none (`Set` is not a `Functor`).
   Checked against GHC 9.4.8: `traverse Just (S.fromList [1])` fails
   with "No instance for (Traversable S.Set)". The spec's list is
   wrong here, and adding the instance would over-accept.
2. **`Array`'s instances are at `Array`, not `Array i`.** AHC's
   `Data.Array` is Int-indexed, `data Array e`
   (`lib/Data/Array.hs:13`), so the head has no index variable. The
   observable behaviour (`fmap`, `sum`, `traverse`, `show`) is base's.
3. **The `[]` instance keeps a direct monadic `mapM`.** This is
   decided up front, not left to the bench. It is the Report's
   one-bind-per-element recursion, equal to `traverse` for every
   lawful monad, and it avoids IO's two-bind `<*>` on the hottest use
   of `mapM`. The new bench `b_mapm` (C6) measures it against v1.20's
   list-only `mapM`.
4. **`(<*>)` gets base's default `liftA2 id`, and `traverse` gets base's
   default `sequenceA . fmap f`.** The spec lists only the
   `liftA2`/`*>`/`<*` and `sequenceA`/`mapM`/`sequence` defaults. With
   both, the minimal definitions are base's (`pure, ((<*>) | liftA2)`
   and `traverse | sequenceA`), so an instance written against base
   draws no "no explicit implementation" warning.
5. **Prerequisite parser work (C1).** `instance Functor ((,) a)` does
   not parse today: AHC v1.20 says `expected a type (found ',')`. The
   tuple type constructors become ordinary prefix types first.
6. **The hint's first line stays one line.** The spec's code block
   wraps "required by the / superclasses of an instance declaration"
   for display. The message keeps today's single line, and only the
   two hint lines are new.
7. **One superclass message for every missing superclass instance.**
   Today a missing instance at a concrete head is reported by `Solve`
   as a bare `no instance for 'Functor Parser'` (probed: AHC v1.20 on
   an Applicative without Functor). The check now solves quietly and
   says `..., required by the superclasses of an instance declaration`
   for both concrete and residual heads. The old text is a prefix of
   the new one. The GND-specific `required by the derived Monad`
   check is deleted: GND instances already go through the general
   check (`Inst.Is_GND`, `ahc-typechecker.adb:2318`), and all GND
   heads are resolved before any solving (`:2259-2263`).

---

### Task C1: the tuple type constructors parse as types

**Files:**
- Modify: `src/ahc-parser.adb:419-435` (`Parse_AType`, the
  `Left_Paren` arm)
- Test: `tests/src/test_parser.adb` (one `Check_Equal` in `Run`)
- Create: `tests/corpus/tuple_tycon.hs` (parse differential)
- Create: `tests/conformance/m150_tuple_tycon.hs` + `.out`

**Interfaces:**
- Produces: a `Con_T` type node named `(,)`, `(,,)`, … (the same text
  `AHC.Builtins` interns for `Env.Tuple_TCs (N)`,
  `src/ahc-builtins.adb:302-318`). Renamer, kinds and instance-head
  resolution already map `Con_T "(->)"` to a wired TyCon by name
  (`src/ahc-rename.adb:2160-2184`), and the tuple TyCons sit in the
  same `Env.TyCons` map (`Def_TyCon`, `ahc-builtins.adb:25-36`). Task
  C4's `instance Functor ((,) a)` relies on this.

Today (`src/ahc-parser.adb:419-435`):

```ada
            when Left_Paren =>
               Advance;
               if At_K (Right_Paren) then
                  Advance;
                  return Arena.Add
                    (Type_Node'(Kind => Con_T, Span => Span,
                                Con => (Unit_Name, Names.No_Name)));
               elsif At_K (Right_Arrow) then
                  Advance;
                  Expect (Right_Paren, "')'");
                  return Arena.Add
                    (Type_Node'(Kind => Con_T, Span => Span,
                                Con => (Arrow_Name, Names.No_Name)));
               end if;
```

- [ ] **Step 1: Implement.** Add a third arm before `end if;`:

```ada
               elsif At_K (Comma) then
                  --  The tuple type constructors (,) (,,) ... as
                  --  prefix types (Report 4.1.2): `(,) a` heads base's
                  --  Functor/Foldable/Traversable pair instances (M150).
                  declare
                     Commas : Natural := 0;
                  begin
                     while At_K (Comma) loop
                        Advance;
                        Commas := Commas + 1;
                     end loop;
                     Expect (Right_Paren, "')'");
                     Check_Tuple_Width (Commas + 1, Span);
                     declare
                        Text : String (1 .. Commas + 2) :=
                          [others => ','];
                     begin
                        Text (1) := '(';
                        Text (Text'Last) := ')';
                        return Arena.Add
                          (Type_Node'(Kind => Con_T, Span => Span,
                                      Con => (Table.Intern (Text),
                                              Names.No_Name)));
                     end;
                  end;
```

  `Check_Tuple_Width` (`:201-210`) reports widths above
  `Builtins.Max_Tuple`, as it does for tuple types.

- [ ] **Step 2: Unit test.** In `tests/src/test_parser.adb`, after the
  "parenthesized operator signature" check (`:57-61`), add:

```ada
      --  M150: the tuple type constructor is a prefix type.
      Check_Equal
        (P ("p :: (,) Int Bool"),
         "(module)|(sig ( p ) (tap (tap (tcon (,)) (tcon Int))"
         & " (tcon Bool)))",
         "tuple type constructor in prefix position");
```

- [ ] **Step 3: Parse-differential case.** Create
  `tests/corpus/tuple_tycon.hs`:

```haskell
-- Report 4.1.2: (,) and (,,) are type constructors, prefix and
-- partially applied (M150).
newtype Wrap f a = Wrap (f a)

pairT :: (,) Int Bool
pairT = (1, True)

tripleT :: (,,) Int Char Bool
tripleT = (1, 'x', False)

wrapped :: Wrap ((,) String) Int
wrapped = Wrap ("k", 2)

main :: IO ()
main = print (pairT, tripleT)
```

- [ ] **Step 4: Conformance program.** Create
  `tests/conformance/m150_tuple_tycon.hs`:

```haskell
-- Report 4.1.2: the tuple type constructors (,), (,,), ... are
-- ordinary type constructors, usable prefix and partially applied -
-- in signatures and in instance heads (M150, for base's ((,) a)).
newtype Wrap f a = Wrap (f a)

pairT :: (,) Int Bool
pairT = (1, True)

tripleT :: (,,) Int Char Bool
tripleT = (1, 'x', False)

unwrap :: Wrap ((,) String) Int -> (String, Int)
unwrap (Wrap p) = p

class Tag f where
  tag :: f b -> String

instance Show a => Tag ((,) a) where
  tag (a, _) = "pair:" ++ show a

instance Tag ((,,) a b) where
  tag _ = "triple"

main :: IO ()
main = do
  print (pairT, tripleT)
  print (unwrap (Wrap ("k", 2)))
  putStrLn (tag (1 :: Int, 'x'))
  putStrLn (tag ('a', "b", True))
```

  Oracle it from the repo root:
  `~/.ghcup/bin/runghc tests/conformance/m150_tuple_tycon.hs > tests/conformance/m150_tuple_tycon.out`.
  The expected (and checked) output is:

```
((1,True),(1,'x',False))
("k",2)
pair:1
triple
```

- [ ] **Step 5: Verify.**
  - semantic-check `src/ahc-parser.adb`;
  - `alr build --validation`;
  - `cd tests && alr build --validation && ./bin/ahc_tests`, which
    passes with the new parser check;
  - `scripts/run_differential.sh`, where
    `ok tests/corpus/tuple_tycon.hs` and nothing else changes;
  - `scripts/ahc-build.sh tests/conformance/m150_tuple_tycon.hs $SCRATCH/tt && $SCRATCH/tt | diff - tests/conformance/m150_tuple_tycon.out`,
    with no diff.

  The user Prelude view already carries the tuple TyCons:
  `src/ahc_main.adb:772-786` copies every `Env.TyCons` entry named
  `(,…)` or `(->)` into `Reg.Public_Base.TyCons`. So no renamer change
  is expected. If the build still says "type not in scope: (,)", look
  there first.
- [ ] **Step 6: Commit.**

```
feat(parser): the tuple type constructors (,) and (,,) parse as prefix types, so ((,) a) can head an instance

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

---

### Task C2: oracle the phase's programs first (they fail on v1.20)

**Files:**
- Create: `tests/conformance/m150_applicative_above_monad.hs` + `.out`
- Create: `tests/conformance/m150_traversable.hs` + `.out`
- Create: `tests/conformance/m150_for_traversable.hs` + `.out`
- Create: `tests/conformance/multi/m150_monad_no_applicative/Main.hs` +
  `expected.err`
- Create: `tests/conformance/multi/m150_applicative_no_functor/Main.hs`
  + `expected.err`
- Create: `tests/corpus-types/bad_m150_monad_no_applicative.hs`,
  `tests/corpus-types/bad_m150_traversable_no_foldable.hs`,
  `tests/corpus-types/ok_m150_monad_context.hs`

**Interfaces:**
- Produces: the oracle goldens that C3-C5 turn green:
  - C3: `m150_applicative_above_monad`, both multi cases,
    `bad_m150_monad_no_applicative`;
  - C4: `ok_m150_monad_context`, `bad_m150_traversable_no_foldable`;
  - C5: `m150_traversable`, `m150_for_traversable`.

- [ ] **Step 1:** create `tests/conformance/m150_applicative_above_monad.hs`:

```haskell
-- M150 phase C: Applicative is Monad's superclass (GHC 7.10's AMP), so
-- a Monad m context alone gives pure, <*>, fmap, *>, <* and liftA2;
-- return defaults to pure; <*> defaults to liftA2 id.
import Control.Applicative (liftA2)

-- Only Monad m in scope: Functor and Applicative come by superclass.
pairUp :: Monad m => m a -> m b -> m (a, b)
pairUp ma mb = (,) <$> ma <*> mb

bump :: Monad m => m Int -> m Int
bump m = fmap (+ 1) m

both :: Monad m => m a -> m b -> m b
both ma mb = ma *> mb

firstOf :: Monad m => m a -> m b -> m a
firstOf ma mb = ma <* mb

lifted :: Monad m => m Int -> m Int -> m Int
lifted = liftA2 (+)

pureIn :: Monad m => a -> m [a]
pureIn x = pure [x, x]

-- A state monad whose Monad instance omits return: base's default
-- return = pure applies.
newtype St s a = St { runSt :: s -> (a, s) }

instance Functor (St s) where
  fmap f (St g) = St (\s -> let (a, s') = g s in (f a, s'))

instance Applicative (St s) where
  pure a = St (\s -> (a, s))
  St f <*> St g = St (\s -> let (h, s1) = f s; (a, s2) = g s1 in (h a, s2))

instance Monad (St s) where
  St g >>= k = St (\s -> let (a, s1) = g s in runSt (k a) s1)

tick :: St Int Int
tick = St (\s -> (s, s + 1))

-- An Applicative that defines liftA2 and not <*>: base's default
-- (<*>) = liftA2 id applies.
newtype Box a = Box a deriving Show

instance Functor Box where
  fmap f (Box a) = Box (f a)

instance Applicative Box where
  pure = Box
  liftA2 f (Box a) (Box b) = Box (f a b)

instance Monad Box where
  Box a >>= k = k a

main :: IO ()
main = do
  print (pairUp (Just 1) (Just 'a'))
  print (pairUp [1, 2] "xy")
  print (bump (Right 41 :: Either String Int))
  print (both (Just 1) (Just 2), both Nothing (Just 2 :: Maybe Int))
  print (firstOf [1, 2] "ab")
  print (lifted (Just 2) (Just 3))
  print (pureIn 'z' :: Maybe String)
  r <- pairUp (return 1) (putStrLn "effect" >> return True)
  print (r :: (Int, Bool))
  print (fst (runSt (do { a <- tick; b <- tick; return (a + b) }) 10))
  print (fst (runSt (pairUp tick (fmap (* 100) tick)) 1))
  print (Box (+ 1) <*> Box 41)
  print (do { x <- Box 2; y <- pure 3; return (x * y) })
  print (Box 'a' *> Box 'b', Box 'a' <* Box 'b')
```

  The oracle output (GHC 9.4.8, checked while planning):

```
Just (1,'a')
[(1,'x'),(1,'y'),(2,'x'),(2,'y')]
Right 42
(Just 2,Nothing)
[1,1,2,2]
Just 5
Just "zz"
effect
(1,True)
21
(1,200)
Box 42
Box 6
(Box 'b',Box 'a')
```

- [ ] **Step 2:** create `tests/conformance/m150_traversable.hs`:

```haskell
-- M150 phase C: mapM, sequence, traverse and sequenceA are Traversable
-- methods over every container base gives an instance (GHC 9.4.8).
import qualified Data.Map as M
import Data.Array (listArray)
import Data.Functor.Identity (Identity (..))

data Tree a = Leaf | Node (Tree a) a (Tree a)
  deriving Show

instance Functor Tree where
  fmap _ Leaf = Leaf
  fmap f (Node l x r) = Node (fmap f l) (f x) (fmap f r)

instance Foldable Tree where
  foldr _ z Leaf = z
  foldr f z (Node l x r) = foldr f (f x (foldr f z r)) l

instance Traversable Tree where
  traverse _ Leaf = pure Leaf
  traverse f (Node l x r) = Node <$> traverse f l <*> f x <*> traverse f r

positive :: Int -> Maybe Int
positive x = if x > 0 then Just x else Nothing

checked :: Int -> Either String Int
checked x = if x > 0 then Right x else Left ("bad " ++ show x)

tree :: Tree Int
tree = Node (Node Leaf 1 Leaf) 2 (Node Leaf 3 Leaf)

main :: IO ()
main = do
  -- Maybe as the container
  print (mapM positive (Just 3))
  print (mapM positive (Nothing :: Maybe Int))
  print (sequence (Just [1, 2 :: Int]))
  print (sequenceA (Just (Right 'x' :: Either String Char)))
  r <- mapM (\x -> print x >> return (x * 2)) (Just (21 :: Int))
  print r
  -- Either as the container and as the effect
  print (mapM checked [1, 2, -3, 4])
  print (mapM checked [1, 2, 3])
  print (sequence (Right (Just 3) :: Either String (Maybe Int)))
  print (traverse positive (Left "no" :: Either String Int))
  -- Map: values in key order
  let m = M.fromList [(3, 30), (1, 10), (2, 20 :: Int)]
  print (traverse positive m)
  print (mapM positive (M.insert 4 0 m))
  _ <- mapM print m
  print (sequence (M.fromList [(1 :: Int, [1, 2 :: Int]), (2, [3])]))
  -- a user Traversable
  print (traverse positive tree)
  print (mapM (\x -> [x, x * 10]) (Node Leaf 1 (Node Leaf 2 Leaf)))
  print (sequenceA (fmap Just tree))
  print (sum tree, length tree, maximum tree)
  -- pairs: Functor, Foldable and Traversable over the second component
  print (fmap (+ 1) ("k", 1 :: Int))
  print (length ("k", 'x'), sum ((), 5 :: Int), elem 'x' (True, 'x'))
  print (traverse (\x -> [x, x + 1]) ("k", 1 :: Int))
  print (sequence ('a', Just True))
  print (mapM positive (0 :: Int, -1))
  -- Identity
  print (runIdentity (traverse (Identity . (* 2)) [1, 2, 3 :: Int]))
  print (traverse (\x -> [x, negate x]) (Identity (3 :: Int)))
  print (sum (Identity (7 :: Int)), fmap show (Identity True))
  -- Array: Functor, Foldable, Traversable
  let a = listArray (0, 2) [1, 2, 3 :: Int]
  print (fmap (* 2) a)
  print (sum a, length a, maximum a)
  print (traverse positive a)
  print (mapM positive (fmap (subtract 2) a))
  -- lists still work, effects in order
  xs <- mapM (\x -> putStrLn ("visit " ++ show x) >> return (x + 1)) [1, 2, 3 :: Int]
  print xs
  ys <- sequence [return 'a', return 'b']
  putStrLn ys
  -- a string literal (OverloadedStrings is unconditional in AHC)
  mapM (\c -> return (succ c)) "abc" >>= putStrLn
```

  The oracle output:

```
Just (Just 3)
Just Nothing
[Just 1,Just 2]
Right (Just 'x')
21
Just 42
Left "bad -3"
Right [1,2,3]
Just (Right 3)
Just (Left "no")
Just (fromList [(1,10),(2,20),(3,30)])
Nothing
10
20
30
[fromList [(1,1),(2,3)],fromList [(1,2),(2,3)]]
Just (Node (Node Leaf 1 Leaf) 2 (Node Leaf 3 Leaf))
[Node Leaf 1 (Node Leaf 2 Leaf),Node Leaf 1 (Node Leaf 20 Leaf),Node Leaf 10 (Node Leaf 2 Leaf),Node Leaf 10 (Node Leaf 20 Leaf)]
Just (Node (Node Leaf 1 Leaf) 2 (Node Leaf 3 Leaf))
(6,3,3)
("k",2)
(1,5,True)
[("k",1),("k",2)]
Just ('a',True)
Nothing
[2,4,6]
[Identity 3,Identity (-3)]
(7,Identity "True")
array (0,2) [(0,2),(1,4),(2,6)]
(6,3,3)
Just (array (0,2) [(0,1),(1,2),(2,3)])
Nothing
visit 1
visit 2
visit 3
[2,3,4]
ab
bcd
```

- [ ] **Step 3:** create `tests/conformance/m150_for_traversable.hs`:

```haskell
-- M150 phase C: Data.Traversable (for, forM, mapAccumL, mapAccumR)
-- and Control.Monad's forM/forM_ over any Traversable/Foldable.
import Control.Monad (forM, forM_)
import Data.Traversable (for, mapAccumL, mapAccumR)
import qualified Data.Traversable as T
import qualified Data.Map as M

main :: IO ()
main = do
  r <- forM (Just 5) (\x -> print x >> return (x * 2 :: Int))
  print r
  forM_ (Just 'q') print
  forM_ (Nothing :: Maybe Int) print
  forM_ (M.fromList [(2, "two"), (1, "one")]) putStrLn
  xs <- forM [1, 2, 3 :: Int] (\x -> return (x * x))
  print xs
  print (for [1, 2, 3 :: Int] (\x -> if x > 0 then Just x else Nothing))
  print (T.forM (Right 4 :: Either String Int) (\x -> [x, x + 1]))
  print (T.traverse (\x -> [x]) (Just 'c'))
  print (mapAccumL (\acc x -> (acc + x, acc * x)) 0 [1, 2, 3 :: Int])
  print (mapAccumR (\acc x -> (acc + x, acc * x)) 0 [1, 2, 3 :: Int])
  print (mapAccumL (\n c -> (n + 1, (n, c))) (0 :: Int) (Just 'z'))
  print (mapAccumL (\acc v -> (acc ++ v, length acc))
                   "" (M.fromList [(1 :: Int, "ab"), (2, "c")]))
  print (T.sequenceA [Just 1, Just (2 :: Int)])
  print (T.mapM (\x -> if x > 1 then Right x else Left x) [2, 3, 1 :: Int])
```

  The oracle output:

```
5
Just 10
'q'
one
two
[1,4,9]
Just [1,2,3]
[Right 4,Right 5]
[Just 'c']
(6,[0,2,9])
(6,[5,6,0])
(1,Just (0,'z'))
("abc",fromList [(1,0),(2,2)])
Just [1,2]
Left 1
```

- [ ] **Step 4:** the negative multi cases. They pin the hint text,
  because `run_conformance.sh` greps each `expected.err` line from
  AHC's stderr with `grep -F` (`scripts/run_conformance.sh:60-95`).

  `tests/conformance/multi/m150_monad_no_applicative/Main.hs`:

```haskell
-- GHC 7.10's AMP: a Monad instance needs an Applicative instance.
newtype Parser a = Parser (String -> [(a, String)])

instance Functor Parser where
  fmap f (Parser p) = Parser (\s -> [(f a, r) | (a, r) <- p s])

instance Monad Parser where
  return a = Parser (\s -> [(a, s)])
  Parser p >>= k = Parser (\s -> concat [q r | (a, r) <- p s, let Parser q = k a])

main :: IO ()
main = putStrLn "unreachable"
```

  `tests/conformance/multi/m150_monad_no_applicative/expected.err`.
  Line 3 starts with exactly 15 spaces:

```
Main.hs:7:1: error: no instance for 'Applicative Parser', required by the superclasses of an instance declaration
  hint: add  instance Applicative Parser where
               pure = return; (<*>) = ap
```

  `tests/conformance/multi/m150_applicative_no_functor/Main.hs`:

```haskell
-- An Applicative instance needs a Functor instance (base's hierarchy).
newtype Parser a = Parser (String -> [(a, String)])

instance Applicative Parser where
  pure a = Parser (\s -> [(a, s)])
  Parser pf <*> Parser pa =
    Parser (\s -> [(f a, r2) | (f, r1) <- pf s, (a, r2) <- pa r1])

instance Monad Parser where
  Parser p >>= k = Parser (\s -> concat [q r | (a, r) <- p s, let Parser q = k a])

main :: IO ()
main = putStrLn "unreachable"
```

  `tests/conformance/multi/m150_applicative_no_functor/expected.err`:

```
Main.hs:4:1: error: no instance for 'Functor Parser', required by the superclasses of an instance declaration
  hint: add  instance Functor Parser where
               fmap = liftM
```

  GHC 9.4.8 rejects both, as checked while planning: "No instance for
  (Applicative Parser) arising from the superclasses of an instance
  declaration" at 7:10, and "(Functor Parser)" at 4:10. AHC reports
  the `instance` keyword's column, 1, as it already does for the
  second case today (`Main.hs:4:1: error: no instance for 'Functor
  Parser'`).

- [ ] **Step 5:** the type-differential corpus
  (`scripts/run_differential_types.sh` runs GHC with `-XHaskell2010
  -fno-code`). Checked while planning: GHC rejects the two `bad_`
  files and accepts `ok_`.
  - `tests/corpus-types/bad_m150_monad_no_applicative.hs`: the same
    text as `multi/m150_monad_no_applicative/Main.hs` above.
  - `tests/corpus-types/bad_m150_traversable_no_foldable.hs`:

```haskell
-- base: class (Functor t, Foldable t) => Traversable t. A Traversable
-- instance without a Foldable instance is rejected (M150).
data Pair a = Pair a a

instance Functor Pair where
  fmap f (Pair x y) = Pair (f x) (f y)

instance Traversable Pair where
  traverse f (Pair x y) = Pair <$> f x <*> f y

main :: IO ()
main = print (fmap (const ()) (Pair 1 2) `seq` ())
```

  - `tests/corpus-types/ok_m150_monad_context.hs`:

```haskell
-- M150: under Monad m alone, Functor and Applicative come by
-- superclass extraction, as GHC's base has them since 7.10.
pairUp :: Monad m => m a -> m b -> m (a, b)
pairUp ma mb = (,) <$> ma <*> mb

bump :: Monad m => m Int -> m Int
bump = fmap (+ 1)

walk :: Monad m => (a -> m b) -> Maybe a -> m (Maybe b)
walk = mapM

main :: IO ()
main = print (pairUp (Just 1) (bump (Just (2 :: Int))), walk Just (Just 'x'))
```

- [ ] **Step 6:** oracle the three flat programs from the repo root,
  so GHC sees the path AHC is given:

```sh
for p in m150_applicative_above_monad m150_traversable m150_for_traversable; do
  ~/.ghcup/bin/runghc tests/conformance/$p.hs > tests/conformance/$p.out
done
```

  Diff each `.out` against the outputs quoted in steps 1-3. They must
  be identical. Run `scripts/run_conformance.sh --oracle` too, and
  check that it prints `oracle rejects` for both new multi cases.
- [ ] **Step 7:** confirm every new case FAILS on the current AHC
  (`alr build --validation` first):
  - `scripts/run_conformance.sh` shows `BUILD-FAIL` for the three
    flat programs. Probed while planning:
    - `m150_traversable`: "couldn't match type '[]' with 'Maybe'";
    - `m150_applicative_above_monad`: "could not deduce 'Functor a'";
    - `m150_for_traversable`: "cannot find module
      'Data.Traversable'".
  - It shows `OVER-ACCEPT` for `multi/m150_monad_no_applicative`.
  - It shows `FAIL ... (wrong rejection)` for
    `multi/m150_applicative_no_functor`, which lacks the
    "required by" text and the hint.
  - `scripts/run_differential_types.sh` shows `OVER-ACCEPT` for both
    `bad_m150_*` files and `UNDER-ACCEPT` for `ok_m150_monad_context`.
- [ ] **Step 8: Commit.**

```
test(conformance): applicative above monad and traversable mapm, oracled against ghc 9.4.8 and failing until m150 phase c lands

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

---

### Task C3: Applicative is wired as Monad's superclass; `return = pure`

One task, because wiring `Applicative` and deleting the Prelude's
source class must land together. The Prelude cannot declare a class
the builtins already define.

**Files:**
- Modify: `src/ahc-builtins.ads:89-93` (the class-id fields)
- Modify: `src/ahc-builtins.adb:528-600` (insert the Applicative block
  between Functor `:528-551` and Monad `:553-600`; Monad gains the
  superclass; the `return` comment `:585-588`)
- Modify: `src/ahc-elaborate.adb:787-890` (Monad's `return` default)
  and `:908-909` (a new Applicative arm)
- Modify: `src/ahc-typechecker.adb`:
  - `:581-587` (delete `Same_Tv_Arg`);
  - `:659-682` (delete `Monad_Entails_In_GHC`, add `AMP_Hint` in its
    place);
  - `:2199-2233` (delete the derived-Monad check);
  - `:2347-2376` (the superclass check).
- Modify: `prelude/Prelude.hs:610-621` (the source `Applicative`
  class becomes its default helpers)
- Modify: `lib/Control/Applicative.hs:18-19` (comment)
- Test: `tests/src/test_typechecker.adb` (three `Check_Equal`s)

**Interfaces:**
- Produces:
  - `Env.Applicative_Cl : Core.Class_Id`, whose methods in dictionary
    order are `pure`, `<*>`, `liftA2`, `*>`, `<*`, with superclass
    `Functor`;
  - `Monad`'s superclasses are `[Applicative]`;
  - Prelude helpers `apDefault_`, `liftA2Default_`, `thenADefault_`,
    `thenLeftADefault_ :: Applicative f => ...` and
    `returnDefault_ :: Monad m => a -> m a`.
  - Task C4's `mapM = traverse` default relies on `Monad m` entailing
    `Applicative m`.

- [ ] **Step 1: `ahc-builtins.ads`.** In the record at `:89-93`
  (`Eq_Cl, Ord_Cl, Show_Cl, Functor_Cl, Monad_Cl, Num_Cl, Real_Cl,`),
  add `Applicative_Cl`:

```ada
      Eq_Cl, Ord_Cl, Show_Cl, Functor_Cl, Applicative_Cl, Monad_Cl,
      Num_Cl, Real_Cl,
      Fractional_Cl, Enum_Cl, Bounded_Cl,
      Integral_Cl, Floating_Cl, RealFrac_Cl, RealFloat_Cl,
      IsString_Cl
        : Core.Class_Id := Core.No_Class;
```

- [ ] **Step 2: `ahc-builtins.adb`, wire Applicative.** After the
  Functor block's `end;` (`:551`) and before `--  Monad (over m :: *
  -> *)` (`:553`), insert the block below. `Sup1` (`:443-449`) is in
  scope here, and Num uses `Sup2` from the same declarative part at
  `:606`. The type actuals mint type nodes in an unspecified order,
  exactly as the Functor and Monad blocks already do. Type ids never
  reach a golden, and no Var is minted among the actuals.
  `Def_Method` mints the selector inside its body.

```ada
         --  Applicative (Functor) over f :: * -> *. Wired since M150
         --  so that Monad can name it as its superclass (GHC 7.10's
         --  Applicative-Monad Proposal). The defaults of <*>, liftA2,
         --  *> and <* are Prelude source (apDefault_, liftA2Default_,
         --  thenADefault_, thenLeftADefault_), applied to the
         --  instance's own dictionary by AHC.Elaborate.
         declare
            Cl : constant Real_Class_Id :=
              Def_Class ("Applicative", Star1, Sup1 (Env.Functor_Cl));
            F  : constant Real_TyVar_Id :=
              M.Mint_TyVar ((Name => Table.Intern ("f"),
                             Tv_Kind => Kind_Id (Star1)));
            A  : constant Real_TyVar_Id := New_Tv ("a");
            B  : constant Real_TyVar_Id := New_Tv ("b");
            C  : constant Real_TyVar_Id := New_Tv ("c");

            --  f t
            function FA (T : Real_TyVar_Id) return Real_Type_Id
            is (AP (TV (F), TV (T)));

            --  The class variable first: the typechecker reads
            --  Tvs (1) as the instance head's position.
            function Sch4 (T : Real_Type_Id) return Real_Scheme_Id is
               Tvs : TyVar_Id_Vectors.Vector;
            begin
               Tvs.Append (F);
               Tvs.Append (A);
               Tvs.Append (B);
               Tvs.Append (C);
               return M.Add (Scheme'(Tvs => Tvs,
                                     Context => Ctx1 (Cl, TV (F)),
                                     S_Body => Type_Id (T)));
            end Sch4;
         begin
            Env.Applicative_Cl := Class_Id (Cl);
            Ignore := Def_Method
              (Cl, "pure", Sch4 (FN (TV (A), FA (A))), False);
            Ignore := Def_Method
              (Cl, "<*>",
               Sch4 (FN (AP (TV (F), FN (TV (A), TV (B))),
                         FA (A), FA (B))), True);
            Ignore := Def_Method
              (Cl, "liftA2",
               Sch4 (FN (FN (TV (A), TV (B), TV (C)),
                         FA (A), FN (FA (B), FA (C)))), True);
            Ignore := Def_Method
              (Cl, "*>", Sch4 (FN (FA (A), FA (B), FA (B))), True);
            Ignore := Def_Method
              (Cl, "<*", Sch4 (FN (FA (A), FA (B), FA (A))), True);
            Finish_Class (Cl);
         end;
```

- [ ] **Step 3: `ahc-builtins.adb`, Monad's superclass and comment.**
  - At `:555`, change
    `Cl : constant Real_Class_Id := Def_Class ("Monad", Star1);` to:

```ada
            Cl : constant Real_Class_Id :=
              Def_Class ("Monad", Star1, Sup1 (Env.Applicative_Cl));
```

  - Replace the comment at `:585-588`:

```ada
            --  return defaults to pure (base's shape; AHC.Elaborate
            --  solves Applicative at the instance head), so a modern
            --  instance omitting it draws no warning.
```

    with:

```ada
            --  return defaults to pure (base's shape): AHC.Elaborate
            --  applies the Prelude's returnDefault_ to the instance's
            --  own dictionary, which reaches pure through the
            --  Applicative superclass (M150).
```

  Wired `Monad []`/`IO`/`Maybe` dictionaries need no change.
  `Prelude_Core.Give_Dict` (`src/ahc-prelude_core.adb:388-424`)
  already fills each superclass slot from the superclass's instance
  at the same head. Here that is the Prelude's source
  `instance Applicative []`/`IO`/`Maybe` (`prelude/Prelude.hs:623-634`),
  which exist by `Install_Bodies` time (`src/ahc_main.adb:1342`, after
  typechecking).
- [ ] **Step 4: `ahc-elaborate.adb`, the defaults.** In
  `Builtin_Default`, replace the whole `when 3 =>` arm of the Monad
  case: from `when 3 =>` and its comment
  `--  return = pure, base's default:` (`:787`) through the `end;` /
  `end;` pair that closes it (`:889-890`), just before `when 4 =>`
  (`:891`). It currently looks `Applicative` up by name, scans its
  instances with `Match_EL`, adds the "required by the default for
  'return'" error, and returns `pure` applied to `Solve_Ev`. The
  replacement:

```ada
                                 when 3 =>
                                    --  return = pure, base's default
                                    --  (M150): the Prelude's
                                    --  returnDefault_ applied to this
                                    --  dictionary takes pure through
                                    --  the Applicative superclass,
                                    --  whose instance the typechecker
                                    --  has already demanded.
                                    declare
                                       F : constant Expr_Id :=
                                         Global_Named ("returnDefault_");
                                    begin
                                       if F = No_Expr then
                                          return No_Expr;
                                       end if;
                                       return Expr_Id
                                         (Ap2E (Real_Expr_Id (F),
                                                V2 (Self_D)));
                                    end;
```

  Then, between the Monad case's `end case;` (`:908`) and
  `elsif (Inst.Of_Class = Env.Enum_Cl` (`:909`), add:

```ada
                           elsif Inst.Of_Class = Env.Applicative_Cl
                             and then MI in 2 .. 5
                           then
                              --  base's Applicative defaults, Prelude
                              --  source (apDefault_ ...), applied to
                              --  this dictionary (M150).
                              declare
                                 F : constant Expr_Id :=
                                   Global_Named
                                     ((case MI is
                                         when 2 => "apDefault_",
                                         when 3 => "liftA2Default_",
                                         when 4 => "thenADefault_",
                                         when others =>
                                           "thenLeftADefault_"));
                              begin
                                 if F = No_Expr then
                                    return No_Expr;
                                 end if;
                                 return Expr_Id
                                   (Ap2E (Real_Expr_Id (F), V2 (Self_D)));
                              end;
```

  `Match_EL` stays referenced at `:254` and `:274`, and `Bag` at
  `:336`, so the deletion leaves no unreferenced entity. The semantic
  check confirms it.
- [ ] **Step 5: `prelude/Prelude.hs`, the class becomes its
  defaults.** Replace `:610-621`:

```haskell
-- Applicative, as GHC's base has it (the Report predates it); an
-- ordinary source class over the wired Functor.
class Functor f => Applicative f where
  pure :: a -> f a
  (<*>) :: f (a -> b) -> f a -> f b
  liftA2 :: (a -> b -> c) -> f a -> f b -> f c
  liftA2 f x y = fmap f x <*> y
  (*>) :: f a -> f b -> f b
  (*>) x y = liftA2 (\_ b -> b) x y
  (<*) :: f a -> f b -> f a
  (<*) x y = liftA2 (\a _ -> a) x y
```

  with:

```haskell
-- Applicative is wired (AHC.Builtins, M150) as Monad's superclass, as
-- GHC's base has it since 7.10: class Functor f => Applicative f with
-- pure, (<*>), liftA2, (*>), (<*). These are its class defaults, and
-- Monad's `return`; AHC.Elaborate applies each to the instance's own
-- dictionary. Minimal definition, as base's: pure, ((<*>) | liftA2).
apDefault_ :: Applicative f => f (a -> b) -> f a -> f b
apDefault_ fs xs = liftA2 id fs xs

liftA2Default_ :: Applicative f => (a -> b -> c) -> f a -> f b -> f c
liftA2Default_ f x y = fmap f x <*> y

thenADefault_ :: Applicative f => f a -> f b -> f b
thenADefault_ x y = liftA2 (\_ b -> b) x y

thenLeftADefault_ :: Applicative f => f a -> f b -> f a
thenLeftADefault_ x y = liftA2 (\a _ -> a) x y

returnDefault_ :: Monad m => a -> m a
returnDefault_ x = pure x
```

  Leave `infixl 4 <$>, <$, <*>, *>, <*` (`:602`) alone. It names the
  wired operators by name, as the fixity seeding expects. Leave the
  export list alone too: `Applicative`, `pure`, `(<*>)`, `(*>)`,
  `(<*)` now resolve to the wired entities, as `Functor`/`fmap` do.
  `liftA2` stays unexported, as in GHC 9.4.8's Prelude.
- [ ] **Step 6: `ahc-typechecker.adb`.**
  - Delete `Same_Tv_Arg` (`:581-587`). Its only caller is
    `Monad_Entails_In_GHC`.
  - Replace `:659-682` (the comment `--  GHC's Monad has Applicative
    and Functor above it; AHC's (the` through
    `end Monad_Entails_In_GHC;`) with:

```ada
      --  M150: GHC 7.10 put Applicative above Monad, so a program
      --  written to the 2010 Report declares Monad alone. Spell the
      --  missing instance out (ap and liftM are Control.Monad's).
      --  Shown is the head as Type_Str printed it, computed once by
      --  the caller.
      function AMP_Hint
        (Of_Class, Missing : Class_Id; Shown : String) return String
      is
         Head : constant String :=
           (if (for some Ch of Shown => Ch = ' ')
            then "(" & Shown & ")" else Shown);
         Pad : constant String := ASCII.LF & "               ";
      begin
         if Missing = Env.Applicative_Cl
           and then Of_Class = Env.Monad_Cl
         then
            return ASCII.LF & "  hint: add  instance Applicative "
              & Head & " where" & Pad & "pure = return; (<*>) = ap";
         elsif Missing = Env.Functor_Cl
           and then (Of_Class = Env.Applicative_Cl
                     or else Of_Class = Env.Monad_Cl)
         then
            return ASCII.LF & "  hint: add  instance Functor "
              & Head & " where" & Pad & "fmap = liftM";
         end if;
         return "";
      end AMP_Hint;
```

  - Delete the derived-Monad block `:2199-2233`, from
    `--  A derived Monad needs an Applicative instance at the head,`
    through its closing `end if;`, leaving `Reduce (...)` followed by
    `GND_Active.Delete_Last;`. The general superclass check below
    covers GND instances (`Inst.Is_GND`, `:2318`), on heads resolved
    before any solving (`:2259-2263`).
  - Replace `:2347-2376`, from `for Super of M.Info (Real_Class_Id
    (Inst.Of_Class))` through the residual loop's `end loop;`, with
    the code below. `Probing` (`:87`) suppresses `Solve`'s own "no
    instance" text, so a superclass with no instance at a concrete
    head gets the same message as a residual one, plus the hint.
    `Shown` is hoisted, because `Type_Str` mints a scheme id.

```ada
                  --  Solved quietly (M150): a superclass with no
                  --  instance is reported once, below, naming the
                  --  instance declaration - with the missing
                  --  Applicative/Functor spelled out for a Monad or
                  --  Applicative instance (AMP_Hint).
                  declare
                     Was_Probing : constant Boolean := Probing;
                  begin
                     Probing := True;
                     for Super of M.Info (Real_Class_Id (Inst.Of_Class))
                                    .Supers
                     loop
                        W_List.Append
                          (Wanted_Rec'
                             (C => Constraint'
                                (Class => Super, Arg => Head_T,
                                 Span => Inst.Span),
                              others => <>));
                        Solve (W_List.Last_Index, 0);
                     end loop;
                     Probing := Was_Probing;
                  end;
                  --  No instance at all (By_Error), or a context
                  --  constraint the instance's own context does not
                  --  give (`instance Ord (T a)` beside `instance Eq a
                  --  => Eq (T a)`), which stays a residual (Unsolved).
                  for I in W_Mark + 1 .. W_List.Last_Index loop
                     if W_List (I).Sol in Unsolved | By_Error then
                        declare
                           Shown : constant String :=
                             Type_Str (W_List (I).C.Arg);
                           Missing : constant Class_Id :=
                             Class_Id (W_List (I).C.Class);
                        begin
                           Bag.Add (Diagnostics.Error,
                                    Diagnostics.Class_No_Instance,
                                    Inst.Span,
                                    "no instance for '"
                                    & Table.Text
                                        (M.Info (W_List (I).C.Class).Name)
                                    & " " & Shown
                                    & "', required by the superclasses"
                                    & " of an instance declaration"
                                    & AMP_Hint (Inst.Of_Class, Missing,
                                                Shown));
                        end;
                        exit;
                     end if;
                  end loop;
```

- [ ] **Step 7: `lib/Control/Applicative.hs`.** Replace the comment
  at `:18-19`:

```haskell
--  Applicative itself (with liftA2, *>, <*), <$> and <$ live in the
--  Prelude and are re-exported here as base's export list has them.
```

  with:

```haskell
--  Applicative itself (with liftA2, *>, <*) is wired in as Monad's
--  superclass (M150); it, <$> and <$ are re-exported here as base's
--  export list has them.
```

- [ ] **Step 8: Unit tests.** In `tests/src/test_typechecker.adb`,
  after "superclass given discharges Eq via Ord" (`:192-195`), add the
  checks below. The harness has no Prelude, but `fmap`, `pure`,
  `negate` and the classes are wired. The printer names type variables
  by first appearance in the body, so `m` prints as `a`, as `compose`
  shows at `:91-94`.

```ada
      --  M150: Monad m entails Applicative m and Functor m.
      Check_Equal
        (TC ("f :: Monad m => m Int -> m Int" & ASCII.LF
             & "f m = fmap negate m"),
         "f :: Monad a => a Int -> a Int",
         "Monad given discharges Functor via Applicative");
      Check_Equal
        (TC ("g :: Monad m => a -> m a" & ASCII.LF
             & "g x = pure x"),
         "g :: Monad b => a -> b a",
         "Monad given discharges Applicative");
      Check_Equal
        (TC ("data P a = P a" & ASCII.LF
             & "instance Functor P where" & ASCII.LF
             & "  fmap f (P a) = P (f a)" & ASCII.LF
             & "instance Monad P where" & ASCII.LF
             & "  P a >>= k = k a"),
         "!errors: 1",
         "Monad instance without Applicative rejected");
```

- [ ] **Step 9: Build and the fast checks.**
  - Semantic-check `ahc-builtins.adb`, `ahc-elaborate.adb` and
    `ahc-typechecker.adb`.
  - `alr build --validation`.
  - `cd tests && alr build --validation && ./bin/ahc_tests`: all pass,
    including the three new checks.
  - `scripts/run_gate.sh unit conformance exec exec-own prelude-exports userlib`.
    Expect every suite ok except `conformance`, which still has
    `BUILD-FAIL` for exactly `m150_traversable.hs` and
    `m150_for_traversable.hs` (Tasks C4/C5). Both
    `multi/m150_*` cases now print `ok ... (rejected)`, and
    `m150_applicative_above_monad.hs`, `lib_monadplus.hs`,
    `ch03_14_unfailable_bind.hs`, `m147r_monad_return_flexible.hs`
    (Monad instances without `return`) and
    `multi/m75_user_applicative` stay ok.
  - `scripts/run_differential_types.sh`:
    `bad_m150_monad_no_applicative` and
    `bad_m147r_gnd_monad_no_applicative` are `ok` (rejected);
    `ok_m150_monad_context` stays `UNDER-ACCEPT` until C4 (its `mapM`
    at Maybe).
- [ ] **Step 10: The golden audit.** Write
  `$SCRATCH/golden_audit.py`. Task C4 uses it again.

```python
#!/usr/bin/env python3
# Golden audit (M150 phase C): compare each committed Core golden
# (git HEAD) with the regenerated one, one top-level group per line,
# entity ids stripped, and name every group that changed. A changed
# group whose binder does not match ALLOW is UNEXPLAINED.
#   python3 -I golden_audit.py 'ALLOW-REGEX'
import glob, re, subprocess, sys
from collections import Counter

allow = re.compile(sys.argv[1])

def groups(text):
    return Counter(re.sub(r"_[0-9]+", "", l) for l in text.split("\n") if l)

def binder(line):
    m = re.match(r"\((?:bind|bindrec) \(+(\S+)", line)
    return m.group(1) if m else line[:60]

bad = False
for path in sorted(glob.glob("tests/golden/*.core")):
    old = subprocess.run(["git", "show", "HEAD:" + path],
                         capture_output=True, text=True, check=True).stdout
    new = open(path).read()
    o, n = groups(old), groups(new)
    for nm in sorted({binder(l) for l in (o - n) + (n - o)}):
        ok = bool(allow.search(nm))
        bad |= not ok
        print(("ok          " if ok else "UNEXPLAINED ") + path + ": " + nm)
sys.exit(1 if bad else 0)
```

  Then:

```sh
alr build --release
scripts/run_golden.sh                 # FAIL only for core_*.core
scripts/run_golden.sh --update
python3 -I $SCRATCH/golden_audit.py \
  '^\$d(Monad|Applicative|Functor)|^(liftA2|\*>|<\*|<\*>|apDefault_|liftA2Default_|thenADefault_|thenLeftADefault_|returnDefault_)$'
git diff --stat tests/golden          # only the three core_*.core
alr build --validation && scripts/run_golden.sh   # all ok
```

  The audit must exit 0. These are the expected changes, line by
  line, and the commit message lists them:
  - every `$dMonad…` dictionary (`Either`, `(->)`) gains one leading
    `app` field holding its `$dApplicative…` dictionary;
  - the lifted source-class defaults `liftA2`, `*>`, `<*` (today's
    `(bindrec (liftA2_877 …`, `*>_881`, `<*_885`) disappear;
  - `$dApplicative…` dictionaries reference
    `liftA2Default_`/`thenADefault_`/`thenLeftADefault_` (and
    `apDefault_` where `<*>` is omitted) applied to `$dSelf`;
  - `returnDefault_` and the helpers appear where the Prelude's
    groups are dumped.

  Any `UNEXPLAINED` line is a regression to investigate, not to
  allowlist.
- [ ] **Step 11: Commit.**

```
feat(classes): applicative is wired as monad's superclass, return defaults to pure, and a monad without applicative is told what to add

Core goldens change beyond renumbering: Monad dictionaries gain the
Applicative superclass field, and the lifted liftA2/*>/<* class
defaults become applications of the Prelude's liftA2Default_ /
thenADefault_ / thenLeftADefault_ to the dictionary.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

---

### Task C4: Traversable takes base's shape; pairs are Functor/Foldable/Traversable

**Files:**
- Modify: `prelude/Prelude.hs:10` (`NOT-METHODS`)
- Modify: `prelude/Prelude.hs:432-442` (list-only `mapM`/`sequence`)
- Modify: `prelude/Prelude.hs:1398-1421` (`Traversable`)
- Test: covered by C2's `ok_m150_monad_context`,
  `bad_m150_traversable_no_foldable`, the pair lines of
  `m150_traversable`, and `scripts/check_prelude_exports.sh` (class
  membership)

**Interfaces:**
- Consumes: `Env.Applicative_Cl` as Monad's superclass (C3), because
  the `mapM = traverse` default needs `Monad m` to entail
  `Applicative m`. Also C1's `(,)` type, and
  `$SCRATCH/golden_audit.py` (C3, step 10).
- Produces:

```haskell
class (Functor t, Foldable t) => Traversable t where
  traverse  :: Applicative f => (a -> f b) -> t a -> f (t b)
  sequenceA :: Applicative f => t (f a) -> f (t a)
  mapM      :: Monad m => (a -> m b) -> t a -> m (t b)
  sequence  :: Monad m => t (m a) -> m (t a)
```

  It has instances `[]`, `Maybe`, `Either a`, `((,) a)` here, and
  `Functor ((,) a)`, `Foldable ((,) a)`. Task C5 adds `Identity` and
  `Array`; `Map k` already exists
  (`lib/Data/Map/Internal.hs:890-891`).

- [ ] **Step 1:** the export-checker line `:10`:

```haskell
-- NOT-METHODS: <$ divMod quotRem mapM sequence sequenceA
```

  becomes:

```haskell
-- NOT-METHODS: <$ divMod quotRem
```

- [ ] **Step 2:** replace `:432-434` (list-only `mapM`):

```haskell
mapM :: Monad m => (a -> m b) -> [a] -> m [b]
mapM _ [] = return []
mapM f (x : xs) = f x >>= \y -> mapM f xs >>= \ys -> return (y : ys)
```

  with the list instance's direct `mapM` (deviation 3):

```haskell
-- The list instance's mapM (M150): the Report's direct monadic
-- recursion, one bind per element, where traverse goes through <*>
-- (two binds in IO). Equal to traverse for every lawful monad.
mapMListR_ :: Monad m => (a -> m b) -> [a] -> m [b]
mapMListR_ _ [] = return []
mapMListR_ f (x : xs) =
  f x >>= \y -> mapMListR_ f xs >>= \ys -> return (y : ys)
```

  Delete `:441-442`:

```haskell
sequence :: Monad m => [m a] -> m [a]
sequence ms = mapM (\m -> m) ms
```

  Keep `mapMList__` (`:436-439`) and `sequenceList__` (`:444-446`).
  `mapM_`/`sequence_` (`:1392-1396`) use them.
- [ ] **Step 3:** replace `:1398-1421`, from `-- Traversable
  (base-compat beyond the 2010 Report, like Applicative` through the
  `instance Traversable (Either a)` body, with:

```haskell
-- Traversable, base's shape (M150): mapM and sequence are methods, so
-- they work over every Traversable, not only lists. Minimal definition
-- as base's: traverse | sequenceA.
class (Functor t, Foldable t) => Traversable t where
  traverse :: Applicative f => (a -> f b) -> t a -> f (t b)
  traverse f t = sequenceA (fmap f t)
  sequenceA :: Applicative f => t (f a) -> f (t a)
  sequenceA t = traverse id t
  mapM :: Monad m => (a -> m b) -> t a -> m (t b)
  mapM f t = traverse f t
  sequence :: Monad m => t (m a) -> m (t a)
  sequence t = sequenceA t

instance Traversable [] where
  traverse f = foldrList_ (\x acc -> pure (:) <*> f x <*> acc) (pure [])
  mapM f xs = mapMListR_ f xs
  sequence ms = mapMListR_ id ms

instance Traversable Maybe where
  traverse _ Nothing = pure Nothing
  traverse f (Just x) = pure Just <*> f x

instance Traversable (Either a) where
  traverse _ (Left e) = pure (Left e)
  traverse f (Right x) = pure Right <*> f x

-- Pairs over their second component, as base: fmap (+1) ("k", 1) is
-- ("k", 2) and length (x, y) is 1.
instance Functor ((,) a) where
  fmap f (x, y) = (x, f y)

instance Foldable ((,) a) where
  foldr f z (_, y) = f y z
  null _ = False
  length _ = 1

instance Traversable ((,) a) where
  traverse f (x, y) = fmap (\y' -> (x, y')) (f y)
```

  Derived Traversable (`src/ahc-derive_functor.adb`) synthesizes only
  `traverse`. `sequenceA`/`mapM`/`sequence` come from these defaults
  through Elaborate's ordinary `Default_Binds` path, so the M148
  deriving programs (`ext_derive_traversable`, `m148r_derive_*`) need
  no change. Each already derives `Foldable` beside `Traversable`.
- [ ] **Step 4: Verify.**
  - `alr build --validation`.
  - `scripts/check_prelude_exports.sh` prints `prelude exports ok`.
    The membership probe now binds `traverse`/`sequenceA`/`mapM`/
    `sequence` in one `Traversable` instance, with no "is not a method
    of the class".
  - `scripts/run_gate.sh unit conformance exec exec-own userlib`: all
    ok except `BUILD-FAIL` for `m150_traversable.hs` (needs C5's
    `Foldable Identity`) and `m150_for_traversable.hs` (needs
    `Data.Traversable`). `lib_traversable.hs`, `lib_map_api.hs`,
    `lib_foldable.hs`, `ext_derive_traversable.hs` and every
    `m148r_derive_*` stay ok.
  - `scripts/run_differential_types.sh`: all `ok`, including
    `ok_m150_monad_context` and `bad_m150_traversable_no_foldable`.
  - goldens:

```sh
alr build --release
scripts/run_golden.sh --update
python3 -I $SCRATCH/golden_audit.py \
  '^\$d(Traversable|Foldable|Functor)|^(traverse|sequenceA|mapM|sequence|mapMListR_)$'
alr build --validation && scripts/run_golden.sh
```

    The audit must exit 0. The expected changes:
    - `$dTraversable…` dictionaries gain a `Foldable` superclass field
      and three method fields;
    - the lifted defaults `traverse`, `sequenceA`, `mapM`, `sequence`
      appear;
    - top-level `mapM`/`sequence`/`sequenceA` are gone;
    - `$dFunctor(,)`/`$dFoldable(,)`/`$dTraversable(,)` are new.
- [ ] **Step 5: Commit.**

```
feat(prelude): traversable takes base's shape, with mapm and sequence as its methods, and pairs are functor, foldable and traversable

Core goldens change beyond renumbering: Traversable dictionaries gain
the Foldable superclass and the sequenceA/mapM/sequence fields, and
the list-only mapM/sequence/sequenceA groups are gone.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

---

### Task C5: `Data.Traversable`, general `forM`/`forM_`, Identity and Array instances

**Files:**
- Create: `lib/Data/Traversable.hs`
- Modify: `lib/Control/Monad.hs:12-13` (imports) and `:50-56` (`forM`,
  `forM_`)
- Modify: `lib/Data/Functor/Identity.hs` (after `:16`)
- Modify: `lib/Data/Array.hs` (after `:68`)

**Interfaces:**
- Consumes: C4's `Traversable` class.
- Produces:
  - `Data.Traversable (Traversable (..), for, forM, mapAccumL,
    mapAccumR)`;
  - `Control.Monad.forM :: (Traversable t, Monad m) => t a ->
    (a -> m b) -> m (t b)` (re-exported, the same entity as
    `Data.Traversable.forM`);
  - `Control.Monad.forM_` is `Data.Foldable.forM_`;
  - instances `Foldable`/`Traversable Identity` and
    `Functor`/`Foldable`/`Traversable Array`.

- [ ] **Step 1:** create `lib/Data/Traversable.hs`:

```haskell
module Data.Traversable
  ( Traversable (..)
  , for, forM
  , mapAccumL, mapAccumR
  ) where

--  GHC 9.4.8's Data.Traversable, minus fmapDefault/foldMapDefault.
--  The class itself is the Prelude's (base's shape since M150, with
--  mapM and sequence as methods).

for :: (Traversable t, Applicative f) => t a -> (a -> f b) -> f (t b)
for t f = traverse f t

forM :: (Traversable t, Monad m) => t a -> (a -> m b) -> m (t b)
forM t f = mapM f t

--  State threaded left to right (base's StateL) ...
newtype StateL_ s a = StateL_ (s -> (s, a))

runStateL_ :: StateL_ s a -> s -> (s, a)
runStateL_ (StateL_ k) = k

instance Functor (StateL_ s) where
  fmap f (StateL_ k) = StateL_ (\s -> let (s', v) = k s in (s', f v))

instance Applicative (StateL_ s) where
  pure x = StateL_ (\s -> (s, x))
  StateL_ kf <*> StateL_ kv =
    StateL_ (\s -> let (s', f) = kf s
                       (s'', v) = kv s'
                   in (s'', f v))

--  ... and right to left (base's StateR).
newtype StateR_ s a = StateR_ (s -> (s, a))

runStateR_ :: StateR_ s a -> s -> (s, a)
runStateR_ (StateR_ k) = k

instance Functor (StateR_ s) where
  fmap f (StateR_ k) = StateR_ (\s -> let (s', v) = k s in (s', f v))

instance Applicative (StateR_ s) where
  pure x = StateR_ (\s -> (s, x))
  StateR_ kf <*> StateR_ kv =
    StateR_ (\s -> let (s', v) = kv s
                       (s'', f) = kf s'
                   in (s'', f v))

mapAccumL :: Traversable t => (s -> a -> (s, b)) -> s -> t a -> (s, t b)
mapAccumL f s t = runStateL_ (traverse (\a -> StateL_ (\s' -> f s' a)) t) s

mapAccumR :: Traversable t => (s -> a -> (s, b)) -> s -> t a -> (s, t b)
mapAccumR f s t = runStateR_ (traverse (\a -> StateR_ (\s' -> f s' a)) t) s
```

- [ ] **Step 2:** `lib/Control/Monad.hs`. After
  `import Control.Applicative (Alternative (..))` (`:13`), add:

```haskell
import Data.Foldable (forM_)
import Data.Traversable (forM)
```

  Replace `:50-56`:

```haskell
--  mapM/mapM_/sequence/sequence_ are the Prelude's, re-exported.

forM :: Monad m => [a] -> (a -> m b) -> m [b]
forM xs f = mapM f xs

forM_ :: Monad m => [a] -> (a -> m b) -> m ()
forM_ xs f = mapM_ f xs
```

  with:

```haskell
--  mapM/mapM_/sequence/sequence_ are the Prelude's, re-exported; forM
--  is Data.Traversable's and forM_ is Data.Foldable's, so importing
--  Control.Monad beside either module names one entity (M150).
```

  The export list (`:1-11`) is unchanged. Data.Foldable and
  Data.Traversable import nothing but the Prelude, so there's no
  import cycle.
- [ ] **Step 3:** `lib/Data/Functor/Identity.hs`, after the `Monad
  Identity` instance (`:14-16`):

```haskell
instance Foldable Identity where
  foldr f z (Identity a) = f a z
  null _ = False
  length _ = 1

instance Traversable Identity where
  traverse f (Identity a) = fmap Identity (f a)
```

- [ ] **Step 4:** `lib/Data/Array.hs`, after the `Eq (Array e)`
  instance (`:67-68`). Deviation 2 applies: the head is `Array`.

```haskell
--  base's instances over the elements, in index order (M150).
instance Functor Array where
  fmap f (MkArray b es) = MkArray b (map f es)

instance Foldable Array where
  foldr f z (MkArray _ es) = foldr f z es
  null (MkArray _ es) = null es
  length (MkArray _ es) = length es

instance Traversable Array where
  traverse f (MkArray b es) = fmap (MkArray b) (traverse f es)
```

  Phase E edits this file's error texts (`:31`, `:37`, `:21`). These
  instances touch other lines, so the two phases merge cleanly.
- [ ] **Step 5: Verify.**
  - `scripts/run_gate.sh`: `GATE ok`, every suite.
    `m150_traversable.hs` and `m150_for_traversable.hs` are now ok,
    and so is the rest of the conformance set, the `lib_*` programs
    included.
  - `AHC_GC=own scripts/run_conformance.sh`: all ok.
  - `scripts/run_separate.sh` and `scripts/run_repl.sh`: rc 0. They
    import `Control.Monad` across module boundaries and at the prompt.
  - `scripts/run_examples.sh`: rc 0.
- [ ] **Step 6: Commit.**

```
feat(lib): data.traversable, forM and forM_ over any traversable, and identity and array are traversable as in base

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

---

### Task C6: bench - `mapM` as a class method costs nothing measurable

**Files:**
- Create: `tests/bench/b_mapm.hs`
- Create: `$SCRATCH/ab_bench.sh` (not committed)

- [ ] **Step 1:** create `tests/bench/b_mapm.hs`. It builds on v1.20
  too, where `mapM` is list-only, so the A/B measures the class
  dispatch directly.

```haskell
-- M150: mapM and sequence are Traversable methods. This pins their
-- cost over lists in Maybe and IO (the [] instance's direct monadic
-- mapM), which the class dispatch must not slow down.
step :: Int -> Maybe Int
step x = if x < 0 then Nothing else Just (x * 2)

main :: IO ()
main = do
  let xs = [1 .. 100000] :: [Int]
  print (fmap sum (mapM step xs))
  print (fmap length (sequence (map Just xs)))
  ys <- mapM (\x -> return (x + 1)) xs
  print (sum ys)
```

  Expected output (GHC 9.4.8 and AHC v1.20 agree):

```
Just 10000100000
Just 100000
5000150000
```

- [ ] **Step 2:** the v1.20 baseline compiler:

```sh
git worktree add $SCRATCH/ahc-v120 v1.20
(cd $SCRATCH/ahc-v120 && alr build --release)
alr build --release        # this tree, at C5's commit
```

- [ ] **Step 3:** write `$SCRATCH/ab_bench.sh`. It uses
  `run_bench.sh`'s method: interleaved best of 5, one warm-up each.

```bash
#!/usr/bin/env bash
# A/B wall time of every tests/bench program built by two compilers.
#   ab_bench.sh OLD_AHC NEW_AHC   (run from the NEW tree's root)
set -u
OLD=$1; NEW=$2
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
now_ms() { python3 -c 'import time; print(int(time.time()*1000))'; }
printf '%-14s %9s %9s %8s\n' program old new delta
for hs in tests/bench/*.hs; do
  b=$(basename "$hs" .hs)
  "$OLD" build "$hs" "$tmp/${b}_old" >/dev/null 2>&1 || { echo "$b: OLD build failed"; continue; }
  "$NEW" build "$hs" "$tmp/${b}_new" >/dev/null 2>&1 || { echo "$b: NEW build failed"; exit 1; }
  diff <("$tmp/${b}_old") <("$tmp/${b}_new") >/dev/null \
    || { echo "$b: OUTPUT MISMATCH"; exit 1; }
  ba=999999999; bb=999999999
  "$tmp/${b}_old" >/dev/null; "$tmp/${b}_new" >/dev/null
  for _ in 1 2 3 4 5; do
    t0=$(now_ms); "$tmp/${b}_old" >/dev/null; t1=$(now_ms)
    [ $((t1-t0)) -lt $ba ] && ba=$((t1-t0))
    t0=$(now_ms); "$tmp/${b}_new" >/dev/null; t1=$(now_ms)
    [ $((t1-t0)) -lt $bb ] && bb=$((t1-t0))
  done
  printf '%-14s %8sms %8sms %7s%%\n' "$b" "$ba" "$bb" \
    "$(python3 -c "print(f'{($bb-$ba)*100/$ba:+.1f}')")"
done
```

- [ ] **Step 4:** run it:
  `bash $SCRATCH/ab_bench.sh $SCRATCH/ahc-v120/bin/ahc ./bin/ahc`.
  The budget is +2% on the sequential programs: `b_bignum`, `b_fib`,
  `b_map`, `b_mapm`, `b_sort`, `b_strictfold`, `b_strings`,
  `b_sumfold`, `b_text`. The parallel `b_par*` programs are recorded,
  not budgeted. On a miss, re-run once to rule out noise. If `b_mapm`
  still misses, the dictionary path is the suspect: the `[]`
  instance's `mapM` must be `mapMListR_` (C4 step 3). Inspect
  `./bin/ahc core tests/bench/b_mapm.hs` for a `traverse`
  application. Paste the table into the C6 commit message body and
  keep it for the write-up.
- [ ] **Step 5:** `scripts/run_bench.sh` still passes, since its
  opt/no-opt agreement check covers `b_mapm`.
- [ ] **Step 6: Commit.**

```
test(bench): b_mapm pins the cost of mapm and sequence as traversable methods

<the ab_bench table, v1.20 vs this commit>

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

  Then remove the worktree: `git worktree remove $SCRATCH/ahc-v120`.

---

### Task C7: EXCLUSIONS, and the phase gate

**Files:**
- Modify: `tests/conformance/EXCLUSIONS.md` (rows at `:12`, `:19`,
  `:31`, `:45`, `:50`)

- [ ] **Step 1:** five exact replacements. Each "old" string occurs
  exactly once, as checked with `grep -cF` while planning.
  - `:12`: delete
    ``; `mapM`/`sequence` are list-only; there is no `Foldable ((,) a)` ``.
  - `:19`: replace
    ``; `Monad` does NOT have `Applicative` as superclass (the 2010 shape - `return` and `pure` are separate but agree), BUT a Monad instance omitting `return` gets base's default: the whole-program frontend solves Applicative at the instance head and takes its `pure` (lib_monadplus.hs)``
    with
    ``; since M150 `Applicative` is `Monad`'s superclass as in base (GHC 7.10's AMP): a `Monad` instance without an `Applicative` instance is rejected with a hint naming the instance to add (multi/m150_monad_no_applicative, multi/m150_applicative_no_functor), `pure`/`<*>`/`fmap` work under `Monad m =>` alone, and `return` defaults to `pure` (m150_applicative_above_monad.hs, lib_monadplus.hs)``.
  - `:31`: delete
    `` Found in passing: base's `instance Functor ((,) a)` is absent (`fmap f (a, s)`)``.
  - `:45`: replace
    ``absent: `fold` and the rest of base's Monoid half (`foldMap'`, `foldr'` as methods), `Foldable` for tuples (base's `length (1,2) == 1` wart), and `Traversable` is still its own small class rather than a `Foldable` subclass.``
    with
    ``absent: `fold` and the rest of base's Monoid half (`foldMap'`, `foldr'` as methods). Since M150 `Traversable` has base's shape, `class (Functor t, Foldable t) => Traversable t` with `traverse`/`sequenceA`/`mapM`/`sequence`, and instances for `[]`, `Maybe`, `Either a`, `((,) a)`, `Identity`, `Map k` and `Data.Array`'s `Array` (no `Set`, as base has none); pairs are `Functor`/`Foldable` as in base (`length (1,2) == 1`); `Data.Traversable` has `for`/`forM`/`mapAccumL`/`mapAccumR`, and `Control.Monad`'s `forM`/`forM_` are the general ones (m150_traversable.hs, m150_for_traversable.hs).``
  - `:50`: replace
    ``with two GHC-shaped exemptions that leave the old run-time gap: `Num`'s Report superclasses `Eq`/`Show` (GHC dropped them, so `instance Num D` alone is legal), and a `Functor`/`Applicative`-like superclass context on a variable the instance context gives `Monad` (GHC's Monad entails them; AHC's 2010-shaped Monad does not) - such a superclass dictionary is still missing at run time if it is ever used``
    with
    ``with one GHC-shaped exemption that leaves the old run-time gap: `Num`'s Report superclasses `Eq`/`Show` (GHC dropped them, so `instance Num D` alone is legal) - such a superclass dictionary is still missing at run time if it is ever used``.
- [ ] **Step 2:** check that no stale claim survives:
  `grep -n "list-only\|does NOT have .Applicative\|Monad_Entails" tests/conformance/EXCLUSIONS.md src/*.adb lib/Control/Monad.hs`.
  It must print nothing about `mapM`, `sequence`, `forM` or Monad's
  superclass. Data.Bits and `asum` stay list-only, and those mentions
  are correct.
- [ ] **Step 3: the phase gate.** Run all of the following, unpiped,
  on the validation build unless stated:
  - `scripts/run_gate.sh` prints `GATE ok`. That is unit,
    conformance, exec, exec-own, golden, prelude-exports and userlib.
  - `AHC_GC=own scripts/run_conformance.sh`: all ok.
  - `scripts/run_differential.sh` and
    `scripts/run_differential_types.sh`: rc 0.
  - `alr build --release && scripts/run_gate.sh golden conformance`:
    ok on the release build too.
  - `scripts/run_separate.sh`, `scripts/run_repl.sh`,
    `scripts/run_examples.sh`, `scripts/run_export.sh`: rc 0.
  - `scripts/run_fuzz.sh 50`: rc 0.
  - The C6 bench table is within budget.
- [ ] **Step 4: Commit.**

```
docs(exclusions): monad has applicative above it and mapm is traversable's, so the 2010-shape clauses go

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

**Gate C:** full suites both GC modes; differential parse + types;
conformance (oracled) - `mapM`/`sequence`/`traverse` over `Maybe`,
`Either`, `Map`, a user `Traversable`, tuples, `Array`; `pure`/`<*>`/
`fmap` used under `Monad m =>` alone; `forM` over `Maybe`; negative
corpus - a Monad without Applicative (pins the hint); Core golden diffs
explained line by line (the Monad dictionary shape changes, so the diff
is not renumber-only); bench delta, 2% budget on the sequential
benchmarks.

Concretely:
- `run_gate.sh` reports `GATE ok`, and `AHC_GC=own run_conformance.sh`
  passes;
- `run_differential.sh` and `run_differential_types.sh` pass;
- the conformance programs are `m150_traversable`,
  `m150_applicative_above_monad`, `m150_for_traversable` and
  `m150_tuple_tycon`;
- the negative cases are `multi/m150_monad_no_applicative` and
  `multi/m150_applicative_no_functor` (expected.err pins the hint),
  plus `corpus-types/bad_m150_*`;
- the golden audits (C3 step 10, C4 step 4) exit 0 on the release
  build, and the validation build reproduces the goldens;
- the `ab_bench.sh` table against v1.20 is within +2% on `b_bignum`,
  `b_fib`, `b_map`, `b_mapm`, `b_sort`, `b_strictfold`, `b_strings`,
  `b_sumfold` and `b_text`.

## Phase D - deriving and structural equality

Spec items D1 (structural dictionaries), D2 (inferred derived contexts)
and D3 (deriving-clause spans, derived `Enum`'s call stack). Phase C
lands first. D does not depend on C's details. Two places touch the
same code, and the tasks below say how to merge each one:
`Give_Dict`'s superclass loop (Task D3) and the superclass-check
message in the typechecker (Task D5).

**Line numbers** are those of commit `23cdddf`, before phases A-C.
Every edit also quotes the code it replaces. Find that code by its
text when phases A-C have shifted the lines.

### Phase-local constraints

- No Prelude or `lib/` edits in this phase. Every new helper is Core
  that `AHC.Prelude_Core` builds, so the Core goldens are not
  renumbered by D. `run_golden.sh` must show only the new `check_m150_*`
  golden.
- `runtime/ahc_rts.c`/`.h` change in Task D4. They are gate inputs:
  no suite may run while they are edited.
- Ada: one node-minting call per statement in all new
  `Prelude_Core` code. Two `V (...)`/`Ap (...)`/`Fresh (...)` calls
  must never be actuals of the same call; hoist them into constants.
  `M` (in out) and an `M.Info (...)` read must never be actuals of the
  same call either; copy the `Instance_Info` into a constant first.
- Semantic-check every changed unit before building:
  `alr exec -- gcc -c -gnatc -gnat2022 -gnatwa -Isrc src/X.adb -o $SCRATCH/ck/X.o`.
- `SCRATCH=/tmp/m150-d` (create it with `mkdir -p $SCRATCH/ck`). The
  bench baseline from Task D1 lives there until the gate.

### The D1 design decision: how a dictionary knows it is structural

**Today.** Every wired and derived `Eq`/`Ord` dictionary gets the same
structural primitives (`primeq` = `ahc_prim_eq_poly`, `primcompare` =
`ahc_prim_compare_poly`). `Give_Dict` takes one lambda per context
constraint and ignores them. A dictionary is a constructor node
`MkDict$C supers... methods...` (`Core.Mk_Dict`, `src/ahc-core.adb:235`).
At run time it is an `AHC_CON` node whose fields are the superclass
dictionaries and then the methods. A reference to a prim compiles to
its C global (`codegen` maps prim vars to symbols,
`src/ahc-codegen.adb:1576-1588`). Each such global is one heap node
built once by `mk_prim2` (`runtime/ahc_rts.c:8836-8837`). Both
collectors are non-moving.

**Options considered.**

1. *Fully static, at compile time.* Prelude_Core decides at every
   dictionary construction site from the concrete field types. This is
   impossible for a type-variable element: `f :: Eq a => [a] -> ...`
   builds `$dEqList d_a` with `d_a` a run-time parameter.
2. *An extra dictionary field or a hidden class method `$structural`.*
   This changes the `Eq`/`Ord` class shape that every source instance,
   Elaborate's dictionary arity (`Mk_Dict`'s precondition), the class
   printer and the goldens see. It is too invasive for one flag.
3. *Method identity (chosen).* A dictionary is structural **exactly
   when its `==` (for `Eq`) or `compare` (for `Ord`) is the one global
   structural primitive node**. Only Prelude_Core's structural builder
   ever puts that node there. A source instance cannot name the prim.
   A GND dictionary *is* its representation's, so it inherits the
   answer. The run-time test is one new primitive,
   `primSameFun a b = (eval a == eval b)`, a pointer comparison.

**The chosen mechanism, in full.**

- *Compile time (`Solve_Needs`, a fixpoint before the instance loop).*
  Each derived `Eq`/`Ord` instance gets a **Need**: either `Never`
  (some field reaches a hand-written instance or a function), or the
  set of its context positions whose dictionaries must be structural.
  Each field type is analysed:
  - a type variable gives its context position;
  - a base wired instance (`Int`, `Char`, `Double`, `Text`, `Ptr`, ...)
    needs nothing;
  - a wired `[a]`/`Maybe a`/`(a,b)` needs all of its arguments;
  - a derived instance needs its own Need, composed through its
    arguments;
  - a GND instance needs whatever its representation needs;
  - a source instance or a function type is `Never`.

  The fixpoint starts optimistic (every Need empty) and grows
  monotonically, so recursive and mutually recursive types settle.
  Wired `[a]`, `Maybe a` and `(a,b)` need every context position.
- *Dictionary construction.* There are three shapes:
  - Need empty: today's structural dictionary. This covers `Eq Int`,
    `Ord Char`, and a derived record of base fields. Strings, `[Int]`
    and derived records keep their speed, and contract discharge keeps
    seeing `ahc_prim_eq_poly`/`ahc_prim_compare_poly`
    (`src/ahc-discharge.adb:133/170/191`) on every base dictionary.
  - `Never`: a field-wise dictionary.
  - Otherwise:
    `\d1..dn -> case primSameFun (sel d_k) primeq && ... of
    True -> STRUCTURAL; _ -> FIELDWISE`.
    The test runs once per dictionary construction, never per
    comparison. It inspects only the instance's **own** parameters, so
    a recursive type never tests itself.
- *Field-wise code* follows Report 11.1 (constructor order for `Ord`):
  - The same constructor compares its fields left to right through
    each field's own instance, found by the generalised
    `Dict_At` (Task D3).
  - Different constructors are unequal (`Eq`) or ordered by
    `primcompare x y`, which decides from the two constructor tags
    alone because `poly_cmp` returns on differing `contag` before it
    reads a field (`runtime/ahc_rts.c:2522-2525`).
  - A field of the instance's own type calls the `let`-bound function
    directly, so a list or tree builds no dictionary per node.
  - The list, `Maybe` and pair instances use the same generic
    constructor walk over their wired constructor schemes.

**Why not test every dictionary at run time?** Testing the field
dictionaries of a recursive type from inside that type's own
dictionary CAF would force the CAF it is building (`<<loop>>`). The
static Need restricts run-time tests to the instance's parameters.

### Spec deviations (recorded here and in the write-up)

1. **D3: the call stack is computed in `ahc_main`, not the renamer.**
   The renamer has no `Sites.Site_Context` (file, module, source text).
   `ahc_main` builds that context for `Desugar_Module`. Right after
   that call, it stamps `Derive_Loc` on the module's derived `Enum`
   instances (range `I0+1 .. M.Last_Instance`). The text is the same
   one the spec names, computed at the same span.
2. **D2: a GND newtype over a derived type keeps the derived type's
   one-constraint-per-parameter context.** GND resolution runs before
   derived inference, unchanged, because GND's reducer reads derived
   instances' contexts. A joint fixpoint would need GND re-resolution
   with duplicate diagnostics. So
   `newtype N a = N (Ph a) deriving newtype Eq` still asks for `Eq a`,
   which is stricter than GHC (an accept gap; EXCLUSIONS records it).
3. **A NaN inside a derived or wired `Ord` still orders by `compare`.**
   `Just nan > Just 1` stays `True`, where GHC's derived `>` gives
   `False`. `Ord Double` is structural by the spec's definition (its
   `compare` *is* `primcompare`), so it is not touched. EXCLUSIONS
   keeps this clause.
4. **Added (not in the spec): Report 6.3.2's `max`/`min` tie rule.** On
   a tie, `max` answers `y` and `min` answers `x`. The field-wise path
   needs it (`max (P (Ci "A") 1) (P (Ci "a") 1)` is `P (Ci "a") 1` in
   GHC). The shared `Max_Min` builder also fixes `max 0.0 (-0.0)`
   (GHC: `-0.0`; AHC v1.20: `0.0`).
5. **Added: a pre-existing crash fixed on the way (Task D3).** Under an
   `Ord a` context, `x == y` at `[Int]`, `Maybe`, pairs or any derived
   parameterised type raised `ahc: selector on a non-dictionary`.
   `Give_Dict` stored the *unapplied* sibling `Eq` instance function
   as `Ord`'s superclass.

### File map (phase D)

| File | Change |
|---|---|
| `src/ahc-syntax.ads` | `Src_Span_Vectors`; `Decl_Node.D_Deriving_Spans` |
| `src/ahc-parser.adb` | `Parse_Deriving` records each class name's span |
| `src/ahc-core.ads` | `Instance_Info.Is_Derived`, `Instance_Info.Derive_Loc` |
| `src/ahc-builtins.adb`, `src/ahc-rename.adb` | the two new fields in every `Mint_Instance` aggregate; derived and GND instances take the class name's span |
| `src/ahc-prelude_core.adb/.ads` | `Dict_At`/`Super_Dicts` (replacing `Dict_For_Class`), `Give_Dict` supers, `Max_Min` tie rule, structural analysis + `Build_Eq_Ord`, `Err_At` for derived `Enum` |
| `runtime/ahc_rts.c`, `runtime/ahc_rts.h` | `ahc_prim_same_fun` |
| `src/ahc-typechecker.adb` | `Constraint_Text`; `Reduce` extracted to `Reduce_Context`; `Infer_Derived_Contexts` |
| `src/ahc_main.adb` | `Site_Ctx` hoisted; `Derive_Loc` stamped after desugaring |
| `tests/conformance/m150_*`, `tests/conformance/multi/m150_derived_enum_cross/`, `tests/corpus-types/*m150*`, `tests/golden/check_m150_derive_errors.*`, `tests/bench/b_streq.hs`, `tests/src/test_typechecker.adb` | tests |
| `tests/conformance/EXCLUSIONS.md`, `src/ahc-prelude_core.ads` | closed clauses, header comment |

---

### Task D1: record GHC's answers first (failing tests)

**Files:**
- Create: `tests/conformance/m150_ord_superclass.hs` (+ `.out`)
- Create: `tests/conformance/m150_structural_eq.hs` (+ `.out`)
- Create: `tests/conformance/m150_overlap_eq.hs` (+ `.out`)
- Create: `tests/conformance/m150_derived_context.hs` (+ `.out`)
- Create: `tests/conformance/m150_derived_enum_errors.hs` (+ `.out`)
- Create: `tests/conformance/multi/m150_derived_enum_cross/{Main.hs,Shapes.hs,expected.out}`
- Create: `tests/corpus-types/bad_m150_derive_show_missing.hs`,
  `bad_m150_derive_eq_function.hs`, `bad_m150_derive_ord_missing.hs`,
  `ok_m150_derive_phantom.hs`
- Create: `tests/bench/b_streq.hs`

**Interfaces:**
- Produces: the oracle goldens every later task in phase D turns
  green, and `$SCRATCH/bench_pre_D.txt`.

- [ ] **Step 1: bench baseline first, before any phase-D code.** Add
  `tests/bench/b_streq.hs`:

```haskell
-- Eq/Ord on String and [Int] (M150): the list instance must keep
-- choosing the structural primitive when its elements' instances are
-- structural, so this costs what it cost before structural
-- dictionaries.
main :: IO ()
main = print (go 20000 0)
  where
    ws = words "the quick brown fox jumps over the lazy dog"
    go :: Int -> Int -> Int
    go 0 acc = acc
    go n acc =
      let s = show (n `mod` 97)
          xs = [n `mod` 7, 2, 3 :: Int]
          a = length (filter (== "fox") ws) + length (filter (< s) ws)
          b = if xs == [3, 2, 3] then 1 else 0
          c = if compare [s] ["5"] == LT then 1 else 0
      in go (n - 1) (acc + a + b + c)
```

  It prints `32140` under both GHC and AHC v1.20. Then record the
  baseline on the unchanged tree:
  `mkdir -p $SCRATCH/ck && alr build --release && scripts/run_bench.sh > $SCRATCH/bench_pre_D.txt`.

- [ ] **Step 2: `m150_ord_superclass.hs`** (spec deviation 5):

```haskell
-- M150 D1: an Ord dictionary for a type with a context carries its
-- Eq superclass applied to the element's Eq (it was the unapplied
-- instance function: "selector on a non-dictionary").
data T a = A | B a deriving (Eq, Ord, Show)

eqViaOrd :: Ord a => a -> a -> Bool
eqViaOrd x y = x == y

neViaOrd :: Ord a => a -> a -> Bool
neViaOrd x y = x /= y

main :: IO ()
main = do
  print (eqViaOrd [1, 2] [1, 2 :: Int], neViaOrd "ab" "ac")
  print (eqViaOrd (Just 'a') (Just 'a'), eqViaOrd (1 :: Int, 'x') (1, 'y'))
  print (eqViaOrd (B [1 :: Int]) (B [1]), eqViaOrd A (B 'c'))
  print (eqViaOrd (Left 3 :: Either Int Bool) (Left 3))
```

  Expected (GHC 9.4.8):

```
(True,True)
(True,False)
(True,False)
True
```

- [ ] **Step 3: `m150_structural_eq.hs`** (`Ci` inside lists, `Maybe`,
  tuples, `Either`, derived records, nested derived types, `compare`
  across constructors, polymorphic code, Ord's Eq superclass, the tie
  rule):

```haskell
-- M150 D1: wired and derived Eq/Ord call a component's own instance
-- whenever that instance is not structural.
import Data.Char (toLower)

newtype Ci = Ci String deriving Show

instance Eq Ci where
  Ci a == Ci b = map toLower a == map toLower b

instance Ord Ci where
  compare (Ci a) (Ci b) = compare (map toLower a) (map toLower b)

data P = P Ci Int deriving (Eq, Ord, Show)

data Rec = Rec { name :: Ci, tags :: [Ci] } deriving (Eq, Ord, Show)

data Tree a = Leaf | Node (Tree a) a (Tree a) deriving (Eq, Ord, Show)

data Shape = Dot | Box Int Int | Named Ci deriving (Eq, Ord, Show)

-- Polymorphic code: the element dictionary arrives at run time.
same :: Eq a => [a] -> [a] -> Bool
same xs ys = xs == ys

order :: Ord a => a -> a -> Ordering
order = compare

-- Ord's Eq superclass, reached from an Ord context alone.
viaOrd :: Ord a => a -> a -> Bool
viaOrd x y = x == y

main :: IO ()
main = do
  print ([Ci "A"] == [Ci "a"], [Ci "A"] /= [Ci "a"])
  print (Just (Ci "X") == Just (Ci "x"), (Ci "a", 1 :: Int) == (Ci "A", 1))
  print (Left (Ci "q") == (Left (Ci "Q") :: Either Ci Int))
  print (P (Ci "Hi") 3 == P (Ci "hI") 3, P (Ci "Hi") 3 == P (Ci "hI") 4)
  print (Rec (Ci "N") [Ci "t"] == Rec (Ci "n") [Ci "T"])
  print (Node Leaf (Ci "K") Leaf == Node Leaf (Ci "k") Leaf)
  print (compare [Ci "b"] [Ci "A"], compare (Just (Ci "a")) (Just (Ci "A")))
  print (compare (P (Ci "a") 2) (P (Ci "A") 1), P (Ci "a") 1 < P (Ci "B") 0)
  print (compare Dot (Box 1 2), compare (Box 1 2) (Named (Ci "z")))
  print (compare (Named (Ci "Z")) (Named (Ci "z")), Box 2 1 > Box 1 9)
  print (maximum [Ci "b", Ci "C", Ci "a"], minimum [P (Ci "b") 1, P (Ci "B") 0])
  print (same [Ci "M"] [Ci "m"], same [1, 2 :: Int] [1, 2])
  print (order (Node Leaf (Ci "a") Leaf) (Node Leaf (Ci "A") Leaf))
  print (viaOrd [1, 2 :: Int] [1, 2], viaOrd (Just (Ci "u")) (Just (Ci "U")))
  print (viaOrd (Node Leaf [Ci "x"] Leaf) (Node Leaf [Ci "X"] Leaf))
  print ("abc" == "abc", [[1, 2], [3 :: Int]] < [[1, 2], [4]], compare "b" "ab")
  print (Node Leaf (1 :: Int) Leaf == Node Leaf 1 Leaf, [Dot, Box 1 1] < [Dot, Box 1 2])
  -- Report 6.3.2's max/min: a tie answers max = y, min = x.
  print (max (P (Ci "A") 1) (P (Ci "a") 1), min (P (Ci "A") 1) (P (Ci "a") 1))
  print (max [Ci "x"] [Ci "X"], max 0.0 (-0.0 :: Double), min (-0.0) (0.0 :: Double))
```

  Expected:

```
(True,False)
(True,True)
True
(True,False)
True
True
(GT,EQ)
(GT,True)
(LT,LT)
(EQ,True)
(Ci "C",P (Ci "B") 0)
(True,True)
EQ
(True,True)
True
(True,True,GT)
(True,True)
(P (Ci "a") 1,P (Ci "A") 1)
([Ci "X"],-0.0,-0.0)
```

  AHC v1.20 prints `(False,True)`, `(False,False)`, `False`, ... and
  crashes at the `viaOrd` line.

- [ ] **Step 4: `m150_overlap_eq.hs`** (the EXCLUSIONS `Eq [Bool]` gap):

```haskell
{-# LANGUAGE FlexibleInstances #-}
-- M150 D1: an OVERLAPPING Eq [Bool] is used inside derived and wired
-- instances, not bypassed by the structural primitive.

instance {-# OVERLAPPING #-} Eq [Bool] where
  xs == ys = length xs == length ys

data Flags = Flags [Bool] Int deriving (Eq, Show)

main :: IO ()
main = do
  print ([True] == [False], [True, True] == [False])
  print (Flags [True] 1 == Flags [False] 1, Flags [True] 1 == Flags [] 1)
  print (Just [True, False] == Just [False, True])
  print ([[True]] == [[False]], ([True], 'x') == ([False], 'x'))
  print ([1, 2 :: Int] == [1, 2], "ab" == "ab")
```

  Expected:

```
(True,False)
(True,False)
True
(True,True)
(True,True)
```

- [ ] **Step 5: `m150_derived_context.hs`** (phantoms, nested,
  self- and mutually recursive types):

```haskell
-- M150 D2: derived Eq/Ord/Show/Read contexts are inferred from the
-- constructor fields, as GHC infers them.

data Ph a = Ph Int deriving (Eq, Ord, Show, Read)

data Wrap a = Wrap [a] (Maybe a) deriving (Eq, Ord, Show)

data L a = N | C a (L a) deriving (Eq, Ord, Show)

data Even a = EZ | ES a (Odd a) deriving (Eq, Show)
data Odd a = OS a (Even a) deriving (Eq, Show)

data Two a b = Two b deriving (Eq, Show)

main :: IO ()
main = do
  print (Ph 1 == (Ph 1 :: Ph (Int -> Int)))
  print (compare (Ph 2) (Ph 1 :: Ph (IO ())), Ph 3 < (Ph 4 :: Ph (Int -> Int)))
  print (Ph 5 :: Ph (Int -> Bool))
  print (read "Ph 7" == (Ph 7 :: Ph (Bool -> Bool)))
  print (Wrap [1, 2] (Just 3) == Wrap [1, 2] (Just (3 :: Int)))
  print (Wrap "ab" Nothing < Wrap "ac" Nothing)
  print (C 1 (C 2 N) == C 1 (C (2 :: Int) N), compare (C 'a' N) (C 'a' (C 'b' N)))
  print (ES 'x' (OS 'y' EZ) == ES 'x' (OS 'y' EZ))
  print (Two 'k' == (Two 'k' :: Two (Int -> Int) Char))
  print (Two True :: Two (IO ()) Bool)
```

  Expected:

```
True
(GT,True)
Ph 5
True
True
True
(True,LT)
True
True
Two True
```

  AHC v1.20 rejects it with `no instance for 'Eq Int -> Int'` and
  similar errors.

- [ ] **Step 6: `m150_derived_enum_errors.hs`** (single module):

```haskell
-- M150 D3: a derived Enum's succ/pred/toEnum errors carry GHC's call
-- stack at the deriving clause's class name.
import Control.Exception

data Colour = Red | Green | Blue
  deriving (Show, Eq, Enum, Bounded)

data Dir = North | South deriving (Show, Enum)

t :: String -> a -> IO ()
t name v = do
  r <- try (evaluate v)
  case r of
    Left e -> putStrLn (name ++ " => " ++ show (e :: SomeException))
    Right _ -> putStrLn (name ++ " => no error")

main :: IO ()
main = do
  t "succ Blue" (succ Blue)
  t "pred Red" (pred Red)
  t "toEnum 7" (toEnum 7 :: Colour)
  t "toEnum (-1)" (toEnum (-1) :: Dir)
  t "succ South" (succ South)
  print [Red ..]
  print (map fromEnum [North, South])
```

  Expected:

```
succ Blue => succ{Colour}: tried to take `succ' of last tag in enumeration
CallStack (from HasCallStack):
  error, called at tests/conformance/m150_derived_enum_errors.hs:6:23 in main:Main
pred Red => pred{Colour}: tried to take `pred' of first tag in enumeration
CallStack (from HasCallStack):
  error, called at tests/conformance/m150_derived_enum_errors.hs:6:23 in main:Main
toEnum 7 => toEnum{Colour}: tag (7) is outside of enumeration's range (0,2)
CallStack (from HasCallStack):
  error, called at tests/conformance/m150_derived_enum_errors.hs:6:23 in main:Main
toEnum (-1) => toEnum{Dir}: tag (-1) is outside of enumeration's range (0,1)
CallStack (from HasCallStack):
  error, called at tests/conformance/m150_derived_enum_errors.hs:8:42 in main:Main
succ South => succ{Dir}: tried to take `succ' of last tag in enumeration
CallStack (from HasCallStack):
  error, called at tests/conformance/m150_derived_enum_errors.hs:8:42 in main:Main
[Red,Green,Blue]
[0,1]
```

  Each stack points at the `Enum` token in the deriving clause.

- [ ] **Step 7: `multi/m150_derived_enum_cross/`.** `Shapes.hs`:

```haskell
module Shapes (Shape (..), Size (..)) where

data Shape = Circle | Square deriving (Show, Enum)

data Size
  = Small
  | Large
  deriving (Show, Eq, Ord, Enum, Bounded)
```

  `Main.hs`:

```haskell
-- M150 D3: a derived Enum in an imported module locates its errors
-- at that module's deriving clause.
import Control.Exception
import Shapes

data Local = One | Two deriving (Show, Enum)

t :: String -> a -> IO ()
t name v = do
  r <- try (evaluate v)
  case r of
    Left e -> putStrLn (name ++ " => " ++ show (e :: SomeException))
    Right _ -> putStrLn (name ++ " => no error")

main :: IO ()
main = do
  t "succ Square" (succ Square)
  t "pred Small" (pred Small)
  t "toEnum 5 :: Size" (toEnum 5 :: Size)
  t "succ Two" (succ Two)
  print [Circle ..]
```

  `expected.out` (GHC names an import `./Shapes.hs`, the root `Main.hs`):

```
succ Square => succ{Shape}: tried to take `succ' of last tag in enumeration
CallStack (from HasCallStack):
  error, called at ./Shapes.hs:3:46 in main:Shapes
pred Small => pred{Size}: tried to take `pred' of first tag in enumeration
CallStack (from HasCallStack):
  error, called at ./Shapes.hs:8:28 in main:Shapes
toEnum 5 :: Size => toEnum{Size}: tag (5) is outside of enumeration's range (0,1)
CallStack (from HasCallStack):
  error, called at ./Shapes.hs:8:28 in main:Shapes
succ Two => succ{Local}: tried to take `succ' of last tag in enumeration
CallStack (from HasCallStack):
  error, called at Main.hs:6:40 in main:Main
[Circle,Square]
```

- [ ] **Step 8: negative and positive type corpus**
  (`run_differential_types.sh` checks accept/reject agreement with
  `ghc -XHaskell2010 -fno-code`). Each file below was probed: GHC
  rejects the three `bad_` files and accepts `ok_`. AHC v1.20 does
  the opposite on all four.

`tests/corpus-types/bad_m150_derive_show_missing.hs`:

```haskell
-- M150 D2: a derived Show whose field has no Show instance is a
-- compile error in both compilers (GHC: No instance for (Show F)).
data F = F

data T = T Int F deriving Show

main :: IO ()
main = print (T 1 F)
```

`tests/corpus-types/bad_m150_derive_eq_function.hs`:

```haskell
-- M150 D2: a function field has no Eq (GHC: No instance for
-- (Eq (Int -> Int)) arising from the first field of 'R').
data R = R { g :: Int -> Int } deriving Eq

main :: IO ()
main = print (g (R (+ 1)) 2)
```

`tests/corpus-types/bad_m150_derive_ord_missing.hs`:

```haskell
-- M150 D2: a derived Ord over a field that has Eq but no Ord.
data F = F deriving Eq

data W a = W a F deriving (Eq, Ord)

main :: IO ()
main = print (W 'x' F == W 'x' F)
```

`tests/corpus-types/ok_m150_derive_phantom.hs`:

```haskell
-- M150 D2: a phantom parameter needs no instance (GHC infers an
-- empty context), so comparing and showing at a function type
-- compiles.
data Ph a = Ph Int deriving (Eq, Ord, Show)

main :: IO ()
main = print (Ph 1 == (Ph 1 :: Ph (Int -> Int)), Ph 2 :: Ph (IO ()))
```

- [ ] **Step 9: oracle from the repo root**, so GHC sees the paths AHC
  is given:

```sh
for f in m150_ord_superclass m150_structural_eq m150_overlap_eq \
         m150_derived_context m150_derived_enum_errors; do
  ~/.ghcup/bin/runghc tests/conformance/$f.hs > tests/conformance/$f.out
done
(cd tests/conformance/multi/m150_derived_enum_cross && \
   ~/.ghcup/bin/runghc Main.hs > expected.out)
```

  Diff each `.out` against the expected blocks above. They must be
  identical.
- [ ] **Step 10: confirm all of them FAIL now.** `scripts/run_conformance.sh`
  shows `FAIL` (or `BUILD-FAIL`) for the six new cases.
  `scripts/run_differential_types.sh` shows `OVER-ACCEPT` for the three
  `bad_m150_*` files and `UNDER-ACCEPT` for `ok_m150_derive_phantom.hs`.
- [ ] **Step 11: commit:**
  `test(conformance): ghc 9.4.8's answers for structural dictionaries, inferred derived contexts and derived enum call stacks, failing until phase d lands`
  with trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

---

### Task D2: a deriving clause keeps each class name's span

**Files:**
- Modify: `src/ahc-syntax.ads:27` (after `QName_Vectors`), `:382` (`D_Deriving`)
- Modify: `src/ahc-parser.adb:2097-2124` (`Parse_Deriving`), `:2134`, `:2181`, `:2225-2236`
- Modify: `src/ahc-core.ads:304-329` (`Instance_Info`)
- Modify: `src/ahc-builtins.adb:217-226` (`Def_Instance`'s aggregate)
- Modify: `src/ahc-rename.adb:1846-2015` (`Declare_Data`'s deriving loop), `:2281-2293` (`Declare_Instance`)

**Interfaces:**
- Produces:
  - `Syntax.Src_Span_Vectors`;
  - `Decl_Node.D_Deriving_Spans`, parallel to `D_Deriving`;
  - `Instance_Info.Is_Derived : Boolean` (a stock deriving clause made
    it, including the Functor family);
  - `Instance_Info.Derive_Loc : Names.Name_Id` (filled in Task D6);
  - a derived or GND instance's `Span` is now its class name's span,
    not the `data` keyword's.

- [ ] **Step 1: syntax.** After `package QName_Vectors ...` (line 27):

```ada
   --  One source span per entry of a parallel vector (M150: the class
   --  names of a deriving clause).
   package Src_Span_Vectors is new Ada.Containers.Vectors
     (Positive, Diagnostics.Source_Span, Diagnostics."=");
```

  In `Decl_Node`, after `D_Deriving : QName_Vectors.Vector;` (line 382):

```ada
            D_Deriving_Spans : Src_Span_Vectors.Vector;  --  parallel
```

- [ ] **Step 2: parser.** `Parse_Deriving` (2097-2124) becomes:

```ada
      procedure Parse_Deriving
        (Into  : in out QName_Vectors.Vector;
         Spans : in out Src_Span_Vectors.Vector) is
      begin
         if not At_K (Kw_Deriving) then
            return;
         end if;
         Advance;
         if At_K (Left_Paren) then
            Advance;
            if not At_K (Right_Paren) then
               loop
                  if Tok.Kind not in Conid | Qconid then
                     Fail ("expected a class name");
                  end if;
                  Into.Append (Tok_QName);
                  Spans.Append (Tok.Span);
                  Advance;
                  exit when not At_K (Comma);
                  Advance;
               end loop;
            end if;
            Expect (Right_Paren, "')'");
         else
            if Tok.Kind not in Conid | Qconid then
               Fail ("expected a class name");
            end if;
            Into.Append (Tok_QName);
            Spans.Append (Tok.Span);
            Advance;
         end if;
      end Parse_Deriving;
```

  In `Parse_Data_Decl`, after `Derivs  : QName_Vectors.Vector;` (2134)
  add `Deriv_Spans : Src_Span_Vectors.Vector;`. Change
  `Parse_Deriving (Derivs);` (2181) to
  `Parse_Deriving (Derivs, Deriv_Spans);`. In both `Decl_Node'`
  aggregates (2227-2229 and 2233-2236), after
  `D_Deriving => Derivs` add `, D_Deriving_Spans => Deriv_Spans`.

- [ ] **Step 3: core.** In `Instance_Info`, before `Span : Diagnostics.Source_Span;` (line 328):

```ada
      --  M150: made by a stock deriving clause (Span is then the
      --  clause's class name). Eq/Ord/Show/Read/Enum/Bounded/Ix ones
      --  get their context inferred from the constructor fields by
      --  the typechecker; Prelude_Core bodies them.
      Is_Derived  : Boolean := False;
      --  M150 D3: for a derived Enum in a user module, GHC's call
      --  stack at that class name ("CallStack (from HasCallStack):"
      --  LF "  error, called at F:L:C in main:Mod"), raised with
      --  succ/pred/toEnum failures; No_Name otherwise.
      Derive_Loc  : Names.Name_Id := Names.No_Name;
```

- [ ] **Step 4: every `Mint_Instance` aggregate names the two fields.**
  - `src/ahc-builtins.adb:217-226`: after `From_Source => False,   --  wired; Prelude_Core binds it`
    add `Is_Derived => False, Derive_Loc => Names.No_Name,`.
  - `src/ahc-rename.adb:2281-2293` (`Declare_Instance`): after
    `From_Source => True,` add
    `Is_Derived => False, Derive_Loc => Names.No_Name,`.
  - In `Declare_Data` the loop header (1846-1852) is:

```ada
         for DC of N.D_Deriving loop
            declare
               Amb : Boolean;
               C : constant Core.Class_Id :=
                 Mod_Find_Class (DC, N.Span, Amb);
            begin
```

  It becomes the following (the body, the trailing `end;`,
  `<<Next_Derive>>` and `end loop;` at 2013-2015 are unchanged):

```ada
         for DI in 1 .. N.D_Deriving.Last_Index loop
            declare
               DC : constant QName := N.D_Deriving (DI);
               --  M150 D3: the class name's own span, GHC's location
               --  for this instance's errors and its call stacks.
               DSpan : constant Diagnostics.Source_Span :=
                 (if DI <= N.D_Deriving_Spans.Last_Index
                  then N.D_Deriving_Spans (DI) else N.Span);
               Amb : Boolean;
               C : constant Core.Class_Id :=
                 Mod_Find_Class (DC, N.Span, Amb);
            begin
```

  - In the GND aggregate (1875-1888), add
    `Is_Derived => False, Derive_Loc => Names.No_Name,` and change
    `Span => N.Span));` to `Span => DSpan));`.
  - In the stock aggregate (1986-2003), add
    `Is_Derived => True, Derive_Loc => Names.No_Name,` and change
    `Span => N.Span));` to `Span => DSpan));`.
  - The `$d...` dictionary vars keep `Span => N.Span`.
  - The renamer's own errors ("cannot derive ...") stay at `N.Span`.
- [ ] **Step 5: audit the span consumers.** Run
  `grep -n "Inst.Span\|).Span" src/ahc-typechecker.adb src/ahc-derive_functor.adb src/ahc-elaborate.adb`.
  Every hit is a diagnostic position, so it moves to the class name,
  which is GHC's position. None reads the span as "the data
  declaration".
- [ ] **Step 6: verify.**
  - Semantic-check `ahc-parser.adb`, `ahc-rename.adb` and
    `ahc-builtins.adb`, then `alr build --validation`.
  - `./bin/ahc check tests/corpus-types/bad_gnd_no_instance.hs` prints
    `tests/corpus-types/bad_gnd_no_instance.hs:3:38: error: cannot derive 'Num' for 'P': no instance 'Num (Int -> Int)'`.
    Column 38 is GHC's `Num`; it was `3:1`.
  - `scripts/run_differential.sh` shows parse differential green.
  - `scripts/run_gate.sh unit golden` gives `GATE ok`.
  - `cd tests && alr build --validation && ./bin/ahc_tests` passes all
    359 tests.
- [ ] **Step 7: commit:**
  `feat(parser): a deriving clause keeps each class name's span, and the instances it makes carry it`
  with trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

---

### Task D3: dictionaries by type, and superclasses applied to the context

**Files:**
- Modify: `src/ahc-prelude_core.adb:384-425` (insert before `Give_Dict`, rewrite `Give_Dict`)
- Modify: `src/ahc-prelude_core.adb:712-807` (delete `Dict_For_Class`)
- Modify: `src/ahc-prelude_core.adb:892-895` (`Derive_Read`'s `Chain`), `:1190-1193` (`Derive_Show`'s `Dict_For`)

**Interfaces:**
- Produces, all local to `Install_Bodies`:
  - `function Same_Under (T; Tvs; A; Hvs) return Boolean`;
  - `function Var_Spine (T) return Boolean`;
  - `procedure Ctx_Pos (T; Cl; Tvs; Inst; P, Via : out Natural)`;
  - `procedure Choose (T; Cl; Pick : out Natural; Args : out Type_Id_Vectors.Vector)`;
  - `function Dict_At (T : Real_Type_Id; Cl : Real_Class_Id; Tvs : TyVar_Id_Vectors.Vector; Inst : Instance_Info; Params : Var_Id_Vectors.Vector) return Expr_Id`;
  - `function Super_Dicts (Inst : Instance_Info; Params : Var_Id_Vectors.Vector) return Expr_Id_Vectors.Vector`.
- `Dict_For_Class` is removed. Its two callers use `Dict_At`.

Today `Dict_For_Class` maps a type variable to a context parameter
**by position**: "type variable I is context parameter I". That holds
only while the renamer gives every derived instance one `C a` per
variable. Task D5 breaks this: a phantom has no constraint, and a
field can need `Eq a` from an `Ord a`. Also, `if IC.Class /= Cl then
return No_Expr` rejected any field instance with a mixed-class
context. `Dict_At` looks the type up in the context **by type**, for
any class. It takes a superclass of a context constraint when needed.

- [ ] **Step 1: insert after `end Max_Min;` (line 383):**

```ada
      ------------------------------------------------------------------
      --  Dictionaries by type (M150): the dictionary of a class at a
      --  type inside an instance - from the instance's own context
      --  (looked up by type, any class, through a superclass when
      --  needed) or from the instance the typechecker would choose.
      ------------------------------------------------------------------

      function Id_T (X : Real_Type_Id) return Real_Type_Id is (X);
      function Match_Inst is new Inst_Match.Match_Instance (Id_T);

      --  T (over Tvs, a constructor scheme's quantifiers) and A (over
      --  Hvs, an instance's head variables) are the same type, the
      --  variables corresponding by position - the declaration order
      --  both lists follow. Wired constructors mint their own
      --  variables per constructor, so the per-constructor Tvs is
      --  always the one passed.
      function Same_Under
        (T : Real_Type_Id; Tvs : TyVar_Id_Vectors.Vector;
         A : Real_Type_Id; Hvs : TyVar_Id_Vectors.Vector) return Boolean
      is
         NT : constant Type_Node := M.Node (T);
         NA : constant Type_Node := M.Node (A);
      begin
         if NT.Kind /= NA.Kind then
            return False;
         end if;
         case NT.Kind is
            when TVar_T =>
               declare
                  IT : constant TyVar_Id_Vectors.Extended_Index :=
                    Tvs.Find_Index (NT.Tv);
                  IA : constant TyVar_Id_Vectors.Extended_Index :=
                    Hvs.Find_Index (NA.Tv);
               begin
                  return NT.Tv = NA.Tv
                    or else (IT /= TyVar_Id_Vectors.No_Index
                             and then IT = IA);
               end;
            when TCon_T =>
               return NT.Con = NA.Con;
            when TApp_T =>
               return Same_Under (NT.T_Fun, Tvs, NA.T_Fun, Hvs)
                 and then Same_Under (NT.T_Arg, Tvs, NA.T_Arg, Hvs);
            when TFun_T =>
               return Same_Under (NT.From, Tvs, NA.From, Hvs)
                 and then Same_Under (NT.To, Tvs, NA.To, Hvs);
            when others =>
               return False;
         end case;
      end Same_Under;

      --  A type variable, or one applied (`f a`): only a context
      --  constraint can supply its dictionary.
      function Var_Spine (T : Real_Type_Id) return Boolean is
         N : constant Type_Node := M.Node (T);
      begin
         return N.Kind = TVar_T
           or else (N.Kind = TApp_T and then Var_Spine (N.T_Fun));
      end Var_Spine;

      --  The context position of Inst constraining T: of class Cl
      --  itself (Via = 0), or of a class whose Via-th superclass is
      --  Cl (an Ord a giving Eq a). P = 0 when there is none.
      procedure Ctx_Pos
        (T : Real_Type_Id; Cl : Real_Class_Id;
         Tvs : TyVar_Id_Vectors.Vector; Inst : Instance_Info;
         P : out Natural; Via : out Natural)
      is
      begin
         P := 0;
         Via := 0;
         for K in 1 .. Inst.Context.Last_Index loop
            if Inst.Context (K).Class = Cl
              and then Same_Under (T, Tvs, Inst.Context (K).Arg,
                                   Inst.Head_Vars)
            then
               P := K;
               return;
            end if;
         end loop;
         for K in 1 .. Inst.Context.Last_Index loop
            if Same_Under (T, Tvs, Inst.Context (K).Arg, Inst.Head_Vars)
            then
               declare
                  Sups : constant Class_Id_Vectors.Vector :=
                    M.Info (Inst.Context (K).Class).Supers;
               begin
                  for S in 1 .. Sups.Last_Index loop
                     if Sups (S) = Class_Id (Cl) then
                        P := K;
                        Via := S;
                        return;
                     end if;
                  end loop;
               end;
            end if;
         end loop;
      end Ctx_Pos;

      --  The instance of Cl the typechecker would choose at T - the
      --  one shared matcher, overlap rule included (M148 review: an
      --  OVERLAPPING `Eq [Bool]` must win over `Eq [a]`) - with its
      --  head variables' bindings in Args. Pick = 0: none.
      procedure Choose
        (T : Real_Type_Id; Cl : Real_Class_Id;
         Pick : out Natural; Args : out Type_Id_Vectors.Vector)
      is
         Cands : Instance_Id_Vectors.Vector;
      begin
         Pick := 0;
         Args.Clear;
         for SI of M.Info (Cl).Instances loop
            declare
               SI_Info : constant Instance_Info := M.Info (SI);
               Ign : Type_Id_Vectors.Vector;
            begin
               if SI_Info.Dict_Global /= No_Var
                 and then Inst_Match."="
                   (Match_Inst (M, Env, SI_Info, T, Ign),
                    Inst_Match.Matched)
               then
                  Cands.Append (SI);
               end if;
            end;
         end loop;
         if Natural (Cands.Length) = 1 then
            Pick := Natural (Cands.First_Element);
         elsif Natural (Cands.Length) > 1 then
            Pick := Inst_Match.Pick (M, Env, Cands);
         end if;
         if Pick /= 0 then
            declare
               P_Info : constant Instance_Info :=
                 M.Info (Real_Instance_Id (Pick));
               Ign : constant Inst_Match.Match_Result :=
                 Match_Inst (M, Env, P_Info, T, Args);
               pragma Unreferenced (Ign);
            begin
               null;
            end;
         end if;
      end Choose;

      --  The Core dictionary of class Cl at the field type T inside
      --  the instance Inst whose context dictionaries are Params. Tvs
      --  are T's quantifiers (the constructor scheme's), positionally
      --  Inst.Head_Vars. No_Expr when no instance supplies it (Task
      --  D.5 makes that a compile error first).
      function Dict_At
        (T : Real_Type_Id; Cl : Real_Class_Id;
         Tvs : TyVar_Id_Vectors.Vector; Inst : Instance_Info;
         Params : Var_Id_Vectors.Vector) return Expr_Id
      is
      begin
         if Var_Spine (T) then
            declare
               P, Via : Natural;
            begin
               Ctx_Pos (T, Cl, Tvs, Inst, P, Via);
               if P = 0 or else P > Params.Last_Index then
                  return No_Expr;
               elsif Via = 0 then
                  return Expr_Id (V (Params.Element (P)));
               end if;
               declare
                  Sel : constant Real_Expr_Id :=
                    V (M.Info (Inst.Context (P).Class).Super_Sels (Via));
                  D : constant Real_Expr_Id := V (Params.Element (P));
               begin
                  return Expr_Id (Ap (Sel, D));
               end;
            end;
         elsif M.Node (T).Kind not in TCon_T | TApp_T then
            return No_Expr;   --  a function type has no Eq/Ord/Show/Read
         end if;
         declare
            Args : Type_Id_Vectors.Vector;
            Pick : Natural;
         begin
            Choose (T, Cl, Pick, Args);
            if Pick = 0 then
               return No_Expr;
            end if;
            declare
               J : constant Instance_Info :=
                 M.Info (Real_Instance_Id (Pick));
               Acc : Expr_Id := Expr_Id (V (J.Dict_Global));
            begin
               for IC of J.Context loop
                  declare
                     A : constant Real_Type_Id :=
                       Inst_Match.Subst_Vars (M, IC.Arg, J.Head_Vars, Args);
                     DA : constant Expr_Id :=
                       Dict_At (A, IC.Class, Tvs, Inst, Params);
                  begin
                     if DA = No_Expr then
                        return No_Expr;
                     end if;
                     Acc := Expr_Id
                       (Ap (Real_Expr_Id (Acc), Real_Expr_Id (DA)));
                  end;
               end loop;
               return Acc;
            end;
         end;
      end Dict_At;

      --  The superclass dictionaries of Inst's dictionary: each the
      --  sibling instance at Inst's own head, APPLIED to dictionaries
      --  drawn from Inst's context. M150: Ord's Eq superclass of
      --  `Ord a => Ord [a]` was the unapplied `$dEqList`, so `x == y`
      --  under `Ord a` at a list raised "selector on a non-dictionary".
      function Super_Dicts
        (Inst : Instance_Info; Params : Var_Id_Vectors.Vector)
         return Expr_Id_Vectors.Vector
      is
         Cl_Info : constant Class_Info :=
           M.Info (Real_Class_Id (Inst.Of_Class));
         Head_T : constant Real_Type_Id :=
           Inst_Match.Instance_Type (M, Env, Inst);
         R : Expr_Id_Vectors.Vector;
      begin
         for Super of Cl_Info.Supers loop
            declare
               D : constant Expr_Id :=
                 Dict_At (Head_T, Real_Class_Id (Super),
                          Inst.Head_Vars, Inst, Params);
            begin
               if D = No_Expr then
                  R.Append (Err ("missing superclass dictionary"));
               else
                  R.Append (D);
               end if;
            end;
         end loop;
         return R;
      end Super_Dicts;
```

- [ ] **Step 2: `Give_Dict` (385-425).** The current body:

```ada
      --  Build a dictionary for Inst with the given method list,
      --  supers solved against sibling instances (context params
      --  ignored: the generic prims need no element evidence).
      procedure Give_Dict
        (Inst_Idx : Real_Instance_Id;
         Methods  : Expr_Id_Vectors.Vector)
      is
         Inst : constant Instance_Info := M.Info (Inst_Idx);
         Cl : constant Real_Class_Id :=
           Real_Class_Id (Inst.Of_Class);
         Cl_Info : constant Class_Info := M.Info (Cl);
         Supers : Expr_Id_Vectors.Vector;
         Params : Var_Id_Vectors.Vector;
         Dict : Real_Expr_Id;
      begin
         for Super of Cl_Info.Supers loop
            ...   --  scan M.Info (Super).Instances for Head = Inst.Head
         end loop;
         Dict := Mk_Dict (M, Cl, Supers, Methods, Span);
         for CI in 1 .. Inst.Context.Last_Index loop
            Params.Append (Fresh ("$d"));
            pragma Unreferenced (CI);
         end loop;
         ...
```

  Replace it with the following. If phase C edited the sibling scan
  (Monad's `Applicative` superclass), `Dict_At` subsumes the edit:
  `Choose` finds the `Applicative` instance at the head the same way.

```ada
      --  Build a dictionary for Inst with the given method list; its
      --  superclasses are the sibling instances applied to this
      --  instance's own context dictionaries (Super_Dicts).
      procedure Give_Dict
        (Inst_Idx : Real_Instance_Id;
         Methods  : Expr_Id_Vectors.Vector)
      is
         Inst : constant Instance_Info := M.Info (Inst_Idx);
         Cl : constant Real_Class_Id :=
           Real_Class_Id (Inst.Of_Class);
         Supers : Expr_Id_Vectors.Vector;
         Params : Var_Id_Vectors.Vector;
         Dict : Real_Expr_Id;
      begin
         for CI in 1 .. Inst.Context.Last_Index loop
            Params.Append (Fresh ("$d"));
            pragma Unreferenced (CI);
         end loop;
         Supers := Super_Dicts (Inst, Params);
         Dict := Mk_Dict (M, Cl, Supers, Methods, Span);
         for PI in reverse 1 .. Params.Last_Index loop
            Dict := Lam (Params (PI), Dict);
         end loop;
         Bind (Inst.Dict_Global, Dict);
      end Give_Dict;
```

- [ ] **Step 3: delete `Dict_For_Class`** (its comment block and body,
  712-807) and repoint its callers:
  - In `Derive_Read`'s `Chain` (892-895):
    `Dict_For_Class (St.FT, Tvs, Cl, Params);` becomes
    `Dict_At (St.FT, Cl, Tvs, Inst, Params);`
  - In `Derive_Show` (1190-1193), `Dict_For` becomes:

```ada
         function Dict_For
           (T : Real_Type_Id; Tvs : TyVar_Id_Vectors.Vector)
            return Expr_Id
         is (Dict_At (T, Cl, Tvs, Inst, Params));
```

- [ ] **Step 4: regression test** is `m150_ord_superclass.hs` from Task
  D.1. It passes now: `$dEqList` still ignores its parameter, but it
  is applied.
- [ ] **Step 5: verify.**

```sh
alr exec -- gcc -c -gnatc -gnat2022 -gnatwa -Isrc src/ahc-prelude_core.adb -o $SCRATCH/ck/pc.o
alr build --validation
T=$(mktemp -d)
./bin/ahc build tests/conformance/m150_ord_superclass.hs -o $T/os && \
  diff tests/conformance/m150_ord_superclass.out <($T/os)    # no output
scripts/run_gate.sh                                          # GATE ok
scripts/run_discharge.sh                                     # 4 x ok, unchanged
```

- [ ] **Step 6: commit:**
  `fix(prelude-core): a dictionary's superclass is its sibling instance applied to the context, so x == y under ord a works at lists`
  with trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

---

### Task D4: structural dictionaries (spec D1)

**Files:**
- Modify: `runtime/ahc_rts.c:2562` (after `p_compare_poly`), `:8664` (globals), `:8837` (init)
- Modify: `runtime/ahc_rts.h:130`
- Modify: `src/ahc-prelude_core.adb:281-283` (prims), `:336-383` (`Cmp_Method`, `Max_Min`)
- Modify: `src/ahc-prelude_core.adb` after `end Derive_Show;` (1381): structural analysis and `Build_Eq_Ord`
- Modify: `src/ahc-prelude_core.adb:1829` (`Solve_Needs` call), `:1859-1892` (the Eq and Ord arms)
- Modify: `src/ahc-prelude_core.ads:8-10` (header comment)
- Modify: `tests/conformance/EXCLUSIONS.md` (in Task D7)

**Interfaces:**
- Consumes: `Dict_At`, `Super_Dicts`, `Same_Under`, `Var_Spine`,
  `Ctx_Pos`, `Choose` (Task D3); `Instance_Info.Is_Derived` (Task D2).
- Produces:
  - the C prim `ahc_prim_same_fun`, and its Core var
    `P_Same` = `primSameFun`;
  - `Cmp_Method (..., Using : Real_Var_Id := P_CmpP)` and
    `Max_Min (Is_Max, Using := P_CmpP)`;
  - `type Need`, `Needs`, `Solve_Needs`;
  - `procedure Build_Eq_Ord (II : Real_Instance_Id)`.

- [ ] **Step 1: runtime** (no suite may be running). After
  `p_compare_poly` (`ahc_rts.c:2562`):

```c
/* M150: are two values the same heap node once evaluated? A wired or
   derived Eq/Ord dictionary is STRUCTURAL exactly when its == (or
   compare) IS the one global ahc_prim_eq_poly (ahc_prim_compare_poly)
   node - only AHC.Prelude_Core's structural builder puts it there, a
   source instance cannot name it, and a GND dictionary is its
   representation's. The [a]/Maybe a/(a,b)/derived instances test
   their element dictionaries with this once, when their own
   dictionary is built, and pick the primitive or field-wise code.
   Both collectors are non-moving, so node identity is stable. */
static AhcNode *p_same_fun(AhcNode *a, AhcNode *b) {
  AhcNode *x = ahc_eval(a);
  AhcNode *y = ahc_eval(b);
  return mk_bool(x == y);
}
```

  - In the globals list (`ahc_rts.c:8664`) change
    `*ahc_prim_eq_poly, *ahc_prim_compare_poly,` to
    `*ahc_prim_eq_poly, *ahc_prim_compare_poly, *ahc_prim_same_fun,`.
  - Make the same edit to the `extern` list (`ahc_rts.h:130`).
  - After `ahc_prim_compare_poly = mk_prim2(p_compare_poly);` (8837),
    add `ahc_prim_same_fun = mk_prim2(p_same_fun);`.

- [ ] **Step 2: the prim var.** After `P_CmpP` (line 283):

```ada
      --  M150 D1: pointer identity of two evaluated values - the
      --  run-time half of the structural-dictionary test.
      P_Same  : constant Real_Var_Id :=
        Prim ("primSameFun", "ahc_prim_same_fun");
```

- [ ] **Step 3: `Cmp_Method` and `Max_Min` take the comparison
  function, and `Max_Min` follows Report 6.3.2.**
  - Change `Cmp_Method`'s profile (336-339) to
    `(Want_Tag : Real_DataCon_Id; Negate : Boolean; Swap : Boolean := False; Using : Real_Var_Id := P_CmpP)`.
  - In its scrutinee, change `Ap2 (V (P_CmpP), V (Y), V (X))` and
    `Ap2 (V (P_CmpP), V (X), V (Y))` to `V (Using)` in place of
    `V (P_CmpP)`.
  - Replace `Max_Min` (365-383) with:

```ada
      --  Report 6.3.2: max x y = if x <= y then y else x and min x y
      --  = if x <= y then x else y, so on a tie max answers y and min
      --  answers x (M150: AHC answered x for both, visible at -0.0
      --  and at any field-wise type whose equal values differ). For
      --  every order x <= y is compare x y /= GT, NaN's GT included.
      function Max_Min
        (Is_Max : Boolean; Using : Real_Var_Id := P_CmpP)
         return Real_Expr_Id
      is
         X : constant Real_Var_Id := Fresh ("x");
         Y : constant Real_Var_Id := Fresh ("y");
         Alts : Alt_Id_Vectors.Vector;
         Cmp : constant Real_Expr_Id := V (Using);
         XE : constant Real_Expr_Id := V (X);
         YE : constant Real_Expr_Id := V (Y);
         Scrut : constant Real_Expr_Id := Ap2 (Cmp, XE, YE);
         On_GT : constant Real_Expr_Id :=
           V (Var_Id (if Is_Max then X else Y));
         Others : constant Real_Expr_Id :=
           V (Var_Id (if Is_Max then Y else X));
      begin
         Alts.Append (M.Add (Alt_Node'
           (Kind => Con_Alt, Span => Span, Alt_Body => On_GT,
            A_Con => Ordering_GT,
            Binders => Var_Id_Vectors.Empty_Vector)));
         Alts.Append (M.Add (Alt_Node'
           (Kind => Default_Alt, Span => Span, Alt_Body => Others)));
         return Lam (X, Lam (Y, M.Add (Expr_Node'
           (Kind => Case_C, Span => Span,
            Scrutinee => Scrut, Alts => Alts))));
      end Max_Min;
```

- [ ] **Step 4: the structural analysis and the builders.** Insert
  after `end Derive_Show;` (1381):

```ada
      ------------------------------------------------------------------
      --  Structural dictionaries (M150 D1)
      --
      --  A dictionary is structural when its ==/compare agrees with
      --  the primitive on every value of its type; it is then built
      --  with the primitive as that method, which is how run-time code
      --  recognises it (primSameFun, ahc_rts.c). A wired base instance
      --  is structural; [a], Maybe a, (a, b) and every derived
      --  instance are structural exactly when every dictionary they
      --  reach is. That is decided per dictionary construction: Need
      --  says statically which of the instance's OWN context
      --  dictionaries must be tested, so a recursive type never tests
      --  itself.
      ------------------------------------------------------------------

      package Pos_Vectors is new Ada.Containers.Vectors
        (Positive, Positive);

      --  Never: some field reaches a hand-written instance or a
      --  function. Otherwise On lists (sorted, distinct) the context
      --  positions whose dictionaries must be structural.
      type Need is record
         Never : Boolean := False;
         On    : Pos_Vectors.Vector;
      end record;

      package Need_Vectors is new Ada.Containers.Vectors
        (Positive, Need);

      Needs : Need_Vectors.Vector;   --  by instance index

      procedure Add (N : in out Need; P : Positive) is
      begin
         for I in 1 .. N.On.Last_Index loop
            if N.On (I) = P then
               return;
            elsif N.On (I) > P then
               N.On.Insert (I, P);
               return;
            end if;
         end loop;
         N.On.Append (P);
      end Add;

      procedure Merge (Into : in out Need; From : Need) is
      begin
         if From.Never then
            Into.Never := True;
         end if;
         for P of From.On loop
            Add (Into, P);
         end loop;
      end Merge;

      function Is_Eq_Ord (Cl : Class_Id) return Boolean is
        (Cl = Env.Eq_Cl or else Cl = Env.Ord_Cl);

      --  The method a structural dictionary of Cl carries as the
      --  primitive (== / compare, both method 1), and that primitive.
      function Struct_Sel (Cl : Class_Id) return Var_Id is
        (M.Info (Real_Class_Id (Cl)).Methods (1).Selector);
      function Struct_Prim (Cl : Class_Id) return Real_Var_Id is
        (if Cl = Env.Eq_Cl then P_EqP else P_CmpP);

      function DC_Scheme (DC : Real_DataCon_Id) return Scheme is
        (M.Node (Real_Scheme_Id (M.Info (DC).Con_Scheme)));

      function Field_Types
        (DC : Real_DataCon_Id) return Type_Id_Vectors.Vector
      is
         T : Real_Type_Id := Real_Type_Id (DC_Scheme (DC).S_Body);
         R : Type_Id_Vectors.Vector;
      begin
         while M.Node (T).Kind = TFun_T loop
            R.Append (M.Node (T).From);
            T := M.Node (T).To;
         end loop;
         return R;
      end Field_Types;

      --  What the structurality of class Cl at field type T (over
      --  Tvs) inside Inst depends on, in Inst's context positions.
      function Need_Of_Type
        (T : Real_Type_Id; Cl : Real_Class_Id;
         Tvs : TyVar_Id_Vectors.Vector; Inst : Instance_Info;
         Depth : Natural := 0) return Need
      is
         R : Need;
      begin
         if Depth > 40 or else not Is_Eq_Ord (Class_Id (Cl)) then
            R.Never := True;
            return R;
         elsif Var_Spine (T) then
            declare
               P, Via : Natural;
            begin
               Ctx_Pos (T, Cl, Tvs, Inst, P, Via);
               if P = 0
                 or else not Is_Eq_Ord
                               (Class_Id (Inst.Context (P).Class))
               then
                  R.Never := True;
               else
                  Add (R, P);
               end if;
               return R;
            end;
         elsif M.Node (T).Kind not in TCon_T | TApp_T then
            R.Never := True;   --  a function never compares
            return R;
         end if;
         declare
            Args : Type_Id_Vectors.Vector;
            Pick : Natural;
            JN : Need;
         begin
            Choose (T, Cl, Pick, Args);
            if Pick = 0 then
               R.Never := True;
               return R;
            end if;
            declare
               J : constant Instance_Info :=
                 M.Info (Real_Instance_Id (Pick));
            begin
               if J.Is_GND then
                  if J.GND_Target = No_Type then
                     R.Never := True;
                     return R;
                  end if;
                  --  A newtype's dictionary IS its representation's.
                  declare
                     Rep : constant Real_Type_Id :=
                       Inst_Match.Subst_Vars
                         (M, Real_Type_Id (J.GND_Target),
                          J.Head_Vars, Args);
                  begin
                     return Need_Of_Type (Rep, Cl, Tvs, Inst, Depth + 1);
                  end;
               elsif J.From_Source then
                  R.Never := True;      --  a hand-written ==/compare
                  return R;
               elsif J.Is_Derived then
                  JN := Needs (Pick);
               else
                  --  Wired: Int, Char, Text, ... need nothing; [a],
                  --  Maybe a, (a, b) need every element.
                  for K in 1 .. J.Context.Last_Index loop
                     Add (JN, K);
                  end loop;
               end if;
               if JN.Never then
                  R.Never := True;
                  return R;
               end if;
               for K of JN.On loop
                  declare
                     A : constant Real_Type_Id :=
                       Inst_Match.Subst_Vars
                         (M, J.Context (K).Arg, J.Head_Vars, Args);
                     Sub : constant Need :=
                       Need_Of_Type (A, J.Context (K).Class, Tvs, Inst,
                                     Depth + 1);
                  begin
                     Merge (R, Sub);
                  end;
               end loop;
               return R;
            end;
         end;
      end Need_Of_Type;

      function Derived_Need (II : Real_Instance_Id) return Need is
         Inst : constant Instance_Info := M.Info (II);
         Cl : constant Real_Class_Id := Real_Class_Id (Inst.Of_Class);
         R : Need;
      begin
         for DCI of M.Info (Real_TyCon_Id (Inst.Head)).Cons loop
            declare
               DC : constant Real_DataCon_Id := Real_DataCon_Id (DCI);
               Tvs : constant TyVar_Id_Vectors.Vector := DC_Scheme (DC).Tvs;
            begin
               for FT of Field_Types (DC) loop
                  Merge (R, Need_Of_Type (Real_Type_Id (FT), Cl, Tvs, Inst));
               end loop;
            end;
         end loop;
         return R;
      end Derived_Need;

      --  Least fixpoint from all-empty: Needs only grow, so recursive
      --  and mutually recursive derived types settle. Past the round
      --  cap every derived dictionary is field-wise, which is always
      --  correct.
      procedure Solve_Needs is
         Changed : Boolean := True;
         Rounds : Natural := 0;
         function Derived_Eq_Ord (II : Real_Instance_Id) return Boolean
         is (M.Info (II).Is_Derived
             and then Is_Eq_Ord (M.Info (II).Of_Class)
             and then M.Info (II).Head /= No_TyCon);
      begin
         Needs := Need_Vectors.To_Vector
           (Need'(others => <>),
            Ada.Containers.Count_Type (M.Last_Instance));
         while Changed loop
            Changed := False;
            Rounds := Rounds + 1;
            for II in 1 .. M.Last_Instance loop
               if Derived_Eq_Ord (Real_Instance_Id (II)) then
                  declare
                     N : constant Need :=
                       Derived_Need (Real_Instance_Id (II));
                  begin
                     if N /= Needs (Positive (II)) then
                        Needs.Replace_Element (Positive (II), N);
                        Changed := True;
                     end if;
                  end;
               end if;
            end loop;
            if Changed and then Rounds >= 64 then
               for II in 1 .. M.Last_Instance loop
                  if Derived_Eq_Ord (Real_Instance_Id (II)) then
                     Needs.Replace_Element
                       (Positive (II),
                        Need'(Never => True, On => <>));
                  end if;
               end loop;
               exit;
            end if;
         end loop;
      end Solve_Needs;

      --  primSameFun (sel d_k) prim && ... over N.On.
      function Struct_Test
        (Inst : Instance_Info; Params : Var_Id_Vectors.Vector; N : Need)
         return Real_Expr_Id
      is
         Acc : Real_Expr_Id := ConE (Env.True_DC);
      begin
         for K of reverse N.On loop
            declare
               Cl_K : constant Class_Id :=
                 Class_Id (Inst.Context (K).Class);
               Sel : constant Real_Expr_Id := V (Struct_Sel (Cl_K));
               D : constant Real_Expr_Id := V (Params.Element (K));
               Meth : constant Real_Expr_Id := Ap (Sel, D);
               Same_F : constant Real_Expr_Id := V (P_Same);
               Prim_V : constant Real_Expr_Id := V (Struct_Prim (Cl_K));
               Test : constant Real_Expr_Id := Ap2 (Same_F, Meth, Prim_V);
               No : constant Real_Expr_Id := ConE (Env.False_DC);
            begin
               Acc := Bool_Case (Test, Acc, No);
            end;
         end loop;
         return Acc;
      end Struct_Test;

      --  The structural dictionary: the primitives (the methods every
      --  wired and derived Eq/Ord had before M150).
      function Struct_Dict
        (Inst : Instance_Info; Params : Var_Id_Vectors.Vector)
         return Real_Expr_Id
      is
         Supers : constant Expr_Id_Vectors.Vector :=
           Super_Dicts (Inst, Params);
         Ms : Expr_Id_Vectors.Vector;
      begin
         if Inst.Of_Class = Env.Eq_Cl then
            declare
               X : constant Real_Var_Id := Fresh ("x");
               Y : constant Real_Var_Id := Fresh ("y");
            begin
               Ms.Append (V (P_EqP));
               Ms.Append
                 (Lam (X, Lam (Y,
                    Bool_Case
                      (Ap2 (V (P_EqP),
                            V (X), V (Y)),
                       ConE (Env.False_DC),
                       ConE (Env.True_DC)))));
            end;
         else
            Ms.Append (V (P_CmpP));   --  compare
            Ms.Append (Cmp_Method (Ordering_LT, False));  --  <
            Ms.Append (Cmp_Method (Ordering_GT, True));   --  <=
            if Inst.Head = Env.Double_TC
              or else Inst.Head = Env.Float_TC
            then
               --  IEEE: every comparison with a NaN is False.
               Ms.Append (Cmp_Method (Ordering_LT, False,
                                      Swap => True));  --  >
               Ms.Append (Cmp_Method (Ordering_GT, True,
                                      Swap => True));  --  >=
            else
               Ms.Append (Cmp_Method (Ordering_GT, False));
               Ms.Append (Cmp_Method (Ordering_LT, True));
            end if;
            Ms.Append (Max_Min (True));
            Ms.Append (Max_Min (False));
         end if;
         return Mk_Dict (M, Real_Class_Id (Inst.Of_Class), Supers, Ms,
                         Span);
      end Struct_Dict;

      --  case C of LT -> LT; EQ -> Rest; GT -> GT
      function Ord_Then (C, Rest : Real_Expr_Id) return Real_Expr_Id is
         Alts : Alt_Id_Vectors.Vector;
         LT_E : constant Real_Expr_Id := ConE (Ordering_LT);
         GT_E : constant Real_Expr_Id := ConE (Ordering_GT);
      begin
         Alts.Append (M.Add (Alt_Node'
           (Kind => Con_Alt, Span => Span, Alt_Body => LT_E,
            A_Con => Ordering_LT,
            Binders => Var_Id_Vectors.Empty_Vector)));
         Alts.Append (M.Add (Alt_Node'
           (Kind => Con_Alt, Span => Span, Alt_Body => Rest,
            A_Con => Ordering_LT + 1,
            Binders => Var_Id_Vectors.Empty_Vector)));
         Alts.Append (M.Add (Alt_Node'
           (Kind => Con_Alt, Span => Span, Alt_Body => GT_E,
            A_Con => Ordering_GT,
            Binders => Var_Id_Vectors.Empty_Vector)));
         return M.Add (Expr_Node'
           (Kind => Case_C, Span => Span, Scrutinee => C, Alts => Alts));
      end Ord_Then;

      --  The field-wise ==/compare (Report 11.1) as \x y -> ...: the
      --  same constructor compares its fields left to right through
      --  their own instances; different constructors are unequal, or
      --  order by declaration - primcompare decides that from the two
      --  tags alone (poly_cmp returns on differing contags before it
      --  reads a field). A field of the instance's own type calls
      --  Self, the let-bound function: a list or tree builds no
      --  dictionary per node.
      function Con_Body
        (Inst : Instance_Info; Params : Var_Id_Vectors.Vector;
         Self : Real_Var_Id) return Real_Expr_Id
      is
         Is_Ord : constant Boolean := Inst.Of_Class = Env.Ord_Cl;
         Cl : constant Real_Class_Id := Real_Class_Id (Inst.Of_Class);
         TC : constant Real_TyCon_Id := Real_TyCon_Id (Inst.Head);
         Sel : constant Var_Id := Struct_Sel (Inst.Of_Class);
         Head_T : constant Real_Type_Id :=
           Inst_Match.Instance_Type (M, Env, Inst);
         Multi : constant Boolean :=
           Natural (M.Info (TC).Cons.Length) > 1;
         X : constant Real_Var_Id := Fresh ("x");
         Y : constant Real_Var_Id := Fresh ("y");
         Outer : Alt_Id_Vectors.Vector;

         function Field_Op
           (FT : Real_Type_Id; Tvs : TyVar_Id_Vectors.Vector;
            A, B : Real_Var_Id) return Real_Expr_Id
         is
            Fn : Real_Expr_Id;
         begin
            if Same_Under (FT, Tvs, Head_T, Inst.Head_Vars) then
               Fn := V (Self);
            else
               declare
                  D : constant Expr_Id :=
                    Dict_At (FT, Cl, Tvs, Inst, Params);
               begin
                  if D = No_Expr then
                     return Err ((if Is_Ord then "deriving Ord"
                                  else "deriving Eq")
                                 & ": unsupported field type");
                  end if;
                  declare
                     S : constant Real_Expr_Id := V (Sel);
                  begin
                     Fn := Ap (S, Real_Expr_Id (D));
                  end;
               end;
            end if;
            declare
               AE : constant Real_Expr_Id := V (A);
               BE : constant Real_Expr_Id := V (B);
            begin
               return Ap2 (Fn, AE, BE);
            end;
         end Field_Op;
      begin
         for DCI of M.Info (TC).Cons loop
            declare
               DC : constant Real_DataCon_Id := Real_DataCon_Id (DCI);
               Tvs : constant TyVar_Id_Vectors.Vector :=
                 DC_Scheme (DC).Tvs;
               FTs : constant Type_Id_Vectors.Vector := Field_Types (DC);
               As, Bs : Var_Id_Vectors.Vector;
               Same : Real_Expr_Id;
               Inner : Alt_Id_Vectors.Vector;
               Inner_Case : Real_Expr_Id;
            begin
               for I in 1 .. FTs.Last_Index loop
                  As.Append (Fresh ("a"));
                  Bs.Append (Fresh ("b"));
               end loop;
               if not Is_Ord then
                  Same := ConE (Env.True_DC);
                  for I in reverse 1 .. FTs.Last_Index loop
                     declare
                        Test : constant Real_Expr_Id :=
                          Field_Op (Real_Type_Id (FTs (I)), Tvs,
                                    Real_Var_Id (As (I)),
                                    Real_Var_Id (Bs (I)));
                        No : constant Real_Expr_Id := ConE (Env.False_DC);
                     begin
                        Same := Bool_Case (Test, Same, No);
                     end;
                  end loop;
               elsif FTs.Is_Empty then
                  Same := ConE (Ordering_LT + 1);   --  EQ
               else
                  Same := Field_Op
                    (Real_Type_Id (FTs.Last_Element), Tvs,
                     Real_Var_Id (As.Last_Element),
                     Real_Var_Id (Bs.Last_Element));
                  for I in reverse 1 .. FTs.Last_Index - 1 loop
                     declare
                        C : constant Real_Expr_Id :=
                          Field_Op (Real_Type_Id (FTs (I)), Tvs,
                                    Real_Var_Id (As (I)),
                                    Real_Var_Id (Bs (I)));
                     begin
                        Same := Ord_Then (C, Same);
                     end;
                  end loop;
               end if;
               Inner.Append (M.Add (Alt_Node'
                 (Kind => Con_Alt, Span => Span, Alt_Body => Same,
                  A_Con => DC, Binders => Bs)));
               if Multi then
                  declare
                     Other : Real_Expr_Id;
                  begin
                     if Is_Ord then
                        declare
                           Cmp : constant Real_Expr_Id := V (P_CmpP);
                           XE : constant Real_Expr_Id := V (X);
                           YE : constant Real_Expr_Id := V (Y);
                        begin
                           Other := Ap2 (Cmp, XE, YE);
                        end;
                     else
                        Other := ConE (Env.False_DC);
                     end if;
                     Inner.Append (M.Add (Alt_Node'
                       (Kind => Default_Alt, Span => Span,
                        Alt_Body => Other)));
                  end;
               end if;
               declare
                  YS : constant Real_Expr_Id := V (Y);
               begin
                  Inner_Case := M.Add (Expr_Node'
                    (Kind => Case_C, Span => Span, Scrutinee => YS,
                     Alts => Inner));
               end;
               Outer.Append (M.Add (Alt_Node'
                 (Kind => Con_Alt, Span => Span, Alt_Body => Inner_Case,
                  A_Con => DC, Binders => As)));
            end;
         end loop;
         declare
            XS : constant Real_Expr_Id := V (X);
            Top : constant Real_Expr_Id := M.Add (Expr_Node'
              (Kind => Case_C, Span => Span, Scrutinee => XS,
               Alts => Outer));
         begin
            return Lam (X, Lam (Y, Top));
         end;
      end Con_Body;

      --  let f = <Con_Body> in MkDict supers f <methods over f>
      function Fieldwise_Dict
        (Inst : Instance_Info; Params : Var_Id_Vectors.Vector)
         return Real_Expr_Id
      is
         Is_Ord : constant Boolean := Inst.Of_Class = Env.Ord_Cl;
         F : constant Real_Var_Id := Fresh (if Is_Ord then "cmp" else "eq");
         Body_F : constant Real_Expr_Id := Con_Body (Inst, Params, F);
         Supers : constant Expr_Id_Vectors.Vector :=
           Super_Dicts (Inst, Params);
         Ms : Expr_Id_Vectors.Vector;
         Binds : Bind_Vectors.Vector;
         Dict : Real_Expr_Id;
      begin
         Ms.Append (V (F));
         if Is_Ord then
            Ms.Append (Cmp_Method (Ordering_LT, False, Using => F));  --  <
            Ms.Append (Cmp_Method (Ordering_GT, True, Using => F));   --  <=
            Ms.Append (Cmp_Method (Ordering_GT, False, Using => F));  --  >
            Ms.Append (Cmp_Method (Ordering_LT, True, Using => F));   --  >=
            Ms.Append (Max_Min (True, Using => F));
            Ms.Append (Max_Min (False, Using => F));
         else
            declare
               X : constant Real_Var_Id := Fresh ("x");
               Y : constant Real_Var_Id := Fresh ("y");
               FE : constant Real_Expr_Id := V (F);
               XE : constant Real_Expr_Id := V (X);
               YE : constant Real_Expr_Id := V (Y);
               Call : constant Real_Expr_Id := Ap2 (FE, XE, YE);
               No : constant Real_Expr_Id := ConE (Env.False_DC);
               Yes : constant Real_Expr_Id := ConE (Env.True_DC);
            begin
               Ms.Append (Lam (X, Lam (Y, Bool_Case (Call, No, Yes))));
            end;
         end if;
         Dict := Mk_Dict (M, Real_Class_Id (Inst.Of_Class), Supers, Ms,
                          Span);
         Binds.Append (Bind_Pair'(Binder => F, Rhs => Body_F));
         return M.Add (Expr_Node'
           (Kind => Let_C, Span => Span, Is_Rec => True,
            Binds => Binds, Let_Body => Dict));
      end Fieldwise_Dict;

      --  Every wired and derived Eq/Ord dictionary: structural,
      --  field-wise, or \ds -> case <test ds> of True -> structural;
      --  _ -> field-wise.
      procedure Build_Eq_Ord (II : Real_Instance_Id) is
         Inst : constant Instance_Info := M.Info (II);
         Params : Var_Id_Vectors.Vector;
         N : Need;
         Dict : Real_Expr_Id;
      begin
         for CI in 1 .. Inst.Context.Last_Index loop
            Params.Append (Fresh ("$d"));
            pragma Unreferenced (CI);
         end loop;
         if Inst.Is_Derived then
            N := Needs (Positive (II));
         else
            --  Wired: [a], Maybe a, (a, b) test every element; Int,
            --  Char, Double, Text, Ptr ... have no context and are
            --  structural outright.
            for K in 1 .. Inst.Context.Last_Index loop
               Add (N, K);
            end loop;
         end if;
         if N.Never then
            Dict := Fieldwise_Dict (Inst, Params);
         elsif N.On.Is_Empty then
            Dict := Struct_Dict (Inst, Params);
         else
            declare
               Test : constant Real_Expr_Id :=
                 Struct_Test (Inst, Params, N);
               SD : constant Real_Expr_Id := Struct_Dict (Inst, Params);
               FD : constant Real_Expr_Id :=
                 Fieldwise_Dict (Inst, Params);
            begin
               Dict := Bool_Case (Test, SD, FD);
            end;
         end if;
         for PI in reverse 1 .. Params.Last_Index loop
            Dict := Lam (Params (PI), Dict);
         end loop;
         Bind (Inst.Dict_Global, Dict);
      end Build_Eq_Ord;
```

- [ ] **Step 5: wire it into the instance loop.** Immediately before
  `for II in 1 .. M.Last_Instance loop` (1829) add:

```ada
      --  M150 D1: which derived Eq/Ord dictionaries are structural.
      Solve_Needs;

```

  Replace the two arms at 1859-1892:

```ada
                  if Cl_Id = Env.Eq_Cl then
                     declare
                        X : constant Real_Var_Id := Fresh ("x");
                        Y : constant Real_Var_Id := Fresh ("y");
                     begin
                        Ms.Append (V (P_EqP));
                        ...
                     Give_Dict (Real_Instance_Id (II), Ms);
                  elsif Cl_Id = Env.Ord_Cl then
                     Ms.Append (V (P_CmpP));   --  compare
                     ...
                     Give_Dict (Real_Instance_Id (II), Ms);
                  elsif Cl_Id = Env.Num_Cl
```

  with:

```ada
                  if Cl_Id = Env.Eq_Cl or else Cl_Id = Env.Ord_Cl then
                     --  M150 D1: structural, field-wise, or decided
                     --  when the dictionary is built.
                     Build_Eq_Ord (Real_Instance_Id (II));
                  elsif Cl_Id = Env.Num_Cl
```

- [ ] **Step 6: header comment.** In `src/ahc-prelude_core.ads:8-10`,
  replace

```
--    - structural equality/comparison prims cover Eq and Ord for all
--      first-order values (including user ADTs, hence derived Eq/Ord),
```

  with

```
--    - structural equality/comparison prims cover Eq and Ord wherever
--      every instance a dictionary reaches is structural (M150);
--      otherwise derived and wired Eq/Ord compare field-wise through
--      the components' own instances,
```

- [ ] **Step 7: regression tests** are `m150_structural_eq.hs` and
  `m150_overlap_eq.hs` from Task D1. `m150_ord_superclass.hs` stays
  green. The bench program `b_streq.hs` is the evidence that the
  structural path is still taken for strings and `[Int]`: if the
  pointer test never matched, every list comparison would go
  field-wise and `b_streq` would slow down visibly.
- [ ] **Step 8: verify.**

```sh
alr exec -- gcc -c -gnatc -gnat2022 -gnatwa -Isrc src/ahc-prelude_core.adb -o $SCRATCH/ck/pc.o
alr build --validation
T=$(mktemp -d)
for f in m150_structural_eq m150_overlap_eq m150_ord_superclass; do
  ./bin/ahc build tests/conformance/$f.hs -o $T/$f && \
    diff tests/conformance/$f.out <($T/$f) && echo "ok $f"
done                                              # three "ok" lines
scripts/run_gate.sh                               # GATE ok (exec-own runs AHC_GC=own)
scripts/run_discharge.sh                          # 4 x ok, as before
scripts/run_separate.sh                           # green
alr build --release && scripts/run_bench.sh > $SCRATCH/bench_post_D4.txt
grep -E '^(b_sort|b_map|b_strings|b_streq) ' $SCRATCH/bench_pre_D.txt $SCRATCH/bench_post_D4.txt
```

  The `opt` column of `b_sort`, `b_map`, `b_strings` and `b_streq`
  must be within 2% of the baseline. If `b_streq` regresses, check
  that `ahc emit tests/bench/b_streq.hs $T/b` puts `ahc_prim_eq_poly`
  (not a lambda) in the `$dEqChar` dictionary, and that
  `ahc_prim_same_fun` evaluates both sides.
- [ ] **Step 9: commit:**
  `fix(prelude-core): eq and ord call a component's own instance unless every dictionary they reach is structural`.
  The body names the `max`/`min` tie rule (Report 6.3.2) and the
  closed `Eq [Bool]` overlap gap. Trailer:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

---

### Task D5: inferred derived contexts and compile-time missing instances (spec D2)

**Files:**
- Modify: `src/ahc-typechecker.adb:1007-1012` (`Solve`'s message)
- Modify: `src/ahc-typechecker.adb:1957-2257`:
  - `Constraint_Text`, `Reduce_State`, `Spine_Is_Var` and
    `Reduce_Context` move to `Check_Module` scope;
  - `Resolve_GND_Now` uses them;
  - `Infer_Derived_Contexts` is new.
- Modify: `src/ahc-typechecker.adb:2259-2265` (pre-pass), `:2362-2372` (superclass message)
- Test: `tests/golden/check_m150_derive_errors.hs` + `.types`
- Test: `tests/src/test_typechecker.adb` (two cases)
- Test: the corpus-types files from Task D1

**Interfaces:**
- Consumes: `Instance_Info.Is_Derived` and the class-name `Span` (Task D2).
- Produces:
  - `function Constraint_Text (C : Class_Id; T : Real_Type_Id) return String`
    (`C T`, with T parenthesised when it is an application or a
    function type that is not already bracketed);
  - `type Reduce_State`;
  - `procedure Reduce_Context (S : in out Reduce_State; C : Class_Id; T : Real_Type_Id; D, Depth : Natural)`;
  - `procedure Infer_Derived_Contexts`.
  - After the pre-pass, every stock-derived instance of a type with
    constructors (Functor family excluded) has the least context its
    fields need, over its own `Head_Vars`.

- [ ] **Step 1: `Constraint_Text`.** Insert before
  `procedure Resolve_GND (II : Real_Instance_Id; Depth : Natural);`
  (1965). This is `Resolve_GND_Now`'s `Shown` (1989-1998) moved out
  and renamed:

```ada
      --  `C T` for a message, as GHC prints a constraint: T in
      --  parentheses when it is an application or a function type
      --  not already bracketed (M150: was 'Eq Int -> Int').
      function Constraint_Text (C : Class_Id; T : Real_Type_Id)
        return String
      is
         Img : constant String := Type_Str (T);
      begin
         return Table.Text (M.Info (Real_Class_Id (C)).Name) & " "
           & (if M.Node (Repr (T)).Kind in TApp_T | TFun_T
                and then Img (Img'First) not in '(' | '['
              then "(" & Img & ")" else Img);
      end Constraint_Text;
```

  In `Solve` (1007-1012), the message

```ada
                        "no instance for '"
                        & Table.Text (M.Info (W.C.Class).Name) & " "
                        & Type_Str (W.C.Arg) & "'");
```

  becomes `"no instance for '" & Constraint_Text (W.C.Class, W.C.Arg) & "'");`.
  In the superclass check (2366-2372),

```ada
                                 "no instance for '"
                                 & Table.Text
                                     (M.Info (W_List (I).C.Class).Name)
                                 & " " & Type_Str (W_List (I).C.Arg)
                                 & "', required by the superclasses"
```

  becomes
  `"no instance for '" & Constraint_Text (W_List (I).C.Class, W_List (I).C.Arg) & "', required by the superclasses"`.
  Phase C's hint lines, if present, follow unchanged.

- [ ] **Step 2: extract the reducer.** Insert after `Constraint_Text`,
  before `procedure Resolve_GND (...)` (1965) and `GND_Active` (1967),
  which stay in place. The body is `Resolve_GND_Now.Reduce`
  (2041-2154) with its closure made explicit:

```ada
      --  Derived-context inference, shared by GND (M147) and stock
      --  deriving (M150): reduce `C T` to constraints on type
      --  variables. A constraint equal to the instance's own head is
      --  satisfied by the (recursive) dictionary itself; any other is
      --  reduced through its one matching instance (M147 review:
      --  copying the instance context unreduced ran as $dMISSING).
      --  The first failure is recorded, not reported: each caller
      --  words its own message.
      type Reduce_Failure is (No_Failure, No_Instance, Overlapping, Cyclic);

      type Reduce_State is record
         Self       : Real_Instance_Id := 1;
         Self_Class : Class_Id := No_Class;
         Self_Head  : Real_Type_Id := Real_Type_Id'First;
         --  GND: never select the instance itself (its head IS the
         --  representation's) and resolve matching newtypes on
         --  demand. Stock: the instance may meet itself at other
         --  arguments (`data N a = N (N [a])`).
         For_GND    : Boolean := False;
         Span       : Diagnostics.Source_Span;
         Ctx        : Constraint_Vectors.Vector;
         Failure    : Reduce_Failure := No_Failure;
         Fail_Class : Class_Id := No_Class;
         Fail_Type  : Type_Id := No_Type;
      end record;

      procedure Resolve_GND (II : Real_Instance_Id; Depth : Natural);

      GND_Active : Instance_Id_Vectors.Vector;   --  being resolved

      function Spine_Is_Var (T : Real_Type_Id) return Boolean is
         N : constant Type_Node := M.Node (Repr (T));
      begin
         case N.Kind is
            when TVar_T => return True;
            when TApp_T => return Spine_Is_Var (N.T_Fun);
            when others => return False;
         end case;
      end Spine_Is_Var;

      procedure Reduce_Context
        (S : in out Reduce_State; C : Class_Id; T : Real_Type_Id;
         D : Natural; Depth : Natural)
      is
         Hits : Natural := 0;
         Pending : Boolean := False;
         Hit : Real_Instance_Id := S.Self;
         Hit_Args : Type_Id_Vectors.Vector;
         Hit_Ids : Instance_Id_Vectors.Vector;

         procedure Fail (K : Reduce_Failure) is
         begin
            S.Failure := K;
            S.Fail_Class := C;
            S.Fail_Type := Type_Id (T);
         end Fail;
      begin
         if S.Failure /= No_Failure or else D > 40 then
            return;
         elsif M.Node (Repr (T)).Kind = TVar_T
           or else Spine_Is_Var (T)
         then
            --  A type variable, or one applied (`Eq (f a)` for
            --  `newtype Wrap f a = Wrap (f a)`), cannot be reduced:
            --  it joins the context as GHC infers it.
            for Old of S.Ctx loop
               if Old.Class = C and then Same_Arg (Old.Arg, T) then
                  return;
               end if;
            end loop;
            S.Ctx.Append (Constraint'(Class => C, Arg => T,
                                      Span => S.Span));
            return;
         elsif C = S.Self_Class and then Same_Arg (T, S.Self_Head) then
            return;
         end if;
         for J of M.Info (Real_Class_Id (C)).Instances loop
            if J /= S.Self or else not S.For_GND then
               --  An unresolved GND instance still matches by its
               --  head TyCon (Haskell 2010 rule), so match FIRST and
               --  resolve only an instance that matches: resolving
               --  every one met here reached back into instances in
               --  progress and reported false cycles.
               if S.For_GND
                 and then M.Info (J).Is_GND
                 and then M.Info (J).GND_Target = No_Type
                 and then not GND_Active.Contains (J)
               then
                  declare
                     A0 : Type_Id_Vectors.Vector;
                  begin
                     if Inst_Match."=" (Match_TC (M, Env, M.Info (J), T, A0),
                                        Inst_Match.Matched)
                     then
                        Resolve_GND (J, Depth + 1);
                     end if;
                  end;
               end if;
               declare
                  A : Type_Id_Vectors.Vector;
                  MR : constant Inst_Match.Match_Result :=
                    Match_TC (M, Env, M.Info (J), T, A);
               begin
                  if Inst_Match."=" (MR, Inst_Match.Matched)
                    and then M.Info (J).Is_GND
                    and then GND_Active.Contains (J)
                    and then M.Info (J).GND_Target = No_Type
                  then
                     --  A matching newtype instance still being
                     --  resolved: A = A B, B = B A (M147 review).
                     Fail (Cyclic);
                     return;
                  elsif Inst_Match."=" (MR, Inst_Match.Matched) then
                     Hits := Hits + 1;
                     Hit := J;
                     Hit_Args := A;
                     Hit_Ids.Append (J);
                  elsif Inst_Match."=" (MR, Inst_Match.Undecided)
                    and then M.Info (J).Overlap /= Incoherent
                    and then not Only_Apart_Vars (T)
                  then
                     Pending := True;
                  end if;
               end;
            end if;
         end loop;
         if Hits > 1 then
            declare
               P : constant Natural := Inst_Match.Pick (M, Env, Hit_Ids);
            begin
               if P /= 0 then
                  Hit := Real_Instance_Id (P);
                  declare
                     Ign : constant Inst_Match.Match_Result :=
                       Match_TC (M, Env, M.Info (Hit), T, Hit_Args);
                     pragma Unreferenced (Ign);
                  begin
                     Hits := 1;
                  end;
               end if;
            end;
         end if;
         if Hits = 1 and then M.Info (Hit).Overlap = Incoherent then
            Pending := False;
         end if;
         if Hits = 0 and then not Pending then
            Fail (No_Instance);
            return;
         elsif Hits > 1 or else Pending then
            Fail (Overlapping);
            return;
         end if;
         declare
            HI : constant Instance_Info := M.Info (Hit);
            Map : TyVar_Type_Maps.Map;
         begin
            for VI in 1 .. HI.Head_Vars.Last_Index loop
               if VI <= Hit_Args.Last_Index then
                  Map.Include (HI.Head_Vars (VI), Hit_Args.Element (VI));
               end if;
            end loop;
            for IC of HI.Context loop
               Reduce_Context (S, IC.Class, Subst_TyVars (IC.Arg, Map),
                               D + 1, Depth);
            end loop;
         end;
      end Reduce_Context;
```

- [ ] **Step 3: `Resolve_GND_Now` uses it.**
  - Delete the now-moved declarations: the original
    `procedure Resolve_GND (...)` spec at 1965 and `GND_Active` at 1967
    (both moved above), `Shown` (1988-1998), `Spine_Is_Var`
    (2013-2023) and `Reduce` (2034-2154). Keep `Name`, `Occurs` and
    `Fail (Msg : String)`.
  - Add `S : Reduce_State;` to `Resolve_GND_Now`'s declarations after
    `Failed : Boolean := False;`.
  - Replace the call `Reduce (Class_Id (Cl), Target, 0);` (2197) with:

```ada
         S.Self := II;
         S.Self_Class := Class_Id (Cl);
         S.Self_Head := Head_T;
         S.For_GND := True;
         S.Span := Inst.Span;
         Reduce_Context (S, Class_Id (Cl), Target, 0, Depth);
         case S.Failure is
            when No_Failure =>
               null;
            when No_Instance =>
               Fail ("no instance '"
                     & Constraint_Text (S.Fail_Class,
                                        Real_Type_Id (S.Fail_Type))
                     & "'");
            when Overlapping =>
               Fail ("overlapping instances for '"
                     & Constraint_Text (S.Fail_Class,
                                        Real_Type_Id (S.Fail_Type))
                     & "'");
            when Cyclic =>
               Fail ("its representation is cyclic");
         end case;
         Ctx := S.Ctx;
```

  The rest of `Resolve_GND_Now` is unchanged, including the derived
  Monad's Applicative check (or phase C's replacement for it) and the
  final `M.Instances (II).Context := Ctx;`.

- [ ] **Step 4: `Infer_Derived_Contexts`.** Insert after
  `end Resolve_GND;` (2257):

```ada
      --  M150 D2: a stock-derived instance's context is inferred from
      --  its constructors' fields, as GHC infers it - a phantom
      --  parameter needs nothing, and a field without an instance is a
      --  compile error at the deriving clause's class name, never a
      --  run-time "unsupported field type". Contexts restart empty (the
      --  renamer's one-per-variable placeholders are dropped) and grow
      --  to the least fixpoint, so mutually recursive types settle
      --  (`data E a = EZ | ES a (O a)`, `data O a = OS a (E a)`). Runs
      --  after GND resolution, which reads the placeholders (deviation
      --  2). Field types are substituted onto the instance's own
      --  Head_Vars: a context mentions only those, and they are what
      --  Only_Apart_Vars recognises as rigid instance variables.
      procedure Infer_Derived_Contexts is

         --  GHC's speakNth: first .. sixth, then 7th, 21st, 22nd ...
         function Ordinal (N : Positive) return String is
            Img : constant String := Positive'Image (N);
            Num : constant String := Img (Img'First + 1 .. Img'Last);
         begin
            case N is
               when 1 => return "first";
               when 2 => return "second";
               when 3 => return "third";
               when 4 => return "fourth";
               when 5 => return "fifth";
               when 6 => return "sixth";
               when others =>
                  return Num & (if N <= 20 then "th"
                                elsif N mod 10 = 1 then "st"
                                elsif N mod 10 = 2 then "nd"
                                elsif N mod 10 = 3 then "rd"
                                else "th");
            end case;
         end Ordinal;

         function Is_Inferred (II : Real_Instance_Id) return Boolean is
            Inst : constant Instance_Info := M.Info (II);
         begin
            return Inst.Is_Derived
              and then Inst.Stock_Derive = No_Stock_Derive
              and then not Inst.Is_GND
              and then Inst.Head /= No_TyCon
              and then not M.Info (Real_TyCon_Id (Inst.Head)).Cons.Is_Empty;
         end Is_Inferred;

         function Same_Context (A, B : Constraint_Vectors.Vector)
           return Boolean is
         begin
            if A.Last_Index /= B.Last_Index then
               return False;
            end if;
            for I in 1 .. A.Last_Index loop
               if A (I).Class /= B (I).Class
                 or else not Same_Arg (A (I).Arg, B (I).Arg)
               then
                  return False;
               end if;
            end loop;
            return True;
         end Same_Context;

         procedure Report_Missing
           (II : Real_Instance_Id; S : Reduce_State; K : Positive;
            Con : Names.Name_Id; FT, Head_T : Real_Type_Id)
         is
            Inst : constant Instance_Info := M.Info (II);
         begin
            if Natural (II) <= Inst_Origins.Last_Index then
               Bag.Set_Origin (Inst_Origins (Natural (II)));
            end if;
            Bag.Add
              (Diagnostics.Error, Diagnostics.Class_No_Instance, Inst.Span,
               (if S.Failure = Overlapping
                then "overlapping instances for '"
                else "no instance for '")
               & Constraint_Text (S.Fail_Class, Real_Type_Id (S.Fail_Type))
               & "', arising from the " & Ordinal (K) & " field of '"
               & Table.Text (Names.Real_Name_Id (Con))
               & "' (type '" & Type_Str (FT) & "'), when deriving '"
               & Constraint_Text (Inst.Of_Class, Head_T) & "'");
         end Report_Missing;

         procedure Infer_One
           (II : Real_Instance_Id; Report : Boolean;
            Changed : in out Boolean)
         is
            Inst : constant Instance_Info := M.Info (II);
            TCI : constant TyCon_Info := M.Info (Real_TyCon_Id (Inst.Head));
            Head_T : Real_Type_Id := TCon (Inst.Head);
            Vars_T : Type_Id_Vectors.Vector;
            S : Reduce_State;
         begin
            for HV of Inst.Head_Vars loop
               declare
                  VT : constant Real_Type_Id := M.Add (Type_Node'
                    (Kind => TVar_T, Tv => Real_TyVar_Id (HV)));
               begin
                  Vars_T.Append (Type_Id (VT));
                  Head_T := Make_App (Head_T, VT);
               end;
            end loop;
            S.Self := II;
            S.Self_Class := Inst.Of_Class;
            S.Self_Head := Head_T;
            S.For_GND := False;
            S.Span := Inst.Span;
            for DCI of TCI.Cons loop
               declare
                  DCInfo : constant DataCon_Info :=
                    M.Info (Real_DataCon_Id (DCI));
                  Sch : constant Scheme :=
                    M.Node (Real_Scheme_Id (DCInfo.Con_Scheme));
                  Map : TyVar_Type_Maps.Map;
                  T : Real_Type_Id := Real_Type_Id (Sch.S_Body);
                  K : Natural := 0;
               begin
                  for I in 1 .. Natural'Min (Sch.Tvs.Last_Index,
                                             Vars_T.Last_Index)
                  loop
                     Map.Include (Real_TyVar_Id (Sch.Tvs (I)),
                                  Real_Type_Id (Vars_T (I)));
                  end loop;
                  while M.Node (T).Kind = TFun_T loop
                     K := K + 1;
                     declare
                        FT : constant Real_Type_Id :=
                          Subst_TyVars (M.Node (T).From, Map);
                     begin
                        Reduce_Context (S, Inst.Of_Class, FT, 0, 0);
                        if S.Failure /= No_Failure then
                           if Report then
                              Report_Missing (II, S, K, DCInfo.Name, FT,
                                              Head_T);
                           end if;
                           return;
                        end if;
                     end;
                     T := M.Node (T).To;
                  end loop;
               end;
            end loop;
            if not Same_Context (S.Ctx, Inst.Context) then
               M.Instances (II).Context := S.Ctx;
               Changed := True;
            end if;
         end Infer_One;

         Changed : Boolean := True;
         Rounds : Natural := 0;
      begin
         for II in 1 .. M.Last_Instance loop
            if Is_Inferred (Real_Instance_Id (II)) then
               M.Instances (Real_Instance_Id (II)).Context.Clear;
            end if;
         end loop;
         while Changed and then Rounds < 50 loop
            Changed := False;
            Rounds := Rounds + 1;
            for II in 1 .. M.Last_Instance loop
               if Is_Inferred (Real_Instance_Id (II)) then
                  Infer_One (Real_Instance_Id (II), False, Changed);
               end if;
            end loop;
         end loop;
         --  One reporting pass over the settled contexts: the first
         --  missing field instance of each derived instance.
         for II in 1 .. M.Last_Instance loop
            if Is_Inferred (Real_Instance_Id (II)) then
               Infer_One (Real_Instance_Id (II), True, Changed);
            end if;
         end loop;
      end Infer_Derived_Contexts;
```

  In the pre-pass (2259-2265), after the GND loop:

```ada
      for II in 1 .. M.Last_Instance loop
         Resolve_GND (Real_Instance_Id (II), 0);
      end loop;
      --  M150 D2: then the stock-derived contexts, from the fields.
      Infer_Derived_Contexts;
```

  The Prelude_Core side needs no change. `Derive_Show`, `Derive_Read`
  and `Build_Eq_Ord` already make one parameter per (now inferred)
  context constraint, and `Dict_At`/`Need_Of_Type` look constraints up
  by type (Task D3).

- [ ] **Step 5: golden for the exact texts.**
  `tests/golden/check_m150_derive_errors.hs`:

```haskell
data F = F

data T = T Int F deriving Show

data U = U [F] | V deriving (Eq)

data R = R { g :: Int -> Int } deriving Eq

data W a = W a F deriving (Eq, Ord)

data Q = Q Int Bool (Maybe F) deriving (Read)

data K = K (IO ()) deriving (Show)

main :: IO ()
main = return ()
```

  GHC 9.4.8 (`ghc -fno-code`) rejects each instance at the same
  line:column, with these constraints and field ordinals:
  - `3:27` (Show F) arising from the second field of 'T' (type 'F');
  - `5:30` (Eq F), first field of 'U' (type '[F]');
  - `7:41` (Eq (Int -> Int)), first field of 'R';
  - `9:28` (Eq F) and `9:32` (Ord F), second field of 'W';
  - `11:41` (Read F), third field of 'Q' (type 'Maybe F');
  - `13:30` (Show (IO ())), first field of 'K'.

  Write `tests/golden/check_m150_derive_errors.types` as exactly:

```
tests/golden/check_m150_derive_errors.hs:3:27: error: no instance for 'Show F', arising from the second field of 'T' (type 'F'), when deriving 'Show T'
tests/golden/check_m150_derive_errors.hs:5:30: error: no instance for 'Eq F', arising from the first field of 'U' (type '[F]'), when deriving 'Eq U'
tests/golden/check_m150_derive_errors.hs:7:41: error: no instance for 'Eq (Int -> Int)', arising from the first field of 'R' (type 'Int -> Int'), when deriving 'Eq R'
tests/golden/check_m150_derive_errors.hs:9:28: error: no instance for 'Eq F', arising from the second field of 'W' (type 'F'), when deriving 'Eq (W a)'
tests/golden/check_m150_derive_errors.hs:9:32: error: no instance for 'Ord F', arising from the second field of 'W' (type 'F'), when deriving 'Ord (W a)'
tests/golden/check_m150_derive_errors.hs:11:41: error: no instance for 'Read F', arising from the third field of 'Q' (type 'Maybe F'), when deriving 'Read Q'
tests/golden/check_m150_derive_errors.hs:13:30: error: no instance for 'Show (IO ())', arising from the first field of 'K' (type 'IO ()'), when deriving 'Show K'
```

  Then check it with `diff <(./bin/ahc check tests/golden/check_m150_derive_errors.hs 2>&1) tests/golden/check_m150_derive_errors.types`.
  Do not create the file with `--update`.

- [ ] **Step 6: unit tests.** In `tests/src/test_typechecker.adb`,
  before `end Run;`:

```ada
      --  M150 D2: derived contexts are inferred from the fields.
      Check_Equal
        (TC ("data F = F" & ASCII.LF
             & "data T = T Int F deriving Show"),
         "!errors: 1",
         "derived Show without a field instance is a compile error");

      Check_Equal
        (TC ("data Ph a = Ph Int deriving Eq" & ASCII.LF
             & "same = Ph 1 == (Ph 1 :: Ph (Int -> Int))"),
         "same :: Bool",
         "a phantom parameter needs no Eq");
```

- [ ] **Step 7: lib and Prelude audit.** Derived instances in
  `prelude/` and `lib/` are now checked. Run
  `for f in $(find lib -name '*.hs'); do ./bin/ahc check $f >/dev/null 2>&1 || echo "REJECT $f"; done`.
  It must print nothing. A rejection there is a real latent bug: a
  field with no instance used to fail only when shown. Fix the
  library type, not the checker.
- [ ] **Step 8: verify.**

```sh
alr exec -- gcc -c -gnatc -gnat2022 -gnatwa -Isrc src/ahc-typechecker.adb -o $SCRATCH/ck/tc.o
alr build --validation
(cd tests && alr build --validation && ./bin/ahc_tests)  # 361 tests, all pass
diff <(./bin/ahc check tests/golden/check_m150_derive_errors.hs 2>&1) \
     tests/golden/check_m150_derive_errors.types         # no output
scripts/run_differential_types.sh                        # all ok, incl. the four m150 files
T=$(mktemp -d)
./bin/ahc build tests/conformance/m150_derived_context.hs -o $T/dc && \
  diff tests/conformance/m150_derived_context.out <($T/dc)   # no output
for f in tests/corpus-types/bad_gnd_*.hs tests/corpus-types/bad_m147r_gnd_*.hs; do
  ./bin/ahc check "$f" 2>&1 | head -1
done        # every GND message as before, apart from the class-name column (Task D2)
scripts/run_gate.sh                                      # GATE ok
```

- [ ] **Step 9: commit:**
  `feat(typechecker): derived contexts are inferred from the fields, and a missing field instance is a compile error at the deriving clause`
  with trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

---

### Task D6: derived Enum errors carry GHC's call stack (spec D3)

**Files:**
- Modify: `src/ahc_main.adb:1023-1059` (the root/import `Desugar_Module` call)
- Modify: `src/ahc-prelude_core.adb:487-535` (`To_E_Lam` and its comment), `:540-574` (`Derive_Enum`)

**Interfaces:**
- Consumes:
  - `Instance_Info.Is_Derived`, `Derive_Loc` and the class-name `Span`
    (Task D2);
  - `AHC.Sites.Call_Stack (Ctx, "error", Span)`, which returns
    `"CallStack (from HasCallStack):" & LF & "  error, called at F:L:C in main:Mod"`
    (`src/ahc-sites.adb:219-240`; `Base_Frames ("error")` is `""`).
- Produces:
  - `function Err_At (Msg : Real_Expr_Id; Loc : Names.Name_Id) return Real_Expr_Id`
    and an overload of it taking a `String` message;
  - `To_E_Lam (TC; Loc : Names.Name_Id := Names.No_Name)`.

- [ ] **Step 1: stamp the location after desugaring.** Today the call
  passes the context inline:

```ada
               if not Bag.Has_Errors then
                  AHC.Desugar.Desugar_Module
                    (L.Ref.all, L_Res, Table, Bag, M, Env, Sigs,
                     L_Annos, L_Preds,
                     Warn_Matches => Is_Root,
                     ...
                     Ctx =>
                       (if L.Ref.Is_Library or else L.Ref.Own_Shadows
                        then AHC.Sites.No_Context
                        else (File => ..., Module => ..., Src => L.Text,
                              Span_File => ...)));
               end if;
```

  Hoist the context into a constant. The conditional expression moves
  verbatim, including its comments, from `Ctx =>` into `Site_Ctx`'s
  initialiser. Then stamp the module's derived Enum instances:

```ada
               if not Bag.Has_Errors then
                  declare
                     use type AHC.Core.Class_Id;
                     Site_Ctx : constant AHC.Sites.Site_Context :=
                       (if L.Ref.Is_Library or else L.Ref.Own_Shadows
                        then AHC.Sites.No_Context
                        else (File =>
                                Ada.Strings.Unbounded.To_Unbounded_String
                                  (if Is_Root
                                   then AHC.Sites.Normalise
                                          (Ada.Strings.Unbounded.To_String
                                             (L.Path))
                                   else Ada.Strings.Unbounded.To_String
                                          (L.Path)),
                              Module =>
                                Ada.Strings.Unbounded.To_Unbounded_String
                                  (Table.Text
                                     (AHC.Names.Real_Name_Id (L.Name))),
                              Src => L.Text,
                              Span_File =>
                                Ada.Strings.Unbounded.To_Unbounded_String
                                  (AHC.Sites.Normalise
                                     (Ada.Strings.Unbounded.To_String
                                        (L.Path)))));
                  begin
                     AHC.Desugar.Desugar_Module
                       (L.Ref.all, L_Res, Table, Bag, M, Env, Sigs,
                        L_Annos, L_Preds,
                        Warn_Matches => Is_Root,
                        Ctx => Site_Ctx);
                     --  M150 D3: a derived Enum of this module raises
                     --  its succ/pred/toEnum errors with GHC's call
                     --  stack at the deriving clause's class name (the
                     --  instance's span since Task D2). A library
                     --  module's stays plain: GHC's is base's.
                     if AHC.Sites.Enabled (Site_Ctx) then
                        for II in I0 + 1 .. Natural (M.Last_Instance) loop
                           declare
                              Id : constant AHC.Core.Real_Instance_Id :=
                                AHC.Core.Real_Instance_Id (II);
                              Inst : constant AHC.Core.Instance_Info :=
                                M.Info (Id);
                           begin
                              if Inst.Is_Derived
                                and then Inst.Of_Class = Env.Enum_Cl
                              then
                                 M.Instances (Id).Derive_Loc :=
                                   AHC.Names.Name_Id (Table.Intern
                                     (AHC.Sites.Call_Stack
                                        (Site_Ctx, "error", Inst.Span)));
                              end if;
                           end;
                        end loop;
                     end if;
                  end;
               end if;
```

  The multi-module expectation (`./Shapes.hs` in a call stack, `Main.hs`
  for the root) is exactly the `File` rule this context already
  implements for M149. Nothing new is needed for paths.

- [ ] **Step 2: `Err_At`.** Insert before
  `function Is_Wired_Enum` (line 487):

```ada
      --  error Msg, or (M150 D3) primErrorLoc Msg Loc: the ErrorCall
      --  then shows GHC's call stack at the deriving clause.
      function Err_At (Msg : Real_Expr_Id; Loc : Names.Name_Id)
        return Real_Expr_Id is
      begin
         if Names."=" (Loc, Names.No_Name) then
            declare
               Fn : constant Real_Expr_Id := V (Env.Error_V);
            begin
               return Ap (Fn, Msg);
            end;
         end if;
         declare
            Fn : constant Real_Expr_Id := V (Lookup ("primErrorLoc"));
            L : constant Real_Expr_Id :=
              Str (Table.Text (Names.Real_Name_Id (Loc)));
         begin
            return Ap2 (Fn, Msg, L);
         end;
      end Err_At;

      function Err_At (Msg : String; Loc : Names.Name_Id)
        return Real_Expr_Id
      is
         S : constant Real_Expr_Id := Str (Msg);
      begin
         return Err_At (S, Loc);
      end Err_At;
```

- [ ] **Step 3: `To_E_Lam`.**
  - Change the comment at 489-494. The text "(GHC also prints a call
    stack at the deriving clause there, which AHC does not -
    EXCLUSIONS.)" becomes "A derived one in a user module raises
    through primErrorLoc with GHC's call stack at the deriving clause
    (M150)."
  - Change the profile to
    `function To_E_Lam (TC : Real_TyCon_Id; Loc : Names.Name_Id := Names.No_Name) return Real_Expr_Id is`.
  - In the `else` branch, delete
    `Err_Fn : constant Real_Expr_Id := V (Env.Error_V);` and change
    `Body_E := Ap (Err_Fn, Msg);` to `Body_E := Err_At (Msg, Loc);`.
  - `Map_To_E` keeps calling `To_E_Lam (TC)`: its enumerations stay in
    range, so they never fail.
- [ ] **Step 4: `Derive_Enum`.** After `N : constant Positive := ...` (542) add:

```ada
         --  M150 D3: GHC's call stack at the deriving clause, or
         --  No_Name (library module: plain error, as before).
         Loc : constant Names.Name_Id := M.Info (II).Derive_Loc;
```

  `Succ_F`/`Pred_F` (552-563) become:

```ada
         function Succ_F (Tag : Positive) return Real_Expr_Id
         is (if Tag < N then ConE (M.Info (TC).Cons (Tag + 1))
             elsif Wired then Err ("Prelude.Enum." & Name & ".succ: bad argument")
             else Err_At ("succ{" & Name & "}: tried to take `succ' of last tag"
                          & " in enumeration", Loc));
         function Pred_F (Tag : Positive) return Real_Expr_Id
         is (if Tag > 1 then ConE (M.Info (TC).Cons (Tag - 1))
             elsif Wired then Err ("Prelude.Enum." & Name & ".pred: bad argument")
             else Err_At ("pred{" & Name & "}: tried to take `pred' of first tag"
                          & " in enumeration", Loc));
```

  Change `Ms.Append (To_E_Lam (TC));` (575) to
  `Ms.Append (To_E_Lam (TC, Loc));`.

- [ ] **Step 5: regression tests** are `m150_derived_enum_errors.hs`
  and `multi/m150_derived_enum_cross` from Task D1. The existing
  `ch06_03_enum_*` and `m149_shown_errors` cases pin that the wired
  Bool/Ordering/() texts are unchanged.
- [ ] **Step 6: verify.**

```sh
alr exec -- gcc -c -gnatc -gnat2022 -gnatwa -Isrc src/ahc_main.adb -o $SCRATCH/ck/main.o
alr exec -- gcc -c -gnatc -gnat2022 -gnatwa -Isrc src/ahc-prelude_core.adb -o $SCRATCH/ck/pc.o
alr build --validation
T=$(mktemp -d)
./bin/ahc build tests/conformance/m150_derived_enum_errors.hs -o $T/de && \
  diff tests/conformance/m150_derived_enum_errors.out <($T/de)   # no output
( cd tests/conformance/multi/m150_derived_enum_cross && \
  ../../../../bin/ahc build Main.hs -o $T/mm ) && \
  diff tests/conformance/multi/m150_derived_enum_cross/expected.out <($T/mm)  # no output
scripts/run_gate.sh                                              # GATE ok
scripts/run_repl.sh                                              # green: REPL modules keep plain texts
```

- [ ] **Step 7: commit:**
  `fix(prelude-core): a derived enum's succ, pred and toEnum errors carry ghc's call stack at the deriving clause`
  with trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

---

### Task D7: EXCLUSIONS says what phase D closed

**Files:**
- Modify: `tests/conformance/EXCLUSIONS.md` rows at lines 21, 48, 55, 59

**Interfaces:** none (documentation of facts the tests above pin).

- [ ] **Step 1:** line 21 (Exceptions): delete the clause
  "a derived `toEnum`/`succ`/`pred` message lacks the call stack GHC
  prints at the deriving clause;". After "(m149_shown_errors.hs, ...,
  multi/m149_located_cross)", add "; a derived `Enum`'s
  `succ`/`pred`/`toEnum` failure carries GHC's call stack at the
  deriving clause since M150 (m150_derived_enum_errors.hs,
  multi/m150_derived_enum_cross)".
- [ ] **Step 2:** line 48: wrap the row's second and third cells in
  `~~...~~` and append "CLOSED in M150: derived contexts are inferred
  from the fields as GHC infers them, and a field with no instance is a
  compile error at the deriving clause's class name, with GHC's
  'arising from the Nth field' wording
  (tests/golden/check_m150_derive_errors.hs,
  corpus-types bad_m150_derive_*); a phantom parameter needs no
  instance (m150_derived_context.hs)".
- [ ] **Step 3:** line 55 (ext): delete "derived Eq/Ord compare
  structurally, so an overlapping `Eq [Bool]` on a field type is not
  used (the structural Eq/Ord milestone); a derived Show whose field
  type has no instance fails at run time, not compile time;". Add "a
  newtype deriving `Eq`/`Ord` by GND over a stock-derived type takes
  that type's one-constraint-per-parameter context rather than the
  inferred one, so a phantom parameter there still asks for an
  instance (M150, plan deviation 2);".
- [ ] **Step 4:** line 59: strike the title cell and replace the
  explanation with "~~...~~ CLOSED in M150: a dictionary is structural
  only when every instance it reaches is; otherwise derived `Eq`/`Ord`
  and the wired list/`Maybe`/pair instances compare field-wise through
  the components' own instances, constructors in declaration order
  (m150_structural_eq.hs, m150_overlap_eq.hs). Still open: a NaN inside
  a derived or wired `Ord` orders by `compare`, so `Just nan > Just 1`
  is True where GHC's derived `>` says False".
- [ ] **Step 5: commit:**
  `docs(exclusions): structural equality, inferred derived contexts and derived enum call stacks are closed`
  with trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

---

### Task D8: phase D gate

**Files:** none changed. This task runs the gate and records results.

- [ ] **Step 1: both builds, unit tests.**
  `alr build --validation && alr build --release && (cd tests && alr build --validation && ./bin/ahc_tests)`.
  All 361 pass.
- [ ] **Step 2: full suites, both GC modes**, on the release binary,
  then on the validation binary: `scripts/run_gate.sh` → `GATE ok`.
  This covers unit, conformance (all 6 new `m150_*` cases `ok`), exec,
  exec-own (`AHC_GC=own`) and golden (only the new
  `check_m150_derive_errors` is added, and no other golden changes).
- [ ] **Step 3: the rest of the CI suite list**, each run unpiped and
  each green:
  - `scripts/run_differential.sh`;
  - `scripts/run_differential_types.sh` (the four m150 corpus files
    `ok`);
  - `scripts/run_discharge.sh` (the same four `ok` lines as before
    phase D);
  - `scripts/run_examples.sh`, `scripts/run_separate.sh`,
    `scripts/run_repl.sh`, `scripts/run_build.sh`,
    `scripts/run_export.sh`;
  - `scripts/run_fuzz.sh` (50 seeds).
- [ ] **Step 4: own collector** (the runtime gained a prim):
  `AHC_OWN_VERIFY=1 scripts/run_own_soak.sh` is green.
- [ ] **Step 5: bench delta.**
  - `alr build --release && scripts/run_bench.sh > $SCRATCH/bench_post_D.txt`.
  - Then
    `grep -E '^(b_sort|b_map|b_strings|b_streq) ' $SCRATCH/bench_pre_D.txt $SCRATCH/bench_post_D.txt`.
  - The `opt` column of `b_sort` and `b_map` (named by the spec), and
    of `b_strings` and `b_streq`, is within 2% of the baseline.
  - Record the four pairs of numbers in the phase-D commit notes for
    the write-up.

**Gate:** conformance (oracled) - `Ci` inside lists, `Maybe`,
tuples, `Either`, derived records, nested derived types; `compare`
across constructors; a phantom parameter; derived `Enum` errors in a
single- and a multi-module program; an overlapping `Eq [Bool]`;
negative corpus - missing `Show`/`Eq`/`Ord` field instances and a
function field; `run_discharge.sh` unchanged; bench delta with
`b_sort` and `b_map` checked by name; full suites both GC modes.

## Phase E - library error texts and `Word`

Independent of phases A-D. E1 (Tasks E1-E4) edits `lib/` only; E2
(Tasks E5-E6) edits `src/`, `prelude/Prelude.hs` and `lib/`.

**Every text in this phase was recorded from the oracle on
2026-10-15**, not transcribed from base's source: probe programs that
`try`/`evaluate` each failure and print `show (e :: SomeException)`,
run with `~/.ghcup/bin/runghc` (9.4.8) and again compiled with
`~/.ghcup/bin/ghc -O0` - the two outputs were byte-identical for
every probe. The conformance programs below are those probes; their
`.out` files are regenerated from the oracle in each task, so the
goldens hold the recorded bytes.

Prototype check (planning, 2026-10-15): every edit below was applied
to a scratch copy of the tree (`$AHC_LIB` for E1; a scratch
`alr build --release` for E2), and `m150_containers_texts`,
`m150_base_texts`, `m150_ix_texts` and `m150_word` were byte-identical
to the oracle; `run_export.sh` passed with the new `Word` export; the
negative corpus case was rejected; `run_differential_types.sh` passed;
the Core goldens changed only as Task E5 step 7 states; the 50
existing conformance and exec cases that import a changed module or
use `Word` stayed green; `check_prelude_exports.sh` stayed green. The
full gate was not run on the prototype, but all of `run_conformance.sh`
(293 programs) and `run_exec.sh` passed there later (Boehm, rc=0
each). Not run there: the unit tests, `AHC_GC=own`, the other gate
scripts.

### Phase E constraints

- **Gate inputs:** `prelude/`, `lib/`, `runtime/` and `bin/ahc`.
  Never edit or rebuild them while a suite runs.
- **Why a library `error` already shows no call stack:**
  `ahc_main.adb:1028-1035` gives a library module
  `AHC.Sites.No_Context` ("a library module's failures are base's in
  GHC, so they keep the plain text"). So every message-only GHC text
  needs only the right message; edited sites still say
  `errorWithoutStackTrace`, as base's source does, so the intent is in
  the code. A text WITH a stack goes through the existing
  `primErrorLoc :: String -> String -> a` (message, constant
  location; `src/ahc-builtins.adb:1104-1105`, runtime `p_error_loc`,
  `runtime/ahc_rts.c:6769`), which library modules can call: they
  resolve through the whole Prelude view (`Reg.Base`), prims included,
  even under `import Prelude hiding (...)` (checked with a scratch
  `$AHC_LIB` module).
- **Ada:** semantic-check each changed unit before building:
  `alr exec -- gcc -c -gnatc -gnat2022 -gnatwa -Isrc src/X.adb -o $TMPDIR/ck/X.o`.
  Never pass two id-minting calls as actuals of one call.
- **Goldens:** E1 does not touch `prelude/` or `src/`, so the Core
  goldens do not move. E2 adds a builtin TyCon and six Prelude
  instances: regenerate on the RELEASE build, check the diff (Task E5
  step 7), then confirm on the validation build.
- **One-case verify** (used by every task; `NAME` is the case):

  ```sh
  t=$(mktemp -d) && scripts/ahc-build.sh tests/conformance/NAME.hs $t/NAME >/dev/null \
    && $t/NAME | diff -u tests/conformance/NAME.out - && echo "ok NAME"
  ```

### The `error` audit of `lib/` (E1)

`grep -rn 'error\b\|errorWithoutStackTrace\|primError' lib/` on
2026-10-15, every hit:

| Site | Today | GHC 9.4.8 (recorded) | Disposition |
|---|---|---|---|
| `Data/Map/Internal.hs:61` `(!)` | `Map.!: given key is not an element in the map` | same + stack `Data/Map/Internal.hs:617:17` | Task E1 |
| `Data/Map/Internal.hs:226` `findIndex` | message only | + stack `1444:23` | Task E1 |
| `Data/Map/Internal.hs:242` `elemAt` | message only | + stack `1485:17` (negative index too) | Task E1 |
| `Data/Map/Internal.hs:251` `deleteAt` | message only | + stack `1598:12` | Task E1 |
| `Data/Map/Internal.hs:305` `findMin` | message only | + stack `1634:17` | Task E1 |
| `Data/Map/Internal.hs:310` `findMax` | message only | + stack `1659:17` | Task E1 |
| `Data/Map/Internal.hs:344` `deleteFindMin` | message only | + stack `3960:15` | Task E1 |
| `Data/Map/Internal.hs:349` `deleteFindMax` | message only | + stack `3970:15` | Task E1 |
| `Data/Map/Internal.hs:884` Foldable `maximum` | message only | + stack `4241:23` | Task E1 |
| `Data/Map/Internal.hs:887` Foldable `minimum` | message only | + stack `4248:23` | Task E1 |
| `Data/Map/Internal.hs:674` `fromDistinctAscList` "list too short" | internal | - | unchanged: the size argument comes from the list itself, unreachable from valid input |
| `Data/Map/Internal.hs:739,745,768,791` `balance`/`balanceL`/`balanceR` | internal | - | unchanged: the balance invariant makes them unreachable |
| `Data/Set.hs:66` `elemAt` | message only | + stack `Data/Set/Internal.hs:1381:17` | Task E1 |
| `Data/Set.hs:76` `findIndex` | message only | + stack `1336:21` | Task E1 |
| `Data/Set.hs:169` `deleteFindMin` | `Set.deleteFindMin: empty set` | `Set.deleteFindMin: can not return the minimal element of an empty set` + stack `1611:18` | Task E1 (not exported, only `glue` calls it on a non-empty set; GHC's text anyway, so a future export is right) |
| `Data.Set` Foldable `maximum`/`minimum` (class default today) | `maximum: empty structure` | `Set.findMax: empty set has no maximal element` + stack `794:17`; `findMin` + `776:17` | Task E1: `maximum = findMax`, `minimum = findMin`, as containers; `findMin`/`findMax` exported as GHC's are |
| `Data/Array.hs:31` `(!)` out of range | `(Array.!): index out of range` | `Ix{Int}.index: Index (5) out of range ((0,2))` (the index type's `Ix`) | Task E2: `(!)` calls `Data.Ix.index` |
| `Data/Array.hs:21,37` undefined element | `(Array.!): undefined array element` | same, no stack | already GHC's; Task E2 spells it `errorWithoutStackTrace` |
| `Data/Ix.hs:18` `Ix Int`, `:27` `Ix Char` | GHC's | same | already GHC's; Task E2 spells them `errorWithoutStackTrace` |
| `Data/Ix.hs:39-102` fixed-width `Ix` | `Error in array index` | `Error in array index` (recorded for all eight and `Word`) | unchanged: already GHC's |
| `Ix Integer`, `Ix (a, b)` | no instance | `Ix{Integer}.index: Index (5) out of range ((0,2))`; pairs `Error in array index` | Task E2 adds both instances |
| derived `Ix` (`ahc-prelude_core.adb:673,676`) | `Error in array index` | same | unchanged: already GHC's |
| `Numeric.hs:14` `showIntAtBase` | `Numeric.showIntAtBase: negative` | `Numeric.showIntAtBase: applied to negative number -1`; base 1: `...applied to unsupported base 1` (AHC loops today) | Task E3 |
| `Data/Char.hs:54` `digitToInt` | no value | `Char.digitToInt: not a digit 'z'` | Task E3 |
| `Data/Char.hs:60` `intToDigit` | no value | `Char.intToDigit: not a digit 20` / `-1` | Task E3 |
| `Data/List.hs:181,188` `maximumBy`/`minimumBy` | list-only, `List.maximumBy: empty list`; a tie keeps the FIRST greatest | Foldable-general, `maximumBy: empty structure`, no stack; a tie keeps the LAST greatest | Task E3 |
| `Data/Ratio.hs:20,58` zero denominator | `ErrorCall` with GHC's text | `ArithException RatioZeroDenominator` (same shown text) | Task E3: `primThrow (primExcArith 5)`, so `catch` at `ArithException` works |
| `Numeric.hs:173` `formatRealFloat`, `:216` `roundTo` | internal | - | unchanged: unreachable from valid input |
| `Text/Printf.hs:439-452` `perror` and its callers | `printf: ...` | same, no stack (recorded: bad formatting char, argument list ended prematurely, formatting string ended prematurely) | unchanged: already GHC's |
| `System/Random/SplitMix.hs:182,187` `bitmaskWithRejection{32,64} 0` | message only | message + a stack naming `spltmx-0.1.3.2-cd654c14` | unchanged: the oracle's stack names a cabal-store unit id specific to that install, not a property of GHC 9.4.8 |
| `System/IO/Error.hs:47` | a string, not a call | - | not an error site |

---

### Task E1: containers' texts and call stacks for `Data.Map` and `Data.Set`

**Files:**
- Create: `tests/conformance/m150_containers_texts.hs` (+ `.out` from the oracle)
- Modify: `lib/Data/Map/Internal.hs:24-25` (helper before `delta`), `:61`, `:226`, `:242`, `:251`, `:305`, `:310`, `:344`, `:349`, `:884`, `:887`
- Modify: `lib/Data/Set.hs:1-7` (exports), `:23-24` (helper), `:60-63` (Foldable), `:66`, `:76`, `:169`, `:171` (`findMin`/`findMax`)

**Interfaces:**
- Produces: `Data.Set.findMin :: Set a -> a`, `Data.Set.findMax :: Set a -> a` (exported); `mapError_ :: String -> String -> a` (Data.Map.Internal, not re-exported by `Data.Map`/`Data.Map.Strict`); `setError_ :: String -> String -> a` (Data.Set, not exported).

- [ ] **Step 1: Failing test first.** Write
  `tests/conformance/m150_containers_texts.hs`:

  ```haskell
  -- M150: the show of a caught Data.Map / Data.Set error is GHC
  -- 9.4.8's, byte for byte, with containers-0.6.7's call stack (its
  -- functions are not HasCallStack, so no frame is the program's).
  import Control.Exception
  import qualified Data.Map as Map
  import qualified Data.Map.Strict as MapS
  import qualified Data.Set as Set

  t :: String -> IO () -> IO ()
  t name act = do
    r <- try act
    case r of
      Left e -> putStrLn (name ++ " => " ++ show (e :: SomeException))
      Right () -> putStrLn (name ++ " ok")

  f :: a -> IO ()
  f x = evaluate x >> return ()

  em :: Map.Map Int Char
  em = Map.empty

  m :: Map.Map Int Char
  m = Map.fromList [(1, 'a'), (2, 'b')]

  es :: Set.Set Int
  es = Set.empty

  s :: Set.Set Int
  s = Set.fromList [1, 2, 3]

  main :: IO ()
  main = do
    t "Map.!" (f (m Map.! 5))
    t "Map.Strict.!" (f (m MapS.! 5))
    t "Map.findIndex" (f (Map.findIndex 5 m))
    t "Map.elemAt" (f (Map.elemAt 7 m))
    t "Map.elemAt negative" (f (Map.elemAt (-1) m))
    t "Map.deleteAt" (f (Map.deleteAt 7 m))
    t "Map.findMin" (f (Map.findMin em))
    t "Map.findMax" (f (Map.findMax em))
    t "Map.deleteFindMin" (f (fst (Map.deleteFindMin em)))
    t "Map.deleteFindMax" (f (fst (Map.deleteFindMax em)))
    t "Map maximum" (f (maximum em))
    t "Map minimum" (f (minimum em))
    t "Map foldr1" (f (foldr1 max em))
    t "Set.elemAt" (f (Set.elemAt 7 s))
    t "Set.findIndex" (f (Set.findIndex 9 s))
    t "Set.findMin" (f (Set.findMin es))
    t "Set.findMax" (f (Set.findMax es))
    t "Set maximum" (f (maximum es))
    t "Set minimum" (f (minimum es))
    t "Set foldr1" (f (foldr1 max es))
    -- the values the same functions return when they succeed
    print (m Map.! 2, Map.elemAt 1 m, Map.findMin m, Map.findMax m)
    print (Map.findIndex 2 m, Map.deleteAt 0 m, fst (Map.deleteFindMax m))
    print (maximum m, minimum m)
    print (Set.findMin s, Set.findMax s, maximum s, minimum s)
    print (Set.findMin (Set.fromList "hello"), Set.findMax (Set.fromList "hello"))
    print (Set.elemAt 2 s, Set.findIndex 3 s)
  ```

  Oracle it from the repo root:
  `~/.ghcup/bin/runghc tests/conformance/m150_containers_texts.hs > tests/conformance/m150_containers_texts.out`.
  Its first lines must read (the recorded bytes):

  ```
  Map.! => Map.!: given key is not an element in the map
  CallStack (from HasCallStack):
    error, called at libraries/containers/containers/src/Data/Map/Internal.hs:617:17 in containers-0.6.7:Data.Map.Internal
  ```

  The one-case verify must FAIL now (`Set.findMin` is not exported:
  BUILD-FAIL).

- [ ] **Step 2: `Data.Map.Internal`.** Insert before `delta :: Int`
  (line 24):

  ```haskell
  -- containers-0.6.7's call stack for an `error` at line:col of its
  -- Data/Map/Internal.hs, as GHC 9.4.8 shows it (recorded from the
  -- oracle, M150). containers' functions are not HasCallStack, so the
  -- stack has no frame in the user's program.
  mapError_ :: String -> String -> a
  mapError_ msg at = primErrorLoc msg
    ("CallStack (from HasCallStack):\n  error, called at libraries/containers/containers/src/Data/Map/Internal.hs:"
     ++ at ++ " in containers-0.6.7:Data.Map.Internal")
  ```

  Then replace each site (the message text is unchanged, recorded
  equal to GHC's; only the location is added):

  | Line | Before | After |
  |---|---|---|
  | 61 | `Nothing -> error "Map.!: given key is not an element in the map"` | `Nothing -> mapError_ "Map.!: given key is not an element in the map" "617:17"` |
  | 226 | `go _ _ Tip = error "Map.findIndex: element is not in the map"` | `go _ _ Tip = mapError_ "Map.findIndex: element is not in the map" "1444:23"` |
  | 242 | `elemAt _ Tip = error "Map.elemAt: index out of range"` | `elemAt _ Tip = mapError_ "Map.elemAt: index out of range" "1485:17"` |
  | 251 | `Tip -> error "Map.deleteAt: index out of range"` | `Tip -> mapError_ "Map.deleteAt: index out of range" "1598:12"` |
  | 305 | `Nothing -> error "Map.findMin: empty map has no minimal element"` | `Nothing -> mapError_ "Map.findMin: empty map has no minimal element" "1634:17"` |
  | 310 | `Nothing -> error "Map.findMax: empty map has no maximal element"` | `Nothing -> mapError_ "Map.findMax: empty map has no maximal element" "1659:17"` |
  | 344 | `Nothing  -> (error "Map.deleteFindMin: can not return the minimal element of an empty map", Tip)` | `Nothing  -> (mapError_ "Map.deleteFindMin: can not return the minimal element of an empty map" "3960:15", Tip)` |
  | 349 | `Nothing  -> (error "Map.deleteFindMax: can not return the maximal element of an empty map", Tip)` | `Nothing  -> (mapError_ "Map.deleteFindMax: can not return the maximal element of an empty map" "3970:15", Tip)` |
  | 884 | `Tip -> error "Data.Foldable.maximum (for Data.Map): empty map"` | `Tip -> mapError_ "Data.Foldable.maximum (for Data.Map): empty map" "4241:23"` |
  | 887 | `Tip -> error "Data.Foldable.minimum (for Data.Map): empty map"` | `Tip -> mapError_ "Data.Foldable.minimum (for Data.Map): empty map" "4248:23"` |

  `Data.Map.Strict` defines none of these (its `(!)` is Internal's),
  so it needs no edit; the test's `MapS.!` line pins that.

- [ ] **Step 3: `Data.Set`.** Exports (lines 5-6) become:

  ```haskell
    , elemAt, findIndex, lookupIndex
    , findMin, findMax
    , filter, map
  ```

  Insert before `delta :: Int` (line 23):

  ```haskell
  -- containers-0.6.7's call stack for an `error` at line:col of its
  -- Data/Set/Internal.hs, as GHC 9.4.8 shows it (recorded, M150).
  setError_ :: String -> String -> a
  setError_ msg at = primErrorLoc msg
    ("CallStack (from HasCallStack):\n  error, called at libraries/containers/containers/src/Data/Set/Internal.hs:"
     ++ at ++ " in containers-0.6.7:Data.Set.Internal")
  ```

  The Foldable instance (lines 60-63) gains containers' `maximum` and
  `minimum` (today the class default raises `maximum: empty
  structure`; GHC's text is `findMax`'s):

  ```haskell
  instance Foldable Set where
    foldr f z s = foldrList_ f z (toAscList s)
    null s = Data.Set.null s
    length s = size s
    -- containers: maximum = findMax, minimum = findMin (their texts).
    maximum s = findMax s
    minimum s = findMin s
  ```

  Line 66: `elemAt _ STip = error "Set.elemAt: index out of range"` →
  `elemAt _ STip = setError_ "Set.elemAt: index out of range" "1381:17"`.

  Line 76: `findIndex _ STip = error "Set.findIndex: element is not in the set"` →
  `findIndex _ STip = setError_ "Set.findIndex: element is not in the set" "1336:21"`.

  Line 169: `deleteFindMin STip = error "Set.deleteFindMin: empty set"` →

  ```haskell
  deleteFindMin STip =
    setError_ "Set.deleteFindMin: can not return the minimal element of an empty set" "1611:18"
  ```

  Insert before `--  Left-biased union, like containers.` (line 171):

  ```haskell
  --  The least and greatest elements: the leftmost and rightmost
  --  nodes, as containers (no comparisons).
  findMin :: Set a -> a
  findMin (SBin _ x STip _) = x
  findMin (SBin _ _ l _) = findMin l
  findMin STip = setError_ "Set.findMin: empty set has no minimal element" "776:17"

  findMax :: Set a -> a
  findMax (SBin _ x _ STip) = x
  findMax (SBin _ _ _ r) = findMax r
  findMax STip = setError_ "Set.findMax: empty set has no maximal element" "794:17"

  ```

  (`Data.Map.Internal` imports `Data.Set` qualified, so the new
  exports do not collide with its own `findMin`/`findMax`.)

- [ ] **Step 4: Verify.**
  - one-case verify `m150_containers_texts` → `ok m150_containers_texts`;
  - `scripts/run_conformance.sh` → no `FAIL`/`BUILD-FAIL`
    (`lib_map_api.hs` catches `Map.elemAt`/`Map.deleteAt` as
    `ErrorCall` and prints the first line only - `primErrorLoc` raises
    an `ErrorCall`, so it stays green; checked in the prototype).

- [ ] **Step 5: Commit.**

  ```
  fix(lib): data.map and data.set errors carry containers' call stacks, as ghc shows them

  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```

---

### Task E2: `Data.Array`'s `!` reports through `Ix`; `Ix Integer` and pairs

**Files:**
- Create: `tests/conformance/m150_ix_texts.hs` (+ `.out` from the oracle)
- Modify: `lib/Data/Ix.hs:12-13` (comment), `:18-19`, `:27-28`, `:33` (new instances before it)
- Modify: `lib/Data/Array.hs:6` (import), `:20-22`, `:28-32`, `:37`

**Interfaces:**
- Consumes: `Data.Ix.index :: Ix a => (a, a) -> a -> Int`.
- Produces: `instance Ix Integer`, `instance (Ix a, Ix b) => Ix (a, b)` in `Data.Ix`.

AHC's `Array` is `Int`-indexed (`data Array e = MkArray (Int, Int)
[e]`, `lib/Data/Array.hs:13`), so `!` reaches only `Ix{Int}`. The
spec's per-type texts are recorded and pinned through `index`
directly. Triples are NOT added: `Ord (a, b, c)` has no instance in
AHC, so `Ix (a, b, c)` fails its superclass check (found in the
prototype: `no instance for 'Ord (a, b, c)'`). `Ix Bool`/`Ix
Ordering` are not in AHC either; their recorded texts are
`Ix{Bool}.index: Index (True) out of range ((False,False))` and
`Ix{Ordering}.index: Index (GT) out of range ((LT,EQ))`, for whoever
adds them.

- [ ] **Step 1: Failing test first.** Write
  `tests/conformance/m150_ix_texts.hs`:

  ```haskell
  -- M150: an Ix index out of range shows GHC 9.4.8's text for the index
  -- type - Ix{Int}/Ix{Char}/Ix{Integer} name the type and print the
  -- index and bounds, while the fixed-width types, pairs and derived
  -- instances say "Error in array index" - plus the Integer and pair
  -- instances' range/index/inRange/rangeSize.
  import Control.Exception
  import Data.Ix
  import Data.Int
  import Data.Word

  data T = A | B | C | D deriving (Show, Eq, Ord, Ix)

  t :: String -> IO () -> IO ()
  t name act = do
    r <- try act
    case r of
      Left e -> putStrLn (name ++ " => " ++ show (e :: SomeException))
      Right () -> putStrLn (name ++ " ok")

  f :: a -> IO ()
  f x = evaluate x >> return ()

  main :: IO ()
  main = do
    t "Int" (f (index (0, 2 :: Int) 5))
    t "Int negative" (f (index (-3, -1 :: Int) 0))
    t "Char" (f (index ('a', 'c') 'z'))
    t "Integer" (f (index (0, 2 :: Integer) 5))
    t "Integer big" (f (index (0, 2 :: Integer) (2 ^ 70)))
    t "pair" (f (index ((0, 0), (1, 1) :: (Int, Int)) (2, 0)))
    t "pair of Char" (f (index (('a', 'a'), ('b', 'b')) ('a', 'z')))
    t "derived" (f (index (A, B) D))
    t "Int8" (f (index (0, 2 :: Int8) 5))
    t "Int64" (f (index (0, 2 :: Int64) 5))
    t "Word8" (f (index (0, 2 :: Word8) 5))
    t "Word64" (f (index (0, 2 :: Word64) 5))
    print (range (3, 6 :: Integer), index (3, 6 :: Integer) 5)
    print (inRange (3, 6 :: Integer) 7, rangeSize (3, 6 :: Integer), rangeSize (6, 3 :: Integer))
    print (range ((0, 0), (1, 2) :: (Int, Int)))
    print (map (index ((0, 0), (1, 2) :: (Int, Int))) [(0, 0), (0, 2), (1, 0), (1, 2)])
    print (inRange ((0, 0), (1, 2) :: (Int, Int)) (1, 3), rangeSize ((0, 0), (1, 2) :: (Int, Int)))
    print (rangeSize ((0, 5), (3, 2) :: (Int, Int)), range ((1, 'a'), (2, 'b') :: (Integer, Char)))
    print (index ((1, 'a'), (2, 'b') :: (Integer, Char)) (2, 'a'))
  ```

  Oracle: `~/.ghcup/bin/runghc tests/conformance/m150_ix_texts.hs > tests/conformance/m150_ix_texts.out`.
  The recorded error lines are:

  ```
  Int => Ix{Int}.index: Index (5) out of range ((0,2))
  Int negative => Ix{Int}.index: Index (0) out of range ((-3,-1))
  Char => Ix{Char}.index: Index ('z') out of range (('a','c'))
  Integer => Ix{Integer}.index: Index (5) out of range ((0,2))
  Integer big => Ix{Integer}.index: Index (1180591620717411303424) out of range ((0,2))
  pair => Error in array index
  pair of Char => Error in array index
  derived => Error in array index
  Int8 => Error in array index
  Int64 => Error in array index
  Word8 => Error in array index
  Word64 => Error in array index
  ```

  The one-case verify must FAIL now (no `Ix Integer`: BUILD-FAIL).

- [ ] **Step 2: `Data.Ix`.** Lines 12-13 become:

  ```haskell
  -- GHC 9.4.8's texts (recorded, M150): Int, Char and Integer name
  -- themselves (base's indexError, no call stack); the fixed-width
  -- types, tuples and derived instances say "Error in array index".
  ```

  Lines 18-19 (`else error ("Ix{Int}.index: ...`) become:

  ```haskell
      else errorWithoutStackTrace ("Ix{Int}.index: Index (" ++ show i
                                   ++ ") out of range (" ++ show b ++ ")")
  ```

  Lines 27-28 (`else error ("Ix{Char}.index: ...`) become:

  ```haskell
      else errorWithoutStackTrace ("Ix{Char}.index: Index (" ++ show c
                                   ++ ") out of range (" ++ show b ++ ")")
  ```

  Insert before line 33 (`-- The fixed-width types (Data.Int /
  Data.Word, M139): through Int.`):

  ```haskell
  instance Ix Integer where
    range (lo, hi) = [lo .. hi]
    index b@(lo, _) i =
      if inRange b i then fromInteger (i - lo)
      else errorWithoutStackTrace ("Ix{Integer}.index: Index (" ++ show i
                                   ++ ") out of range (" ++ show b ++ ")")
    inRange (lo, hi) i = i >= lo && i <= hi
    rangeSize (lo, hi) = if hi < lo then 0 else fromInteger (hi - lo + 1)

  -- Pairs, row-major as base's; an index outside the box is base's
  -- hopelessIndexError, whatever the component types. rangeSize is
  -- the product: zero exactly when base's `inRange b hi` is False.
  instance (Ix a, Ix b) => Ix (a, b) where
    range ((l1, l2), (u1, u2)) =
      [(i1, i2) | i1 <- range (l1, u1), i2 <- range (l2, u2)]
    index b@((l1, l2), (u1, u2)) i@(i1, i2) =
      if inRange b i
        then index (l1, u1) i1 * rangeSize (l2, u2) + index (l2, u2) i2
        else errorWithoutStackTrace "Error in array index"
    inRange ((l1, l2), (u1, u2)) (i1, i2) =
      inRange (l1, u1) i1 && inRange (l2, u2) i2
    rangeSize ((l1, l2), (u1, u2)) = rangeSize (l1, u1) * rangeSize (l2, u2)

  ```

- [ ] **Step 3: `Data.Array`.** Line 6 `import Data.List (find,
  sortOn)` gains a line above it:

  ```haskell
  import Data.Ix (index)
  import Data.List (find, sortOn)
  ```

  Lines 28-32:

  ```haskell
  (!) :: Array e -> Int -> e
  (!) (MkArray (lo, hi) es) i =
    if i < lo || i > hi
      then error "(Array.!): index out of range"
      else pickAt es (i - lo)
  ```

  become:

  ```haskell
  -- Out of range is the index type's Ix error, as GHC's (!) reports it:
  -- Ix{Int}.index: Index (5) out of range ((0,2)).
  (!) :: Array e -> Int -> e
  (!) (MkArray b es) i = pickAt es (index b i)
  ```

  Line 21 `fromMaybe (error "(Array.!): undefined array element")` →
  `fromMaybe (errorWithoutStackTrace "(Array.!): undefined array element")`;
  line 37 `pickAt [] _ = error "(Array.!): undefined array element"` →
  `pickAt [] _ = errorWithoutStackTrace "(Array.!): undefined array element"`
  (texts unchanged: recorded equal to GHC's).

- [ ] **Step 4: Regression for `!`.** The `!` texts are pinned by
  Task E3's `m150_base_texts.hs` (`Array ! high`, `Array ! low`,
  `Array undefined element`, `Array short list`), which also imports
  this module; run its one-case verify after Task E3. Here:
  - one-case verify `m150_ix_texts` → `ok m150_ix_texts`;
  - one-case verify `lib_array_read`, `lib_numeric_bits_ix`,
    `ch11_01_derives`, `lib_data_int_word` → `ok` each;
  - `scripts/run_exec.sh` → `ok   tests/exec/ix_index_bounds.hs`
    (its golden `ahc: error: Error in array index` is unchanged).

- [ ] **Step 5: Commit.**

  ```
  fix(lib): an array index out of range reports through its ix instance, and ix covers integer and pairs

  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```

---

### Task E3: base's texts for `Data.Char`, `Numeric`, `maximumBy`/`minimumBy` and `Ratio`

**Files:**
- Create: `tests/conformance/m150_base_texts.hs` (+ `.out` from the oracle)
- Modify: `lib/Data/Char.hs:54`, `:60`
- Modify: `lib/Numeric.hs:13-14`
- Modify: `lib/Data/List.hs:180-192`
- Modify: `lib/Data/Foldable.hs:9-10`
- Modify: `lib/Data/Ratio.hs:20`, `:58`
- Modify: `tests/conformance/EXCLUSIONS.md:21`

**Interfaces:**
- Produces: `Data.List.maximumBy, minimumBy :: Foldable t => (a -> a -> Ordering) -> t a -> a`, re-exported by `Data.Foldable`.

- [ ] **Step 1: Failing test first.** Write
  `tests/conformance/m150_base_texts.hs`:

  ```haskell
  -- M150: the show of a caught error from Data.Array, Data.Char,
  -- Numeric, Data.List/Data.Foldable's maximumBy/minimumBy and
  -- Data.Ratio is GHC 9.4.8's, byte for byte (base raises these with
  -- errorWithoutStackTrace, or as ArithException), and maximumBy keeps
  -- the LAST of equal greatest elements, as base's does.
  import Control.Exception
  import qualified Data.Foldable as F
  import qualified Data.Map as Map
  import qualified Data.Set as Set
  import Data.Array
  import Data.Char (digitToInt, intToDigit)
  import Data.List (maximumBy, minimumBy)
  import Data.Ord (comparing)
  import Data.Ratio
  import Numeric (showHex, showIntAtBase)

  t :: String -> IO () -> IO ()
  t name act = do
    r <- try act
    case r of
      Left e -> putStrLn (name ++ " => " ++ show (e :: SomeException))
      Right () -> putStrLn (name ++ " ok")

  f :: a -> IO ()
  f x = evaluate x >> return ()

  main :: IO ()
  main = do
    t "Array ! high" (f (listArray (0, 2) "abc" ! (5 :: Int)))
    t "Array ! low" (f (listArray (0, 2) "abc" ! (-1 :: Int)))
    t "Array undefined element" (f (array (0, 2) [(0, 'a')] ! (1 :: Int)))
    t "Array short list" (f (listArray (0, 2) "a" ! (2 :: Int)))
    t "showIntAtBase negative" (f (length (showIntAtBase 10 intToDigit (-1) "")))
    t "showIntAtBase base 1" (f (length (showIntAtBase 1 intToDigit 5 "")))
    t "showHex negative" (f (length (showHex (-255 :: Int) "")))
    t "digitToInt" (f (digitToInt 'z'))
    t "intToDigit" (f (intToDigit 20))
    t "intToDigit negative" (f (intToDigit (-1)))
    t "maximumBy" (f (maximumBy compare ([] :: [Int])))
    t "minimumBy" (f (minimumBy compare ([] :: [Int])))
    t "maximumBy Maybe" (f (F.maximumBy compare (Nothing :: Maybe Int)))
    t "minimumBy Set" (f (F.minimumBy compare (Set.empty :: Set.Set Int)))
    t "ratio zero" (f (1 % (0 :: Integer)))
    t "recip zero" (f (recip (0 :: Rational)))
    r <- try (evaluate (3 % (0 :: Int)))
    putStrLn (either (\e -> "ArithException: " ++ show (e :: ArithException))
                     show r)
    -- the values the same functions return when they succeed
    print (listArray (0, 2) "abc" ! (2 :: Int), showIntAtBase 2 intToDigit 10 "")
    print (map digitToInt "09afAF", map intToDigit [0, 9, 10, 15])
    -- ties: maximumBy keeps the LAST greatest, minimumBy the FIRST least
    let xs = [(1, 'a'), (3, 'b'), (3, 'c'), (1, 'd')] :: [(Int, Char)]
    print (maximumBy (comparing fst) xs, minimumBy (comparing fst) xs)
    print (F.maximumBy (comparing negate) (Map.fromList [(1 :: Int, 5 :: Int), (2, 9), (3, 9)]))
    print (F.maximumBy (comparing (`mod` 3)) (Set.fromList [1 .. 10 :: Int]))
    print (F.minimumBy compare (Just 'q'), 6 % (4 :: Int), recip (3 % 4 :: Rational))
  ```

  Oracle: `~/.ghcup/bin/runghc tests/conformance/m150_base_texts.hs > tests/conformance/m150_base_texts.out`.
  The whole recorded output is:

  ```
  Array ! high => Ix{Int}.index: Index (5) out of range ((0,2))
  Array ! low => Ix{Int}.index: Index (-1) out of range ((0,2))
  Array undefined element => (Array.!): undefined array element
  Array short list => (Array.!): undefined array element
  showIntAtBase negative => Numeric.showIntAtBase: applied to negative number -1
  showIntAtBase base 1 => Numeric.showIntAtBase: applied to unsupported base 1
  showHex negative => Numeric.showIntAtBase: applied to negative number -255
  digitToInt => Char.digitToInt: not a digit 'z'
  intToDigit => Char.intToDigit: not a digit 20
  intToDigit negative => Char.intToDigit: not a digit -1
  maximumBy => maximumBy: empty structure
  minimumBy => minimumBy: empty structure
  maximumBy Maybe => maximumBy: empty structure
  minimumBy Set => minimumBy: empty structure
  ratio zero => Ratio has zero denominator
  recip zero => Ratio has zero denominator
  ArithException: Ratio has zero denominator
  ('c',"1010")
  ([0,9,10,15,10,15],"09af")
  ((3,'c'),(1,'a'))
  5
  8
  ('q',3 % 2,4 % 3)
  ```

  AHC today prints `((3,'b'),(1,'a'))` for the tie line (a wrong
  answer, not just a text) and fails to build (`F.maximumBy` is not
  exported by `Data.Foldable`).

- [ ] **Step 2: `Data.Char`.** Line 54
  `| otherwise            = error "Char.digitToInt: not a digit"` →

  ```haskell
    | otherwise            =
        errorWithoutStackTrace ("Char.digitToInt: not a digit " ++ show c)
  ```

  Line 60 `| otherwise          = error "Char.intToDigit: not a digit"` →

  ```haskell
    | otherwise          =
        errorWithoutStackTrace ("Char.intToDigit: not a digit " ++ show n)
  ```

- [ ] **Step 3: `Numeric`.** Lines 13-14:

  ```haskell
  showIntAtBase base toDig n s
    | n < 0     = error "Numeric.showIntAtBase: negative"
  ```

  become (GHC checks the base first; base 1 loops today, since
  `div n 1 == n`):

  ```haskell
  showIntAtBase base toDig n s
    | base <= 1 = errorWithoutStackTrace
        ("Numeric.showIntAtBase: applied to unsupported base " ++ show base)
    | n < 0     = errorWithoutStackTrace
        ("Numeric.showIntAtBase: applied to negative number " ++ show n)
  ```

  (`showHex`/`showOct` call it, so they inherit GHC's text, as GHC's
  do - the test's `showHex negative` line.)

- [ ] **Step 4: `maximumBy`/`minimumBy`.** `lib/Data/List.hs:180-192`
  (both functions and the helpers `pickMax`/`pickMin`, which nothing
  else uses - `grep -rn 'pickMax\|pickMin' lib prelude` shows only
  these lines) become:

  ```haskell
  -- Foldable-general, as base's (Data.List re-exports Data.Foldable's):
  -- a strict left fold where a tie keeps the LATER element for
  -- maximumBy and the earlier one for minimumBy, and an empty structure
  -- is base's errorWithoutStackTrace text.
  maximumBy :: Foldable t => (a -> a -> Ordering) -> t a -> a
  maximumBy cmp t = case foldr (:) [] t of
    [] -> errorWithoutStackTrace "maximumBy: empty structure"
    (x : xs) -> go x xs
    where
      go acc [] = acc
      go acc (y : ys) =
        let m = case cmp acc y of { GT -> acc; _ -> y } in m `seq` go m ys

  minimumBy :: Foldable t => (a -> a -> Ordering) -> t a -> a
  minimumBy cmp t = case foldr (:) [] t of
    [] -> errorWithoutStackTrace "minimumBy: empty structure"
    (x : xs) -> go x xs
    where
      go acc [] = acc
      go acc (y : ys) =
        let m = case cmp acc y of { GT -> y; _ -> acc } in m `seq` go m ys
  ```

  `lib/Data/Foldable.hs:9-10` (`  , find` / `  ) where`) become:

  ```haskell
    , find
    , maximumBy, minimumBy
    ) where

  import Data.List (maximumBy, minimumBy)
  ```

  (no cycle: `Data.List` imports only `Data.Ord`.)

- [ ] **Step 5: `Data.Ratio`.** GHC raises `ArithException
  RatioZeroDenominator` (recorded: catching at `ArithException`
  succeeds); the runtime's arith code 5 is that constructor
  (`lib/Control/Exception.hs:67-69`, `runtime/ahc_rts.c:3394-3397`).
  Line 20 `reduceR _ 0 = error "Ratio has zero denominator"` →
  `reduceR _ 0 = primThrow (primExcArith 5)`; line 58
  `| a == 0 = error "Ratio has zero denominator"` →
  `| a == 0 = primThrow (primExcArith 5)`.

- [ ] **Step 6: EXCLUSIONS.** In `tests/conformance/EXCLUSIONS.md`
  line 21 (the `9, lib 42` Exceptions row), delete exactly this
  clause, including its leading `; `:

  ```
  ; library modules keep their own error texts without GHC's call stacks (`Data.Map`/`Data.Set` `!`/`findMin`/`elemAt`, `Data.Array`'s `!`, `maximumBy`, `showIntAtBase`, `digitToInt`/`intToDigit`, `Word`'s `Enum` naming `Word64`)
  ```

  and after `multi/m149_located_cross).` (the end of the "Since M149"
  sentence) insert:

  ```
   Since M150 library errors are GHC's too: `Data.Map`/`Data.Set` carry containers-0.6.7's call stacks, `Data.Array`'s `!` reports through the index's `Ix` instance, and `Data.Ix`, `Data.Char`, `Numeric`, `maximumBy`/`minimumBy` (Foldable-general) and `Data.Ratio` (an `ArithException`) raise base's texts (m150_containers_texts.hs, m150_ix_texts.hs, m150_base_texts.hs).
  ```

  (The derived-`Enum` clause in the same row is Phase D's; the
  `Word` part of the deleted clause is closed by Task E5.)

- [ ] **Step 7: Verify.**
  - one-case verify `m150_base_texts` and `m150_containers_texts` →
    `ok` each;
  - `scripts/run_conformance.sh` → no `FAIL`/`BUILD-FAIL`
    (`lib_control_exception.hs` lists the ArithException texts and is
    unchanged);
  - one-case verify `lib_data_list` → `ok` (the only other
    `maximumBy` user in `tests/` and `examples/`; no ties);
  - `scripts/run_examples.sh` → green.

- [ ] **Step 8: Commit.**

  ```
  fix(lib): char, numeric, maximumby and ratio raise base's texts, and maximumby keeps the last of equal maxima

  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```

---

### Task E4: E1 gate run

**Files:** none changed.

- [ ] **Step 1:** `scripts/run_gate.sh` → `GATE ok` (unit,
  conformance, exec, exec-own, golden, prelude-exports, ...).
- [ ] **Step 2:** `AHC_GC=own scripts/run_conformance.sh` → no
  `FAIL`.
- [ ] **Step 3:** `scripts/run_differential_types.sh`,
  `scripts/run_separate.sh`, `scripts/run_userlib.sh` → green
  (`Data.Foldable` now imports `Data.List`, and `Data.Array` imports
  `Data.Ix`: separate compilation must see the new edges).
- [ ] **Step 4:** no commit (gate only). If anything fails, fix it in
  the task that introduced it and amend nothing - add a `fix(lib): ...`
  commit naming the defect.

---

### Task E5: `Word` is its own type

**Files:**
- Create: `tests/conformance/m150_word.hs` (+ `.out` from the oracle)
- Create: `tests/corpus-types/bad_word_as_word64.hs`
- Modify: `src/ahc-builtins.ads:76-81`
- Modify: `src/ahc-builtins.adb:274`, `:974-978`
- Modify: `src/ahc-prelude_core.adb:1840-1842`
- Modify: `src/ahc-desugar.adb:2840-2841`
- Modify: `prelude/Prelude.hs:1434-1437`, `:1896-1897` (Word block after)
- Modify: `lib/Data/Bits.hs:173` (append), `lib/Data/Ix.hs:105` (append),
  `lib/Text/Printf.hs:104-106`, `lib/System/Random.hs:27-28`, `:341-347`,
  `:315-316`, `:445-447`, `lib/Data/Word.hs:3-5`
- Modify: `tests/golden/core_class_dict.core`, `core_exprs.core`, `core_patterns.core` (regenerated)
- Modify: `tests/conformance/EXCLUSIONS.md:30`

**Interfaces:**
- Produces: `Builtins.Global_Env.Word_TC : Core.TyCon_Id` (the wired
  `Word`); Prelude `narrowWord_ :: Integer -> Word`, `toWord_ :: Word
  -> Integer`; instances `Eq`/`Ord`/`Show` (wired), `Num`, `Bounded`,
  `Real`, `Enum`, `Integral`, `Read` (Prelude), `Bits`
  (`Data.Bits`), `Ix` (`Data.Ix`), `PrintfArg` (`Text.Printf`),
  `Uniform`/`UniformRange`/`Random` (`System.Random`).

Design: `Word` is NOT a ninth `C_Fix_Kind`. That enumeration is the C
widths and converts positionally to `Core.Fixed_Marshal`
(`ahc-builtins.ads:58-61`; `ahc-desugar.adb:2845-2848`), and every
`case` over `Fixed_Marshal` in codegen/bindgen would grow an arm that
means `uint64_t` again. `Word` is a separate handle beside the
`CFix_TCs`, with Word64's runtime nodes (`AHC_INT`, a bignum above
2^63), Word64's wired `Eq`/`Ord`/`Show` dictionaries, and `M_U64`
marshalling. AHC has no `FiniteBits` class (`finiteBitSize` is a
`Data.Bits` function over `bitSizeOf`), so the spec's `FiniteBits` is
`Bits` here, as it is for `Word64`.

- [ ] **Step 1: Failing tests first.** Write
  `tests/conformance/m150_word.hs`:

  ```haskell
  -- M150: Word is its own type, as in GHC - Word64's width and
  -- wrapping, every instance Word64 has, texts that name {Word}, and
  -- a class with separate Word and Word64 instances.
  import Control.Exception
  import Data.Bits
  import Data.Ix
  import Data.Word
  import System.Random
  import Text.Printf

  class Describe a where
    describe :: a -> String

  instance Describe Word where
    describe w = "Word " ++ show w

  instance Describe Word64 where
    describe w = "Word64 " ++ show w

  t :: String -> IO () -> IO ()
  t name act = do
    r <- try act
    case r of
      Left e -> putStrLn (name ++ " => " ++ show (e :: SomeException))
      Right () -> putStrLn (name ++ " ok")

  f :: a -> IO ()
  f x = evaluate x >> return ()

  main :: IO ()
  main = do
    let w = 41 :: Word
    print (w + 1, w * 3 - 200, negate w, abs w, signum w)
    print (maxBound :: Word, minBound :: Word)
    print (fromIntegral (maxBound :: Word) :: Int)
    print (fromIntegral (-1 :: Int) :: Word)
    print (toInteger (maxBound :: Word) + 1)
    print (read "123" :: Word, read "-1" :: Word, read "18446744073709551616" :: Word)
    print (reads "42 rest" :: [(Word, String)])
    print (quotRem (100 :: Word) 7, divMod (100 :: Word) 7)
    print (w .&. 12, w .|. 2, xor w 1, shiftL w 60, shiftR (maxBound :: Word) 60)
    print (complement (0 :: Word), popCount (maxBound :: Word), testBit w 0)
    print (finiteBitSize w, bit 63 :: Word, setBit w 7, clearBit w 0)
    print ([1 .. 5] :: [Word], [10, 8 .. 1] :: [Word])
    print (take 3 [maxBound - 1 ..] :: [Word])
    print (range (3, 6 :: Word), index (3, 6 :: Word) 5, inRange (3, 6 :: Word) 9, rangeSize (3, 6 :: Word))
    print (toRational w, realToFrac w :: Double, fromIntegral w :: Double)
    print (showsPrec 11 w "", show [w, 0])
    print (compare w 42, max w 50, w == 41)
    putStrLn (printf "%d %5d %x %o %u" w w (255 :: Word) (8 :: Word) w)
    print (fromIntegral (300 :: Word) :: Word8, fromIntegral (maxBound :: Word64) :: Word)
    print (succ w, pred w, toEnum 7 :: Word, fromEnum w)
    putStrLn (describe w ++ ", " ++ describe (fromIntegral w + 1 :: Word64))
    let g = mkStdGen 42
    print (take 3 (randoms g :: [Word]), fst (randomR (10, 20 :: Word) g))
    print (take 3 (randoms g :: [Word]) == map fromIntegral (take 3 (randoms g :: [Word64])))
    t "succ maxBound" (f (succ (maxBound :: Word)))
    t "pred minBound" (f (pred (minBound :: Word)))
    t "toEnum negative" (f (toEnum (-1) :: Word))
    t "fromEnum big" (f (fromEnum (maxBound :: Word)))
    t "div zero" (f (div w 0))
    t "quot zero" (f (quot w 0))
    t "rem zero" (f (rem w 0))
    t "mod zero" (f (mod w 0))
    t "index out of range" (f (index (3, 6 :: Word) 9))
    t "read no parse" (f (read "x" :: Word))
    t "Word64 succ maxBound" (f (succ (maxBound :: Word64)))
    t "Word64 toEnum negative" (f (toEnum (-1) :: Word64))
  ```

  Oracle: `~/.ghcup/bin/runghc tests/conformance/m150_word.hs > tests/conformance/m150_word.out`.
  The recorded error lines (the texts this task exists for) are:

  ```
  succ maxBound => Enum.succ{Word}: tried to take `succ' of maxBound
  pred minBound => Enum.pred{Word}: tried to take `pred' of minBound
  toEnum negative => Enum.toEnum{Word}: tag (-1) is outside of bounds (0,18446744073709551615)
  fromEnum big => Enum.fromEnum{Word}: value (18446744073709551615) is outside of Int's bounds (-9223372036854775808,9223372036854775807)
  div zero => divide by zero
  quot zero => divide by zero
  rem zero => divide by zero
  mod zero => divide by zero
  index out of range => Error in array index
  read no parse => Prelude.read: no parse
  Word64 succ maxBound => Enum.succ{Word64}: tried to take `succ' of maxBound
  Word64 toEnum negative => Enum.toEnum{Word64}: tag (-1) is outside of bounds (0,18446744073709551615)
  ```

  (and `Word 41, Word64 42` for the class line). Today AHC rejects
  the file - the two `Describe` instances are one instance under
  `type Word = Word64` - and, without them, prints `{Word64}` in the
  four `Word` lines.

  Write `tests/corpus-types/bad_word_as_word64.hs`:

  ```haskell
  -- Word and Word64 are distinct types in GHC (same width): passing a
  -- Word where a Word64 is expected needs fromIntegral. AHC had
  -- `type Word = Word64` until M150 and accepted this.
  import Data.Word

  bump :: Word64 -> Word64
  bump x = x + 1

  main :: IO ()
  main = print (bump (3 :: Word))
  ```

  `scripts/run_differential_types.sh` must report
  `OVER-ACCEPT  tests/corpus-types/bad_word_as_word64.hs` now (GHC:
  `Couldn't match expected type 'Word64' with actual type 'Word'`;
  AHC: rc 0).

- [ ] **Step 2: Wire the TyCon.** `src/ahc-builtins.ads:79-80`:

  ```ada
        Arrow_TC, Ptr_TC, FunPtr_TC, Text_TC, Exc_TC, IOExc_TC, IORef_TC
          : Core.TyCon_Id := Core.No_TyCon;
  ```

  gains after it:

  ```ada
        --  Word (M150): its own type with Word64's representation and
        --  marshalling; not a C_Fix_Kind (that enumeration is the C
        --  widths, positional with Core.Fixed_Marshal).
        Word_TC : Core.TyCon_Id := Core.No_TyCon;
  ```

  `src/ahc-builtins.adb:274`
  (`Env.CFix_TCs (C_U64) := TyCon_Id (Def_TyCon ("Word64", 0, Star_K));`)
  gains after it:

  ```ada
        --  Word: GHC's distinct type of Word64's width (M150). Same
        --  runtime nodes as Word64 (AHC_INT, a bignum above 2^63).
        Env.Word_TC := TyCon_Id (Def_TyCon ("Word", 0, Star_K));
  ```

  `src/ahc-builtins.adb:974-978`, the loop

  ```ada
           for K in C_Fix_Kind loop
              Def_Instance (Cl (Env.Eq_Cl), TCn (Env.CFix_TCs (K)));
              Def_Instance (Cl (Env.Ord_Cl), TCn (Env.CFix_TCs (K)));
              Def_Instance (Cl (Env.Show_Cl), TCn (Env.CFix_TCs (K)));
           end loop;
  ```

  gains after `end loop;`:

  ```ada
           Def_Instance (Cl (Env.Eq_Cl), TCn (Env.Word_TC));
           Def_Instance (Cl (Env.Ord_Cl), TCn (Env.Word_TC));
           Def_Instance (Cl (Env.Show_Cl), TCn (Env.Word_TC));
  ```

  `src/ahc-prelude_core.adb:1840-1842` (Show at a fixed-width head
  uses Int's `showsPrec` prims; `Eq`/`Ord` are the structural prims
  for every head):

  ```ada
              function Is_Fix (T : TyCon_Id) return Boolean
              is (for some K in Builtins.C_Fix_Kind =>
                    Env.CFix_TCs (K) = T);
  ```

  becomes:

  ```ada
              function Is_Fix (T : TyCon_Id) return Boolean
              is ((for some K in Builtins.C_Fix_Kind =>
                     Env.CFix_TCs (K) = T)
                  or else T = Env.Word_TC);
  ```

  `src/ahc-desugar.adb:2840-2841` in `Classify`:

  ```ada
                       elsif Core.TyCon_Id (TN.Con) = Env.Text_TC then
                          K := Core.M_Text;
  ```

  gains after it:

  ```ada
                       elsif Core.TyCon_Id (TN.Con) = Env.Word_TC then
                          --  Word crosses as uint64_t, as Word64 (M150).
                          K := Core.M_U64;
  ```

  Semantic-check `ahc-builtins.adb`, `ahc-prelude_core.adb`,
  `ahc-desugar.adb` with the `-gnatc` command in the constraints.

- [ ] **Step 3: Prelude instances.** `prelude/Prelude.hs:1434-1437`:

  ```haskell
  -- GHC 9.4.8's. This block is GENERATED (one shape, eight types): edit
  -- the generator's shape in the M139 plan, not one copy.

  type Word = Word64
  ```

  becomes:

  ```haskell
  -- GHC 9.4.8's. This block is GENERATED (one shape, eight types): edit
  -- the generator's shape in the M139 plan, not one copy. Word, the
  -- ninth, follows Word64's block by hand (M150).
  ```

  After `instance Read Word64` (lines 1896-1897) insert:

  ```haskell

  -- Word (M150): GHC's distinct unsigned type of Word64's width, wired
  -- as its own TyCon (Builtins.Word_TC) with Word64's representation,
  -- so mixing the two needs fromIntegral. Written by hand in the
  -- generated blocks' shape; its texts name {Word}, as GHC's.

  narrowWord_ :: Integer -> Word
  narrowWord_ x = primFixCast (primNarrow 64 0 (primFixCast x))

  toWord_ :: Word -> Integer
  toWord_ = primFixCast

  instance Num Word where
    a + b = narrowWord_ (toWord_ a + toWord_ b)
    a - b = narrowWord_ (toWord_ a - toWord_ b)
    a * b = narrowWord_ (toWord_ a * toWord_ b)
    negate a = narrowWord_ (negate (toWord_ a))
    abs a = narrowWord_ (abs (toWord_ a))
    signum a = narrowWord_ (signum (toWord_ a))
    fromInteger i = narrowWord_ i

  instance Bounded Word where
    minBound = narrowWord_ (0)
    maxBound = narrowWord_ (18446744073709551615)

  instance Real Word where
    toRational a = toRational (toWord_ a)

  instance Enum Word where
    toEnum i =
      if i < 0
        then error ("Enum.toEnum{Word}: tag (" ++ show i
                    ++ ") is outside of bounds (0,18446744073709551615)")
        else narrowWord_ (toInteger i)
    fromEnum a =
      let i = toWord_ a
      in if i > 9223372036854775807
           then errorWithoutStackTrace ("Enum.fromEnum{Word}: value (" ++ show i
                       ++ ") is outside of Int's bounds (-9223372036854775808,9223372036854775807)")
           else fromInteger i
    succ a = if a == maxBound
               then error "Enum.succ{Word}: tried to take `succ' of maxBound"
               else a + 1
    pred a = if a == minBound
               then error "Enum.pred{Word}: tried to take `pred' of minBound"
               else a - 1
    enumFrom a = enumFromTo a maxBound
    enumFromTo a b = fixedEnumFromTo_ a b
    enumFromThen a b = enumFromThenTo a b (if b >= a then maxBound else minBound)
    enumFromThenTo a b c = fixedEnumFromThenTo_ a b c

  instance Integral Word where
    quot a b = overflowQuot_ (False) (b == narrowWord_ (-1))
                 (narrowWord_ (quot (toWord_ a) (toWord_ b)))
    rem a b = narrowWord_ (rem (toWord_ a) (toWord_ b))
    div a b = overflowQuot_ (False) (b == narrowWord_ (-1))
                (narrowWord_ (div (toWord_ a) (toWord_ b)))
    mod a b = narrowWord_ (mod (toWord_ a) (toWord_ b))
    toInteger a = toWord_ a

  instance Read Word where
    readsPrec _ s = [(narrowWord_ i, r) | (i, r) <- readsInteger_ s]
  ```

  (`Word` stays in the Prelude export list, line 59; it now names the
  wired TyCon, like `Int`. `check_prelude_exports.sh` is unchanged.)

- [ ] **Step 4: Library instances.** Append to `lib/Data/Bits.hs`
  (after line 173, the end of `instance Bits Word64`):

  ```haskell

  instance Bits Word where
    (.&.) a b = primFixCast (primNarrow 64 0 (primAndI (primFixCast a) (primFixCast b))) :: Word
    (.|.) a b = primFixCast (primNarrow 64 0 (primOrI (primFixCast a) (primFixCast b))) :: Word
    xor a b = primFixCast (primNarrow 64 0 (primXorI (primFixCast a) (primFixCast b))) :: Word
    complement a = primFixCast (primNarrow 64 0 (primComplementI (primFixCast a))) :: Word
    shift a i = primFixCast (primNarrow 64 0 (if i >= 0 then primShiftLI (primFixCast a) i
                                            else primShiftRU (primFixCast a) (negate i))) :: Word
    bit i = if i < 0 then primThrow (primExcArith 0)
            else primFixCast (primNarrow 64 0 (primShiftLI 1 i)) :: Word
    testBit a i = if i < 0 then primThrow (primExcArith 0)
                  else i < 64 && primAndI (primShiftRU (primFixCast a :: Int) i) 1 /= 0
    popCountBits a = primPopCountI (primNarrow 64 0 (primFixCast a))
    bitSizeOf _ = 64
  ```

  Append to `lib/Data/Ix.hs` (after line 105, the end of `instance
  Ix Word64`; recorded: GHC's `Ix Word` says `Error in array index`):

  ```haskell

  instance Ix Word where
    range (lo, hi) = [lo .. hi]
    index b@(lo, _) i =
      if inRange b i then fromIntegral i - fromIntegral lo
      else errorWithoutStackTrace "Error in array index"
    inRange (lo, hi) i = i >= lo && i <= hi
    rangeSize (lo, hi) =
      if hi < lo then 0 else fromIntegral hi - fromIntegral lo + 1
  ```

  `lib/Text/Printf.hs`, after `instance PrintfArg Word64` (lines
  104-106) insert:

  ```haskell
  instance PrintfArg Word where
    formatArg x = formatIntB (toInteger x) 0
    parseFormat _ = parseIntFormat
  ```

  `lib/System/Random.hs`: before `instance UniformRange Integer where`
  (line 347) insert:

  ```haskell
  -- Word (M150, its own type): random's Word instances are its Word64
  -- algorithms at the same width.
  uniformWord_ :: RandomGen g => g -> (Word, g)
  uniformWord_ g = case genWord64 g of (w, g') -> (fromIntegral w, g')

  instance Uniform Word where
    uniformP = uniformWord_
  instance UniformRange Word where
    uniformRP = unsignedBitmaskWithRejectionRM uniformWord_

  ```

  and before `instance Random Char where` (line 448):

  ```haskell
  instance Random Word where
    randomR = uniformRP
    random = uniformP
  ```

  Comments that described the synonym: `lib/System/Random.hs:27-28`

  ```haskell
  --   * `Word` is AHC's synonym for Word64, so the Word64 instances
  --     serve Word (random's two Word instances are the same algorithm).
  ```

  becomes

  ```haskell
  --   * `Word` is its own type (M150) whose instances run the Word64
  --     algorithms (random's two Word instances are the same algorithm).
  ```

  and line 315 `-- Int algorithms are its Int64 ones (genWord64, Word = Word64), so`
  becomes `-- Int algorithms are its Int64 ones (genWord64, Word's width), so`.
  `lib/Data/Word.hs:3-5`

  ```haskell
  -- See Data.Int. `Word` is a SYNONYM for Word64 here (GHC's is a
  -- distinct type of the same width) - the one observable divergence:
  -- an instance written for Word64 also serves Word, and vice versa.
  ```

  becomes

  ```haskell
  -- See Data.Int. `Word` is its own type of Word64's width, as GHC's
  -- (M150): the Prelude exports it, and mixing it with Word64 needs
  -- fromIntegral.
  ```

- [ ] **Step 5: Build and run the tests.**
  - `alr build --validation` (no background suite running);
  - one-case verify `m150_word` → `ok m150_word`;
  - `scripts/run_differential_types.sh` → `ok           tests/corpus-types/bad_word_as_word64.hs`
    and rc 0 (AHC now says `couldn't match type 'Word64' with 'Word'`);
  - one-case verify `lib_fixed_width_bounds` (its `row (0 :: Word)`
    exercises Num/Integral/Read/Enum/Real/Bounded at `Word`),
    `lib_data_int_word`, `lib_m146_review` (`toEnum 0 :: Word`),
    `lib_data_bits`, `lib_printf`, `lib_random`, `lib_splitmix`,
    `lib_to_rational` → `ok` each.

- [ ] **Step 6: EXCLUSIONS.** `tests/conformance/EXCLUSIONS.md` line
  30 (the `lib 23/24, base` row): replace

  ```
  `Word` is a SYNONYM for Word64 (GHC: a distinct type);
  ```

  with

  ```
  `Word` is its own type of Word64's width, as GHC's (M150: every Word64 instance, texts naming `{Word}`, uint64_t at the FFI; m150_word.hs, tests/corpus-types/bad_word_as_word64.hs);
  ```

  and delete `; error texts at `Word` name `{Word64}` where GHC's say `{Word}``
  (leaving the sentence ending `(tests/exec/word64_from_enum.hs).`).

- [ ] **Step 7: Goldens.** A new builtin TyCon renumbers the Core
  goldens, and the six new Prelude instances add bindings:
  - `alr build --release && scripts/run_golden.sh --update`;
  - check the diff is renumber-only plus the six dictionaries:

    ```sh
    for f in tests/golden/*.core tests/golden/*.types; do
      diff <(git show HEAD:$f | sed 's/_[0-9][0-9]*//g' | sort) \
           <(sed 's/_[0-9][0-9]*//g' $f | sort)
    done | grep '^[<>]' | cut -c1-30 | sort | uniq -c
    ```

    Expected (measured on the prototype), and nothing else - no `<`
    line, no `.types` change:

    ```
       3 > (bind ($dBoundedWord (letre
       3 > (bind ($dEnumWord (letrec (
       3 > (bind ($dIntegralWord (letr
       3 > (bind ($dNumWord (letrec ((
       3 > (bind ($dReadWord (letrec (
       3 > (bind ($dRealWord (letrec (
    ```

  - `alr build --validation && scripts/run_golden.sh` → green on the
    validation build too (a swap-only difference between the builds
    is the actual-evaluation-order bug, not a renumber).

- [ ] **Step 8: Verify.** `scripts/run_gate.sh` → `GATE ok`;
  `scripts/check_prelude_exports.sh` → `prelude exports ok`.

- [ ] **Step 9: Commit.**

  ```
  feat(types): word is its own type, as ghc's, with word64's width and every instance word64 has

  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```

---

### Task E6: `Word` across the FFI

**Files:**
- Create: `tests/exec/ffi_word.hs`, `tests/exec/ffi_word.out`
- Modify: `tests/export/MathLib.hs` (append), `tests/export/main.c:2-4`, `:22`, `tests/export/expected.out` (append)

**Interfaces:**
- Consumes: `Word_TC` classified as `Core.M_U64` (Task E5 step 2).

Today a `Word` in a foreign type is `Word64` by synonym; after E5 it
reaches `Classify` as its own TyCon, and without the E5 arm it would
be rejected as unmarshallable. Bindgen maps by marshal kind
(`ahc-bindgen.adb:30-35`, `:156`, `:313`), so `M_U64` gives
`uint64_t` / `u64` / `uint64` with no bindgen change. No C-header
importer maps `size_t`/`uintptr_t` in AHC (`grep -rn
'size_t\|uintptr_t' src/ scripts/` finds only codegen/runtime C
text); the one `size_t` mapping is the `CSize` synonym
(`ahc-builtins.adb:349`), which stays `Word64` - GHC's `CSize` is a
newtype over `Word64`, not `Word`.

- [ ] **Step 1: Import direction.** Write `tests/exec/ffi_word.hs`:

  ```haskell
  -- Word (M150, its own type) crosses the FFI as uint64_t, as Word64
  -- does: size_t in and out, including a Word above 2^63 (a bignum in
  -- AHC's representation) as an argument.
  {-# LANGUAGE ForeignFunctionInterface #-}

  foreign import ccall "strnlen" c_strnlen :: String -> Word -> Word

  main :: IO ()
  main = do
    print (c_strnlen "fixed widths" 5)
    print (c_strnlen "abc" maxBound)
    print (c_strnlen "" 0, c_strnlen "twelve chars" 100 + 1)
  ```

  and `tests/exec/ffi_word.out`:

  ```
  5
  3
  (0,13)
  ```

  (`strnlen` is POSIX 2008: present on macOS and glibc. Measured on
  the prototype under Boehm and `AHC_GC=own`.)

- [ ] **Step 2: Export direction.** Append to `tests/export/MathLib.hs`:

  ```haskell

  -- Word is its own type (M150) and crosses as uint64_t, as Word64.
  foreign export ccall wordPred :: Word -> Word
  wordPred :: Word -> Word
  wordPred w = w - 1
  ```

  In `tests/export/main.c`, the includes (lines 2-4) become (the
  generated header uses `uint64_t` without including `<stdint.h>`, so
  the host includes it first):

  ```c
  #include <inttypes.h>
  #include <stdio.h>
  #include <stdlib.h>
  #include "ahc_exports.h"
  ```

  and after `printf("square(6) = %ld (still alive)\n", square(6));`
  (line 22) insert:

  ```c

    /* Word wraps below zero and returns above 2^63 (M150). */
    printf("wordPred(0) = %" PRIu64 "\n", wordPred(0));
    printf("wordPred(UINT64_MAX) = %" PRIu64 "\n", wordPred(UINT64_MAX));
  ```

  Append to `tests/export/expected.out`:

  ```
  wordPred(0) = 18446744073709551615
  wordPred(UINT64_MAX) = 18446744073709551614
  ```

- [ ] **Step 3: Bindgen spellings.** With the export in place:

  ```sh
  t=$(mktemp -d)
  scripts/ahc-build.sh --lib tests/export/MathLib.hs $t/m.a >/dev/null
  for l in cpp rust go; do ./bin/ahc bindgen $l tests/export/MathLib.hs $t/m.a >/dev/null; done
  grep -h 'wordPred\|WordPred' $t/m.a.build/ahc_exports.h $t/m.a.build/ahc_exports.hpp \
    $t/m.a.build/ahc_exports.rs $t/m.a.build/ahc.go
  ```

  Expected (measured on the prototype):

  ```
  uint64_t wordPred(uint64_t a0);
    uint64_t wordPred(uint64_t a0) {
      uint64_t r_ = ::wordPred(a0);
          pub fn wordPred(a0: u64) -> u64;
  pub fn wordPred(a0: u64) -> Result<u64, String> {
          let r_ = raw::wordPred(a0);
  func WordPred(a0 uint64) (uint64, error) {
                  r = uint64(C.wordPred(C.uint64_t(a0)))
  ```

- [ ] **Step 4: Verify.**
  - `scripts/run_export.sh` → `ok   tests/export (C main against AHC library)`;
  - `scripts/run_bindgen.sh` → every `ok   examples/ffi/...` line it
    printed before the change (Engine.hs has no `Word`; this pins
    no regression);
  - `scripts/run_exec.sh` and `AHC_GC=own scripts/run_exec.sh` →
    `ok   tests/exec/ffi_word.hs`, `ok   tests/exec/ffi_word64.hs`,
    `ok   tests/exec/ffi_fixed.hs` (CSize stays Word64);
  - `scripts/run_golden.sh` → green (`check_foreign_errors` /
    `check_foreign_export_errors` unchanged).

- [ ] **Step 5: Commit.**

  ```
  feat(ffi): word crosses the boundary as uint64_t in both directions and in every bindgen language

  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```

**Write-up inputs (for the milestone write-up, not this phase):**
`README.md:406` says `` `Word` = `Word64` ``; `docs/MANUAL.md:1359-1370`
lists the fixed-width FFI types without `Word` (add: `Word` marshals
as `uint64_t`); its sentence "the Haskell-to-C direction accepts
`0..2^63-1` in v1" is stale since the M139 review (`ffi_word64.hs`
and `ffi_word.hs` pass `maxBound`); CHANGES gets the `maximumBy` tie
fix as a correctness fix, not a text change.

**Gate E:** conformance (oracled) - a probe per changed site (caught
`show`), a `Word` program (arithmetic, `show`/`read`, `Enum` errors,
`Bits`, conversions); negative corpus - `Word` used as `Word64`;
`run_export.sh` and `run_bindgen.sh`; full suites both GC modes.
EXCLUSIONS loses the library-text clause.

## Milestone gate

After E6, on the release and the validation build:

**Gate:** full suites in both builds and both GC modes
(`scripts/run_gate.sh`); `scripts/run_own_soak.sh` with
`AHC_OWN_VERIFY=1` (from the 64KB floor); `scripts/run_tsan.sh`;
`scripts/run_fuzz_par.sh 300 8`; `scripts/run_differential.sh` and
`scripts/run_differential_types.sh`; `scripts/run_export.sh`,
`scripts/run_bindgen.sh`, `scripts/run_discharge.sh`; bench delta
against v1.20 within 2% with `b_sort` and `b_map` named. Then the
adversarial review (`fix: N defects an adversarial review of m150
found`) and the write-up (CHANGES, README, MANUAL, EXCLUSIONS, the
memory notes; README:406 and MANUAL:1368-1370 are stale about `Word`).
