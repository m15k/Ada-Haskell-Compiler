# M147 GHC extensions - Implementation Plan

**Goal:** `LambdaCase`, `FlexibleInstances`, `TypeSynonymInstances` and
`GeneralizedNewtypeDeriving` work as in GHC 9.4.8, always on.

**Architecture:** `\case` is desugared in the parser to `\lc$ -> case lc$ of`.
`lc$` is a name no source program can spell, so no new AST kind and no
downstream pass changes are needed.

Instances keep their full head type (`Instance_Info.Head_Type`). One generic
one-way matcher in a new package, `AHC.Inst_Match`, serves the typechecker's
`Solve`, elaborate's `Solve_Ev` and the duplicate check.

Newtypes are erased in **codegen**, not desugar. A newtype constructor is the
identity and a case on it binds without forcing. That covers every Core producer
at once: desugared patterns, prelude_core's derived `Show`/`Read`, and selectors.
GND instances reuse their representation's dictionary, resolved in a typechecker
pre-pass and bound by elaborate.

Spec: `docs/specs/2026-10-09-m147-ghc-extensions.md`.

## Global constraints

- **Oracle:** GHC 9.4.8 (`~/.ghcup/bin/runghc`). Conformance is stdout
  byte-identical (`scripts/run_conformance.sh` takes no names; to run one
  program, build it with `scripts/ahc-build.sh tests/conformance/X.hs OUT` and
  diff against `X.out`). Exec tests compare `2>&1` and pin AHC's `ahc:` banner
  (EXCLUSIONS row 9).
- **No pragma gating.** Test programs carry GHC's `LANGUAGE` pragmas, so the
  oracle accepts them; AHC ignores them.
- **Gate inputs:** `prelude/`, `lib/` and `runtime/ahc_rts.c` are gate inputs.
  Never edit them, or rebuild `bin/ahc`, while a suite runs.
- **Gate command:** `./scripts/run_gate.sh`, in the background with a 2-hour
  limit, alone on the machine.
- **Goldens:** a new Prelude binding or wired entity renumbers the Core goldens.
  Check binding-name sets with
  `names() { grep -o '^(bind[a-z]* (\$\?[^ ]*' "$1" | sed 's/^(bind[a-z]* (//; s/_[0-9]*$//' | sort -u; }`,
  and strip `_[0-9]+` to see the content diff. Run goldens on BOTH the
  validation and release builds before a phase is done (memory:
  ada-actual-evaluation-order). Never pass two id-minting calls as actuals of
  one call.
- **Identity, not names:** instances, dictionaries and TyCons are found by id,
  never by name or span (memory: ahc-namespaces).
- **Commits:** conventional prefix, lowercase prose subject, trailer
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## File map

