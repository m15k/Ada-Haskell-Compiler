# M143 and M144 - the REPL loads multi-module programs; own-vs-import ambiguity

Two small milestones, done in order, in an isolated worktree.

## M143 - the REPL loads multi-module programs

### Phase 1 - reproduce and scope

Setup: /tmp/m143/p/{Main,Shapes,Util}.hs (Main imports Shapes and
`qualified Util as U`; Shapes imports Util and re-exports it).
Driven as scripts/run_repl.sh does (stdin session, AHC_REPL_DIR).

Observed (before any change):

- `:l p/Main.hs` prints nothing at all (no `loaded:`, no error); the
  session stays empty; `Repl.main` then says "module 'Repl' does not
  export 'main'", `area (Sq 2)` says "variable not in scope".
- `:l p/Shapes.hs` likewise silent.
- The same from inside the program's own directory.

Root cause (two defects):

1. `Module_Path` in src/ahc_main.adb (Root_Dir, line 315; lookup at
   line 345) resolves a sibling import beside the ROOT FILE of the
   compile. The REPL compiles the scratch `Repl.hs`, so `import
   Shapes` looks for `<scratch>/Shapes.hs`; the loaded file's own
   directory is never searched. `ahc check Repl.hs` fails with
   "ahc: cannot find module 'Shapes' (looked for ./Shapes.hs)".
2. `Put_Diagnostics` in src/ahc-repl.adb prints only lines containing
   ": error:" / ": warning:", so the driver-level "ahc: cannot find
   module" line was dropped and the failed `:load` was completely
   silent.
3. (scope) `Load` puts the file's `import` lines in the verbatim body
   of Repl.hs; Repl has no export list, so the expression module Main
   (which only imports Repl and the *entered* imports) never saw the
   loaded file's imports - `double` (via Shapes) and `U.double`
   could not be used at the prompt, unlike GHCi's `*Main>`.

GHCi target (same session, ghci from ~/.ghcup/bin): `:l Main.hs`
prints `[1 of 3] Compiling Util ...` / `Ok, three modules loaded.`;
at `*Main>` the loaded module's top level AND its imports (including
qualified names `U.double`, sibling constructors, types) are in
scope; `:r` reloads changed modules; an error in a sibling is
reported with that sibling's file name.

Gate: this paragraph, committed.

### Phase 2 - fix

- src/ahc_main.adb: a new `AHC_PATH` environment variable (colon
  separated, like GHC's -i) of extra module directories, searched
  after the root file's directory and before dependency roots.
- src/ahc-repl.adb: `:load` sets AHC_PATH to the loaded file's
  directory; the loaded file's top-level `import` lines become
  session imports (so Main sees them); Put_Diagnostics also prints
  the driver's `ahc:` lines.
- docs/repl-design-note.md, docs/MANUAL.md REPL section.

Gate: `./scripts/run_repl.sh` green with new cases (multi-module
load, imported name, qualified name, sibling constructor/type,
`:reload` after editing a sibling, sibling load error named by file).

### Phase 3 - full gate

Gate: `./scripts/run_gate.sh` -> `GATE ok`; `./scripts/run_repl.sh` green.

## M144 - own declaration vs import: report ambiguity like GHC

### Phase 1 - sweep the blast radius (before changing anything)

Gate: the sweep list committed here; if more than 20 sites, STOP and
report.

#### Method

The rule was implemented in a scratch copy of the tree (own declaration
vs an unqualified import, or vs the implicit Prelude; modular path only)
and `ahc check` was run with the OLD and the NEW binary over EVERY .hs
file under lib/, tests/ (conformance, exec, golden, corpus, bench,
build, examples/, ...) and examples/; any difference in outcome or
message is a site. Because a failing library module stops the check
before its importers, the sweep was iterated: fix a module, re-run.

#### A finding that shapes the rule: AHC's Prelude is wider than GHC's

`prelude/Prelude.hs` has no export list, so the implicit-Prelude
snapshot (`Reg.Base`) holds `fromMaybe`, `isJust`, `isNothing`, `swap`
and ~75 internal helpers that GHC's Prelude does not export. A naive
"own vs Prelude" ambiguity would REJECT programs GHC accepts (any
program defining its own `swap` or `fromMaybe`). So the own-vs-Prelude
arm of the rule fires only for names GHC 9.4.8's Prelude exports: a
generated table (scripts/gen_report_prelude.py -> src/ahc-report_prelude.adb,
256 names from `ghc -e ':browse Prelude'`). Own-vs-import needs no table
(module facades have export lists).

#### The sweep (own declaration used unqualified/exported while an
unqualified import or the Prelude supplies the same name)

lib/ (3 modules, 15 use sites):
- lib/Data/Set.hs: own `null` (line 33), `filter` (222), `map` (229) vs
  the Prelude - flagged at the export-list entries, 2:28, 6:5, 6:13
  (3 sites). Fix: `import Prelude hiding (null, filter, map)`.
- lib/Data/Map.hs: own `null`, `lookup`, `map`, `filter` vs the Prelude -
  2:28, 3:5, 6:5, 6:10, 53:11, 54:11, 59:8, 68:8, 187:12, 221:40, 221:50
  (11 sites). Fix: `import Prelude hiding (filter, lookup, map, null)`.
- lib/System/IO.hs: own `interact` (107) vs the Prelude's (which exists
  since M141) - export entry 3:37 (1 site). Fix: delete the duplicate
  definition so the export re-exports the Prelude's entity (GHC's shape).
Because own already won everywhere, adding a `hiding` clause cannot
change what any use inside these modules means.

tests/, examples/: 0 sites (the only file whose outcome differs is
prelude/Prelude.hs itself when mis-fed to `check` as a user module, which
is not a gate input; the Prelude is compiled by the non-modular pass).
tests/conformance/ch05_wired_shadowing.hs defines its own `filter` but
only ever uses `Prelude.filter`/qualified names, which GHC accepts.

Total 15 sites (<= 20) in 3 library modules -> proceed to Phase 2.
Unit tests (330) pass against the experimental binary.

### Phase 2 - implement (only if the sweep is <= 20 sites)

Gate: `./scripts/run_gate.sh` -> `GATE ok`; run_differential.sh and
run_differential_types.sh green; `./scripts/run_fuzz_par.sh 300 6 1`
all ok.

### M143 phase 2 result

Implemented as planned, plus `:! CMD` (GHCi's shell escape) so a
transcript can edit a sibling between `:r`s. New transcripts:
tests/repl/multi.in (load Main; `Repl.main`; imported name `double`;
qualified `U.double`; sibling constructor/type `Rect 2 3`, `:t Sq`,
`Red == Green`; `:l` of a sibling module; a load whose import is
missing -> `ahc: cannot find module` shown, session rolled back) and
tests/repl/multi_reload.in (edit Util.hs, `:r`, new value; introduce a
type error in Util.hs -> reported as tests/repl/work/Util.hs:3:1;
repair, `:r`). Fixtures: tests/repl/multi/, tests/repl/nomod.hs.
load.out re-pinned: the help text gained two lines and the fixture's
import moved ahead of the body (Probe line 3 -> 4).
`./scripts/run_repl.sh` rc=0 (5 transcripts ok).
Known remaining: errors inside the loaded ROOT file cite Repl.hs.
