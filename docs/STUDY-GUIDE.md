# A study guide: understanding AHC from the ground up

This is the guided path through the project for someone who has
built languages before — a DSL or two, a lexer, a recursive-descent
parser, maybe a tree-walking interpreter — and now wants to
understand a *complete compiler for a real language*. It tells you
what order to read things in, what to run at each step, and how to
know you have actually understood a stage before moving on. The
[MANUAL](MANUAL.md) is the theory companion (every design decision,
written for a reader who is not a compiler engineer); this guide is
the curriculum through it and the source.

Two facts shape everything below.

**First: your DSL experience covers about a third of this project.**
Lexing, parsing, ASTs, and name resolution will feel familiar — AHC
just does them at industrial scale and in Ada. The genuinely new
territory is what a DSL never forces you to build: the layout
algorithm (Haskell's indentation rules as a formal state machine),
Hindley-Milner type inference, type classes compiled into
dictionary passing, and — the biggest single idea — *call-by-need
graph reduction*, where "running the program" means rewriting a
heap graph of unevaluated thunks. Budget your attention
accordingly: skim the familiar, camp on the new.

**Second: this compiler narrates itself.** Every pipeline stage has
a CLI command that dumps its output, so you never have to imagine
what a stage produces — you look:

    echo 'main = print (map (+ 1) [1, 2, 3])' > /tmp/t.hs
    ./bin/ahc lex --layout /tmp/t.hs   # tokens, with invisible {;} shown
    ./bin/ahc parse /tmp/t.hs          # the AST, fixity-resolved
    ./bin/ahc core  /tmp/t.hs          # desugared, typed, dictionary-passing Core
    ./bin/ahc check /tmp/t.hs          # every top-level's inferred type
    ./bin/ahc emit  /tmp/t.hs /tmp/t   # the generated C, in /tmp/t.build/
    ./bin/ahc repl                     # all of it, interactively

The single most effective study technique for this codebase:
**write a five-line program, dump every stage, and account for
every line of output**. When a line surprises you, that surprise is
the day's lesson. Do this once per station below.

## 0. Setup (one sitting)

Build it, run the suite, and skim the two orientation documents:

    alr build --validation        # contracts on - the development build
    scripts/run_conformance.sh    # 69 programs, byte-identical to GHC

Read [README](../README.md) top to bottom, then MANUAL chapters 1-2
(orientation; why Ada and what Design-by-Contract buys). Don't read
further into the MANUAL yet. Skim [CHANGES.md](../CHANGES.md)
headers only — v1.0 through v1.3 — to get the arc: architecture,
polish, verification tooling.

## 1. Reading Ada here (before the first source file)

You don't need to know Ada; you need five house idioms, and then
the code reads like verbose ML. Keep this list beside you:

1. **Arenas and typed ids, not pointers.** Every tree (tokens, AST,
   Core, types) lives in a growable vector; a node "reference" is a
   typed integer id (`Real_Expr_Id`, `Real_Var_Id`). `M.Node (E)`
   fetches; `M.Add (...)` appends and returns the new id. There is
   no aliasing and no null — an id is always valid, and distinct id
   TYPES can't be mixed up (the type system rejects passing an
   expression id where a pattern id is expected).
2. **Variant records are sum types.** `type Expr_Node (Kind :
   Expr_Kind := Var_C) is record ... case Kind is ...` is exactly a
   datatype with constructors; `case N.Kind is when App_C => ...`
   is pattern matching. Aggregates like `(Kind => App_C, Fun => F,
   Arg => A, ...)` are constructor applications.
3. **Contracts are executable comments.** `with Pre => ...` /
   `Post => ...` on a subprogram state its interface obligations
   and are CHECKED in the validation build. When you wonder "can
   this input happen?", the contract is the authoritative answer.
4. **State is threaded `in out`, never global.** A stage is a
   package with one entry procedure taking the arenas and a
   diagnostic bag `in out`. Reading a stage = reading its entry
   procedure top to bottom.
