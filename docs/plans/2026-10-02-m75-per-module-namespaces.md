# M75 Per-module type and constructor namespaces - Implementation Plan

**Goal:** two modules of one program may declare the same type,
constructor, class or type-synonym name, and a qualified import
disambiguates them - as GHC does, and as AHC's *value* namespace
already does.

**Architecture:** the renamer ALREADY resolves use sites per module,
through `Own : Modules.Iface` plus `Imp_Views` plus the `Reg.Base`
Prelude snapshot. The defect is on the other side: user *declarations*
are also poured into the program-wide `Builtins.Global_Env` maps
(`Env.TyCons`, `Env.DataCons`, `Env.Classes`, `Env.Synonyms`), which is
where the clash is detected, and `AHC.Kinds` then re-finds entities **by
name** from that same global map instead of using what the renamer
resolved. So the fix is not a new namespace mechanism; it is to stop
re-resolving by name after the renamer has already decided. Three moves:
carry declaration->entity on `Resolutions`, make synonym expansion
follow the per-module table, then stop registering user declarations
globally and delete the clash errors.

## Global constraints

- Oracle is **GHC 9.4.8** (`$HOME/.ghcup/bin/runghc`); every new
  conformance program is oracled against it and must be byte-identical.
- Report sections in scope: **5.1-5.3** (module namespaces, qualified
  names), **5.5.2** (ambiguous unqualified names are an error at the USE
  site, not the declaration), **4.2.1** (two declarations of one name
  *within* one module stay an error).
- `AHC_GC=own` and the default collector must both pass `run_exec.sh`.
- The Prelude keeps exactly its current namespace behaviour: builtins
  and Prelude declarations stay in `Env` and reach every module
  unqualified. Only *user* modules change.
- No new `Env` field, and no map keyed by `(module, name)` - that shape
  was considered and rejected (it preserves the conceptual error of
  resolving by name downstream, and touches every reader).
- Codegen is NOT in scope and needs no change: constructors are numeric
  `u.con.contag` values, not C symbols, and global value symbols are
  already `g_<Owner>_<Name>` with a `Taken` uniquifier
  (`src/ahc-codegen.adb:1529-1545`). Verified before planning.
- Gates run per phase, never only at the end. Use
  `scripts/run_gate.sh` - unpiped, per-suite rc. Never pipe a suite
  into a filter to read its status.
- `prelude/` and `lib/` are gate inputs: no background suite may run
  while they change. This plan does not edit them.

## The flat-namespace surface, as of v1.14

Line numbers are anchors - the surrounding code is quoted in each task
so it stays findable if they drift.

| Site | File:line | What it does |
|---|---|---|
| Type clash check | `src/ahc-rename.adb:1130-1146` | `Env.TyCons` + `Env.Synonyms` lookup -> "type 'T' is defined more than once"; then `Env.TyCons.Include` beside `Own.TyCons.Include` |
| Constructor clash | `src/ahc-rename.adb:1171-1181` | `Env.DataCons.Contains` -> "constructor 'C' is defined more than once"; then `Env.DataCons.Include` |
| Class clash | `src/ahc-rename.adb:1310-1327` | `Env.Classes.Contains` -> "class 'C' is defined more than once"; then `Env.Classes.Include` |
| Synonym clash | `src/ahc-rename.adb:1805-1815` | the synonym equivalents |
| Kinds: decl -> TyCon **by name** | `src/ahc-kinds.adb:899, 921` | `Env.TyCons.Find (N.D_Name)` inside `Pre_Data`/`Do_Data` |
| Kinds: con -> DataCon **by name** | `src/ahc-kinds.adb:978` | `Env.DataCons.Find (CN.Name.Name)` |
| Kinds: synonym by name | `src/ahc-kinds.adb:292, 433, 466, 1180, 1210` | `Env.Synonyms (Name)` for expansion and caching |
| Prelude snapshot | `src/ahc_main.adb:489-494` | `Reg.Base.TyCons := Env.TyCons` etc., taken AFTER the Prelude's passes |
| Per-module driver | `src/ahc_main.adb:683, 688` | `Resolve_Module` then `Kinds.Check_Module`, once per user module, sharing the mutable `Env` |

