# M149 Runtime errors better than GHC's - Implementation Plan

**Goal:** a caught exception's `show` text equals GHC 9.4.8's,
including call stacks and `PatternMatchFail`. An uncaught error prints
a report with location, snippet, enclosing function and the failing
value, and `ahc build --trail` adds an evaluation trail.

**Architecture:** desugar turns every runtime failure point into a
**site**: one string literal, built at compile time, that holds GHC's
exact text and the report's material. Pattern fallthroughs call a new
primitive, `primFailMatch`. Uses of registered partial functions are
rewritten to located variants that take the site. The runtime raises
GHC-shaped exceptions and keeps each report in a side table, which only
the uncaught-error printer reads.

Spec: `docs/specs/2026-10-13-m149-runtime-errors.md`.

## Global constraints

- **Oracle:** compiled GHC 9.4.8 (`~/.ghcup/bin/ghc -O0`). Recorded
  oracle texts live in the conformance goldens, never in prose.
- **Observable behaviour is byte-identical to GHC:** `show` and
  `displayException` of exceptions, exception types, and exit codes.
  Stderr is AHC's own; the exec goldens pin it.
- **Gate inputs:** `prelude/`, `lib/`, `runtime/ahc_rts.c` and
  `bin/ahc`. Never edit or rebuild them while a suite runs.
- **Goldens:** every new builtin renumbers the Core goldens.
  Regenerate them with `run_golden.sh --update` on BOTH builds, and
  check the diff is renumber-only (strip `_[0-9]+`) plus the intended
  `primFailMatch` / located-variant changes.
- **Ada:**
  - Never pass two id-minting calls, or an `in out M` together with an
    `M.Info`/`M.Node` read, as actuals of one call; hoist them into
    constants.
  - Avoid reserved words as names.
  - Semantic-check with
    `alr exec -- gcc -c -gnatc -gnat2022 -gnatwa -Isrc src/X.adb -o <scratch>/ck/X.o`
    before building.
- **Own collector:** a runtime object is fully built and rooted before
  anything that points to it is allocated.
- **Bench:** without `--trail`, `run_bench.sh` stays within 2% of
  v1.19.1. A located `div` family that misses that budget is dropped
  from the located list (Task C3, step 3).
- **Platforms:** CI is green on ubuntu-24.04 and macOS.

## Spec deviations (decided while planning, recorded here and in the write-up)

1. **Sites are string literals, not dense integer ids.** Separate
   compilation caches each module's C object, so program-wide numbering
   would invalidate every cache entry when any module changed. A string
   literal stays local to its unit, costs nothing until forced, and
   needs no codegen table.
2. **Value rendering uses a per-site type schema, not a global
   constructor-name table.** A runtime constructor node holds only
   `contag` and `arity`, with no type identity
   (`runtime/ahc_rts.h:36`), so a global table could not name a nested
   constructor. Each pattern site records the constructor names of the
   scrutinee's type, and of each field whose declared type is a
   concrete type constructor, down to depth 3. A field whose type is a
   type variable renders as a primitive (Int/Char/Double/bignum by node
   tag, a string when its spine is evaluated Chars) or as `_`.
3. **`read`'s report shows the input but not the target type.** Desugar
   runs before the typechecker, so the type is unknown when the site is
   built.
4. **`show (e :: ErrorCall)` omits the call stack** where GHC's
   `ErrorCallWithLocation` includes it. Matching it needs pattern
   synonyms, so that `ErrorCall m` still matches. `show (e ::
   SomeException)`, the common case, includes it. EXCLUSIONS records
   the gap.
5. **Class methods are not located.** That means `div`/`mod`/`quot`/
   `rem`/`divMod`/`quotRem`, `toEnum`, `succ` and `pred`: desugar runs
   before instance resolution, so a method's call site cannot be
   rewritten by identity. GHC 9.4.8 gives these no call stack, so the
   shown text already matches. Only their uncaught report lacks a
   location, and `--trail` covers it (Tasks C2 step 3, C3).
6. **Missing record field and record-update failure** raise
   `PatternMatchFail`-kind exceptions carrying GHC's exact text. GHC
   raises `RecConError` / `RecUpdError` there, which AHC does not
   model, so the shown text matches but catching by those types is not
   possible. EXCLUSIONS records it.
7. **`<<loop>>` and stack overflow keep their current messages.**
   Naming the looping binder or the deepest function needs per-thunk or
   per-frame labels at all times, which is the always-on cost the user
   ruled out. Under `--trail` the report's evaluation trail shows where
   evaluation was. Task E1 prints the trail for these two failures
   too.

## File map

