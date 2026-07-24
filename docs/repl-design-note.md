# Design note: `ahc repl`

**Status:** IMPLEMENTED (M79 designs, M80 builds). See the MANUAL's
CLI chapter for the user-facing summary and `tests/repl/` for the
pinned transcripts.

An interactive read-eval-print loop for AHC. The interesting design
question is not the loop - it is *what executes the code*, because
AHC has exactly one evaluator: the compiled-C graph-reduction
runtime. Everything follows from refusing to grow a second one.

## 1. The architecture: compile-and-run, honestly

Three ways a compiler grows a REPL:

- **A Core interpreter** inside the compiler. Rejected: it
  duplicates the runtime's semantics in a second implementation -
  every primitive (bignums, Doubles, file handles, check_claim...)
  reimplemented in Ada and drifting from the C truth. AHC's whole
  verification story rests on there being ONE evaluator whose
  output is byte-compared against GHC; a second evaluator is a
  second thing to be wrong.
- **In-process incremental codegen** with dynamic loading
  (dlopen per entered line). Rejected for v1: sharing live heap
  state and GC roots across dynamically loaded objects is a
  genuinely hard systems problem, and the payoff is latency we do
  not need yet.
- **Compile-and-run per entry** over the M63 object cache.
  Chosen. Every entered expression becomes a real program,
  compiled by the real pipeline and executed by the real runtime.
  The REPL adds *zero* new semantics: anything it prints is
  exactly what the batch compiler would print, so every guarantee
  the conformance suite establishes carries over unchanged.

The M63 separate-compilation work is what makes this viable: the
Prelude, the stdlib, and the runtime compile once into
content-addressed objects, the session's declarations compile only
when they change, and each entered expression recompiles one tiny
module. After the first evaluation warms the cache, a line costs
two frontend passes plus one small clang invocation and a link -
interactive on a human scale (~1s), and the design note says so
rather than pretending otherwise.

## 2. The session model: two modules

Session state is two generated source files in a scratch
directory:

    Repl.hs  -- module Repl where
             -- <accumulated imports>
             -- <accumulated declarations, one entry per line>

    Main.hs  -- module Main where
             -- import Repl
             -- it = <the entered expression>
             -- main = print it        (or: main = it, for IO)

Two modules, not one, for two reasons. First, the object cache:
declarations change rarely, expressions change every line - in a
single module every entry would recompile everything, split this
way an expression recompiles only Main. Second, name hygiene: the
synthesized `main`/`it` live in Main, so a *loaded* program's
`main` is an ordinary member of Repl that never collides with the
runner (type `Repl.main` to run a loaded main - the one shadowing
corner, documented in `:help`).

Entered declarations append to Repl.hs; entered imports append to
its import block. Every candidate state is validated with an
in-pipeline `check` BEFORE it is accepted - a declaration that
does not typecheck is reported and rolled back, and the session
continues from the last good state. Errors never poison the
session.

## 3. Classifying a line

GHCi's grammar problem in miniature: is `x = 5` a declaration or
an expression? The classification, in order:

1. Blank -> ignored. `:cmd ...` -> command.
2. `import ...` -> import entry (validated like a declaration).
3. `let x = e` -> declaration `x = e` (GHCi habit, accepted).
4. A leading declaration keyword (`data`, `newtype`, `type`,
   `class`, `instance`, `infix[lr]`, a `{-#` pragma) ->
   declaration.
5. Otherwise, PARSE the line as a module body: if it parses as
   declarations, it is one (this is what makes `f x = x + 1` a
   definition while `f x` and `(+ 1) 2` fall through); if not, it
   is an expression.

Rule 5 uses the real parser, not a regex - the same commitment as
everywhere else in AHC. Multiple declarations go on one line with
explicit semicolons (`f :: Int -> Int; f x = x + 1`), which the
layout algorithm already accepts; the signature-and-binding pair
that GHCi lets you enter across two prompts is entered as one line
here (a signature alone is rejected by the normal
signature-without-binding error, which is the correct message).

## 4. Evaluating an expression

For an entered expression E:

1. Write Probe.hs = Main.hs shape but with only `it = E`, and run
   the frontend (`check`) on it. Errors? Report, done - this is
   where "no instance", scope errors, and type errors surface,
   with the ordinary diagnostics.
2. Read `it`'s inferred type from the check output. This answers
   `:type` directly, and decides the runner:
   - `it :: IO t` -> `main = it` (run the action);
   - anything else -> `main = print it` (needs Show, and a missing
     Show instance is reported by the ordinary machinery).
3. Write Main.hs accordingly, compile through `ahc-build.sh` (the
   same script, the same cache), and run the binary with the
   REPL's stdin/stdout/stderr - interactive programs work at the
   prompt.

Deliberate GHCi divergences, stated rather than hidden:
- `it` is not rebound across entries (re-evaluating a side effect
  behind a variable that LOOKS like a value is exactly the kind of
  surprise this project avoids).
- An IO action's non-() result is not printed (`main = it`
  discards it); bind it if you want it shown.
- No extended defaulting: `return 5` alone is ambiguous here as it
  is in a source file; annotate.

## 5. Commands

`:quit`/`:q`, `:help`/`:h`, `:type E`/`:t E` (probe only, print
the inferred scheme), `:load PATH`/`:l` (the file's imports and
declarations REPLACE the session - GHCi's reset-on-load
semantics), `:reload`/`:r` (re-run the last `:load`), `:clear`
(empty session). Line numbers in diagnostics refer to the
generated Repl.hs, where each accepted entry is one line - so the
N-th entry is line N plus the import block, close enough to be
useful and documented in `:help`.

## 6. Testing

The REPL's plumbing is text-in, text-out, so it is tested the way
everything else is: pinned transcripts. `scripts/run_repl.sh`
feeds each `tests/repl/*.in` to `ahc repl` in a fresh scratch
directory and byte-compares the full stdout against the `.out`
golden - prompts, results, error messages, recovery. The
transcripts cover declarations and shadowing-by-redefinition,
expressions pure and IO, `:type`, error-then-recovery (the
rolled-back state must keep working), `:load`/`:reload`, and the
multi-declaration line. The SEMANTICS need no new oracle: every
result a transcript pins was produced by the same pipeline the
conformance suite already byte-compares against GHC.

## 7. Future work, explicitly out of v1

Persistent `it`; multi-line block entry (`:{ :}`); readline
editing and history (use `rlwrap ahc repl` today); a shared
cross-session object cache (the per-session cache already makes
line two fast; sharing would make line ONE fast); `:browse`;
running a loaded `main` bare. None is architectural - the
compile-and-run skeleton accepts each as an increment.
