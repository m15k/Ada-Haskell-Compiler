# M149 - runtime errors better than GHC's

**Status:** design approved in brainstorming, 2026-10-13; this spec is
awaiting review.
**Oracle:** GHC 9.4.8, compiled (`~/.ghcup/bin/ghc -O0`). `runghc`
renders some exceptions differently, so oracle runs use the compiled
form.
**Scope:** runtime errors only. The correctness items found in M148's
review move to M150: derived Eq/Ord through field instances,
`mapM`/`sequence` over Traversable, BangPatterns, and the small parser
gaps.

## Why

GHC's runtime errors are a well-known weakness:
- `Prelude.head: empty list` says where in `base` it failed, not in
  your program;
- `Prelude.read: no parse` does not say what it tried to parse, or as
  which type;
- `Non-exhaustive patterns in function area` does not say what value
  arrived.

AHC is behind GHC here too. Probed with one program against both
compilers:

| Failure | GHC 9.4.8 `show` (caught) | AHC v1.19.1 `show` |
|---|---|---|
| `error "boom"` | `boom` + `CallStack (from HasCallStack):` + `error, called at E.hs:11:24 in main:Main` | `boom` |
| `undefined` | `Prelude.undefined` + call stack | `Prelude.undefined` |
| `head []` | `Prelude.head: empty list` + 4 frames, the last `head, called at E.hs:13:23 in main:Main` | `Prelude.head: empty list` |
| `fromJust Nothing` | `Maybe.fromJust: Nothing` + 2 frames | `Maybe.fromJust: Nothing` |
| `[1,2,3] !! 5` | `Prelude.!!: index too large` + 3 frames | `Prelude.!!: index too large` |
| `area (Triangle 3 4)` | `E.hs:(5,1)-(6,19): Non-exhaustive patterns in function area` + newline | `non-exhaustive patterns in function` |
| `case Just 1 of Nothing -> 0` | `E.hs:19:23-60: Non-exhaustive patterns in case` + newline | `non-exhaustive case` |
| `(\(Just x) -> x) Nothing` | `E.hs:20:26-39: Non-exhaustive patterns in lambda` + newline | `lambda pattern match failed` |
| `read "x" :: Int`, `1 \`div\` 0` | `Prelude.read: no parse`, `divide by zero` | identical |

So this milestone has two goals, both driven by one mechanism, a
**site table**:

1. **Conformance:** what a program can *observe* of a runtime error
   becomes byte-identical to GHC. That covers the `show` and
   `displayException` text of a caught exception, the exception's type
   (`PatternMatchFail` exists and is raised), and the exit code.
2. **Better than GHC:** an *uncaught* error, which goes to stderr and
   which conformance never compares, prints a report. The report gives
   the location, a source snippet, the enclosing function, the value
   that failed, and what the code handles. An opt-in call trail is
   available through `ahc build --trail`.

## The boundary