| File | Change |
|---|---|
| `src/ahc-sites.ads/.adb` (new) | `Site` record, `Encode` to the literal format, GHC span text, base-frame table, render schema |
| `src/ahc-desugar.ads/.adb` | `Site_Context` parameter; pattern fallthroughs call `primFailMatch`; located-variant rewrite |
| `src/ahc-syntax.ads`, `src/ahc_main.adb` | `{-# AHC_LOCATED f = f_at_ #-}` pragma detection (like `Detect_Overlap`) |
| `src/ahc-rename.ads/.adb` | resolve pragma pairs into `Resolutions.Located` |
| `src/ahc-builtins.adb`, `src/ahc-prelude_core.adb` | `primFailMatch`, `primErrorAt`, `primExcLocation`, `primExcPatternFail` |
| `src/ahc-codegen.adb`, `src/ahc_main.adb` | `--trail`: entry pushes and the name table |
| `runtime/ahc_rts.c/.h` | `EXC_PATTERN`, ErrorCall location field, site parsing, side table, renderer, uncaught report, trail ring |
| `prelude/Prelude.hs` | `*_at_` located variants and `AHC_LOCATED` pragmas |
| `lib/Control/Exception.hs` | `PatternMatchFail`; `Show SomeException` appends the location |
| `lib/Data/Maybe.hs` | `fromJust_at_` and its pragma |
| `scripts/run_conformance.sh` | multi-module cases build from inside the case directory |
| `tests/conformance/m149_*`, `tests/exec/m149_*`, `tests/src/test_sites.adb` | tests |

## The site literal format

Fields are separated by `\x1f` (unit separator); list items within a
field by `\x1e`. Field order:

```
0  ghc_text     the exception's GHC show text, without the CallStack block
1  ghc_stack    the CallStack block (lines joined by \n), "" if none
2  headline     "pattern match failure" | "empty list" | "index out of range" | ...
3  file         path as given on the command line
4  line:col-line:col   the span, 1-based, end inclusive
5  in           enclosing top-level binding
6  snippet      the spanned source lines (max 6), \x1e-separated, first line number prefixed "L|"
7  handled      constructor names the alternatives match, \x1e-separated
8  schema       the render schema (deviation 2), see AHC.Sites.Schema_Text
9  note         an extra note line or ""
```

---

## Phase A - the exception model

### Task A1: record the oracle texts (failing tests first)

**Files:**
- Create: `tests/conformance/m149_shown_errors.hs` (+ `.out` from the oracle)
- Create: `tests/conformance/m149_shown_patterns.hs` (+ `.out`)

- [ ] **Step 1:** write `m149_shown_errors.hs`. A `t name action`
  harness catches `SomeException` and prints
  `name ++ " => " ++ show e`. It covers:
  - `error "boom"`, `errorWithoutStackTrace "plain"`, `undefined`;
  - `head []`, `tail []`, `init []`, `last []`, `[1,2,3] !! 5`,
    `[1] !! (-1)`, `maximum []`, `minimum []`,
    `foldr1 (+) ([] :: [Int])`, `foldl1 (+) ([] :: [Int])`,
    `cycle ([] :: [Int])`;
  - `fromJust Nothing` (`import Data.Maybe`), `read "x" :: Int`;
  - `toEnum 5 :: Bool`, `chr 99999999`, `succ (maxBound :: Int)`;
  - `1 \`div\` (0 :: Int)`, `mod`, `quot`, `rem`, `divMod`, `quotRem`
    by zero;
  - `minBound \`div\` (-1 :: Int)`.

  Each case is on its own line, so the columns are distinct.
- [ ] **Step 2:** write `m149_shown_patterns.hs` the same way. It
  covers a function with no matching equation (multi-line span), a
  one-line `case`, a lambda, a `let (Just x) = Nothing in x`, an
  irrefutable `~(Just y)`, a multi-way if with no true guard, a guard
  fallthrough in a function, a missing record field at construction, a
  record update of a constructor without the field, and `case x of {}`.
  It also catches `PatternMatchFail` by type and prints `"by type"`.
  It imports `Control.Exception (PatternMatchFail (..))`; until A2,
  that line fails to build.
- [ ] **Step 3:** oracle both with `scripts/run_conformance.sh
  --oracle`. If the full oracle run is too slow, run
  `~/.ghcup/bin/runghc tests/conformance/X.hs > tests/conformance/X.out`
  from the repo root, so GHC sees the same path AHC is given. Then
  check that the `.out` files contain `CallStack (from HasCallStack):`
  and `Non-exhaustive patterns in function`. Copy GHC's
  `base`-internal frame lines into the table in Task C1, verbatim.
- [ ] **Step 4:** confirm both programs FAIL on the current AHC:
  `scratchpad/one.sh conformance m149_shown_errors` shows a diff.
