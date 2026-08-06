# Real GitHub projects AHC compiles

AHC implements Haskell 2010 and ships its own small library set — no
Hackage, no `cabal`, no GHC extensions. That rules out most of GitHub,
but not the part of it worth reading: single-file interpreters,
textbook exercise code, algorithm collections, puzzle solvers. This
page lists nine repositories, none written with AHC in mind, that AHC
compiles today, with the exact commands and the output they produce.

Every entry below was cloned fresh and run against `./bin/ahc`. Where a
repo needs a change to build, the change is stated — there are only two,
both structural (AHC resolves imports beside the root file, so a
`src/`+`app/` layout needs its modules in one directory), and neither
touches a line of Haskell.

## The nine

| Repo | Size | What it does under AHC |
|---|---|---|
| [ncollins/tic-tac-tonad](https://github.com/ncollins/tic-tac-tonad) | 1 file, 96 loc | Plays a full interactive game |
| [2016rshah/sudoku-solver](https://github.com/2016rshah/sudoku-solver) | 2 modules, 244 loc | Solves the bundled puzzle set |
| [OliverMead/mazer-hs](https://github.com/OliverMead/mazer-hs) | 6 modules, 509 loc | Generates and solves mazes in box-drawing characters |
| [rst0git/Game-of-Life-Haskell](https://github.com/rst0git/Game-of-Life-Haskell) | 1 file, 180 loc | Animates Conway's Life to "Game Over" |
| [from0tohero/NQueens](https://github.com/from0tohero/NQueens) | 1 file, 27 loc | Counts n-queens solutions |
| [ahjmorton/mazeHS](https://github.com/ahjmorton/mazeHS) | 1 file, 102 loc | Reads a maze on stdin and solves it |
| [Carrotlord/matrix-library](https://github.com/Carrotlord/matrix-library) | 1 file, 229 loc | Symbolic matrices — typechecks and generates C |
| [leroux/haskell-99-problems](https://github.com/leroux/haskell-99-problems) | 1 file, 66 loc | The H-99 list exercises |
| [Bradcomp/nqueens](https://github.com/Bradcomp/nqueens) | 1 file, 47 loc | Compiles and links |

The last three have no runnable `main` of their own (H-99 defines `main
= undefined`; the other two keep theirs in a test file or omit it), so
what they demonstrate is that the frontend, typechecker and code
generator handle the whole file. The first six produce a working
program.

## Running them

The commands below `cd` into a cloned repo, so they assume AHC's `bin/`
is on your PATH:

```bash
export PATH="$PWD/bin:$PATH"
```

**Tic-tac-toe.** A hand-rolled `Functor`/`Applicative`/`Monad` over a
board-state newtype — user-defined dictionaries and interactive IO
end to end.

```bash
git clone --depth 1 https://github.com/ncollins/tic-tac-tonad && cd tic-tac-tonad && ahc build main.hs -o ttt && ./ttt
```

**Sudoku.** Copy the modules beside each other first (`Main.hs` imports
`Sudoku`, and both live in `src/`), then run it from the repo root so it
finds its board files.

```bash
git clone --depth 1 https://github.com/2016rshah/sudoku-solver && cd sudoku-solver && cp src/*.hs . && ahc build Main.hs -o sudoku && ./sudoku examples
```

```
36..712..  -->  364871295
.5....18.  -->  752936184
..92.47..  -->  819254736
```

**Mazes.** Six modules under `app/` and `src/`; flatten them into one
directory so the driver's import resolution finds them.

```bash
git clone --depth 1 https://github.com/OliverMead/mazer-hs && cd mazer-hs && mkdir -p flat && cp app/*.hs src/*.hs flat/ && cd flat && ahc build Main.hs -o mazer && ./mazer
```

```
┓╻╻
┗╋┫
╺┛┗
```

**Conway's Life.** This is the Life program from Hutton's *Programming
in Haskell* — strict Haskell 2010, no imports at all. The repo's file
is a module of definitions with no `main`, so give it one:

```bash
git clone --depth 1 https://github.com/rst0git/Game-of-Life-Haskell && cd Game-of-Life-Haskell
(echo 'module Life where'; cat game-of-life.hs) > Life.hs
printf 'module Main where\nimport Life\nmain :: IO ()\nmain = life example\n' > Main.hs
ahc build Main.hs -o life && ./life
```

**N-queens.** Takes the board size as an argument; `8` should print
`92`.

```bash
git clone --depth 1 https://github.com/from0tohero/NQueens && cd NQueens && ahc build nQueens.hs -o queens && ./queens 8
```

**The three that compile without running.** `ahc check` runs the whole
frontend through typechecking; `ahc emit` adds code generation.

```bash
ahc check symbolic.hs      # Carrotlord/matrix-library
ahc build h99.hs -o h99    # leroux/haskell-99-problems
ahc build nqueens.hs -o q  # Bradcomp/nqueens
```

## Finding more

GitHub's `language:haskell` search sorted by stars is useless here —
every popular Haskell repo is built on extensions and Hackage. What
works is searching by *topic* and filtering mechanically:

```bash
gh search repos --language=haskell --limit 20 "sudoku solver"
```

Then reject anything with a `{-# LANGUAGE ... #-}` pragma or an import
outside AHC's set. This filter — no pragmas, and every import either
local or one of AHC's modules — is what produced the list above out of
roughly ninety candidates:

```bash
gh api "repos/$REPO/git/trees/HEAD?recursive=1" -q '.tree[].path' | grep '\.hs$'
```

Categories that pay off: textbook exercise code (Hutton's *Programming
in Haskell* is the richest single vein — it is strict Haskell 2010 with
no dependencies, and dozens of repos mirror it), H-99 solutions,
Project Euler sets, puzzle solvers, and small interpreters written
"from scratch".

## What usually blocks a repo

In rough order of how often it came up:

- **Hackage dependencies.** `containers`, `vector`, `text`,
  `random`, `parsec`, `mtl`, `gloss`. Nothing to be done short of the
  package existing in `lib/`.
- **`Control.Applicative` / `Alternative`.** Every hand-rolled parser
  reaches for `<|>` and `many`; AHC has `Applicative` in the Prelude
  but no `Alternative` class and no `Control.Applicative` module. This
  is the most common blocker among otherwise-clean repos.
- **Extensions.** `LambdaCase` dominates, then
  `ScopedTypeVariables`, `TupleSections`, `BangPatterns`.
  (`OverloadedStrings` is CLOSED as of the string milestone F1:
  AHC's literal overloading is unconditional, so modules carrying
  the pragma just work.)
- **`System.Random`.** Common in games and puzzle generators.

Gaps found this way and since closed: `(!!)`, `FilePath` and `read`
were all missing from the Prelude, and an empty string literal in
pattern position (`f "" = ...`) crashed the parser. See CHANGES.md.