| File | Change |
|---|---|
| `src/ahc-parser.adb` | `\case` branch in `Parse_LExp`; `LC_Name` constant |
| `src/ahc-layout.adb` | open a layout block after `case` when preceded by `\` |
| `src/ahc-core.ads` | `Instance_Info.Head_Type`, `Is_GND`, `GND_Target` |
| `src/ahc-inst_match.ads/.adb` (new) | `Match_Result`, generic `Match_Head`, `Instance_Type`, `Heads_Equal` |
| `src/ahc-rename.adb` | synonym and type-variable instance heads; dictionary naming; newtype deriving marks GND |
| `src/ahc-kinds.adb` | `Do_Instance` stores `Head_Type`/`Head`, checks duplicates |
| `src/ahc-typechecker.adb` | `Solve` by matching; instance-type rebuilds; `Resolve_GND` pre-pass; GND superclass check |
| `src/ahc-elaborate.adb` | `Solve_Ev` by matching; instance-type rebuilds; GND dictionary bodies |
| `src/ahc-prelude_core.adb` | skip GND instances in the wired/derived loop |
| `src/ahc-codegen.adb` | newtype erasure in `Con_C`, `App_C` and `Case_C` |
| `src/ahc-builtins.adb` | `Mint_Instance` aggregate gains the new fields |
| `tests/conformance/` | `ext_lambda_case`, `ext_flexible_instances`, `ext_gnd`, `ch04_02_newtype_seq` |
| `tests/corpus-types/` | `bad_overlap_use`, `bad_duplicate_flexible`, `bad_gnd_no_instance`, `bad_gnd_eta` |
| `tests/src/` | unit tests for `Inst_Match` |
| docs | CHANGES, MANUAL, repos-to-try Extensions bullet |

---

## Phase A - LambdaCase

### Task A1: parse `\case`

**Files:** `src/ahc-parser.adb` (constants near line 25; `Parse_LExp` `Backslash`
branch near 870), `src/ahc-layout.adb` (near 197).

- [ ] **Step 1: The test first.** Write `tests/conformance/ext_lambda_case.hs`
  and oracle it with
  `cd tests/conformance && ~/.ghcup/bin/runghc ext_lambda_case.hs > ext_lambda_case.out`.

  ```haskell
  {-# LANGUAGE LambdaCase #-}
  -- \case, always on in AHC (M147), oracled against GHC 9.4.8.
  classify :: Int -> String
  classify = \case
    0 -> "zero"
    n | n < 0 -> "negative"
      | even n -> "even"
    _ -> "odd"

  firstJust :: [Maybe a] -> Maybe a
  firstJust = foldr (\case { Just x -> const (Just x); Nothing -> id }) Nothing

  depth :: [Either Int String] -> [Int]
  depth = map $ \case
    Left n -> n * 2
    Right s -> length s
    where _unused = ()

  nested :: Maybe (Maybe Int) -> Int
  nested = \case
    Just inner -> (\case Just v -> v; Nothing -> -1) inner
    Nothing -> -2

  main :: IO ()
  main = do
    mapM_ (putStrLn . classify) [0, -3, 4, 7]
    print (firstJust [Nothing, Just 'a', Just 'b'], firstJust ([] :: [Maybe Int]))
    print (depth [Left 3, Right "four"], map nested [Just (Just 5), Just Nothing, Nothing])
    r <- (\case { [] -> return 0; xs -> return (sum xs) }) [1, 2, 3 :: Int]
    print r
  ```

- [ ] **Step 2: Layout.** In `src/ahc-layout.adb`, replace the
  `when Kw_Let | Kw_Where | Kw_Do | Kw_Of =>` arm with:

  ```ada
                  when Kw_Let | Kw_Where | Kw_Do | Kw_Of | Kw_Case =>
                     Enqueue (S, T);
                     --  `case` opens a block only as `\case`
                     --  (LambdaCase, M147); a plain `case e of`
                     --  opens its block at `of`.
                     if T.Kind /= Kw_Case
                       or else (S.I > S.Input.First_Index
                                and then S.Input (S.I - 1).Kind = Backslash)
                     then
                        --  Input always ends with End_Of_File, so I+1
                        --  is safe: {n} unless an explicit brace
                        --  follows.
                        S.Await_Open :=
                          S.Input (S.I + 1).Kind /= Left_Brace;
                     end if;
  ```

  Check that `S.Input` is indexed from `First_Index` (read the declaration). If
  `S.Input (S.I - 1)` is the previous *raw* token, comments and pragmas are not
  in it, because the lexer drops them.
- [ ] **Step 3: Parser.** Next to `Colon_Name` add:

  ```ada
      --  The binder of `\case` (LambdaCase, M147): `\case alts` parses
      --  as `\lc$ -> case lc$ of alts`. No source program can spell
      --  `lc$`, so it can neither capture nor be captured; an inner
      --  `\case` shadows an outer one harmlessly, since nothing but
      --  the generated scrutinee ever names it.
      LC_Name : constant Names.Real_Name_Id := Table.Intern ("lc$");
  ```

  In `Parse_LExp`'s `when Backslash =>`, right after `Advance;`:

  ```ada
               if Tok.Kind = Kw_Case then
                  Advance;
                  declare
                     Alts : Alt_Id_Vectors.Vector;
                     Pats : Pat_Id_Vectors.Vector;
                     Scrut : Real_Expr_Id;
                  begin
                     Parse_Alt_Block (Alts);
                     if Alts.Is_Empty then
                        Fail ("empty \case block");
                     end if;
                     Pats.Append (Arena.Add
                       (Pat_Node'(Kind => Var_P, Span => Span,
                                  Var => Names.Name_Id (LC_Name))));
                     Scrut := Arena.Add
                       (Expr_Node'(Kind => Var_E, Span => Span,
                                   Name => (Name => Names.Name_Id (LC_Name),
                                            Qualifier => Names.No_Name)));
                     return Arena.Add
                       (Expr_Node'(Kind => Lambda_E, Span => Span,
                                   L_Pats => Pats,
                                   L_Body => Arena.Add
                                     (Expr_Node'(Kind => Case_E,
                                                 Span => Span,
                                                 Scrutinee => Scrut,
                                                 Alts => Alts))));
                  end;
               end if;
  ```

  Check how `Var_P` and `Var_E` nodes are built at parser.adb:550 and :815,
  and copy their exact field spelling. `Parse_Alt_Block` must accept a layout
  block opened by the layout pass, which it does for `of`.
- [ ] **Step 4: Verify.**
  - `alr build --validation`
  - Build `ext_lambda_case` with `scripts/ahc-build.sh` and diff it against the
    `.out`.
  - A negative check: `\case` with no alternatives is a parse error, and
    `f = \ x -> case x of ...` is unchanged.
- [ ] **Step 5: Goldens and commit.** `feat(parser): lambdacase - \case is \lc$ -> case lc$ of its alternatives`.

**Gate:** `./scripts/run_gate.sh` → `GATE ok` + `run_differential.sh` (the
parse corpus) + `run_repl.sh`.

---

## Phase B - instance heads by full type

### Task B1: `Head_Type` and the matcher

**Files:** `src/ahc-core.ads:289-308`, new `src/ahc-inst_match.ads/.adb`,
`src/ahc-builtins.adb:217`, `src/ahc-rename.adb:1695,1934` (the aggregates),
`tests/src/` (unit tests).

**Interfaces produced:**

```ada
--  ahc-core.ads, Instance_Info, new components (with defaults):
      --  The full instance head type, synonyms expanded, over
      --  Head_Vars (M147, FlexibleInstances). No_Type for wired and
      --  stock-derived instances, whose head is Head applied to
      --  Head_Vars; Instance_Type below builds it.
      Head_Type   : Type_Id := No_Type;
      --  GeneralizedNewtypeDeriving (M147): the dictionary is the
      --  representation's (GND_Target's) dictionary.
      Is_GND      : Boolean := False;
      GND_Target  : Type_Id := No_Type;
