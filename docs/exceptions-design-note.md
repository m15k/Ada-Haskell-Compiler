# Synchronous exceptions: a design note

M136. Follow-on to `docs/io-design-note.md` and
`docs/concurrency-design-note.md`. The brief is one sentence long:
**AHC has no way to recover from any error.** There is no `ioError`,
`userError`, `catch`, `System.IO.Error`, or `Control.Exception`;
every failure path in the runtime ends in `ahc_die`, which prints
and calls `exit(1)`. The Report's Prelude requires `ioError` and
`userError` (section 9, "Input/Output"); the Library Report has a
whole chapter (42, `System.IO.Error`) AHC does not ship; and
`tests/conformance/EXCLUSIONS.md` did not even list the gap. This
note designs the smallest exception system that closes it honestly,
under the house constraints: one evaluator, byte-identical to GHC
where a portable program can observe it, and a reproducible
schedule.

## Part 1: what the runtime already has

Three pieces of unwinding machinery exist, all built for other
reasons, and the design below is mostly a matter of unifying them.

1. **Per-task error frames** (`AhcTask.err_stack`, `ahc_err_frame`,
   `die_unwind_if_armed`). Every spawned green task starts under a
   `setjmp` frame in `task_trampoline`: a death inside the task
   longjmps there, the task goes to state 3 with the message in
   `err_msg`, and `await`/scope-exit decide who inherits it. Library
   mode (`--lib`) arms the same frame around every exported entry so
   a runtime error unwinds to the host instead of killing it
   (`ahc_last_error`). Sparks arm it too.
2. **The re-raising thunk** (`mk_sparked_die`). When a spark's
   evaluation dies, the spark's root thunk is updated to a thunk
   that dies again with the same message when demanded - the GHC
   rule that a thunk whose evaluation raised re-raises on the next
   force, applied to exactly one thunk.
3. **The message channel is a C string.** `ahc_die(const char *)`
   carries text, not a value; `err_msg[512]` is the only thing a
   frame receives.

So: frames exist, but only at task/spark/FFI boundaries; the payload
is text; and thunks blackholed *under* the unwinding frame are left
as blackholes (the spark path fixes up its root only - an inner
thunk it had claimed spins forever if anything demands it later, a
latent gap this milestone closes as a side effect).

## Part 2: what GHC does, and how much of it a Haskell 2010 program can see

GHC's `Control.Exception` is built on `SomeException`, an existential
over the `Exception` class, dispatched by `Typeable`. None of that is
Haskell 2010, and a portable program observes only:

- `IOError` values: their `show`, the `System.IO.Error` predicates and
  accessors, `ioError`/`userError`, `catchIOError`/`tryIOError`.
- Uncaught exceptions on stderr, which the conformance oracle does
  not capture (it compares stdout only).
- `Control.Exception`'s `catch`/`try`/`throwIO`/`evaluate`/`bracket`/
  `finally` over a fixed set of types (`IOException`, `ErrorCall`,
  `ArithException`, `ExitCode`, `SomeException`) - base-compat, not
  Report, in the same spirit as `Applicative` and `Semigroup`.

The oracle formats that matter (GHC 9.4.8, probed):

| Value | `show` |
| --- | --- |
| `readFile` on a missing file | `PATH: openFile: does not exist (No such file or directory)` |
| `userError "x"` | `user error (x)`; `userError ""` is `user error` |
| `hGetLine` at end of file | `FILE: hGetLine: end of file` (`<stdin>` for stdin) |
| `hGetLine` on a closed handle | `FILE: hGetLine: illegal operation (handle is closed)` |
| `hPutStr` on a read handle | `FILE: hPutStr: illegal operation (handle is not open for writing)` |
| `readFile` on a directory | `PATH: openFile: inappropriate type (is a directory)` |
| `1 \`div\` 0` | `divide by zero` |
| `ErrorCall "m"` | `m` |
| `error "m"` caught and shown | `m` + newline + `CallStack (from HasCallStack):` + `  error, called at F:L:C in main:Main` |
| `ExitFailure 3` | `ExitFailure 3` |