- [ ] **Step 5:** commit:
  `test(conformance): ghc 9.4.8's shown text for every runtime failure kind, failing until m149 lands`.

### Task A2: ErrorCall's location, PatternMatchFail (runtime + lib)

**Files:**
- Modify: `runtime/ahc_rts.c`:
  - `#define EXC_ERROR_CALL 1`, which gains field 1;
  - new `#define EXC_PATTERN 5`;
  - `exc_error_call`, `exc_render`, the `primExc*` accessors.
- Modify: `src/ahc-builtins.adb`, `src/ahc-prelude_core.adb`
  (`Def_Global` + `BP` pairs for the new primitives)
- Modify: `lib/Control/Exception.hs`

**Interfaces:**
- Produces:
  - `primExcLocation :: SomeException -> String` (field 1 of an
    ErrorCall, `""` if none);
  - `primExcPatternFail :: String -> SomeException`;
  - the C function `exc_error_call_at(msg, loc)`;
  - kind 5 from `primExcKind`.

- [ ] **Step 1:** implement the runtime side:

```c
#define EXC_ERROR_CALL 1   /* [message :: String, location :: String] */
#define EXC_PATTERN    5   /* [message :: String]  (PatternMatchFail) */

static AhcNode *exc_error_call_at(AhcNode *msg, AhcNode *loc) {
  AhcNode *e = ahc_mk_con(EXC_ERROR_CALL, 2);  /* msg, loc built first */
  e->u.con.fields[0] = msg;
  e->u.con.fields[1] = loc;
  return e;
}
static AhcNode *exc_error_call(AhcNode *msg) {
  return exc_error_call_at(msg, ahc_nil());    /* "" location */
}
```

  `exc_render`'s `EXC_ERROR_CALL` case prints the message. When the
  location is non-empty, it then prints `\n` and the location.
  `EXC_PATTERN` prints its message. Check every place that reads
  `fields[0]` of an ErrorCall (`grep -n EXC_ERROR_CALL
  runtime/ahc_rts.c`) and leave each one correct.
- [ ] **Step 2:** register the primitives:
  - `Def_Global ("primExcLocation", Mono (FN (Exc_T, Str)))`;
  - `Def_Global ("primExcPatternFail", Mono (FN (Str, Exc_T)))`;
  - the matching `BP` lines.
- [ ] **Step 3:** update `lib/Control/Exception.hs`:

```haskell
instance Show SomeException where
  showsPrec p se = case primExcKind se of
    1 -> let loc = primExcLocation se
         in showsPrec p (ErrorCall (primExcMessage se))
              . (if null loc then id else showString ('\n' : loc))
    2 -> showsPrec p (arithFromCode (primExcCode se))
    3 -> showsPrec p (primExcIO se)
    5 -> showString (primExcMessage se)
    _ -> showsPrec p (exitFromCode (primExcCode se))

newtype PatternMatchFail = PatternMatchFail String

instance Show PatternMatchFail where
  showsPrec _ (PatternMatchFail m) = showString m

instance Exception PatternMatchFail where
  toException (PatternMatchFail m) = primExcPatternFail m
  fromException se
    | primExcKind se == 5 = Just (PatternMatchFail (primExcMessage se))
    | otherwise = Nothing
```

  Export `PatternMatchFail (..)`. `primExcMessage` must accept kind 5:
  extend `exc_field`'s check.
- [ ] **Step 4:** verify that nothing visible changed yet:
  `./scripts/run_gate.sh` → `GATE ok`; `./scripts/run_export.sh`
  rc 0.
- [ ] **Step 5:** commit:
  `feat(runtime): errorcall carries a location and patternmatchfail is an exception kind`.

**Gate (Phase A):**
- `run_gate.sh` (unit, conformance, exec, exec-own, golden), with
  goldens regenerated renumber-only;
- `run_export.sh`, `run_userlib.sh`, `run_differential_types.sh`.

---

## Phase B - sites and pattern failures

### Task B1: `AHC.Sites`

**Files:**
- Create: `src/ahc-sites.ads`, `src/ahc-sites.adb`
- Test: `tests/src/test_sites.adb/.ads` (registered in
  `tests/src/ahc_tests_main.adb` like the other `Test_*` packages)

**Interfaces:**
- Produces: the spec below.