5. **`Vectors` and `Hashed_Maps` are the only containers.** If you
   can read `std::vector`/`unordered_map` code, you can read this.

MANUAL chapter 2 explains *why*; you now know *how* to read it.

## 2. The curriculum: eight stations

Each station names the theory (MANUAL chapter), the code (with line
counts, so you can budget), an experiment, and a test question.
The stations follow the pipeline, which is also dependency order —
nothing forward-references. A station is an evening or two; the
starred ones (★) are the conceptual heavy lifts and deserve twice
that.

### Station 1 — tokens and the lexer (familiar ground, new house)

- **Read:** MANUAL ch. 4 (names/interning); `src/ahc-lexer.adb`
  (793 lines), skimming — you have written this before. What to
  study instead of the scanning: the `Name_Table` (every identifier
  interned once, compared as integers) and how errors become
  diagnostics with source spans rather than exceptions.
- **Do:** `./bin/ahc lex` on a file with a string escape, a
  qualified name (`Data.Map.empty`), and an operator. Find where
  `{-# ... #-}` pragmas are recorded but not tokenized (the
  contracts extension hangs off this).
- **You understand it when** you can say why the lexer records
  pragma SPANS instead of pragma TOKENS.

### Station 2 — layout ★ (the first genuinely Haskell thing)

- **Read:** MANUAL ch. 3 (reading Haskell — yes, read it even
  though you know Haskell-ish syntax; it defines the vocabulary the
  rest of the book uses); then the layout part of ch. 3 and
  `src/ahc-layout.adb` — only 262 lines, but it implements Report
  §10.3's `L` function, the algorithm that turns indentation into
  invisible `{`, `;`, `}`.
- **Do:** write the same function three ways (all on one line with
  explicit braces; laid out with indentation; a `where` block) and
  diff the `ahc lex --layout` output — it should converge. Then
  read the "Layout vs. lookahead" and "stolen body" war stories in
  ch. 19: this tiny file produced two of the project's five
  fuzzer/REPL-found bugs.
- **You understand it when** you can explain why the layout
  algorithm cannot be a pure function of the token stream — why it
  needs the PARSER to tell it about parse errors (the
  `parse-error(t)` rule), and why that coupling made lookahead
  dangerous.

### Station 3 — parser, AST, fixity (scale, not novelty)

- **Read:** `src/ahc-syntax.ads` first (the AST as data — always
  read the types before the code that builds them), then
  `src/ahc-parser.adb` (2280 lines) *selectively*: pick three
  productions you find interesting (`case`, record syntax, operator
  sections) and trace only those. Then `src/ahc-fixity.adb` (517
  lines): operator expressions parse FLAT and are re-associated
  afterward against declared precedences — a clean separable
  algorithm worth reading whole.
- **Do:** `ahc parse` a nest of operators (`1 + 2 * 3 ^ 4 ^ 5`) and
  confirm the tree matches Haskell's fixities; declare your own
  `infixr 2` operator and watch the tree change.
- **You understand it when** you can say why fixity resolution is a
  separate pass instead of precedence-climbing inside the parser.

### Station 4 — names and modules (where DSL intuition breaks)

- **Read:** the rest of MANUAL ch. 4; `src/ahc-rename.adb` (2019
  lines) — the entry points `Mod_Find_TyCon` / `Lookup_Value` and
  the import-view construction (`Filter`), not every line. The key
  design: per-module *views* over interfaces, a flat global
  environment for speed, and an immutable Base snapshot of the
  Prelude — and the "stolen body" war story is what happens when
  something consults the mutable map where it needed the snapshot.
- **Do:** write a two-module program (`A.hs` + `Main.hs`); use
  `import qualified`, `hiding`, an alias. Break it three ways
  (unexported name, ambiguous import, `import Prelude ()` then
  using `putStrLn`) and read the errors.
- **You understand it when** you can explain the resolution order
  for an unqualified name (own module, unqualified imports,
  Prelude) and where `import Prelude hiding (map)` interrupts it.