| Observable by the program (must equal GHC 9.4.8) | AHC's own (stderr only) |
|---|---|
| `show` / `displayException` of every exception | the uncaught-error report's format and content |
| the exception's type and constructor | the "--> file:line:col" header, snippet, notes |
| exit codes (1 for an uncaught error, ExitCode's own) | the opt-in trail |

Library mode (`ahc_last_error`, M93) keeps its current text. The export
gate pins it.

## Unit 1 - the site table (`AHC.Sites`, new)

A **site** is a place in the source that can fail at run time:
- every pattern-match fallthrough desugar emits: function equations,
  `case`, lambda, `let`/`where` pattern bindings, irrefutable patterns,
  multi-way if, record construction with a missing field, record
  update, and empty case;
- every use of a partial Prelude entity (Unit 3);
- every use of `error`, `errorWithoutStackTrace` and `undefined`.

Each site records:
- the source file (as given on the command line, which is GHC's
  convention), the start and end line and column, and the module name;
- the enclosing top-level binding's name;
- its kind (`function NAME`, `case`, `lambda`, `multi-way if`, a
  partial-function name, ...);
- for a pattern site, the constructors the alternatives handle, as
  `DataCon_Id`s;
- the source lines the site spans, at most 6, so the report needs no
  source file at run time.

`AHC.Sites` owns the table during compilation: `Add (Site) return
Site_Id`, then iterate for codegen. Site ids are dense per program, and
code refers to a site by an `Int` literal.

## Unit 2 - pattern-match failure (desugar + runtime)

Desugar's generic `Error_Call ("non-exhaustive ...")` sites become
`failMatch# site args`. `args` is the failing scrutinee: the argument
tuple for a multi-argument equation, the scrutinee for a `case`.
`failMatch#` is a new runtime primitive. It:
- raises `PatternMatchFail` (new, exported from `Control.Exception` as
  in base). Its `show` is GHC's `FILE:SPAN: Non-exhaustive patterns in
  KIND`, followed by GHC's trailing newline, with SPAN in GHC's syntax:
  `L:C1-C2` on one line, `(L1,C1)-(L2,C2)` across lines;
- records a report beside the exception (Unit 4).

The other texts (multi-way if, irrefutable and `let` patterns, missing
field, record update, empty case) are each taken from the oracle. The
plan's first task records every one of them in a conformance program.

## Unit 3 - located partial functions and `error`

Desugar rewrites a use of a Prelude entity on a fixed list into its
located variant applied to the site id. The entity is identified by the
renamer's identity, never by name, so a user's own `head` is untouched.

The list: `error`, `errorWithoutStackTrace`, `undefined`, `head`,
`tail`, `init`, `last`, `!!`, `fromJust`, `maximum`, `minimum`,
`foldr1`, `foldl1`, `cycle`, `read`, `toEnum` (enumerations), `chr`,
`succ`/`pred` at bounds, and `div`/`mod`/`quot`/`rem`/`divMod`/
`quotRem` at Int and Integer. Data.Map's partial functions (`!`,
`findMin`, ...) are in scope only where GHC's message is location-free;
the plan records the oracle text for each.

A located variant (`head'at :: Int -> [a] -> a`, unspellable by users)
behaves exactly like the original but, on failure, raises with:
- **GHC's caught text:** the message, then the `CallStack (from
  HasCallStack):` block. Its `base`-internal frames are constant
  strings recorded from GHC 9.4.8 (e.g.
  `error, called at libraries/base/GHC/List.hs:1646:3 in
  base:GHC.List`), and its last frame is the user's call site:
  `head, called at FILE:L:C in main:MODULE`.
- **the report:** the site, plus the operands: `!!`'s index and the
  list's length when it is already evaluated, `div`'s operands,
  `read`'s input (truncated to 60 characters) and its target type
  (the site records the type the typechecker resolved).

Functions that GHC 9.4.8 gives no call stack (`read`, `div`) keep GHC's
text unchanged. Only their report gains context.

An unapplied use (`map head xs`) becomes `map (head'at s) xs`, which is
still correct. A located variant passed across modules carries its
original site.

## Unit 4 - the report, the side table and the renderer (runtime)

- **Side table.** When a located failure raises, the runtime stores
  `(exception node, report)` in a small fixed-size table. Rethrowing
  keeps the same node, so the report survives `catch`/`throwIO`.
  Entries are replaced oldest-first. Sparks and green threads raise on
  several OS threads, so the table is lock-protected and TSan-gated.
  Both collectors are non-moving, so a node's address is a stable key.
  The table's entries are GC roots for as long as they live.
  - **Own collector:** the report is fully built and rooted before the
    exception node is allocated (the allocation-order invariant).
- **Constructor-name table.** Codegen emits one entry per data
  constructor: its name, arity, and whether it is infix.
- **Renderer.** It walks the failing value without ever calling
  `ahc_eval`: an unevaluated node prints as `_`. It prints:
  - constructors from the name table, at most 3 levels deep;
  - Int, Integer, Double and Char as GHC's `show` would;
  - strings as literals.

  Output is capped at 60 characters, ending `...` when cut. Records
  print positionally (`R 1 _`), not as record syntax. The report can
  therefore never diverge or raise.
- **Uncaught printer.** `exc_uncaught` prints the report when the side
  table has one for this exception; otherwise it prints GHC's text as
  today. The format follows AHC's compile-time diagnostics:

```
ahc: runtime error: pattern match failure
  --> Main.hs:5:1
   |
 5 | area (Circle r) = pi * r * r
 6 | area (Square s) = s * s
   | ^^^^ no equation matches `Triangle 3.0 4.0`
   = note: `area` handles Circle, Square
   = in: area
```

  The headline names the failure kind: "pattern match failure", "empty
  list", "index out of range", "no parse", "divide by zero", "error
  called", and so on. The exit code stays 1.

  The `<<loop>>` and stack-overflow messages (runtime-detected, not
  sited) gain the binding's name where the runtime knows it. The
  self-loop check knows the thunk's binder when codegen labels it. The
  plan decides whether stack overflow can name the deepest function;
  if it cannot, its message stays as it is.

## Unit 5 - the opt-in trail (`ahc build --trail`)

With `--trail`, codegen emits, at entry to every function (top-level
and local), a push of the function's id into a 16-entry per-OS-thread
ring buffer, plus a function-name table. The uncaught report then adds:

```
   = most recent evaluations (newest first): area, total, main
```

It is labelled as evaluation order, because under laziness that is
what it is. Without the flag no trail code or table is emitted. The
build test proves this: the generated C contains no trail calls.

## Error handling

- A report that cannot be built (allocation fails while erroring)
  falls back to GHC's text alone. An error report must never mask the
  error.
- A site whose file is no longer readable is not a problem: the
  snippet was embedded at compile time.
- `--trail` combined with `--lib` emits the trail, and the C caller's
  `ahc_last_error` stays GHC's text.

## Gates

- **Conformance (the oracle half).** New programs that catch and
  `show` every failure kind above, byte-identical to compiled GHC
  9.4.8:
  - errors raised from a second module (`main:Mod`);
  - a user's own `head` shadowing the Prelude's, which must stay
    unlocated;
  - a located function passed unapplied;
  - `PatternMatchFail` caught by type.
- **Exec (the report half).** Goldens for the uncaught report of each
  failure kind. The existing exec goldens that print `ahc: error: ...`
  are regenerated, and each diff is reviewed as an intended change.
- **No-forcing guarantee.** An exec test whose failing value holds
  `undefined`, an infinite list and an unevaluated field. The report
  prints `_` and terminates.
- **Trail.** An exec test with `--trail`. The build test checks that
  there is no trail code without the flag.
- **Library mode.** `run_export.sh` stays green, and `ahc_last_error`
  text is unchanged.
- **Bench.** `run_bench.sh` without `--trail` stays within 2% of
  v1.19.1. The `--trail` overhead is recorded.
- **Goldens.** Core goldens change where desugar now emits
  `failMatch#` and located variants. The diff must be renumber-only
  plus those intended changes, and is regenerated on both builds.
- **Milestone gate.** Full suites in both GC modes, the own soak with
  `AHC_OWN_VERIFY=1`, TSan (the side table), fuzz 300, and ubuntu CI
  green.

## Out of scope

- The M150 correctness items: derived Eq/Ord through instances,
  Traversable `mapM`/`sequence`, BangPatterns, and the parser gaps.
- Full `HasCallStack` as a user-visible constraint. Only the Prelude
  list above is located.
- `Debug.Trace`-style live tracing, colour, and machine-readable
  (JSON) reports.
- Locating partial functions of `lib/` modules beyond those listed.
