# M141 Repo-driven breadth, round two - Implementation Plan

**Goal:** ten more real GitHub programs, none written with AHC in mind,
that AHC compiles and runs; the compiler and library gaps they expose
closed; `docs/repos-to-try.md` extended to twenty entries.

**Architecture:** the milestone is a SEARCH, and the deliverable of the
search is the gap list, not the repositories. Round one produced seven
compiler fixes that way. A scouting script does the mechanical part -
find, filter, clone, build, classify - so the judgement can go into the
failures. Since round one, AHC gained exceptions, `Data.Int`/`Word`/
`Bits`/`IORef` and sockets, which should unlock categories that were
blocked before: mutable-state programs, bit twiddling, programs that
handle `IOError`, and anything using `Data.Map`/`Data.Set` (present
since v1.2 but never exercised by outside code).

## Global constraints
- A repo counts only if AHC compiles it AS PUBLISHED, modulo file MOVES (AHC resolves imports beside the root file, so a `src/`+`app/` layout is flattened). Editing a line of Haskell disqualifies it; the whole point is that the code was not written for AHC.
- Every gap the search finds is either fixed with a regression test in this repository, or written into `tests/conformance/EXCLUSIONS.md` with the repo that showed it. No silent skips.
- The oracle stays GHC 9.4.8: where a repo runs under both, the outputs must agree byte for byte, and that comparison is the test.
- Gates run per fix, not per repo: `run_conformance.sh`, `run_exec.sh` (both GC modes), `run_golden.sh`, unit tests.
- No repository is vendored into this tree. The script clones into a scratch directory; what lands here is the documentation, the gap fixes, and their tests.

## Phase A - the scout
`scripts/scout_repos.sh` (new, not a gate - a research tool):
- `search <query>`: `gh search repos --language=haskell`, then for each candidate fetch the file list through the API and reject anything with a non-`.hs` build input it needs (`.cabal` dependencies beyond `base`), a `LANGUAGE` pragma, or an import outside AHC's module set. Print the survivors with size and import set.
- `try <owner/repo>`: shallow-clone into the scratch tree, flatten `src/`+`app/`, find the module with `main`, run `ahc build`, and classify the outcome: `BUILDS`, `PARSE`, `RENAME` (name not in scope - the gap list), `TYPE`, `LINK`, `RUNTIME`. On success, run it, and if GHC accepts the same program, diff the two outputs.
- `report`: a table of everything tried, for pasting into the doc.
**Gate:** the script runs on the round-one repos and reproduces their known results (a scout that cannot re-find what round one found is not evidence).

## Phase B - the search
Work the categories round one named as productive, plus the three the
new library surface opens:
1. Hutton's *Programming in Haskell* exercise sets (richest vein).
2. Project Euler / H-99 solution sets.
3. Puzzle solvers and small games (mutable state now works).
4. Small interpreters and virtual machines written "from scratch" (`Data.Map` environments, `Data.Bits` opcodes).
5. Text utilities: word counts, CSV, Markdown, formatters.
Twenty candidates tried per category is the budget; every failure is
recorded with its exact diagnostic.
**Gate:** ten repos that build and run, each with the command line that
does it and the output it produces.

## Phase C - the gaps
For each distinct diagnostic the search produced: decide fix or
exclusion, and for a fix write the regression test first (a conformance
program when GHC can run it, an exec test when it is AHC-only).
**Gate:** full suites both GC modes; the failing repo now builds.

## Phase D - write-up and release
`docs/repos-to-try.md` extended to twenty with the same table shape, its
"what usually blocks a repo" list re-ordered by what round two saw, and
the closed gaps struck through; CHANGES; adversarial review if the phase
touched the compiler; release.

---

## Phase D - adversarial review (2026-09-15)

The milestone touched the kind checker, the renamer, the typechecker's
defaulting, the Prelude and two derives, so the review targeted what
each change could plausibly have broken rather than re-running the
gate (which was green independently).

**Kind pre-pass - does assigning kinds up front MASK kind errors?**
No. Six programs, AHC and GHC agreeing on accept/reject for all six:
`data A = A (Int Int)`, `data A = A B` with `data B a = B a` (the
forward reference to a type of the WRONG kind - the case the pre-pass
newly makes reachable), `data A = A (B Int)` with nullary `B`, and
`data A a = A (B a)` are all still rejected with a kind mismatch; the
two legal higher-kinded programs still compile. The pre-pass assigns
METAS, which unify and fail exactly as before - it changes when a
tycon has a kind, not whether the kind is checked.

**Derived Read - the generated parser.** Constructor-name boundaries
(`C` / `Cons` / `CX` in one type, where a prefix match would silently
succeed and leave a remainder), `readList` through the list instance,
nested records, a single-field record, a tuple field, a type mixing
prefix + infix + record constructors, whitespace and newlines between
lexemes, and partial input yielding `[]`. All byte-identical to GHC.

**Foldable and defaulting - the string-literal shapes.** Thirteen
lines covering `length "abc"`, `elem` sections over literals,
`filter (`elem` lit)`, numeric and stringy defaulting in the same
expression, `read` at Int and Double, and Foldable over Set and Map.
All byte-identical to GHC.

**Module system.** `C(..)` re-exported from a module that only
imported the class, a method imported by name, a class method with a
default, and `import Prelude hiding (lookup)` beside
`import qualified Prelude (lookup)` - all agree with GHC. The
negative cases still fail correctly: importing a name a module does
not export, and a missing instance. The new Quiet lookup mode did not
silence either.

**One finding, recorded rather than fixed.** A derived Show or Read
on a field type with no instance (`data F = F (Int -> Int) deriving
Read`) compiles and fails at RUN time where GHC rejects it at compile
time. Derived Show has done this since it was written - the derives
resolve field dictionaries statically and emit an `error` where one is
missing - and making Read behave the same way was the consistent
choice; inventing a second convention for one derive would be worse.
Now in EXCLUSIONS. Fixing it properly means the derives reporting a
diagnostic instead of emitting `Err`, which is a change to both and
belongs in its own milestone.

**Verdict: GO.** No defect found that the milestone introduced.