```ada
with Ada.Strings.Unbounded;
with AHC.Source_Text;
with AHC.Diagnostics;

package AHC.Sites is
   use Ada.Strings.Unbounded;

   --  Where a module's sites come from: the file as given on the
   --  command line (GHC prints the same), its module name, its text.
   type Site_Context is record
      File   : Unbounded_String;
      Module : Unbounded_String;
      Src    : access constant Source_Text.Source := null;
   end record;

   type Site is record
      Ghc_Text  : Unbounded_String;
      Ghc_Stack : Unbounded_String;
      Headline  : Unbounded_String;
      Span      : Diagnostics.Source_Span;
      Enclosing : Unbounded_String;
      Handled   : Unbounded_String;  --  names joined by ASCII.RS
      Schema    : Unbounded_String;
      Note      : Unbounded_String;
   end record;

   --  GHC's span text: "F:L:C1-C2" on one line,
   --  "F:(L1,C1)-(L2,C2)" across lines (end column inclusive).
   function Ghc_Span (Ctx : Site_Context; Span : Diagnostics.Source_Span)
     return String;

   --  The literal of the format in the plan header.
   function Encode (Ctx : Site_Context; S : Site) return String
     with Post => Encode'Result'Length > 0;

   --  base's fixed frames for a located Prelude function, recorded
   --  from GHC 9.4.8 (Task A1); "" for functions GHC gives no stack.
   function Base_Frames (Fn : String) return String;
end AHC.Sites;
```

- [ ] **Step 1:** implement `Ghc_Span`. Line and column come from
  `Source_Text.Line_Of` / `Column_Of` of `Span.Start` and of
  `Span.Stop - 1`. Columns are 1-based, as GHC's are.
- [ ] **Step 2:** implement `Encode`. Join fields 0-9 with
  `ASCII.US`. The snippet is lines L1..min(L2, L1+5), each prefixed
  `"L|"`, joined by `ASCII.RS`.
- [ ] **Step 3:** implement `Base_Frames` as a case on `Fn`. It
  returns the exact text recorded in A1. For example, `"head"` returns
  `"  error, called at libraries/base/GHC/List.hs:1646:3 in base:GHC.List"
  & LF & "  errorEmptyList, called at ..." & LF & "  badHead, called at ..."`;
  the caller appends the user's frame.
- [ ] **Step 4:** unit tests in `test_sites.adb`:
  - `Ghc_Span` on a one-line span gives `"E.hs:19:23-60"`;
  - on a two-line span it gives `"E.hs:(5,1)-(6,19)"`;
  - `Encode` round-trip: the field count is 10;
  - `Base_Frames ("head")` ends with `"badHead, called at libraries/base/GHC/List.hs:81:28 in base:GHC.List"`.

  Run them with `cd tests && alr build --validation && ./bin/ahc_tests`,
  which must report `failed: 0`.
- [ ] **Step 5:** commit:
  `feat(sites): ahc.sites encodes a runtime failure site with ghc's span text`.

### Task B2: `primFailMatch` (runtime + builtin)

**Files:**
- Modify: `runtime/ahc_rts.c`, `runtime/ahc_rts.h`,
  `src/ahc-builtins.adb`, `src/ahc-prelude_core.adb`

**Interfaces:**
- Produces: `primFailMatch :: String -> a -> b`, in C
  `ahc_prim_fail_match`. This task does not record a report yet;
  Phase D adds that.

- [ ] **Step 1:** implement the primitive:

```c
/* The site literal's field K as a fresh String (C-side parse; the
   literal is forced once, on the failure path only). */
static AhcNode *site_field(AhcNode *site, int k);

static AhcNode *p_fail_match(AhcNode *site, AhcNode *scrut) {
  AhcNode *msg = site_field(site, 0);
  AhcNode *e;
  (void)scrut;                       /* Phase D renders it */
  fflush(stdout);
  e = ahc_mk_con(EXC_PATTERN, 1);    /* msg built first: own GC order */
  e->u.con.fields[0] = msg;
  ahc_throw(e);
}
```

  `site_field` walks the literal's list, counting `\x1f` separators,
  and copies field k into a new list.
- [ ] **Step 2:** register `Def_Global ("primFailMatch", Poly2 (A, B,
  FN (String_T, TV (A), TV (B))))` and `BP ("primFailMatch",
  "ahc_prim_fail_match")`. Record it as `Env.Fail_Match_V` (add the
  field to `Global_Env`, next to `Error_V`).
- [ ] **Step 3:** commit together with B3 (B2 alone has no producer).

### Task B3: desugar emits sites for pattern fallthroughs

**Files:**
- Modify: `src/ahc-desugar.ads` (a new `Ctx : Sites.Site_Context`
  parameter, defaulting to an empty context);
- Modify: `src/ahc-desugar.adb` (the sites at lines ~380, 1212, 1274,
  1335, 1435, 1539, 1605 and 1652 that today call `Error_Call` with
  "non-exhaustive ..."/"... failed"/"empty case"/"missing field ...");
- Modify: `src/ahc_main.adb:903,1020` (pass each module's context:
  path as given, module name, `Src`).

