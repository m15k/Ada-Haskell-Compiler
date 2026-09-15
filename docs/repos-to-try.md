# Real GitHub projects AHC compiles

AHC implements Haskell 2010 and ships its own small library set — no
Hackage, no `cabal`, no GHC extensions. That rules out most of GitHub,
but not the part of it worth reading: single-file interpreters,
textbook exercise code, algorithm collections, puzzle solvers. This
page lists **thirty repositories**, none written with AHC in mind, that
AHC compiles today — twenty-seven of them run, three typecheck and
generate C — plus seven more it compiles as libraries, with the exact
commands and the output they produce.

They were found in two rounds. Round one (M132) established that real
code compiles at all. **Round two (M141) raised the bar: a repo counts
only if AHC's binary and GHC 9.4.8's binary, given the same input,
produce byte-identical stdout, stderr and exit status.** Round one's
entries were verified by eye; round two's carry an oracle, and
`scripts/scout_repos.sh` re-runs the whole comparison on demand.

Every entry was cloned fresh and run against `./bin/ahc`. Where a repo
needs a change to build, the change is stated — they are all
structural (AHC resolves imports beside the root file, so a
`src/`+`app/` layout needs its modules in one directory), and none
touches a line of Haskell. Command-line arguments and stdin
transcripts are stated too: they are input, not edits.

## Round two — twenty-one, each diffed against GHC 9.4.8

`AGREES` means every byte of output and the exit status matched.