Already per-module and needing no change: `Mod_Find_TyCon`
(`rename.adb:249`), `Mod_Find_DataCon` (`:292`), `Mod_Find_Class`
(`:336`), `Mod_Syn_Visible`, and every use-site table
(`Res.Ty_Res`, `Res.Class_Res`).

## Files

| File | Responsibility in this plan |
|---|---|
| `src/ahc-rename.ads` | add `DataCon_Res_Vectors`; add `Decl_TyCon`, `Decl_Con`, `Decl_Syn` to `Resolutions` |
| `src/ahc-rename.adb` | populate the three new tables; drop the four global clash checks; stop writing `Env.*` for user declarations; keep the within-module duplicate check |
| `src/ahc-modules.ads` | `Iface.Synonyms` carries `Builtins.Syn_Rec`, not a name set |
| `src/ahc-kinds.adb` | read `Res.Decl_TyCon` / `Res.Decl_Con` / `Res.Decl_Syn` instead of `Env.*.Find`; expand synonyms through the per-module table |
| `src/ahc_main.adb` | gate the `Env` writes on "this is the Prelude pass" |
| `tests/conformance/multi/dupnames/` | new: two modules declaring the same type AND constructor |
| `tests/conformance/multi/dupsyn/` | new: same synonym and class name in two modules |
| `tests/corpus/bad_dup_in_module.hs` | new: within-module duplicate still rejected by both compilers |
| `tests/src/test_rename.adb` | unit cases for the new `Resolutions` tables |
| `tests/conformance/EXCLUSIONS.md` | strike the flat-namespace clause from the Report 5 row |
| `docs/MANUAL.md` | module-system section: qualified disambiguation now works |

---

## Phase A - carry declaration identity on Resolutions

Pure refactor. Names are still global and still clash at the end of
this phase; nothing observable changes. That is the point: it must be
invisible, which makes the gate meaningful.

### Task A1: add the declaration->entity tables

**Files:**
- Modify: `src/ahc-rename.ads:50-57` (vector packages), and the
  `Resolutions` record below it
- Modify: `src/ahc-rename.adb` - the `Resolutions` sizing loop that
  currently fills `Res.Ty_Res` / `Res.Decl_Var` (search
  `Res.Decl_Var.Append`)

**Interfaces:**
- Produces: `Rename.DataCon_Res_Vectors`,
  `Resolutions.Decl_TyCon`, `.Decl_Con`, `.Decl_Syn` - consumed by
  Tasks A2, B2, C2.

- [ ] **Step 1: Implement** - in `src/ahc-rename.ads`, beside the
      existing vector packages:

```ada
   package DataCon_Res_Vectors is new Ada.Containers.Vectors
     (Positive, Core.DataCon_Id, Core."=");
```

      and in `Resolutions`, after `Decl_Class`:

```ada
      --  Declaration -> entity. Later phases must NEVER re-find an
      --  entity by name: two modules may declare the same type,
      --  constructor, class or synonym, and only the renamer knows
      --  which one a given declaration minted (M75).
      Decl_TyCon : TyCon_Res_Vectors.Vector;   --  Data_D/Newtype_D
      Decl_Con   : DataCon_Res_Vectors.Vector; --  Con_Node id
      Decl_Syn   : TyCon_Res_Vectors.Vector;   --  Type_Syn_D, see B1
```

      Size all three in the same loop that sizes `Res.Decl_Var`,
      `Decl_TyCon`/`Decl_Syn` over `Arena.Last_Decl` and `Decl_Con`
      over the constructor arena (`Arena.Last_Con`):

```ada
      for I in 1 .. Natural (Arena.Last_Decl) loop
         Res.Decl_TyCon.Append (Core.No_TyCon);
         Res.Decl_Syn.Append (Core.No_TyCon);
      end loop;
      for I in 1 .. Natural (Arena.Last_Con) loop
         Res.Decl_Con.Append (Core.DataCon_Id'(0));
      end loop;
```

- [ ] **Step 2: Populate** - in `Declare_Data`
      (`src/ahc-rename.adb:1130`), beside each existing
      `Own.*.Include`, record the id against the declaration:

```ada
         Own.TyCons.Include (N.D_Name, TC);
         Res.Decl_TyCon.Replace_Element (Positive (D), Core.TyCon_Id (TC));
```

      and in the constructor loop, beside `Own.DataCons.Include`:

```ada
                  Own.DataCons.Include (Info.Name, DC);
                  Res.Decl_Con.Replace_Element
                    (Positive (CI), Core.DataCon_Id (DC));
```

      `Declare_Data` currently has `pragma Unreferenced (D);` at its
      end (`src/ahc-rename.adb:1301`) - delete it, `D` is now used.

- [ ] **Step 3: Regression test** - add to `tests/src/test_rename.adb`,
      in the style of the existing resolution cases:

```ada
      --  M75: the renamer records which entity each declaration
      --  minted, so Kinds never has to look one up by name.
      Check_Equal
        (RN ("data T = C Int" & ASCII.LF & "data U = D Bool"),
         "decl_tycon:T=1 decl_tycon:U=2 decl_con:C=1 decl_con:D=2",
         "each data declaration records its own TyCon and DataCon");
```

      with the `RN` helper extended to print the new tables (mirror the
      existing printer for `Ty_Res`).

- [ ] **Step 4: Verify** - `cd tests && alr build && ./bin/ahc_tests`;
      expect `failed: 0`.
- [ ] **Step 5: Commit** - `refactor(rename): record the entity each
      type, constructor and synonym declaration mints`

### Task A2: Kinds reads the tables instead of the global maps

**Files:**
- Modify: `src/ahc-kinds.adb:894-925` (`Pre_Data`, `Do_Data`)
- Modify: `src/ahc-kinds.adb:975-980` (the constructor lookup)
- Modify: `src/ahc-kinds.ads:57` - `Check_Module` already takes
  `Res : Rename.Resolutions`; confirm and use it

**Interfaces:**
- Consumes: `Res.Decl_TyCon`, `Res.Decl_Con` from Task A1.

- [ ] **Step 1: Implement** - `Pre_Data` and `Do_Data` currently open
      with:

```ada
         TC : constant Core.Real_TyCon_Id :=
           Builtins.TyCon_Maps.Element (Env.TyCons.Find (N.D_Name));
```

      Both take only `N : Decl_Node`, so they cannot reach the
      declaration id. Change both signatures to
      `(D : Real_Decl_Id; N : Decl_Node)` - matching `Do_Class`, which
      already takes `D` - and replace the body's first line with:

```ada
         TC : constant Core.Real_TyCon_Id :=
           Core.Real_TyCon_Id (Res.Decl_TyCon (Positive (D)));
```

      Update both call sites in the driver loops
      (`src/ahc-kinds.adb:1196-1215`): `Pre_Data (D, N);` and
      `Do_Data (D, N);`.

      In the constructor loop, replace:

```ada
               DC : constant Core.Real_DataCon_Id :=
                 Builtins.DataCon_Maps.Element
                   (Env.DataCons.Find (CN.Name.Name));
```

      with:

```ada
               DC : constant Core.Real_DataCon_Id :=
                 Core.Real_DataCon_Id (Res.Decl_Con (Positive (CI)));
```

- [ ] **Step 2: Regression test** - no new test: the existing 105
      conformance programs and 74 exec goldens ARE the test. A refactor
      that changes behaviour shows up there.
- [ ] **Step 3: Verify** - `./scripts/run_gate.sh`; expect `GATE ok`.
      If `golden rc=1`, diff the binding-name SETS before regenerating:

```bash
names() { grep -o '^(bind[a-z]* (\$\?[^ ]*' "$1" \
            | sed 's/^(bind[a-z]* (//; s/_[0-9]*$//' | sort -u; }
./bin/ahc core tests/golden/core_class_dict.hs > /tmp/new.core
diff <(names tests/golden/core_class_dict.core) <(names /tmp/new.core)
```

      An empty diff means ids shifted only; a refactor that ADDS or
      REMOVES a binding is a bug in this task, not a golden to update.
- [ ] **Step 4: Commit** - `refactor(kinds): take data and constructor
      entities from the renamer, not from a name lookup`

**Gate:** `scripts/run_gate.sh` green (unit, conformance, exec both GC
modes, golden) with **no golden regeneration** - this phase changes no
behaviour, so a golden diff beyond id renumbering is a defect.

---

## Phase B - per-module synonym expansion

Synonyms are the one entity whose *expansion* reads the global map by
name, so they need their own phase. `Iface.Synonyms` is today a name
set (`Fixity.Fixity_Maps.Map` "used as a name set" -
`src/ahc-modules.ads`); it becomes the real table.