**Interfaces:**
- Consumes: `AHC.Sites`, `Env.Fail_Match_V`.
- Produces: in desugar,
  `function Fail_Match (Kind : String; Span : Source_Span; Scrut : Real_Expr_Id; Handled : String) return Real_Expr_Id`,
  plus a desugar-wide `Current_Top : Unbounded_String`, set as each
  top-level binding is desugared.

- [ ] **Step 1:** add the helper:

```ada
function Fail_Match
  (Kind : String; Span : Diagnostics.Source_Span;
   Scrut : Core.Real_Expr_Id; Handled : String)
   return Core.Real_Expr_Id
is
   S : Sites.Site;
begin
   S.Ghc_Text := To_Unbounded_String
     (Sites.Ghc_Span (Ctx, Span) & ": Non-exhaustive patterns in "
      & Kind & ASCII.LF);
   S.Headline := To_Unbounded_String ("pattern match failure");
   S.Span := Span;
   S.Enclosing := Current_Top;
   S.Handled := To_Unbounded_String (Handled);
   declare
      Lit : constant Core.Real_Expr_Id :=
        Str_Lit (Sites.Encode (Ctx, S), Span);
      Fm : constant Core.Real_Expr_Id := Global (Env.Fail_Match_V, Span);
   begin
      return App2 (Fm, Lit, Scrut, Span);
   end;
end Fail_Match;
```

  `Kind` is `"function " & Name`, `"case"`, `"lambda"`, `"multi-way
  if"` or the A1-recorded text for each other kind. Where GHC's
  wording differs from "Non-exhaustive patterns in" (irrefutable
  patterns, missing fields, record update, empty case), add a
  `Ghc_Text` override parameter that takes the exact A1 text.
- [ ] **Step 2:** replace each `Error_Call` fallthrough with
  `Fail_Match`. Pass the scrutinee variable, or a tuple of the
  equation's argument variables for a multi-argument function; build
  the tuple in a hoisted constant. `Handled` is the constructor names
  that appear in the alternatives' top-level patterns.
- [ ] **Step 3:** pass the context at both `Desugar_Module` calls in
  `ahc_main.adb`. The REPL path passes `File => "<interactive>"`,
  which is GHC's own name for it.
- [ ] **Step 4:** regenerate the goldens (`run_golden.sh --update`)
  and check the diff: stripped of `_[0-9]+`, the only changes are
  `(var error) (str "non-exhaustive...")` →
  `(var primFailMatch) (str "...") (var ...)`.
- [ ] **Step 5:** verify:
  - `scratchpad/one.sh conformance m149_shown_patterns` → `ok`;
  - `./scripts/run_gate.sh` → `GATE ok`.

  `multiway_if_fail.out` and the other exec goldens change in Phase D,
  not here: the uncaught printer still prints GHC's text. Expect
  `exec` to fail only where a golden printed the old desugar text, and
  regenerate those goldens after confirming each new line equals
  GHC's.
- [ ] **Step 6:** commit:
  `feat(desugar): a pattern-match failure raises patternmatchfail with ghc's span text`.

**Gate (Phase B):**
- the unit tests;
- `run_gate.sh` in both GC modes;
- goldens on both builds, the diff renumber-only plus the intended
  changes;
- `run_differential.sh`, `run_differential_types.sh`, `run_repl.sh`
  and `run_separate.sh`;
- `m149_shown_patterns` byte-identical.

---

## Phase C - located partial functions

### Task C1: the `AHC_LOCATED` pragma and its resolution

**Files:**
- Modify: `src/ahc-syntax.ads` (add `Located : Located_Vectors.Vector`
  of `(Plain, At : Names.Name_Id)` to `Module_Arena`);
- Modify: `src/ahc_main.adb` (a `Detect_Located (Src, Spans, Arena)`
  beside `Detect_Overlap`. It parses `{-# AHC_LOCATED f = f_at_ #-}`
  with the same `Inner_Of` and a case-sensitive split on `=`, and
  handles operators written `(!!)`);