The general IOError shape is `[FILE ": "] [LOC ": "] TYPE [" (" DESC ")"]`
with `ioeGetErrorString` returning the description for user errors
and the type's string otherwise. The one format AHC will not chase
is the `CallStack` suffix that `show` adds to an `ErrorCall` raised
by `error` (a HasCallStack artifact; the `ErrorCall m` pattern yields
the bare message in both compilers, and that is what a portable
program uses).

## Part 3: AHC's design

### Surface

Three new library modules and two Prelude entries, all ordinary
Haskell in `lib/` and `prelude/`:

- **Prelude** (Report 9): `type IOError = IOException`, `ioError`,
  `userError`, and the `Show`/`Eq` instances for `IOException`.
- **`System.IO.Error`** (Library Report 42): `IOErrorType` (the eight
  Report kinds, plus `ResourceVanished`/`OtherError` for the errno
  mapping), the `is*Error`/`is*ErrorType` predicates, `*ErrorType`
  constants, `ioeGet*`/`ioeSet*` accessors, `mkIOError`,
  `annotateIOError`, `modifyIOError`, `catchIOError`, `tryIOError`.
  `ioeGetHandle`/`ioeSetHandle` are omitted (AHC's `Handle` is an
  opaque index; the field is never populated in GHC's own IOErrors
  from `openFile` either).
- **`Control.Exception`** (base-compat subset): `SomeException`,
  class `Exception` (`toException`, `fromException`,
  `displayException`), `ErrorCall`, `ArithException`, instances for
  `IOException`, `ErrorCall`, `ArithException`, `ExitCode`,
  `SomeException`; `throw`, `throwIO`, `catch`, `handle`, `try`,
  `evaluate`, `bracket`, `bracket_`, `finally`, `onException`.
- **`System.IO.withFile`** becomes `bracket`-based, so the handle is
  closed when the body raises - GHC's behaviour, and the reason the
  probe above says `withFile:` where AHC says `openFile:`.
  (`readFile`/`writeFile` keep AHC's `openFile` location: both are
  wrong relative to GHC in one direction or the other, and a
  portable program does not print an IOError's location without
  also printing the path GHC would have chosen.)

### The exception value

The runtime needs a *value* to raise, and the Haskell side needs to
pattern-match on it, but the Prelude has no export list (everything
it defines is visible to every program, and constructor names are
program-global), so the constructors cannot live in Haskell source
without polluting every namespace with `EOF`, `UserError`,
`IOError`... Instead:

**`SomeException` and `IOException` are wired, opaque builtin types**
- exactly like `Text`: a `Def_TyCon` in `AHC.Builtins`, no source
constructors, primitives for construction and inspection. The
runtime owns their representation (a constructor node whose tag is
the exception *kind*), and the Haskell side reaches the fields
through primitives:

```
primExcKind      :: SomeException -> Int          -- 1 ErrorCall, 2 Arith, 3 IO, 4 Exit
primExcMessage   :: SomeException -> String       -- kind 1: the ErrorCall message
primExcCode      :: SomeException -> Int          -- kind 2: ArithException index; kind 4: exit code
primExcIO        :: SomeException -> IOException  -- kind 3
primExcErrorCall :: String -> SomeException
primExcArith     :: Int -> SomeException
primExcFromIO    :: IOException -> SomeException
primExcExit      :: Int -> SomeException
primMkIOError    :: Int -> String -> String -> Maybe String -> IOException
                    -- type, location, description, filename
primIoeType      :: IOException -> Int
primIoeLocation  :: IOException -> String
primIoeDescription :: IOException -> String
primIoeFilename  :: IOException -> Maybe String
```