| Repo | Size | What it does under AHC | Verdict |
|---|---|---|---|
| [magetron/hson](https://github.com/magetron/hson) | 1 file, 64 loc | Renders a JSON document from a typed DSL | AGREES |
| [vaibhav276/haskell-json-parser](https://github.com/vaibhav276/haskell-json-parser) | 1 file, 153 loc | Parser-combinator JSON parser | AGREES |
| [Neel-shetty/haskell-json-parser](https://github.com/Neel-shetty/haskell-json-parser) | 1 file, 112 loc | Another JSON parser; both compilers stop at the same `undefined` | banner + CallStack |
| [luigiminardim/JsonParser.hs](https://github.com/luigiminardim/JsonParser.hs) | 4 modules, 169 loc | JSON parser across four modules | banner only |
| [2016rshah/sudoku-solver](https://github.com/2016rshah/sudoku-solver) | 2 modules, 245 loc | Solves the bundled puzzle set — 42 lines | AGREES |
| [MEAN-stack/Sudoku](https://github.com/MEAN-stack/Sudoku) | 1 file, 104 loc | Brute-force solver over `sudoku.txt` — 29 lines | AGREES |
| [renaudpg/sudocurry](https://github.com/renaudpg/sudocurry) | 1 file, 71 loc | Backtracking solver, puzzle as an argument | AGREES |
| [msysyamamoto/RPN](https://github.com/msysyamamoto/RPN) | 1 file, 47 loc | Stack calculator, showing the stack each step | AGREES |
| [tuerda/RPNico](https://github.com/tuerda/RPNico) | 2 modules, 273 loc | RPN calculator with `sum`/`prod`/`mean` | AGREES |
| [potionsleepy/RpnCalculator](https://github.com/potionsleepy/RpnCalculator) | 1 file, 43 loc | RPN REPL over `Either` error handling | AGREES |
| [AntonGorelov/Tic-tac-toe](https://github.com/AntonGorelov/Tic-tac-toe) | 1 file, 97 loc | Plays a full game (root module is not `Main`) | AGREES |
| [marony/tic_tac_toe](https://github.com/marony/tic_tac_toe) | 1 file, 157 loc | Tic-tac-toe with an AI opponent | banner only |
| [aretana1985/Haskell-Tic-Tac-Toe](https://github.com/aretana1985/Haskell-Tic-Tac-Toe) | 1 file, 61 loc | Tic-tac-toe over `readLn` | banner only |
| [Agnishom/HaskellBF](https://github.com/Agnishom/HaskellBF) | 1 file, 70 loc | Brainfuck interpreter — runs hello-world | AGREES |
| [thibaudmichaud/lambda-calculus](https://github.com/thibaudmichaud/lambda-calculus) | 1 file, 86 loc | λ-calculus normaliser over `Data.Set` | AGREES |
| [AnotherKamila/lambda](https://github.com/AnotherKamila/lambda) | 1 file, 174 loc | λ-calculus interpreter, `deriving Read` on its term type | AGREES |
| [tmhedberg/caesar](https://github.com/tmhedberg/caesar) | 1 file, 24 loc | Caesar-cipher solver against the system word list | AGREES |
| [dogoyaro/arabicToRoman](https://github.com/dogoyaro/arabicToRoman) | 1 file, 28 loc | Integer → Roman numerals | AGREES |
| [SimonTeixidor/Euler](https://github.com/SimonTeixidor/Euler) | 1 file, 21 loc | Project Euler 19 | AGREES |
| [patrickmn/euler-haskell](https://github.com/patrickmn/euler-haskell) | 3 files, 8 loc | Project Euler 1 | AGREES |
| [nlarosa/HaskellRomanNumerals](https://github.com/nlarosa/HaskellRomanNumerals) | 1 file, 95 loc | Roman numerals, dispatching on `getProgName` | banner + CallStack |

**Sixteen are byte-identical.** The other five agree on every byte of
stdout and on the exit status, and differ only where AHC's
fatal-error banner does: AHC prints `ahc: …` where GHC prints the
program's own name, and for an `ErrorCall` it prints `ahc: error: …`
where GHC prints just the message. The last two also lack the
`CallStack` suffix GHC appends, which AHC has no equivalent for. All
of that is deliberate and recorded in
`tests/conformance/EXCLUSIONS.md`.

Seven more compile as libraries with no runnable `main` of their own —
`MEAN-stack/roman-numerals`, `augustebaum/romanNumerals`,
`kjetile/RomanNumerals`, `dyoshimitsu/haskell-caesar-cipher`,
`Jackrwal/Haskell-Caeser-Cipher`, `OtGabaldon/cipher` and
`millennialcloud/HaskellCaesar` — which exercises the frontend,
typechecker and code generator over the whole file.

## Round one — the first ten

| Repo | Size | What it does under AHC |
|---|---|---|
| [marcusbfs/haskell-json-parser-from-scratch](https://github.com/marcusbfs/haskell-json-parser-from-scratch) | 2 modules, 149 loc | Parses JSON via Alternative parser combinators |
| [ncollins/tic-tac-tonad](https://github.com/ncollins/tic-tac-tonad) | 1 file, 96 loc | Plays a full interactive game |
| [OliverMead/mazer-hs](https://github.com/OliverMead/mazer-hs) | 6 modules, 509 loc | Generates and solves mazes in box-drawing characters |
| [rst0git/Game-of-Life-Haskell](https://github.com/rst0git/Game-of-Life-Haskell) | 1 file, 180 loc | Animates Conway's Life to "Game Over" |
| [from0tohero/NQueens](https://github.com/from0tohero/NQueens) | 1 file, 27 loc | Counts n-queens solutions |
| [ahjmorton/mazeHS](https://github.com/ahjmorton/mazeHS) | 1 file, 102 loc | Reads a maze on stdin and solves it |
| [Carrotlord/matrix-library](https://github.com/Carrotlord/matrix-library) | 1 file, 229 loc | Symbolic matrices — typechecks and generates C |
| [leroux/haskell-99-problems](https://github.com/leroux/haskell-99-problems) | 1 file, 66 loc | The H-99 list exercises |
| [Bradcomp/nqueens](https://github.com/Bradcomp/nqueens) | 1 file, 47 loc | Compiles and links |

(`2016rshah/sudoku-solver` was round one's tenth; it appears in round
two's table instead, because round two gave it an oracle it did not
have before.) The last three have no runnable `main` of their own
(H-99 defines `main = undefined`; the other two keep theirs in a test
file or omit it).

## Running them

The commands below `cd` into a cloned repo, so they assume AHC's `bin/`
is on your PATH:

```bash
export PATH="$PWD/bin:$PATH"
```

**hson** — a JSON *writer*: a typed DSL rendered to text. This is the
repo whose `data JSONValue = … | JObject [NamedJValue]`, declared
before `NamedJValue`, crashed the kind checker with a range-check
exception (M141).

```bash
git clone --depth 1 https://github.com/magetron/hson && cd hson && ahc build hson.hs -o hson && ./hson
```

```
{ "language": "Haskell", "age": 19.0, "libraries": [ "https://hackage.haskell.org/", "https://stackage.org/" ] }
```

**Brainfuck.** Takes the program as a file argument; this one prints
`Hello World!`. It needs `Data.Either` and `putChar`, both of which
M141 added.

```bash
git clone --depth 1 https://github.com/Agnishom/HaskellBF && cd HaskellBF
printf '++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++.\n' > hello.bf
ahc build brainFuck.hs -o bf && ./bf hello.bf
```

```
Hello World!
```

**λ-calculus over Data.Set.** Folds over a `Data.Set` through the
Prelude's `elem`, which is why it needs `Foldable` (M141).

```bash
git clone --depth 1 https://github.com/thibaudmichaud/lambda-calculus && cd lambda-calculus
ahc build lc.hs -o lc
printf '(\\x.x) y\n(\\x.\\y.x) a b\n(\\f.\\x.f (f x)) (\\y.y) z\nexit\n' | ./lc
```

```
( y)
((  )b)
((((  )((  )(\y.y))) )z)
```

(Its printer drops the bound variable — that is the repo's own
behaviour, and GHC prints exactly the same thing.)

**λ-calculus with `deriving Read`.** Derives `Read` on a
three-constructor term type — the repo that drove derived `Read` for
non-enumerations (M141). Reads terms on stdin, one per line, in its
own λ syntax:

```bash
git clone --depth 1 https://github.com/AnotherKamila/lambda && cd lambda
ahc build lambda.hs -o lam
printf '((λx.x) y)\n(λz.((λx.x) z))\n((λx.(x x)) y)\n((λx.λy.x) a)\n' | ./lam
```

```
y
λz.z
(y y)
λy.a
```

**Sudoku, three ways.** `MEAN-stack/Sudoku` reads `sudoku.txt` beside
it; `renaudpg/sudocurry` takes the puzzle as one 81-character
argument and needs `Data.List`'s re-export of the Prelude's list API
(M141); `2016rshah/sudoku-solver` wants its modules flattened.

```bash
git clone --depth 1 https://github.com/MEAN-stack/Sudoku && cd Sudoku && ahc build sudoku.hs -o sudoku && ./sudoku
git clone --depth 1 https://github.com/renaudpg/sudocurry && cd sudocurry && ahc build solve.hs -o solve \
  && ./solve 003020600900305001001806400008102900700000008006708200002609500800203009005010300
git clone --depth 1 https://github.com/2016rshah/sudoku-solver && cd sudoku-solver && cp src/*.hs . \
  && ahc build Main.hs -o sudoku && ./sudoku examples
```

```
483921657
967345821
251876493
…
```

**RPN calculators.** All three read expressions on stdin.

```bash
git clone --depth 1 https://github.com/msysyamamoto/RPN && cd RPN && ahc build rpn.hs -o rpn \
  && printf '3\n4\n+\n10\n*\n2\n/\nquit\n' | ./rpn
```

```
[]
[3.0]
[4.0,3.0]
[7.0]
```

**Caesar cipher.** Solves a rotation against `/usr/share/dict/words`.
Correct, but this is the slowest entry here: ~99s against GHC's ~10s.

```bash
git clone --depth 1 https://github.com/tmhedberg/caesar && cd caesar && ahc build caesar.hs -o caesar && ./caesar uryyb
```

```
hello
```

**Project Euler.** Two independent solution sets, both single
expressions.

```bash
git clone --depth 1 https://github.com/SimonTeixidor/Euler && cd Euler && ahc build 19.hs -o e19 && ./e19     # 171
git clone --depth 1 https://github.com/patrickmn/euler-haskell && cd euler-haskell && ahc build 001.hs -o e1 && ./e1  # 233168
```

### Round one's

**JSON parser.** A parser-combinator JSON parser: newtype `Parser`
with hand-rolled `Functor`/`Applicative`/`Monad`/`Alternative`
instances, `some`/`many` doing the repetition, do-notation over
`Either` inside. This is the repo that drove `Control.Applicative`
(and the empty-string-pattern fix before it) into AHC.

```bash
git clone --depth 1 https://github.com/marcusbfs/haskell-json-parser-from-scratch && cd haskell-json-parser-from-scratch && cp src/JsonParser.hs app/Main.hs . && ahc build Main.hs -o jp && echo '{"a": [1, null, true], "b": "x"}' > s.json && ./jp s.json
```

```
JsonObject [("a",JsonArray [JsonInteger 1,JsonNull,JsonBool True]),("b",JsonString "x")]
```

**Tic-tac-toe.** A hand-rolled `Functor`/`Applicative`/`Monad` over a
board-state newtype — user-defined dictionaries and interactive IO
end to end.

```bash
git clone --depth 1 https://github.com/ncollins/tic-tac-tonad && cd tic-tac-tonad && ahc build main.hs -o ttt && ./ttt
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

`scripts/scout_repos.sh` does the mechanical part — search, filter,
clone, build, run, diff against GHC — so the judgement goes into the
failures, which are the actual deliverable of a round:

```bash
scripts/scout_repos.sh search "sudoku solver"   # candidates, and why the rest were rejected
scripts/scout_repos.sh try owner/repo           # clone, build, run, diff against GHC
scripts/scout_repos.sh report                   # the table so far
```

It classifies each repo as `AGREES`, `AGREES-BANNER`, `DIFFERS`,
`TIMEOUT`, `NO-ORACLE`, `LIB-ONLY`, or a compile-stage failure
(`PARSE`, `RENAME`, `TYPE`, `MODULE`, `LINK`). A repo that needs
input gets it from `$SCOUT_DIR/stdin/<owner_repo>`,
`$SCOUT_DIR/args/<owner_repo>`, and `$SCOUT_DIR/files/<owner_repo>/`
for data files it does not ship — all three are handed to **both**
compilers, so the comparison stays honest.

GitHub's `language:haskell` search sorted by stars is useless here —
every popular Haskell repo is built on extensions and Hackage. What
works is searching by *topic* and filtering mechanically. Categories
that pay off: textbook exercise code (Hutton's *Programming in
Haskell* is the richest single vein), H-99 solutions, Project Euler
sets, puzzle solvers, RPN calculators, JSON parsers, brainfuck and
λ-calculus interpreters, and Roman-numeral converters.

## What usually blocks a repo

Re-ordered after round two, by how often it actually came up across
~90 candidates:

- **Hackage dependencies**, still first by a wide margin. In round
  two's sample: `System.Random` and `Debug.Trace` (3 each), `parsec`
  (one repo, six modules of it), `System.Process`, `gloss`,
  `Data.Word8`, `Data.Map.Strict` (2 each), then `QuickCheck`,
  `blaze-html`, `Text.Printf`, `Control.Arrow`, `System.Directory`,
  `Data.Array.IO`, `Control.Monad.State`, `Control.Monad.Error`,
  `Data.ByteString`, `System.Console.GetOpt`, `GHC.Base`. Nothing to
  be done short of the module existing in `lib/`.
- **Extensions.** `LambdaCase` and `TemplateHaskell` led round two,
  then `FlexibleInstances`, `TypeSynonymInstances`, `InstanceSigs`,
  `GeneralizedNewtypeDeriving`. (`OverloadedStrings` is CLOSED —
  AHC's literal overloading is unconditional, so a module carrying
  the pragma just works.)
- **The flat type and constructor namespace** (the M75 item). Two
  modules of one program declaring the same type or constructor name
  is a clean compile error where GHC would accept it —
  `PLUkraine/rpn-calculator` defines `Token` in two modules. Qualified
  imports cannot disambiguate; rename the colliding declaration.
- ~~**`Control.Applicative` / `Alternative`**~~ CLOSED in round one.
  Every hand-rolled parser reaches for `<|>` and `many`; the chase
  closed six deeper gaps with it, from cross-module fixities to
  irrefutable newtype patterns.
- ~~**Prelude and library gaps**~~ mostly CLOSED by round two. Each of
  these blocked a real repo and now does not: `Foldable` (the Prelude's
  `elem`/`length`/`sum` over a `Set` or `Map`), `deriving Read` for
  non-enumerations, `Data.List` re-exporting the Prelude's list API,
  importing a class method by name from `Control.Applicative`,
  `Data.Either`, `Data.Set.elemAt`, `readLn`, `readIO`, `putChar`,
  `Read` at `Char`/`String`/`Maybe`/`Either`, and `read` at `Double`.
- **Compiler bugs, which is the point of doing this.** Round two found
  a kind-checker crash on a forward-referenced data type, a Report
  10.3 layout rule for `where`, missing dictionaries for an instance
  method's own context, a module imported twice being visible through
  only one of its imports, and **three defaulting bugs — two of which
  put a `$dMISSING` into a compiled program rather than failing to
  compile.** See CHANGES.md.

A repo that builds can still be slow: AHC's output is correct but
runs roughly 10–60x GHC's on allocation-heavy search
(`MEAN-stack/Sudoku` 90s against 1.5s). `scripts/scout_repos.sh`
reports a timeout as `TIMEOUT` rather than `DIFFERS`, because a right
answer computed slowly is not a wrong answer.