### Station 5 — Core and the desugarer ★ (the compiler's fulcrum)

- **Read:** MANUAL ch. 7; `src/ahc-core.ads` (the eight-shape IR —
  this half-hour of reading pays off more than any other in the
  project, because EVERY later stage consumes this type); then
  `src/ahc-desugar.adb` (1659 lines) with the pattern-match
  compiler as the centerpiece: multi-equation definitions and
  nested patterns become decision trees of flat `case`, with
  fall-through as LET-BOUND JOIN POINTS. The tree invariant —
  "Core is a tree; every reference is a fresh node" — has its own
  war story (ch. 19, "the shared-node evidence bug"); read it here.
- **Do:** `ahc core` on a two-equation function with nested
  patterns and guards; account for every `$fail`/`$k` binding in
  the output. Then desugar a list comprehension and a `do` block by
  hand and check yourself against the dump.
- **You understand it when** you can explain what breaks if two
  case alternatives SHARE a failure-continuation node instead of
  referencing a let-bound variable.

### Station 6 — types and classes ★★ (the deepest water)

- **Read:** MANUAL ch. 5 then ch. 6, slowly — they were written
  precisely for this station. Then `src/ahc-typechecker.adb` (1733
  lines) in three passes: (1) unification and the occurs check —
  note the `Pre`/`Post` contracts here are the PRD's marquee
  verification claims; (2) generalization, binding groups, the
  monomorphism restriction; (3) skip the rest until after ch. 6,
  then read `src/ahc-elaborate.adb` (625 lines): type classes
  become dictionary RECORDS, class methods become field selectors,
  and a constrained function grows extra dictionary parameters.
- **Do:** FIRST read `examples/hm/Main.hs` - Algorithm W in a
  page (a miniature of this station's machinery, compiled by it,
  with the unifier's obligations stated as contracts); run it on
  its tests and predict each answer before looking. Then
  `ahc check` on `let`-polymorphism, on a function the MR
  restricts, on an ambiguous `show . read`. Then the single most
  instructive dump in the project: `ahc core` on
  `f x y = x == y && x < y` — find the ONE dictionary parameter,
  the two selector applications, and say why there is one
  dictionary, not two.
- **You understand it when** the sentence "a class is a record
  type, an instance is a value of it, a constraint is an implicit
  parameter" feels concrete, and you can predict which of the
  `$d...` globals in a core dump is applied where.

### Station 7 — laziness and the runtime ★★ (read C before codegen)

- **Read:** MANUAL ch. 8 (laziness, honestly explained) and ch. 9;
  then — deliberately out of pipeline order —
  `runtime/ahc_rts.c` (1828 lines) BEFORE the code generator. The
  runtime is the semantics: node tags (thunk, function, con, int),
  `ahc_eval`'s update-in-place loop (a thunk is computed once and
  overwritten with its value — that is what "call-by-need" means
  mechanically), curried application, and IO as world-passing
  functions. With that mental machine installed,
  `src/ahc-codegen.adb` (859 lines) becomes almost obvious: each
  Core expression compiles to calls that BUILD graph.
- **Do:** `ahc emit` hello-world and read the generated C for
  `main` end to end (it is short). Then emit
  `main = print (take 3 [1 ..])` and find where the infinite list
  lives — and why the program terminates anyway. Read the
  "stack-overflow-after-success" war story.
- **You understand it when** you can trace, on paper, the heap
  states of `let xs = 1 : xs in take 2 xs` — and say which thunks
  are ever forced.

### Station 8 — everything above the line

Now the pipeline is yours, and the rest is applications of it, each
readable in an afternoon, in any order:

- **The optimizer** (`src/ahc-optimizer.adb`, 544 lines; MANUAL
  ch. 15): five transforms, each argued correct against sharing and
  strictness. Read alongside `scripts/run_bench.sh` — every
  transform shipped with a measurement.