- Modify: `src/ahc-rename.ads/.adb` (add `Resolutions.Located :
  Var_Maps.Map` from the plain entity's `Var_Id` to the located one,
  filled by resolving both names in the module's own scope);
- Modify: `src/ahc-sites.adb` (`Base_Frames` holds every A1 frame).

**Interfaces:**
- Produces: `Res.Located` (plain → located). The map is program-wide:
  `ahc_main` merges each module's map into `Program_Located`, which is
  passed to every later `Desugar_Module`.

- [ ] **Step 1:** implement the detection and resolution. A pragma
  naming an unknown entity is a compile error in the declaring module:
  "AHC_LOCATED: 'x' is not defined here".
- [ ] **Step 2:** unit test in `test_sites.adb`: the pragma `{-#
  AHC_LOCATED (!!) = index_at_ #-}` splits to `("!!", "index_at_")`.
- [ ] **Step 3:** commit with C2.

### Task C2: the located variants (Prelude, Data.Maybe)

**Files:**
- Modify: `prelude/Prelude.hs`, `lib/Data/Maybe.hs`,
  `src/ahc-builtins.adb`, `src/ahc-prelude_core.adb`,
  `runtime/ahc_rts.c`

**Interfaces:**
- Produces:
  - `primErrorAt :: String -> String -> a`, which raises an ErrorCall
    whose message is the argument and whose location is the site's
    field 1;
  - the variants `error_at_`, `undefined_at_`, `head_at_`, `tail_at_`,
    `init_at_`, `last_at_`, `index_at_`, `maximum_at_`,
    `minimum_at_`, `foldr1_at_`, `foldl1_at_`, `cycle_at_`,
    `fromJust_at_`, `read_at_`, `toEnum` (per derived Enum: see
    step 3), `chr_at_`, `succ_at_`, `pred_at_`.

- [ ] **Step 1:** implement `primErrorAt` (C):

```c
static AhcNode *p_error_at(AhcNode *site, AhcNode *msg) {
  AhcNode *loc = site_field(site, 1);      /* "" when GHC has none */
  fflush(stdout);
  ahc_throw(exc_error_call_at(msg, loc));
}
```

- [ ] **Step 2:** write the variants. Each mirrors its plain
  definition exactly, with `error m` replaced by `primErrorAt s m`:

```haskell
{-# AHC_LOCATED head = head_at_ #-}
head_at_ :: String -> [a] -> a
head_at_ _ (x : _) = x
head_at_ s [] = primErrorAt s "Prelude.head: empty list"

{-# AHC_LOCATED error = error_at_ #-}
error_at_ :: String -> String -> a
error_at_ s m = primErrorAt s m

{-# AHC_LOCATED (!!) = index_at_ #-}
index_at_ :: String -> [a] -> Int -> a
index_at_ s xs n
  | n < 0 = primErrorAt s "Prelude.!!: negative index"
  | otherwise = go xs n
  where go [] _ = primErrorAt s "Prelude.!!: index too large"
        go (y : ys) k = if k == 0 then y else go ys (k - 1)
```

  `index_at_` must keep `indexGo_`'s strictness: compare it with
  `prelude/Prelude.hs:374-380` and copy it.
- [ ] **Step 3:** decide on `toEnum`, `succ` and `pred`. These are
  class methods whose instance is chosen after desugar, so a call site
  cannot be rewritten by identity. Locate only the Prelude functions
  that are not methods. For the derived-Enum `toEnum` error, the
  derived code already raises, and its report gets the instance's type
  name from prelude_core. Record this in the write-up. `chr` is a
  plain function, so it is located.
- [ ] **Step 4:** in desugar, rewrite each `Var_E` occurrence whose
  resolution is a key of `Program_Located` to
  `App1 (Global (Located), Str_Lit (Encode (Ctx, S)))`. Here
  `S.Ghc_Stack` is `"CallStack (from HasCallStack):" & LF &
  Base_Frames (Name)` followed by `"  " & Name & ", called at " &
  File & ":" & L & ":" & C & " in main:" & Module` when `Base_Frames`
  is non-empty or the name is `error`/`undefined`. Otherwise it is
  `""`.
- [ ] **Step 5:** regenerate the goldens and check the diff as in B3.
  Then verify:
  - `scratchpad/one.sh conformance m149_shown_errors` → `ok`;
  - a user module defining its own `head` and calling it on `[]`
    prints that module's own error text with no call stack. That's
    conformance program `m149_user_head.hs`, oracled.
- [ ] **Step 6:** commit:
  `feat(prelude): partial prelude functions and error report their call site as ghc's call stack does`.

### Task C3: arithmetic by zero

- [ ] **Step 1:** `div`, `mod`, `quot`, `rem`, `divMod` and `quotRem`
  are `Integral` methods, so they are not rewritable by identity (see
  C2 step 3). GHC's text for them carries no location, and AHC's
  already matches. Their report gains the site through the opt-in
  trail only. Record this as a deviation from the spec's located list.
- [ ] **Step 2:** check that `m149_shown_errors`' arithmetic lines are
  byte-identical. They already are.
- [ ] **Step 3:** no bench risk follows. Note it in the write-up.

**Gate (Phase C):**
- `run_gate.sh` in both GC modes;
- goldens on both builds;
- both differentials, `run_repl.sh`, `run_separate.sh`,
  `run_userlib.sh`, `check_prelude_exports.sh` (no `*_at_` name
  leaks into the user Prelude view);
- `run_bench.sh` within 2% of v1.19.1, since every `head` now passes a
  site;
- `m149_shown_errors`, `m149_shown_patterns` and `m149_user_head`
  byte-identical.

---

## Phase D - the uncaught report

### Task D1: the render schema

**Files:**
- Modify: `src/ahc-sites.ads/.adb`
  (`Schema_Text (M, Env, Tc : TyCon_Id; Depth : Natural) return String`)
- Modify: `src/ahc-desugar.adb` (fill `S.Schema` at pattern sites
  whose handled constructors give a TyCon)

- [ ] **Step 1:** the schema grammar:
  `T{C1/n1:f,f;C2/n2:...}`. Each constructor carries its arity and a
  per-field type code:
  - `i` Int, `d` Double, `f` Float, `c` Char, `z` Integer;
  - `s` String;
  - `l<code>` a list of that code;
  - a nested `T{...}` for a concrete TyCon, down to depth 3;
  - `?` for a type variable or beyond the depth.
- [ ] **Step 2:** unit test: for `data Shape = Circle Double | Triangle
  Double Double`, the schema is `"Shape{Circle/1:d;Triangle/2:d,d}"`.
- [ ] **Step 3:** commit with D2.

### Task D2: side table, renderer, uncaught printer (runtime)

**Files:**
- Modify: `runtime/ahc_rts.c` (new section "runtime error reports")

- [ ] **Step 1:** add the side table:

```c
#define REPORT_SLOTS 32
static struct { AhcNode *exc; AhcNode *site; AhcNode *value; } reports[REPORT_SLOTS];
static unsigned report_next;
static pthread_mutex_t report_mu = PTHREAD_MUTEX_INITIALIZER;
/* Called by p_fail_match / p_error_at AFTER the exception node exists;
   the slots are GC roots (register with both collectors the way the
   global root list is registered - grep "ahc_add_root"). */
static void report_note(AhcNode *exc, AhcNode *site, AhcNode *value);
static int report_find(AhcNode *exc, AhcNode **site, AhcNode **value);
```

- [ ] **Step 2:** add the renderer. `render_value(buf, cap, node,
  schema, depth)` follows `AHC_IND`. It treats `AHC_THUNK`,
  `AHC_BLACKHOLE` and `AHC_FUN` as `_`; INT/DOUBLE/CHAR/BIGINT through
  the existing GHC-exact show helpers (grep `show_double`); and
  `AHC_CON` through the schema: its name by `contag`, then its fields
  parenthesized when nested. Output is capped at 60 bytes, ending
  `...`. **It must never call `ahc_eval`.** Assert that in a comment
  and review it.
- [ ] **Step 3:** add the printer. `exc_uncaught` calls
  `report_find`; on a hit it prints the format below, and otherwise
  keeps today's output:

```
ahc: runtime error: <headline>
  --> <file>:<line>:<col>
   |
 L | <snippet line>
   | ^^^^ <detail>
   = note: `<in>` handles <handled>      (pattern sites with handled)
   = in: <in>
```

  `<detail>` is ``no equation matches `<rendered value>` `` for a
  pattern site and `called here` for a located function. The `^`
  count is the span's column width on its first line.
- [ ] **Step 4:** commit with D3.

### Task D3: exec goldens

**Files:**
- Create: one exec test per kind:
  - `tests/exec/m149_report_function.hs`, `m149_report_case.hs`,
    `m149_report_head.hs`, `m149_report_index.hs`,
    `m149_report_error.hs`, `m149_report_fromjust.hs`,
    `m149_report_nested.hs` (a value with a nested constructor and a
    string field);
  - `m149_report_noforce.hs`: the failing value holds `undefined`, an
    infinite list and an unevaluated field. The report shows `_` and
    the test exits 1.
- Modify: the existing exec goldens whose stderr text changes.

- [ ] **Step 1:** write the tests. Each prints one stdout line and then
  fails uncaught.
- [ ] **Step 2:** `./scripts/run_exec.sh --update`, then read every
  changed golden. The new report must be the format above, with the
  right line and column. For the no-force test, run the binary 20
  times; it must exit 1 each time with no hang.
- [ ] **Step 3:** verify:
  - `./scripts/run_exec.sh` and `AHC_GC=own ./scripts/run_exec.sh`
    have rc 0;
  - `./scripts/run_tsan.sh` has rc 0, since the side table takes a
    lock;
  - `AHC_OWN_VERIFY=1 ./scripts/run_own_soak.sh` has rc 0;
  - `./scripts/run_export.sh` has rc 0 (`ahc_last_error` unchanged).
- [ ] **Step 4:** commit:
  `feat(runtime): an uncaught error prints a report - where, the snippet, the failing value and what the code handles`.

**Gate (Phase D):**
- exec in both GC modes, TSan, the own soak with
  `AHC_OWN_VERIFY=1`, `run_export.sh`, `run_examples.sh`;
- the full `run_gate.sh`.

---

## Phase E - the opt-in trail

### Task E1: `ahc build --trail`

**Files:**
- Modify:
  - `src/ahc_main.adb`: parse `--trail` next to `--no-opt` at lines
    ~1628 and ~1750, and pass it to codegen;
  - `src/ahc-codegen.ads/.adb`: a `Trail : Boolean` option; when set,
    emit `AHC_TRAIL("<name>");` as the first statement of each emitted
    function body;
  - `runtime/ahc_rts.h`:
    `#define AHC_TRAIL(n) ahc_trail_push(n)`;
  - `runtime/ahc_rts.c`: a `__thread const char *trail[16]` ring, and
    the printer's `= most recent evaluations (newest first): ...`
    line. The `<<loop>>` and stack-overflow messages also print it,
    when the ring is non-empty (deviation 7);
  - `src/ahc-build.adb`: make sure `--trail` reaches the cache key, so
    a trail build never reuses a non-trail object.

- [ ] **Step 1:** implement. With the flag off, no `AHC_TRAIL` appears
  in the generated C.
- [ ] **Step 2:** tests:
  - `tests/exec/m149_trail.hs`, with `.env` or a build flag: check how
    `run_exec.sh` takes per-test build flags (`tests/exec/*.env` is
    for runtime env vars). If there is no per-test build flag, add a
    `tests/exec/<name>.flags` file read by `run_exec.sh`;
  - a `run_build.sh` step: build `tests/exec/hello.hs` without
    `--trail` and `grep -c AHC_TRAIL` the generated C → 0.
- [ ] **Step 3:** bench:
  - `scratchpad/ab_bench.sh` (OLD = v1.19.1 worktree) without
    `--trail` stays within 2%;
  - record the `--trail` overhead on `b_fib` and `b_map` for the
    write-up.
- [ ] **Step 4:** commit:
  `feat(codegen): ahc build --trail records the most recent evaluations for the error report`.

**Gate (Phase E):**
- exec in both GC modes, `run_build.sh`, `run_install.sh`;
- the bench delta recorded.

---

## Phase F - milestone gate, review, write-up

### Task F1: the multi-module path alignment

- [ ] **Step 1:** `run_conformance.sh` multi-module cases run GHC from
  inside the case directory, so GHC prints `Mod.hs:L:C`. Build AHC the
  same way:
  `(cd "$dir" && "$root/scripts/ahc-build.sh" Main.hs "$tmp/mm_$base")`.
  Verify `ahc-build.sh` works from another cwd. If it does not, make
  it resolve `bin/ahc` relative to its own location.
- [ ] **Step 2:** add `tests/conformance/multi/m149_located_cross/`.
  `Main.hs` imports `Lib.hs`. Lib fails with `head []` and `error`;
  Main catches and shows. Oracle it.
- [ ] **Step 3:** verify `./scripts/run_conformance.sh` → all ok.
- [ ] **Step 4:** commit:
  `test(conformance): multi-module cases build from their own directory, as the oracle runs`.

### Task F2: the milestone gate

- [ ] Run the following:
  - the release build;
  - goldens on both builds;
  - `run_gate.sh` on both builds;
  - `AHC_GC=own run_conformance.sh`;
  - both differentials;
  - userlib, separate, repl, examples, export, bindgen, discharge,
    build, install, stack, TSan;
  - `AHC_OWN_VERIFY=1 run_own_soak.sh`;
  - `run_fuzz_par.sh 300 6 <seed>`;
  - the bench against v1.19.1;
  - ubuntu CI green after the push.

### Task F3: adversarial review (the adversarial-review skill)

Dimensions:
1. **Rendering safety:** any path where the renderer forces, loops or
   reads past a field.
2. **Side table:** concurrency, GC rooting, and a rethrown or wrapped
   exception.
3. **Conformance texts:** spans with tabs and Unicode columns, operator
   sections, `where`-bound functions, instance methods, local
   functions (whose name GHC uses).
4. **Located rewrite:** shadowing, qualified use, re-exports, REPL.
5. **Claims audit.**

Land the fixes as `fix: N defects an adversarial review of m149 found`.

### Task F4: write-up and release

- [ ] Update:
  - CHANGES v1.20, recording the four spec deviations and the C2/C3
    decisions;
  - the manual: a "runtime errors" section, covering the site format,
    the report and `--trail`;
  - EXCLUSIONS: deviation 4, and that the `Integral` methods are not
    located;
  - the README;
  - a memory note for the area.
- [ ] The release (`release: v1.20 - ...`) needs the user's approval.

**Gate (Phase F):** everything in F2, green after the review's fixes,
plus ubuntu CI green.
