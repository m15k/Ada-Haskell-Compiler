# mini-lisp — the AHC dogfood program

A Scheme-flavored Lisp interpreter written in Haskell 2010 and
compiled by AHC itself. It exists to prove the compiler on a real
multi-module program — and it earned its keep on day one (see
"War stories" in `docs/MANUAL.md`: its first compile found a real
cross-module bug no test had ever hit).

The same source runs under GHC, and must behave **byte-identically**
under both compilers — that is the test (`scripts/run_examples.sh`,
goldens regenerated from GHC with `--oracle`).

## Build and run

```sh
scripts/ahc-build.sh examples/lisp/Main.hs examples/lisp/minilisp
./examples/lisp/minilisp                        # REPL (Ctrl-D exits)
./examples/lisp/minilisp examples/lisp/tests/programs.scm   # batch
```

Both modes print the value of every top-level expression;
definitions are silent. A REPL error keeps the session and its
definitions.

## The language

- **Numeric tower**: `Integer` (arbitrary precision — `(fact 25)`
  just works) < exact `Rational` (`(/ 1 3)` is `1/3`; `(+ 1/2 1/3)`
  is `5/6`) < `Double`. Exact results with denominator 1 demote to
  integers; any Double operand makes the result Double.
- **Special forms**: `quote` (and `'x`), `if`, `define` (both
  forms), `lambda`, `let`, `let*`, `letrec`, `begin`, `cond`
  (with `else`), `and`, `or`.
- **Semantics**: closures capture their lexical locals; free
  variables resolve against the global environment at call time, so
  top-level mutual recursion and REPL redefinition work with pure
  environments (no mutation anywhere). `letrec` restricts
  right-hand sides to lambdas and ties the recursive knot with
  Haskell's laziness.
- **Primitives**: arithmetic (`+ - * /`, `quotient`, `remainder`,
  `modulo`, `expt`, `sqrt`, `abs`, `min`, `max`, `numerator`,
  `denominator`, `exact->inexact`), chained comparisons
  (`= < > <= >=`), predicates, lists (`car`, `cdr`, `cons`, `list`,
  `append`, `length`, `reverse`), `eq?`/`equal?`, strings,
  `apply`, `error`.
- **Boot prelude, written in mini-lisp**: `map`, `filter`,
  `fold-left`, `fold-right`, `assoc`, `member`, `range`, `sum`,
  `cadr`, `caddr` — evaluated at startup from source embedded in
  `Main.hs`.
- Proper lists only (no dotted pairs), no mutation (`set!`), no
  IO primitives — output is the REPL printing values. Division by
  zero is an error even at Double (no `Infinity`), so output never
  depends on IEEE corner cases.

## Structure

Environments are `Data.Map` (AHC's own weight-balanced tree from
`lib/`; GHC's containers when run under GHC) - the port that
motivated building the library, and whose first compile found two
compiler bugs (qualified type names; constraints from
multi-equation where-helpers).

| Module | Role |
|---|---|
| `Lisp/Val.hs` | `Value` (code *is* data), environments, printers |
| `Lisp/Parser.hs` | tokenizer + reader: text -> `[Value]` |
| `Lisp/Eval.hs` | evaluator, special forms, primitives, numeric tower |
| `Main.hs` | REPL / batch driver, boot prelude |

The evaluator is pure — `Either String Value` threaded explicitly
(AHC's Monad instances cover IO/[]/Maybe, not Either, and the
explicit style runs identically under GHC). IO happens only at the
REPL boundary, using `isEOF` — a primitive added to AHC's
`System.IO` the day this REPL needed it.