`IOErrorType` is a plain source enum in `System.IO.Error` whose
`fromEnum` order is the runtime's kind table (one table, in
`runtime/ahc_rts.c`, documented in the module). `ErrorCall`,
`ArithException`, and `ExitCode` (which already exists in
`System.Exit`) stay ordinary source types; `toException` and
`fromException` convert through the primitives. `SomeException` is
therefore a *closed* sum: a program cannot declare its own exception
type. That is the honest scope - Haskell 2010 has no user exception
types at all - and it is written into EXCLUSIONS.

The `Exception` class is real (`class Show e => Exception e`), so
`catch :: Exception e => IO a -> (e -> IO a) -> IO a` has GHC's
signature and dispatches by handler type in Haskell:

```haskell
catch act h = primCatch act (\se -> case fromException se of
                                      Just e  -> h e
                                      Nothing -> primThrowIO se)
```

### The five runtime primitives

```
primCatch    :: IO a -> (e -> IO a) -> IO a   -- e is SomeException; the lib pins it
primThrowIO  :: e -> IO a
primThrow    :: e -> a
primEvaluate :: a -> IO a
primExitWith :: Int -> IO a                   -- exitWithCode, now a raise
```

`primCatch` runs its action under a **catch frame**; `primThrow`
and `primThrowIO` call `ahc_throw(node)`, which unwinds to the
nearest frame of *either* kind. Frames are a per-task chain:

```c
typedef struct AhcCatch {
  jmp_buf jb;
  struct AhcCatch *prev;
  struct AhcEvalFrame *eval_top;  /* thunks under evaluation at push */
  int err_depth;                  /* boundary depth at push */
} AhcCatch;
```

stack-allocated inside `io_catch` (so nesting is unbounded, unlike
the fixed `err_stack`), linked from `cur_task->catch_top`. The
existing boundary frames (`ahc_err_frame`: task, spark, FFI entry)
keep their array and their public API; a raise picks the catch
frame if one was pushed *after* the newest boundary
(`catch_top->err_depth == cur_task->err_depth`), else the boundary.

### Two kinds of failure, deliberately

`ahc_throw` is for **exceptions** - failures a program may
legitimately handle. `ahc_die` stays for **fatal deaths** - the
runtime cannot continue, or the program is wrong in a way the
extension promised to catch. A die still unwinds to a *boundary*
frame (a task fails, an FFI entry reports), but it skips catch
frames: `catch` can never observe one. The classification:

| Path | Becomes | Catchable |
| --- | --- | --- |
| `error`, `undefined`, pattern-match failure, `head []` and friends | `ErrorCall` | yes |
| `div`/`mod`/`quot`/`rem` by zero, Integer division by zero | `ArithException DivideByZero` | yes |
| file/handle failures (open, EOF, closed handle, wrong mode) | `IOException` with the errno-derived type | yes |
| `exitWith`/`exitSuccess`/`exitFailure` | `ExitCode` (GHC: it is an exception) | yes |
| `ioError`, `throwIO`, `throw` | the value given | yes |
| refinement violation, contract violation | fatal | **no** - the extension's guarantee is that the program stops |
| `<<loop>>`, deadlock, spin watchdog | fatal | no (GHC's `NonTermination`/`BlockedIndefinitely` are catchable; AHC's scheduler reports are diagnostics, not values) |
| out of memory, FFI marshalling deaths, internal invariants | fatal | no |

Owner calls recorded here, reversible: refinement/contract
violations stay fatal; `<<loop>>`/deadlock stay fatal; exit is an
exception (a `catch`-all handler sees `ExitFailure n` exactly as in
GHC, and an uncaught one still exits with that code, silently).

### Thunks under evaluation

A `longjmp` over `ahc_eval` frames abandons thunks that were claimed
and blackholed on the way down. GHC updates each to re-raise; AHC
must too, or `let x = error "e" in catch (evaluate x) h >> evaluate x`
reports `<<loop>>` on the second force, and a green task parked on
one of them never wakes. So `ahc_eval` keeps a per-task intrusive
stack of the thunks it is evaluating:

```c
typedef struct AhcEvalFrame { AhcNode *node; struct AhcEvalFrame *prev; } AhcEvalFrame;
/* in the THUNK case, after the BLACKHOLE publish: */
AhcEvalFrame ef = { n, cur_task->eval_top }; cur_task->eval_top = &ef;
v = ahc_eval(code(env));
cur_task->eval_top = ef.prev;
```

and `ahc_throw` walks that stack down to the target frame's saved
`eval_top`, updating every node to an indirection to a **rethrow
thunk** (a thunk whose code raises the same exception value) and
waking its waiters, before it jumps. Two stores per thunk
evaluation on the hot path; the bench gate records the delta. The
boundary frames get the same fix-up (a task's or spark's abandoned
inner thunks become rethrows rather than dead blackholes), which is
the latent gap from Part 1.

### Concurrency

- **A task that raises** goes to state 3 carrying the exception
  value (`AhcTask.exc`) rather than only text; `await` and the
  scope's join re-**throw** that value in the parent, so a parent's
  `catch` around a `scope` sees the child's `IOError`. A task that
  *dies* (fatal) keeps today's text path: the parent dies too.
- **A scope body that raises** must still join its children (Ada's
  master rule does not stop for an exception): `io_scope` arms a
  catch frame, joins every child on the unwinding path, then
  rethrows the original. Children's own failures during that join
  are lost - the first exception wins, as in Ada.
- **Sparks**: a raise inside a spark updates the spark root to a
  rethrow thunk (generalising `mk_sparked_die`) and the exception
  surfaces when the program demands the value, on whichever task
  demands it. Deterministic, because demand is.
- **FFI callbacks**: a raise reaching a callback's boundary frame is
  fatal at that boundary (no unwinding through foreign C frames),
  exactly as a die is today.
- No asynchronous exceptions, no `timeout`, no `killThread` - the
  concurrency note's non-goals stand.

### Uncaught

`ahc_run_main` arms a boundary frame; an exception that reaches it is
rendered by ONE C renderer (`exc_render`) that produces the same text
`show` does, prefixed `ahc: `, and exits 1 (`ExitCode`: exits with the
code, printing nothing). `ErrorCall` keeps today's `ahc: error: MSG`
form and `ArithException` today's `ahc: divide by zero`, so every
existing exec golden on those paths stays byte-identical; the two
IOError goldens (`handle_errors`, `handle_missing`) change to the
GHC-shaped text, deliberately. Library mode renders the same text
into `ahc_last_error`.

## Part 4: implementation plan

`docs/plans/2026-09-07-m136-exceptions.md`. Three milestones, in the
IO note's shape:

- **M136** - this note; the plan; EXCLUSIONS entry for the current state.
- **M137** - runtime + builtins: frames, `ahc_throw`, the eval stack
  and rethrow thunks, the classification table applied to every die
  site it names, task/scope/spark/main integration, the sixteen
  primitives, exec tests for each path (both GC modes, TSan, soak).
- **M138** - library: Prelude entries, `System.IO.Error`,
  `Control.Exception`, `withFile` via `bracket`, GHC-oracled
  conformance programs, MANUAL chapter, README, EXCLUSIONS rewrite.

## Part 5: non-goals

- User-defined exception types (`instance Exception MyError`) -
  needs an open `SomeException`, i.e. `Typeable`; not Haskell 2010.
- Asynchronous exceptions and `mask`; `throwTo`; `timeout`.
- GHC's `CallStack` suffix on `ErrorCall` from `error`.
- `PatternMatchFail` as a distinct type with GHC's `F:L:C1-C2` text:
  pattern-match failures raise `ErrorCall` with AHC's message.
- `NonTermination`/`BlockedIndefinitelyOnMVar` as catchable values.
- Catching refinement or contract violations.