```

```ada
--  src/ahc-inst_match.ads
with AHC.Core;
with AHC.Builtins;
package AHC.Inst_Match is
   use AHC.Core;

   --  One-way matching of an instance head against a wanted type
   --  (M147). Matched: the head's variables bind and nothing else is
   --  needed. No_Match: no instantiation of the head equals the
   --  type. Undecided: a metavariable in the type sits where the head
   --  needs structure, so the answer waits for unification.
   type Match_Result is (Matched, No_Match, Undecided);

   --  Norm follows solved metavariables and expands the wired Rational
   --  placeholder; the typechecker passes Repr-plus-expansion,
   --  elaborate passes expansion alone (its types are zonked). Args
   --  receives the binding of each of Vars, in order (No_Type for an
   --  unbound one, which a well-formed head never leaves).
   generic
      with function Norm (T : Real_Type_Id) return Real_Type_Id;
   function Match_Head
     (M      : Core_Module;
      Env    : Builtins.Global_Env;
      Pat    : Real_Type_Id;
      Vars   : TyVar_Id_Vectors.Vector;
      Target : Real_Type_Id;
      Args   : out Type_Id_Vectors.Vector) return Match_Result;

   --  The head type of an instance: Head_Type, or Head applied to
   --  Head_Vars for a wired/derived one.
   function Instance_Type
     (M : in out Core_Module; Env : Builtins.Global_Env;
      I : Instance_Info) return Real_Type_Id;

   --  Equal up to a consistent renaming of type variables: a
   --  duplicate instance.
   function Heads_Equal
     (M : Core_Module; A, B : Real_Type_Id) return Boolean;