### Task B1: Iface carries Syn_Recs

**Files:**
- Modify: `src/ahc-modules.ads` - the `Iface` record
- Modify: `src/ahc-rename.adb` - every `Own.Synonyms.Include` and the
  import/export filters that copy `Synonyms`
- Modify: `src/ahc-kinds.adb:1180, 1210` - `Do_Synonym` writes the
  cached `Core_Rhs` into the per-module table

**Interfaces:**
- Produces: `Modules.Iface.Synonyms : Builtins.Syn_Maps.Map` - consumed
  by Task B2.

- [ ] **Step 1: Implement** - in `src/ahc-modules.ads`:

```ada
   type Iface is record
      Values   : Builtins.Var_Maps.Map;
      TyCons   : Builtins.TyCon_Maps.Map;
      DataCons : Builtins.DataCon_Maps.Map;
      Classes  : Builtins.Class_Maps.Map;
      --  The synonym TABLE, not a name set (M75): expansion must
      --  follow the module the name resolved in, because two modules
      --  may declare the same synonym name.
      Synonyms : Builtins.Syn_Maps.Map;
      Fixities : Fixity.Fixity_Maps.Map;
   end record;
```

      In `rename.adb`, the export filter currently records visibility
      with a dummy value:

```ada
                           Ent.Exports.Synonyms.Include
                             (E.Name.Name,
                              Fixity.Fixity_Info'(others => <>));
```

      Replace with the resolved record, which must come from `Own` (the
      module's own synonym) or from the import view it was re-exported
      from:

```ada
                           Ent.Exports.Synonyms.Include
                             (E.Name.Name, Syn_Rec_For (E.Name.Name));
```

      where `Syn_Rec_For` is a new local in the export block:

```ada
            --  A synonym being exported is either this module's own or
            --  one it imported and is re-exporting; take the record
            --  from whichever has it, Own first (Report 5.2).
            function Syn_Rec_For
              (N : Names.Name_Id) return Builtins.Syn_Rec
            is
            begin
               if Own.Synonyms.Contains (N) then
                  return Own.Synonyms (N);
               end if;
               for V of Imp_Views loop
                  if V.Visible.Synonyms.Contains (N) then
                     return V.Visible.Synonyms (N);
                  end if;
               end loop;
               return Reg.Base.Synonyms (N);
            end Syn_Rec_For;
```

- [ ] **Step 2: Regression test** - the existing
      `tests/conformance/multi/synonym/` case already crosses a module
      boundary with a synonym; it must still pass byte-identically.
- [ ] **Step 3: Verify** - `./scripts/run_gate.sh conformance unit`.
- [ ] **Step 4: Commit** - `refactor(modules): a module interface
      carries its synonym records, not just their names`

### Task B2: expansion follows the resolution

**Files:**
- Modify: `src/ahc-kinds.adb:285-300` (the expansion entry) and
  `:430-470` (the two `Env.Synonyms.Contains` guards)
- Modify: `src/ahc-kinds.ads:57` - `Check_Module` gains the resolved
  per-module synonym table, or reads it off `Res.Decl_Syn`

**Interfaces:**
- Consumes: `Modules.Iface.Synonyms` (B1), `Res.Decl_Syn` (A1).

- [ ] **Step 1: Implement** - `Kinds` currently expands with

```ada
         Syn : constant Builtins.Syn_Rec := Env.Synonyms (Name);
```

      which is the global map. The renamer already decided visibility
      in `Mod_Syn_Visible`; what it does not yet hand over is WHICH
      record. Add a synonym resolution table beside `Res.Ty_Res`,
      filled in `Rename_Type`'s `Con_T` branch when the head resolves
      to a synonym rather than a tycon:

```ada
      --  Con_T occurrences that are synonyms, resolved to the
      --  defining module's record. Ty_Res stays No_TyCon for these.
      Syn_Res : Syn_Res_Maps.Map;   --  Syntax.Type_Id -> Syn_Rec
```

      and in `Kinds`, expand through it:

```ada
         Syn : constant Builtins.Syn_Rec :=
           (if Res.Syn_Res.Contains (Syntax.Type_Id (T))
            then Res.Syn_Res (Syntax.Type_Id (T))
            else Env.Synonyms (Name));   --  Prelude/builtin synonyms
```

      The `else` branch is not a fallback for user code: it is how
      `String` and the other wired synonyms keep working, and it is
      correct precisely because `Env` holds only builtins and Prelude
      after Phase C.

- [ ] **Step 2: Regression test** - create
      `tests/conformance/multi/dupsyn/` with the SAME synonym and class
      name in two modules:

      `Left.hs`:
```haskell
module Left (Pair, Named (..), describe) where
type Pair = (Int, Int)
class Named a where
  name :: a -> String
data L = L
instance Named L where
  name _ = "left"
describe :: Pair -> String
describe (a, b) = "L" ++ show (a + b)
```

      `Right.hs`:
```haskell
module Right (Pair, Named (..), describe) where
type Pair = (Bool, Bool)
class Named a where
  name :: a -> String
data R = R
instance Named R where
  name _ = "right"
describe :: Pair -> String
describe (a, b) = "R" ++ show (a && b)
```

      `Main.hs`:
```haskell
module Main where
import qualified Left as L
import qualified Right as R
main :: IO ()
main = do
  putStrLn (L.describe (2, 3))
  putStrLn (R.describe (True, False))
  putStrLn (L.name L.L ++ R.name R.R)
```

      Oracle it: `runghc Main.hs > expected.out` from that directory,
      and check `expected.out` in.

      This case is expected to FAIL until Phase C removes the clash
      errors. Land it in Phase C's Task C2, not here - a checked-in
      failing conformance program would red the gate for two tasks.
      Write it now, keep it in the working tree, add it with C2.
- [ ] **Step 3: Verify** - `./scripts/run_gate.sh`; expect `GATE ok`
      (the dupsyn case is not yet added).
- [ ] **Step 4: Commit** - `refactor(kinds): expand a synonym through
      the module it resolved in`

**Gate:** `scripts/run_gate.sh` green, and
`tests/conformance/multi/synonym/` still byte-identical.

---

## Phase C - stop registering user declarations globally

The behaviour change. Everything before this was preparation.

### Task C1: Env becomes builtins-and-Prelude only

**Files:**
- Modify: `src/ahc-rename.ads` - `Resolve_Module` gains
  `Global_Scope : Boolean`
- Modify: `src/ahc-rename.adb:1143, 1179, 1326, 1814` - the four
  `Env.*.Include` calls for user declarations
- Modify: `src/ahc_main.adb:595` (Prelude pass -> `Global_Scope => True`)
  and `:683` (user modules -> `False`)

**Interfaces:**
- Produces: `Rename.Resolve_Module (..., Global_Scope : Boolean)`.

- [ ] **Step 1: Implement** - add the parameter, defaulting to `False`
      so a missed call site fails closed (a user module that wrongly
      registered globally is the bug being fixed):

```ada
   procedure Resolve_Module
     (...;
      --  True only for the Prelude pass: its declarations join the
      --  builtins in Env and reach every module unqualified. A user
      --  module's declarations live in its own Iface (M75).
      Global_Scope : Boolean := False);
```

      Guard each of the four writes:

```ada
         Own.TyCons.Include (N.D_Name, TC);
         if Global_Scope then
            Env.TyCons.Include (N.D_Name, TC);
         end if;
```

      `src/ahc_main.adb:595` passes `Global_Scope => True`; `:683`
      leaves the default.

- [ ] **Step 2: Regression test** - the Prelude itself is the test: if
      `Global_Scope` is wrong for the Prelude pass, nothing compiles at
      all, loudly.
- [ ] **Step 3: Verify** - `./scripts/run_gate.sh`; expect `GATE ok`.
- [ ] **Step 4: Commit** - `feat(rename): only the Prelude's
      declarations are program-global`

### Task C2: drop the clash errors, keep the within-module one

**Files:**
- Modify: `src/ahc-rename.adb:1130-1146, 1171-1181, 1310-1327,
  1805-1815` - delete the four cross-module clash diagnostics
- Create: `tests/conformance/multi/dupnames/{Left,Right,Main}.hs` +
  `expected.out`
- Create: `tests/conformance/multi/dupsyn/` (written in B2)
- Create: `tests/corpus/bad_dup_in_module.hs`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Implement** - the type check currently reads:

```ada
            C : constant Builtins.TyCon_Maps.Cursor :=
              Env.TyCons.Find (N.D_Name);
            Clash : Boolean := Env.Synonyms.Contains (N.D_Name);
         begin
            if Builtins.TyCon_Maps.Has_Element (C)
              and then not M.Info
                (Builtins.TyCon_Maps.Element (C)).Is_Builtin
            then
               Clash := True;
            end if;
```

      Replace the `Env` lookups with `Own`, so the error means
      "declared twice **in this module**" (Report 4.2.1), which stays
      an error in GHC too:

```ada
            --  Report 4.2.1: one module may not declare a name twice.
            --  ACROSS modules it is legal and qualified imports
            --  disambiguate, so this asks Own, not Env (M75).
            Clash : constant Boolean :=
              Own.TyCons.Contains (N.D_Name)
                or else Own.Synonyms.Contains (N.D_Name);
```

      Apply the same change to the constructor, class and synonym
      checks: `Env.DataCons.Contains` -> `Own.DataCons.Contains`,
      `Env.Classes.Contains` -> `Own.Classes.Contains`.

- [ ] **Step 2: Regression test** - add `multi/dupnames/`, two modules
      declaring the same TYPE and the same CONSTRUCTOR:

      `Left.hs`:
```haskell
module Left (Shape (..), area) where
data Shape = Circle Double | Square Double
area :: Shape -> Double
area (Circle r) = 3.0 * r * r
area (Square s) = s * s
```

      `Right.hs`:
```haskell
module Right (Shape (..), area) where
data Shape = Circle Int | Square Int
area :: Shape -> Int
area (Circle r) = 3 * r * r
area (Square s) = s * s
```

      `Main.hs`:
```haskell
module Main where
import qualified Left as L
import qualified Right as R
main :: IO ()
main = do
  print (L.area (L.Circle 2.0))
  print (R.area (R.Square 3))
  print (map L.area [L.Circle 1.0, L.Square 2.0])
```

      Oracle both new cases:

```bash
(cd tests/conformance/multi/dupnames && runghc Main.hs > expected.out)
(cd tests/conformance/multi/dupsyn  && runghc Main.hs > expected.out)
```

      And pin that the WITHIN-module duplicate is still rejected, in
      the both-compilers-reject corpus - `tests/corpus/bad_dup_in_module.hs`:

```haskell
module Main where
data Shape = Circle Double
data Shape = Square Double
main :: IO ()
main = putStrLn "unreachable"
```

- [ ] **Step 3: Verify** - `./scripts/run_gate.sh` -> `GATE ok` with
      **107 conformance programs** (105 + the two new multi cases), and

```bash
./bin/ahc build tests/corpus/bad_dup_in_module.hs -o /dev/null 2>&1 | head -2
runghc tests/corpus/bad_dup_in_module.hs 2>&1 | grep -c error
```

      Both must reject. Then confirm the repo the gap blocked now
      builds:

```bash
./scripts/scout_repos.sh try PLUkraine/rpn-calculator
```

      Expect `AGREES` or `AGREES-BANNER`, not
      `type 'Token' is defined more than once`.
- [ ] **Step 4: Commit** - `feat(rename): two modules may declare the
      same type, constructor, class or synonym`

**Gate:** `scripts/run_gate.sh` green with 107 conformance programs;
`bad_dup_in_module.hs` rejected by both compilers;
`PLUkraine/rpn-calculator` no longer blocked;
`scripts/run_differential.sh` and `run_differential_types.sh` green
(they share `tests/corpus*`, which this phase adds to).

---

## Phase D - adversarial review, docs, release

### Task D1: adversarial review

- [ ] **Step 1** - run the `adversarial-review` skill over
      `git diff v1.14..HEAD`. Target what this plan could plausibly
      have broken, not the gate: (a) a name that resolves to the WRONG
      module's entity - the same constructor name in two modules used
      unqualified from a third should be an **ambiguity error at the
      use site** (Report 5.5.2), not a silent pick; (b) a synonym
      expanding through the wrong module's `Core_Rhs`; (c) `deriving`
      on two same-named types producing one dictionary; (d) record
      field selectors with the same name in two modules - selectors are
      `Values`, already per-module, but confirm; (e) instance coherence
      - two modules declaring the same class name and both instancing
      it for `Int` must NOT collapse into one instance.
- [ ] **Step 2** - each finding gets a conformance or corpus case,
      then the fix. Findings land as one commit:
      `fix: N defects an adversarial review of M75 found`.

**Gate:** review verdict recorded in this plan file, GO or NO-GO stated
explicitly; every finding has a regression test.

### Task D2: docs and release

**Files:**
- Modify: `tests/conformance/EXCLUSIONS.md` - the Report 5 row
- Modify: `docs/MANUAL.md` - module-system section
- Modify: `docs/repos-to-try.md` - the blockers list
- Modify: `CHANGES.md`, `README.md`, `src/ahc.ads`, `alire.toml`

- [ ] **Step 1** - in `EXCLUSIONS.md`, the Report 5 row currently says
      the namespace is "Still flat, and a clean compile ERROR where GHC
      would accept: same-named type SYNONYMS in two modules ... and
      same-named data CONSTRUCTORS in two modules ... both namespaces
      are program-global, so qualified imports cannot disambiguate
      them; rename the colliding declaration." Strike that clause
      through and state what remains true: within-module duplicates are
      still an error, and the Prelude's names are still program-global.
- [ ] **Step 2** - `docs/repos-to-try.md`: strike the
      "flat type and constructor namespace" bullet from "what usually
      blocks a repo"; re-verify and re-table
      `PLUkraine/rpn-calculator`.
- [ ] **Step 3** - version: bump `src/ahc.ads` **and** rebuild
      (`cd tests && alr build`), bump `alire.toml`, add the README
      release-history entry, promote `CHANGES.md`, then
      `./scripts/check_version.sh v1.15` until `VERSION ok`.
- [ ] **Step 4** - `release:` commit, annotated tag on the **promoted**
      commit, push `main` then the tag, then
      `gh release create` with notes immediately (the
      `release.yml` workflow fires on the tag and uploads the Linux
      tarball onto whatever release exists; if it wins the race, use
      `gh release edit`).

**Gate:** `scripts/run_gate.sh` green on the rebuilt compiler;
`check_version.sh v1.15` -> `VERSION ok`; release notes record the
review verdict.

---

## Self-review

**Spec coverage.** Every site in the surface table maps to a task:
rename clash checks and `Env` writes -> C1/C2; Kinds' by-name tycon and
datacon lookups -> A2; Kinds' synonym expansion -> B2; the `Iface`
name-set -> B1; `ahc_main`'s driver -> C1. The Prelude snapshot
(`ahc_main.adb:489-494`) needs no change and the plan says why.

**Placeholders.** None: every step shows the actual Ada or Haskell, the
two new conformance cases are written out in full with their oracle
commands, and the corpus case is complete.

**Consistency.** `Decl_TyCon`/`Decl_Con`/`Decl_Syn` are introduced in
A1 and consumed by name in A2 and B2. `Global_Scope` is introduced in
C1 with its default stated. `Syn_Rec_For` is defined where it is used.
`Syn_Res`/`Syn_Res_Maps` is introduced in B2 - **note for the
implementer:** B2 Step 1 declares `Syn_Res` on `Resolutions` but A1
declares `Decl_Syn` there too. Decide in B2 whether `Decl_Syn` (keyed
by declaration) or `Syn_Res` (keyed by type-occurrence) is the one you
need; occurrences are what expansion sees, so `Syn_Res` is likely
correct and `Decl_Syn` should be dropped from A1. Resolve this before
starting A1 so the record is right the first time.

**Gate audit.** A: full gate, no golden regeneration. B: full gate plus
the existing synonym case. C: full gate at 107 programs, both-reject
corpus case, the unblocked repo, and both differential suites - which
matters because C2 adds to `tests/corpus`. D: review verdict, version
check, release. The union exercises the frontend (golden,
differential), library semantics (conformance), and the runtime under
both collectors (exec) - which is everything this plan changes.

**Known risk the plan does not remove.** Report 5.5.2 says an ambiguous
*unqualified* use of a name visible from two modules is an error at the
use site. `Lookup_Value` already implements this for values
("ambiguous name 'x' (imported from several modules)"), but
`Mod_Find_TyCon`, `Mod_Find_DataCon` and `Mod_Find_Class` take the
FIRST hit across `Imp_Views` rather than detecting two. Phase C makes
that reachable for types and constructors for the first time. D1(a)
targets it, but if it is confirmed it is a real sub-feature, not a
finding - budget a Task C3 for it: mirror the `Found`/`Amb` shape from
`Lookup_Value` into the three `Mod_Find_*` functions.