- **Refinements and contracts** (`src/ahc-refine.adb`, 640;
  `src/ahc-discharge.adb`, 601; MANUAL ch. 14 + the two design
  notes): the Ada extension. Discharge is a bonus station: a
  complete constant EVALUATOR for Core in 600 lines — a miniature
  of the interpreter you have already written for a DSL, aimed at
  proofs instead of execution. Read `examples/cal/Main.hs` first,
  from the *user's* side: a calendar that declares every bound and
  every relation and writes no validation code at all, so each
  failure message you can provoke from it names a check one of
  these two files inserted.
- **The fuzzer** (`tests/fuzz/Gen.hs` — Haskell, not Ada!) and
  **the REPL** (`src/ahc-repl.adb`, 524 lines +
  `docs/repl-design-note.md`): the verification tooling. Both are
  studies in *reuse* — the REPL adds no evaluator, the fuzzer
  generates only pre-verified constructs.
- **The stdlib** (`prelude/Prelude.hs`, 403 lines, and `lib/`):
  ordinary Haskell compiled by the compiler itself. Reading
  `Prelude.hs` after station 6 is quietly satisfying: you now know
  exactly what the compiler does to every line of it.

## 3. How the project was CONSTRUCTED (the meta-level)

You asked how it is built, not just what it contains. Five rules
explain most decisions, and they are visible in the artifacts:

1. **GHC is the oracle; never grade your own homework.** Expected
   outputs are whatever GHC 9.4.8 prints, byte for byte
   (`scripts/run_conformance.sh`). MANUAL ch. 16 argues why this
   single decision outranks every other testing choice.
2. **Twenty harnesses, layered.** Goldens catch *change*, the
   oracle catches *wrongness*, differentials catch front-end drift,
   the fuzzer catches the unknown unknowns. Read the table in
   ch. 16; then read ONE golden file next to its source.
3. **Honesty over coverage.** What AHC does not do is a documented
   row in `tests/conformance/EXCLUSIONS.md`, never a silent gap —
   and rows get struck (foldl', handles) rather than reworded.
4. **Milestones, each independently shippable.** 82 milestones
   from M0, every one landing with the full suite green. The best
   textbook in the repo is `git log --oneline --reverse` read
   alongside CHANGES.md from the bottom up: you can watch the
   architecture appear in the same order this guide teaches it.
5. **Measurement before machinery.** The optimizer exists because
   a benchmark justified each transform; case-of-case was designed
   and then NOT shipped when the profile said no. The bench
   harness was hardened against noise before the first transform
   was written.

## 4. An exercise ladder

Understanding is tested by change. In rising order of depth, each
exercise touching one more stage than the last — do them with the
full suite green afterward, per house law:

1. **Prelude:** add `subsequencesOfSize` or similar to
   `lib/Data/List.hs`, with a conformance test oracled against GHC.
2. **Lexer/parser:** make the parser reject something it currently
   mis-accepts, or improve one error message; pin it in a golden.
3. **Fuzzer:** add a generator production for a construct the menu
   lacks (first verify it byte-identical on both compilers - the
   menu rule). Run 300 seeds.
4. **Runtime:** add a primitive (`hSeek`? `cpuTime`?) end to end:
   C function, extern, wiring, scheme, source wrapper, tests. M78's
   commit is the template.
5. **Types:** allow `divMod` (currently absent - the fuzzer menu
   note in Gen.hs says so): tower method, dict entries, prim,
   conformance test.
6. **Capstone:** pick any EXCLUSIONS row and either implement it or
   write the design note explaining its real cost. Non-nullary
   `deriving Read` and Unicode `Data.Char` are both honest
   candidates.

By exercise 4 you will know this codebase better than most
contributors ever know a compiler they use daily; after the
capstone you could have written station 8 yourself.

## 5. What to keep open while you work

| Always open | Why |
|---|---|
| `docs/MANUAL.md` ch. 20-21 | glossary + source map - the lookup tables |
| a scratch `.hs` file + the five dump commands | the microscope |
| `tests/golden/` | worked examples with pinned answers |
| MANUAL ch. 19 | when something seems needlessly careful, a war story usually explains the scar |
