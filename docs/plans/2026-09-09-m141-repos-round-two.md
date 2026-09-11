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