end AHC.Inst_Match;
```

- [ ] **Step 1: The body.** Write `src/ahc-inst_match.adb`.

  ```ada
  with Ada.Containers.Hashed_Maps;
  package body AHC.Inst_Match is

     function Hash (T : Real_TyVar_Id) return Ada.Containers.Hash_Type
     is (Ada.Containers.Hash_Type (T));
     package Bind_Maps is new Ada.Containers.Hashed_Maps
       (Real_TyVar_Id, Real_Type_Id, Hash, "=");

     function Combine (A, B : Match_Result) return Match_Result
     is (if A = No_Match or else B = No_Match then No_Match
         elsif A = Undecided or else B = Undecided then Undecided
         else Matched);

     function Match_Head
       (M      : Core_Module;
        Env    : Builtins.Global_Env;
        Pat    : Real_Type_Id;
        Vars   : TyVar_Id_Vectors.Vector;
        Target : Real_Type_Id;
        Args   : out Type_Id_Vectors.Vector) return Match_Result
     is
        B : Bind_Maps.Map;

        --  Structural equality for a repeated head variable
        --  (`instance C (Either a a)`).
        function Same (X, Y : Real_Type_Id) return Match_Result is
           NX : constant Type_Node := M.Node (Norm (X));
           NY : constant Type_Node := M.Node (Norm (Y));
        begin
           if NX.Kind = TMeta_T or else NY.Kind = TMeta_T then
              return (if NX = NY then Matched else Undecided);
           elsif NX.Kind /= NY.Kind then
              return No_Match;
           end if;
           case NX.Kind is
              when TVar_T => return (if NX.Tv = NY.Tv then Matched else No_Match);
              when TCon_T => return (if NX.Con = NY.Con then Matched else No_Match);
              when TApp_T =>
                 return Combine (Same (NX.T_Fun, NY.T_Fun), Same (NX.T_Arg, NY.T_Arg));
              when TFun_T =>
                 return Combine (Same (NX.From, NY.From), Same (NX.To, NY.To));
              when TMeta_T => return Undecided;
           end case;
        end Same;

        function Go (P, T0 : Real_Type_Id) return Match_Result is
           PN : constant Type_Node := M.Node (P);
           T  : constant Real_Type_Id := Norm (T0);
           TN : constant Type_Node := M.Node (T);
        begin
           if PN.Kind = TVar_T then
              if B.Contains (PN.Tv) then
                 return Same (B.Element (PN.Tv), T);
              end if;
              B.Include (PN.Tv, T);
              return Matched;
           elsif TN.Kind = TMeta_T then
              return Undecided;
           end if;
           case PN.Kind is
              when TCon_T =>
                 return (if TN.Kind = TCon_T and then TN.Con = PN.Con
                         then Matched else No_Match);
              when TApp_T =>
                 if TN.Kind = TApp_T then
                    declare
                       R1 : constant Match_Result := Go (PN.T_Fun, TN.T_Fun);
                    begin
                       return Combine (R1, Go (PN.T_Arg, TN.T_Arg));
                    end;
                 elsif TN.Kind = TFun_T then
                    --  (->) a b as an application spine (M142).
                    declare
                       PF : constant Type_Node := M.Node (PN.T_Fun);
                    begin
                       if PF.Kind = TApp_T then
                          declare
                             R1 : constant Match_Result := Go (PF.T_Fun, Arrow_Con);
                             R2 : constant Match_Result := Go (PF.T_Arg, TN.From);
                          begin
                             return Combine (Combine (R1, R2), Go (PN.T_Arg, TN.To));
                          end;
                       end if;
                       return No_Match;
                    end;
                 end if;
                 return No_Match;
              when TFun_T =>
                 if TN.Kind = TFun_T then
                    declare
                       R1 : constant Match_Result := Go (PN.From, TN.From);
                    begin
                       return Combine (R1, Go (PN.To, TN.To));
                    end;
                 end if;
                 return No_Match;
              when TVar_T | TMeta_T =>
                 return No_Match;   --  TVar handled above; heads hold no metas
           end case;
        end Go;
     begin
        ...
     end Match_Head;
  ```

  `Arrow_Con` is the `TCon_T` node for `Env.Arrow_TC`. `M` is read-only here,
  so the pattern side passes `TApp (TApp (Arrow, a), b)` only if the head was
  written as `(->) a b`; a head written `a -> b` is a `TFun_T` and takes the
  `TFun_T` arm. Find the existing `TCon` node for `Arrow_TC` (the typechecker's
  `Arrow_Spine` builds one); if `M` must be `in out` to add it, make the
  generic take `M : in out Core_Module`.

  The body of `Match_Head` resets `B`, calls `Go (Pat, Target)`, then fills
  `Args` from `B` in `Vars` order (`No_Type` when unbound) and returns the
  result. Each `declare` binds `R1` before computing the second operand: two
  `Go` calls must never be actuals of one call. They mutate `B`, and Ada leaves
  the order of actuals unspecified (memory: ada-actual-evaluation-order).

  `Instance_Type` returns `I.Head_Type` when it is not `No_Type`. Otherwise it
  folds `Builtins.Make_App` over a `TCon Head` node and a `TVar` node per head
  variable, which is exactly what typechecker.adb:1789-1798 does today.

  `Heads_Equal` walks both types in parallel, keeping a map from A's type
  variables to B's that must be a bijection.
- [ ] **Step 2: Add the new components to the three aggregates**
  (builtins.adb:217, rename.adb:1695, rename.adb:1934):
  `Head_Type => Core.No_Type, Is_GND => False, GND_Target => Core.No_Type`.
- [ ] **Step 3: Unit tests.** Add a test procedure in `tests/src/` following
  the existing typechecker tests' pattern (find one with
  `grep -l Typechecker tests/src/*.adb`). Over a scratch `Core_Module` it
  checks that:
  - `[a]` matches `[Int]` → `Matched` with `a := Int`;
  - `[Char]` against `[Int]` → `No_Match`;
  - `[Char]` against `[?m]` → `Undecided`;
  - `Either a a` against `Either Int Int` → `Matched`, against
    `Either Int Bool` → `No_Match`;
  - a bare `a` matches anything;
  - `(->) r` against `Int -> Bool` (as the partial spine) → `Matched`
    `r := Int`.

  Register it in the test runner.
- [ ] **Step 4: Verify.** `cd tests && alr build --validation && ./bin/ahc_tests` passes. The compiler builds.
- [ ] **Step 5: Commit.** `feat(core): an instance keeps its full head type, and one matcher decides instance selection`.

### Task B2: heads with synonyms, concrete arguments and bare variables

**Files:** `src/ahc-rename.adb:1852-1945` (`Instance_Head`,
`Declare_Instance`), `src/ahc-kinds.adb:1150-1188` (`Do_Instance`).

- [ ] **Step 1: Test first.** Write `tests/conformance/ext_flexible_instances.hs`
  and oracle it.

  ```haskell
  {-# LANGUAGE FlexibleInstances, TypeSynonymInstances #-}
  -- FlexibleInstances/TypeSynonymInstances, always on in AHC (M147).
  class Pretty a where
    pretty :: a -> String

  instance Pretty String where
    pretty s = "str:" ++ s
  instance Pretty (Maybe Int) where
    pretty m = "maybe-int:" ++ show m
  instance Pretty (Maybe Bool) where
    pretty m = "maybe-bool:" ++ show m
  instance Pretty (Either String Int) where
    pretty = either ("left:" ++) (("right:" ++) . show)
  instance Show a => Pretty [Maybe a] where
    pretty xs = "maybes:" ++ show xs

  class Describe a where
    describe :: a -> String
  instance Describe [Char] where
    describe _ = "a string"
  instance Describe [a] where
    describe xs = "a list of " ++ show (length xs)

  class Shout a where
    shout :: a -> String
  instance Shout a where
    shout _ = "!"

  type Name = String
  greet :: Pretty Name => Name -> String
  greet n = pretty n

  main :: IO ()
  main = do
    putStrLn (pretty "hi")
    putStrLn (pretty (Just (3 :: Int)))
    putStrLn (pretty (Just True))
    putStrLn (pretty (Left "e" :: Either String Int))
    putStrLn (pretty (Right 7 :: Either String Int))
    putStrLn (pretty [Just 'x', Nothing])
    putStrLn (describe [True, False])
    putStrLn (shout (1 :: Int) ++ shout "s")
    putStrLn (greet "ada")
  ```

  `describe "x"` is deliberately absent, because it is GHC's overlap error (the
  corpus-types reject below).
- [ ] **Step 2: Renamer.** Change `Instance_Head`'s `Con_T` arm. When
  `Mod_Find_TyCon` finds nothing and the name is not ambiguous, try
  `Mod_Find_Syn` (read its signature near `Mod_Find_TyCon`). If a synonym is
  found, return `Core.No_TyCon` and set a new `out` parameter
  `Deferred := True`; Kinds sets the real head. Do the same for `Var_T`, the
  bare-variable head. Keep the "type not in scope" error for a name that is
  neither.

  In `Declare_Instance`:
  - Continue when `Deferred` (with `Head = No_TyCon`).
  - Drop the duplicate loop (rename.adb:1916-1920); Kinds does it with full
    types.
  - Name the dictionary `"$d" & Class & <TyCon or synonym name, or "Var">`,
    plus a numeric suffix `"$" & Img (count)` when an earlier instance of the
    same class has the same TyCon. The name is cosmetic, since identity is the
    `Instance_Id`.
- [ ] **Step 3: Kinds.** In `Do_Instance`, after `Convert`, keep `R`:

  ```ada
            declare
               I : constant Core.Instance_Id :=
                 Res.Decl_Inst.Element (Positive (D));
            begin
               if Core."/=" (I, 0) then
                  declare
                     II : constant Core.Real_Instance_Id :=
                       Core.Real_Instance_Id (I);
                  begin
                     M.Instances (II).Head_Vars := Order;
                     M.Instances (II).Context := Ctx;
                     M.Instances (II).Head_Type := R;
                     M.Instances (II).Head := Head_TyCon_Of (R);
                     --  Duplicate: an earlier instance of this class
                     --  with an equal head (up to renaming). Overlap
                     --  alone is legal, as in GHC.
                     for J of M.Info (Core.Real_Class_Id (Cl_Id)).Instances loop
                        exit when J = II;
                        if Inst_Match.Heads_Equal
                             (M, Core.Real_Type_Id (R),
                              Inst_Match.Instance_Type (M, Env, M.Info (J)))
                        then
                           Bag.Add (Diagnostics.Error,
                                    Diagnostics.Class_Duplicate_Instance,
                                    N.Span, "duplicate instance");
                        end if;
                     end loop;
                  end;
               end if;
            end;
  ```

  `Head_TyCon_Of` is a local function: the TyCon at the spine head of `R`
  (`TFun_T` → `Env.Arrow_TC`), or `No_TyCon` for a type variable. Check that
  `Convert` expands synonyms in `R`. It does for ordinary types (M75's
  `Syn_At`), so `String` arrives as `[Char]`. Confirm that `R`'s variables are
  exactly `Order`'s.
- [ ] **Step 4: Readers of `Head`.** `grep -n '\.Head\b' src/*.adb`. Every
  reader that can see a source instance must accept `Head = No_TyCon` (a bare
  variable head). The typechecker's superclass-check guard (typechecker.adb:1775
  `and then Inst.Head /= No_TyCon`) becomes
  `and then (Inst.Head /= No_TyCon or else Inst.Head_Type /= No_Type)`. The
  prelude_core readers see only wired and derived instances. List each reader
  and its verdict in the commit body.

### Task B3: resolution by matching

**Files:** `src/ahc-typechecker.adb` (`Solve` 681-783; rebuilds 1789-1798,
1863-1874), `src/ahc-elaborate.adb` (`Solve_Ev` 166-287; rebuilds near 353
and 721).

- [ ] **Step 1: Typechecker `Solve`.** Instantiate the matcher once, in the
  typechecker's declarative part:

  ```ada
      function Norm_TC (T : Real_Type_Id) return Real_Type_Id;
      --  Repr, then the wired Rational placeholder expanded to its
      --  Data.Ratio synonym (the expansion Head_Of does today).
      function Match_TC is new Inst_Match.Match_Head (Norm_TC);
  ```

  `Norm_TC` returns `Repr (T)`, except that a `TCon_T` of `Env.Rational_TC`
  with a cached `Core_Rhs` returns that. Move the code from `Head_Of`
  (typechecker.adb:650-670) into it.

  Replace the body from `Head_Of (W.C.Arg, Head, Args);` through the instance
  loop with:

  ```ada
            declare
               Hits : Natural := 0;
               Hit  : Instance_Id := No_Instance;
               Hit_Args : Type_Id_Vectors.Vector;
               Pending : Boolean := False;
            begin
               for Inst_Id of M.Info (W.C.Class).Instances loop
                  declare
                     Inst : constant Instance_Info := M.Info (Inst_Id);
                     A : Type_Id_Vectors.Vector;
                     R : constant Inst_Match.Match_Result :=
                       Match_TC (M, Env,
                                 Inst_Match.Instance_Type (M, Env, Inst),
                                 Inst.Head_Vars, W.C.Arg, A);
                  begin
                     case R is
                        when Inst_Match.Matched =>
                           if List_Element_Is_Char (Inst) then
                              Hits := Hits + 1;
                              Hit := Instance_Id (Inst_Id);
                              Hit_Args := A;
                           end if;
                        when Inst_Match.Undecided =>
                           Pending := True;
                        when Inst_Match.No_Match =>
                           null;
                     end case;
                  end;
               end loop;
               if Pending and then Hits <= 1 then
                  return;   --  residual: wait for unification
               elsif Hits > 1 then
                  --  "overlapping instances for C T"; list the heads.
                  ...report with Class_Overlap (new diagnostic code), W.Sol := By_Error...
               elsif Hits = 1 then
                  ...the existing context instantiation, with
                  Map.Include (Inst.Head_Vars (VI), Hit_Args (VI))
                  for every VI...
               end if;
            end;
  ```

  Keep the IsString special case `List_Element_Is_Char`, now taking the
  instance (it tests `Class = IsString_Cl and Inst.Head = List_TC`). It still
  unifies a metavariable element with `Char`, which is how `"x"` at `[?a]`
  resolves. The "no instance" path is unchanged, and a type-variable head
  (residual) still returns before it.

  Add `Class_Overlap` to `Diagnostics` (ahc-diagnostics.ads) next to
  `Class_No_Instance`. The message is
  `overlapping instances for '<Class> <type>': <head 1>, <head 2>`, using the
  existing type printer the no-instance message uses.

  One subtlety: `Undecided` from an instance that can never match once
  resolved costs nothing, because the constraint is retried when its
  metavariable is solved and the typechecker's final pass reports it. Check
  how an unsolved residual is finally reported (search for where `Unsolved`
  wanteds become "ambiguous" errors). An `Undecided` with no possible match
  must not become silent.
- [ ] **Step 2: Rebuild sites.** typechecker.adb:1789-1798 and 1863-1874, and
  elaborate.adb near 353 (superclass slots) and 721 (Monad `return` default),
  each become `Head_T := Inst_Match.Instance_Type (M, Env, Inst);`. At 721 the
  `Has_App` loop matches with `Inst_Match.Heads_Equal` or a `Match_Head` of
  each Applicative instance against `H`, instead of comparing `Head`.
- [ ] **Step 3: Elaborate `Solve_Ev`.** Instantiate `Match_EL` with a
  `Norm_EL` that only expands Rational (types are zonked). Replace the
  `Head_Of`/`Inst.Head = Head` loop with a `Match_EL` loop that takes the single
  `Matched` instance. `Args` comes from the match, in `Head_Vars` order, so
  `Subst_Head (IC.Arg, Inst.Head_Vars, Args)` stays as it is. Delete the local
  `Head_Of`.
- [ ] **Step 4: Rejects.** Add to `tests/corpus-types/`, with the expected
  message checked the way the existing `bad_*` files are (read
  `scripts/run_differential_types.sh` for the convention):
  - `bad_overlap_use.hs`: `C [Char]` plus `C [a]`, used at `"x"` →
    overlapping instances.
  - `bad_duplicate_flexible.hs`: two `instance C (Maybe Int)` → duplicate
    instance.
- [ ] **Step 5: Verify.**
  - `ext_flexible_instances` matches GHC.
  - Both rejects fail with the right message.
  - Every existing conformance and exec program passes. Those with
    `IsString`/OverloadedStrings are the sensitive ones:
    `grep -l OverloadedStrings tests/conformance/*.hs`.
- [ ] **Step 6: Goldens and commit.** The goldens should be renumber-only,
  apart from dictionary names gaining no suffix in practice.
  Commit: `feat(types): flexible and type-synonym instance heads, selected by one-way matching with ghc's overlap rule`.

**Gate:** full gate in both GC modes, both differential suites, `run_userlib`,
`run_separate`, `run_repl`, goldens on both builds, and fuzz 100.

---

## Phase C - newtype erasure

### Task C1: erase in codegen

**Files:** `src/ahc-codegen.adb` (`Con_C` near 612, `App_C` peephole near
634, `Case_C` near 812), `runtime/ahc_rts.c`/`.h` (an identity function
global).

- [ ] **Step 1: Test first.** Write `tests/conformance/ch04_02_newtype_seq.hs`
  and oracle it.

  ```haskell
  -- Report 4.2.3: a newtype adds no run-time box (M147).
  import Control.Exception

  newtype N = N Int deriving (Show, Eq, Ord)
  newtype R = R { unR :: [Int] } deriving (Show, Read)
  data D = D N String deriving (Show, Eq)

  probe :: a -> IO ()
  probe x = do
    r <- try (evaluate x)
    putStrLn (either (\e -> "bottom: " ++ takeWhile (/= '\n') (show (e :: ErrorCall))) (const "value") r)

  main :: IO ()
  main = do
    probe (N undefined `seq` ())
    probe (case (undefined :: N) of N _ -> ())
    probe (let N _ = undefined in ())
    print (N 3, unR (R [1, 2]), (R [3]) { unR = [4] }, read "R {unR = [5]}" :: R)
    print (D (N 1) "a" == D (N 1) "a", compare (N 2) (N 3), map unR [R [], R [0]])
    print (showsPrec 11 (N (-4)) "", show (Just (N 7)))
  ```

  Check the oracle's first line: `bottom: Prelude.undefined`.
- [ ] **Step 2: Runtime identity.** Add `ahc_prim_newtype_id = mk_prim1(p_newtype_id)`,
  with `static AhcNode *p_newtype_id(AhcNode *a) { return a; }`. It returns
  the argument **unevaluated**. Declare it in `ahc_rts.h`, next to
  `ahc_prim_seq`.
- [ ] **Step 3: Codegen.** Add a local function:

  ```ada
      --  Newtype erasure (M147, Report 4.2.3): a newtype's constructor
      --  is the identity and a case on it binds its field to the
      --  scrutinee without forcing. Every Core producer - desugared
      --  patterns, derived Show/Read, record selectors and updates -
      --  emits ordinary constructor cases, so erasing here erases
      --  them all.
      function Is_NT_Con (DC : Real_DataCon_Id) return Boolean is
        (M.Info (Real_TyCon_Id (M.Info (DC).TyCon)).Is_Newtype);
  ```

  - **`Con_C`:** `if Is_NT_Con (N.Con) then return "ahc_prim_newtype_id"; end if;`
  - **`App_C`:** where the function is a `Con_C` of a newtype constructor,
    return the argument's generated code: `Gen_Lazy (N.Arg, Scope)` in a lazy
    context, and `Gen_Force` in a forcing one. Read both generator functions
    and mirror how each treats `App_C`.
  - **`Case_C`:** if the first `Con_Alt` is a newtype constructor, emit
    `({ AhcNode *<binder> = <Gen_Lazy scrutinee>; r = <Gen_Force body>; r; })`
    with no `ahc_eval` of the scrutinee. If the binder list is empty (a
    wildcard field), evaluate nothing. Ignore a `Default_Alt`, since it is
    unreachable. Make the same change in `Free_Vars` only if its shape
    differs; it doesn't, because binders are still bound.
- [ ] **Step 4: Audit.** Grep the codebase for other places that inspect a
  constructor tag or a `CON` node of a possibly-newtype type, and record the
  verdict for each in the commit body:
  - `runtime/ahc_rts.c`: `contag`, `AHC_CON`, structural `p_eq_poly`/`compare_poly`;
  - `src/ahc-optimizer.adb`: case of known constructor;
  - `src/ahc-exhaustive.adb`;
  - FFI marshalling (`Marshal_Kind_Of`);
  - `src/ahc-bindgen.adb`.

  **The optimizer is the risky one.** If it rewrites `case N e of N x -> b` to
  `let x = e in b`, that is consistent with erasure. If it does anything else
  keyed on constructor tags, check it. The structural `P_EqP` primitive now
  compares the field directly for a newtype, which equals comparing the boxed
  value.
- [ ] **Step 5: Verify.**
  - `ch04_02_newtype_seq` matches GHC.
  - Every conformance and exec program passes in both GC modes.
    Newtype-wrapped parsers (`some`/`many`'s knot, the M141 repos) are the
    sensitive ones: `grep -l newtype tests/conformance/*.hs tests/exec/*.hs`.
- [ ] **Step 6: Commit.** `fix(codegen): newtypes are erased - the constructor is the identity and a case on it never forces`.

**Gate:** full gate in both GC modes, own soak with `AHC_OWN_VERIFY=1`,
`run_tsan`, `run_examples`, `run_export`, `run_bindgen`, goldens on both
builds, and bench A/B against v1.17 for the newtype-heavy benches (and
`scripts/scout_repos.sh` agreement on the repos with newtype parsers, if it
runs offline).

---

## Phase D - GeneralizedNewtypeDeriving

### Task D1: newtype deriving marks GND

**Files:** `src/ahc-rename.adb:1600-1710` (the deriving loop).

- [ ] **Step 1: Test first.** Write `tests/conformance/ext_gnd.hs` and oracle
  it.

  ```haskell
  {-# LANGUAGE GeneralizedNewtypeDeriving #-}
  -- GND, always on in AHC (M147): every class but Show/Read derives
  -- through the representation's instance.
  newtype Age = Age Int
    deriving (Show, Read, Eq, Ord, Bounded, Enum, Num, Real, Integral)
  newtype Score = Score Double deriving (Show, Eq, Ord, Num, Fractional)
  newtype W a = W (Maybe a) deriving (Show, Eq, Functor)
  newtype Box a = Box [a] deriving (Show, Functor, Semigroup, Monoid)
  newtype Counter a = Counter (Either String a) deriving (Show, Functor, Applicative, Monad)

  tick :: Counter Int -> Counter Int
  tick c = do
    n <- c
    if n > 2 then Counter (Left "too big") else return (n + 1)

  main :: IO ()
  main = do
    print (Age 3 + 4, Age 10 `div` 3, [Age 1 .. Age 3], maxBound :: Age)
    print (read "Age 7" :: Age, toInteger (Age 9), succ (Age 5), fromIntegral (Age 2) + (1 :: Int))
    print (Score 1.5 * 2, recip (Score 4), Score 1 < Score 2)
    print (fmap (+ 1) (W (Just 1)), W (Just 'a') == W (Just 'a'))
    print (Box [1, 2] <> Box [3], mempty :: Box Int, fmap show (Box [True]))
    print (tick (Counter (Right 1)), tick (tick (tick (Counter (Right 1)))))
  ```

  If GHC rejects a line, for example because a `Semigroup`/`Monoid` derive
  needs a context, adjust the program until runghc accepts it. Never weaken
  what AHC is tested on without saying so in the commit.
- [ ] **Step 2: Rename.** In the deriving loop, when `Is_NT` (the declaration
  is a newtype) and the class is in scope and is not the Prelude's
  `Show`/`Read` by identity (`Stock_Derivable (C, Name)` and the name is
  `Show`/`Read`):
  - skip the Enum/Bounded/Ix nullary check;
  - mint the instance with `Is_GND => True`, `Head_Vars` empty and `Context`
    empty, because the typechecker's `Resolve_GND` fills them.

  A newtype deriving `Show`/`Read` takes the stock path as today. A `data`
  type takes the stock path, unchanged.

### Task D2: resolve GND instances

**Files:** `src/ahc-typechecker.adb` (a pre-pass before instance method
checking), `src/ahc-elaborate.adb` (dictionary bodies),
`src/ahc-prelude_core.adb:1773` (exclusion).

- [ ] **Step 1: `Resolve_GND`.** In the typechecker, before the superclass and
  method checks (near 1770), visit every instance with `Is_GND`:

  ```ada
      --  GeneralizedNewtypeDeriving (M147). For newtype T v1..vn = K R:
      --  a kind-* class gets head T v1..vn and target R; a
      --  constructor class (kind * -> *) eta-reduces: R must be
      --  R' vn with vn not free in R', the head is T v1..vn-1 and the
      --  target R'. The target's own instance (one-way match, its
      --  type variables rigid) supplies the context; a bare type
      --  variable target needs C v as context. No instance -> error.
      procedure Resolve_GND (II : Real_Instance_Id);
  ```

  1. Read the newtype's constructor:
     `M.Info (Real_TyCon_Id (Inst.Head)).Cons (1)`. Its `Con_Scheme` body is
     `R -> T v1..vn`, quantified over `Tvs`. Take `R` and the `Tvs`.
  2. Decide the class kind:
     `M.Node (Real_Kind_Id (M.Info (Cl).Var_Kind)).Kind = KFun_K` means a
     constructor class. Check the accessor name for kind nodes in
     ahc-core.ads before writing it.
  3. **Kind `*`:** `Head_Type := T v1..vn`, `Head_Vars := Tvs`,
     `Target := R`.
  4. **Constructor class:**
     - `Tvs` must be non-empty and `R` must be `TApp (R', TVar vn)` with `vn`
       not occurring in `R'`. Otherwise report a new diagnostic,
       `Class_Gnd_Eta`: "cannot derive 'C' for 'T': its representation does
       not end in its last type variable".
     - `Head_Type := T v1..vn-1`, `Head_Vars := v1..vn-1`, `Target := R'`.
  5. **Target is a bare `TVar`:** `Context := [C Target]`.
  6. **Otherwise:** match every instance of `C` against `Target` with
     `Match_TC`; the target's variables are rigid `TVar_T` nodes, so they bind
     only to pattern variables.
     - **Exactly one `Matched`:** its `Context`, substituted with the match
       arguments, becomes the GND instance's context. If that instance is
       itself GND and not yet resolved, resolve it first (recursion with a
       depth guard).
     - **None:** report `Class_Gnd_No_Instance`: "cannot derive 'C' for 'T':
       no instance 'C <R>'".
     - **Several:** the overlap error.
  7. Store `GND_Target := Target` and `Head := T`, which is unchanged.

  Then run the existing superclass check on GND instances too. Widen its guard
  from `Inst.From_Source` to `Inst.From_Source or else Inst.Is_GND`, so that
  `deriving (Integral)` without `Real` and `Enum` is the same compile error as
  GHC's.
- [ ] **Step 2: Elaborate.** Where elaborate binds dictionaries for
  `From_Source` instances, add a branch for `Is_GND`. The dictionary global's
  body is a lambda over one parameter per `Context` constraint, the same
  `Param_Vars` shape as source instances; mint them in elaborate if the
  typechecker didn't. Its body is
  `Solve_Ev (Constraint'(Class => Of_Class, Arg => GND_Target, ...), Givens_From_Params, Span, 0)`.
  With no context, the body is `Solve_Ev`'s result directly, for example
  `$dNumInt`.
- [ ] **Step 3: prelude_core.** In the "Instance dictionaries without bodies
  yet" loop (prelude_core.adb:1773), add `and then not Inst.Is_GND` to the
  condition, so the wired/derived dispatcher never sees a GND instance.
- [ ] **Step 4: Rejects.** Add to `tests/corpus-types/`:
  - `bad_gnd_no_instance.hs`: `newtype P = P (Int -> Int) deriving (Num)`
    reports no instance `Num (Int -> Int)`.
  - `bad_gnd_eta.hs`:
    `newtype Parser a = Parser (String -> [(a, String)]) deriving (Functor)`
    reports the eta error, since the representation does not end in `a`.
  - `bad_gnd_superclass.hs`: `newtype I = I Int deriving (Integral)` reports
    no instance `Real I`.

  Oracle each with `runghc` to confirm GHC rejects it too, and record GHC's
  message in a comment at the top of the file.
- [ ] **Step 5: Verify.**
  - `ext_gnd` matches GHC.
  - The rejects fail as expected.
  - The M146-design probe `gnd.hs` (`deriving (Num)` and
    `deriving (Functor, Show)` on `Counter`) prints GHC's output.
  - The full conformance and exec suites pass.
- [ ] **Step 6: Commit.** `feat(deriving): generalizednewtypederiving - a newtype's instance is its representation's dictionary`.

**Gate:** full gate in both GC modes, both differential suites, `run_repl`,
`run_separate`, goldens on both builds, and fuzz 100.

---

## Phase E - milestone gate

- [ ] Release build.
- [ ] Goldens on both builds.
- [ ] Full gate in both GC modes.
- [ ] Both differential suites.
- [ ] `run_repl`, `run_examples`, `run_bindgen`, `run_separate`, `run_export`,
  `run_userlib`, `run_tsan`.
- [ ] `AHC_OWN_VERIFY=1 ./scripts/run_own_soak.sh`.
- [ ] `./scripts/run_fuzz_par.sh 300 6 1`.
- [ ] **Bench** against v1.17. Build v1.17 in the `/private/tmp/claude-501/ahc-v115`
  worktree (`git checkout v1.17 && alr build --release`), then run the
  scratchpad `ab_bench.sh` (interleaved best of 5) on a quiet machine.
  Arbitrate any wall-clock delta above 3% with `/usr/bin/time -l`
  instructions retired.
- [ ] **Scout:** re-run `scripts/scout_repos.sh` on the repos
  `docs/repos-to-try.md` lists as blocked by these extensions, and record
  which now agree with GHC.

**Gate:** all of the above green; bench and scout recorded in the plan's
verdict paragraph.

## Phase F - review, write-up, release

- [ ] **F1 Adversarial review.** Use the adversarial-review skill, scope
  `git diff v1.17..HEAD`. Dimensions:
  1. `\case` parsing and layout: nesting, operator sections, `where`, `let`
     blocks inside alternatives, explicit braces, error recovery.
  2. Instance matching: overlap, residuals and defaulting, superclasses of
     flexible instances, IsString, Rational, `(->)` instances, separate
     compilation and the REPL.
  3. Newtype erasure, at every place that inspects a constructor.
  4. GND: contexts, chains of newtypes, constructor classes, superclass
     dictionaries, interaction with stock-derived Show/Read.
  5. Claims audit.

  Findings land as `fix: N defects an adversarial review of M147 found`.
- [ ] **F2 Security pass.** Only if FFI marshalling changed in Phase C.
- [ ] **F3 Write-up.**
  - CHANGES `## v1.18 (unreleased)`.
  - MANUAL: an extensions section, instance resolution by matching, newtype
    erasure.
  - `docs/repos-to-try.md`: the Extensions bullet, with the four marked
    CLOSED.
  - Memory: update ahc-classes with matching, GND and overlap.
- [ ] **F4 Release v1.18,** with the user's go-ahead.

---

**Verdict (2026-10-10): GO as of d5983b4.** Phases A to D landed as
planned, with these changes:

- **Phase B** needed the Haskell 2010 spine rule kept for wired and
  stock-derived instances. Building full heads for those broke
  `IsString [a]`.
- **Phase C's** bench was folded into Phase E's.
- **Phase E:** milestone gate green, bench within noise, scout recorded
  in CHANGES and repos-to-try.
- **Adversarial review:** four reviewers found 20 defects, all fixed in
  one commit with 29 new tests, then the full gate re-run green.
- **Not fixed:** the pre-existing structural Eq/Ord divergence the
  review confirmed is recorded in EXCLUSIONS for its own milestone.
- **Security pass:** not required. FFI marshalling is unchanged;
  newtypes in FFI signatures stay rejected.
