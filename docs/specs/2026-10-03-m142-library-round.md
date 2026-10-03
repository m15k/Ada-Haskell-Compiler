# M142 - the library round (spec)

**Status:** approved design, 2026-10-03. Next: implementation plan
(writing-plans skill), `docs/plans/2026-10-03-m142-library-round.md`.

## Purpose

Hackage-style modules are, by a wide margin, the first reason real
GitHub Haskell code does not build under AHC (`docs/repos-to-try.md`,
"What usually blocks a repo", ~90 candidates across two scout rounds).
M142 closes the most frequent of them. Success is measured the M141
way: GHC 9.4.8 byte-identical output on oracled conformance programs,
and repositories that were blocked becoming `AGREES` /
`AGREES-BANNER` under `scripts/scout_repos.sh`.

## Scope

In:

| Module / item | Blocked repos (round two) | Kind of work |
|---|---|---|
| `Debug.Trace` | 3 | lib + one stderr primitive |
| `Data.Map.Strict` | 2 | lib (re-export + strict variants) |
| `toRational` runtime | (found in M75; EXCLUSIONS lib 23/24) | runtime / Prelude |
| `Control.Monad.State` | 1 | lib |
| instances over `(->)` | (prerequisite) | typechecker |
| `Text.Printf` | 1 | lib, after the typechecker fix |
| `System.Random` | 3 | lib, exact random-1.2 algorithm |
| `System.Directory` | 1 | C runtime + FFI |
| `System.Process` | 2 | C runtime + FFI |

Out (deferred, recorded in repos-to-try.md): `Data.ByteString`,
`Data.Word8` (a Hackage package, not base), `Control.Arrow`,
`Control.Monad.Error`, `Data.Array.IO`, `System.Console.GetOpt`,
`GHC.Base`. `Control.Arrow` becomes cheap once Phase C lands; it is
out only because no scouted repo needed it alone.

## Oracle

GHC 9.4.8 at `~/.ghcup/bin`. Its global package db already has
`containers`, `mtl`, `transformers`, `process`, `directory`,
`bytestring`. `random` (and its dependency `splitmix`) is NOT
installed; Phase D installs it into the GHC user package db with
`cabal install --lib random-1.2.1.2` (exact version pinned in the
plan and recorded in the conformance README) before any
System.Random program is oracled. This is the only change to the
oracle environment.

## Phases

### Phase A - Debug.Trace, Data.Map.Strict, toRational

- **Debug.Trace**: `trace`, `traceShow`, `traceShowId`, `traceId`,
  `traceM`, `traceShowM`. `trace msg x` writes `msg` and a newline to
  stderr when the `trace` application is forced, then returns `x`.
  One new primitive (write a String to stderr unbuffered, as GHC's
  `trace` does - it bypasses the `stderr` Handle buffer) used under a
  forced sequence.
  Ordering relative to stdout follows evaluation order. Where the
  Report fixes that order (`seq`, case scrutiny, IO sequencing), AHC
  must match GHC. Where GHC's order is an artifact of its evaluator,
  the oracled program is written to avoid depending on it, and the
  difference is documented in EXCLUSIONS rather than chased.
- **Data.Map.Strict**: same `Map` type as `Data.Map` (values mix
  freely). Re-exports the lazy API; overrides the value-producing
  functions with value-strict versions (`insert`, `insertWith`,
  `insertWithKey`, `adjust`, `adjustWithKey`, `alter`, `update`,
  `fromList`, `fromListWith`, `fromListWithKey`, `map`, `mapWithKey`,
  `singleton`, `unionWith`, `unionsWith`, `foldl'`-style folds
  already strict). Strictness = WHNF via `seq`, as containers does.
  Observable test: a strict insert of `undefined` raises where the
  lazy one does not.
- **toRational**: `toRational` currently has no runtime at Int,
  Integer, Double ("method 'toRational' has no runtime yet"), even
  with Data.Ratio imported; `realToFrac` therefore works only from
  some source types. Give `Real Int`, `Real Integer`, `Real Double`,
  `Real Float` (and the Int8..Word64 types) a `toRational` producing
  Data.Ratio's `Ratio Integer`, exactly as GHC (Double: the exact
  binary value, `toRational 0.1 = 3602879701896397 % 36028797018963968`).
  The design must respect AHC's arrangement that the Prelude's
  `Rational` is a wired placeholder Data.Ratio defines (see the M75
  memory note): the implementation lives where the placeholder's
  definition is known, and the EXCLUSIONS lib 23/24 clause is struck.

### Phase B - Control.Monad.State

mtl's `MonadState s m | m -> s` needs multi-parameter classes with
functional dependencies, which Haskell 2010 lacks. AHC ships the
class-free core of the API:

- `newtype StateT s m a = StateT { runStateT :: s -> m (a, s) }`,
  `type State s = StateT s Identity` with `Identity` (from a new
  `Data.Functor.Identity`), `runState`, `evalState`, `execState`,
  `evalStateT`, `execStateT`, `state`, `withState`, `mapState`.
- `get`, `put`, `modify`, `modify'`, `gets` at type
  `Monad m => ... StateT s m ...` - plain functions, not methods.
- `Functor`/`Applicative`/`Monad` instances for `StateT s m`
  (given `Monad m`), `lift :: Monad m => m a -> StateT s m a` and
  `liftIO :: IO a -> StateT s IO a` as plain functions; re-export of
  `Control.Monad` (mtl does this).
- Documented limitation (EXCLUSIONS): signatures written against
  `MonadState s m =>` / `MonadIO m =>`, and `lift` for other
  transformers, do not compile; the error names the class.

### Phase C - instances over (->), then Text.Printf

- **Typechecker**: AHC represents `a -> b` as a dedicated `TFun_T`
  node, not as `(->)` applied to two arguments. A type variable of
  kind `* -> * -> *` applied to arguments (`k a b`) therefore never
  unifies with a function type, and an instance head over `(->)` or
  `a -> r` is not matched. Fix: unification treats `TApp (TApp k a) b`
  against `TFun a' b'` as `k := (->)`, `a ~ a'`, `b ~ b'` (and the
  partially applied `TApp k a` against `(->) a'`), and instance
  lookup matches a function type against an instance whose head is
  `(->)`. The probe that must compile and run like GHC:
  `instance Cat (->)` with `idC (5 :: Int)`, and
  `instance (Show a, PT r) => PT (a -> r)`.
- **Text.Printf** in base's own shape: `printf :: PrintfType r =>
  String -> r`, `hPrintf`, `PrintfType` instances for `String`
  (via base's `IsChar c => [c]` trick, Haskell-2010 legal), `IO a`,
  and `(PrintfArg a, PrintfType r) => a -> r`; `PrintfArg` for Int,
  Integer, Double, Float, Char, String and the fixed-width integers.
  Formats `%d %i %u %s %c %f %F %e %E %g %G %x %X %o %b %%` with
  `-`, `+`, space, `0`, `#` flags, width, precision and `*`. Error
  texts for bad formats / argument mismatches match base's
  (`printf: bad formatting char 'q'`, `printf: argument list ended
  prematurely`, `printf: formatting string ended prematurely`).
  `printf`'s result at `IO ()` is the common case and must not need
  an annotation.

### Phase D - System.Random

Implement random-1.2's algorithms exactly in Haskell over AHC's
`Word64` and `Data.Bits`:

- `StdGen` = SplitMix64 (`SMGen seed gamma`), `mkStdGen :: Int ->
  StdGen` (splitmix's `mkSMGen` on the Int as Word64), `split`,
  `genWord64`, `genWord32`, `next`-free API (random-1.2 style).
- `Random`/`UniformRange` behaviour for Int, Integer, Word*, Int*,
  Char, Bool, Double, Float: `random`, `randomR`, `randoms`,
  `randomRs`, `uniform`, `uniformR`, using random-1.2's algorithms
  (bitmask-with-rejection for bounded integers, its Integer
  algorithm, `word64ToDoubleInUnitInterval`-style conversion for
  floating point - each copied from the 1.2.1.2 source, cited by
  function in comments).
- `Show StdGen` exactly as random prints it (`StdGen {unStdGen =
  SMGen ... ...}`).
- `getStdGen`, `setStdGen`, `newStdGen`, `getStdRandom`,
  `randomIO`, `randomRIO`, `initStdGen`: the global generator is an
  IORef seeded from the clock at first use (random-1.2 seeds from
  time/entropy - nondeterministic, so these are tested by properties:
  range, distinctness across runs, split independence - never by
  golden output).
Known-answer gate: for seeds {0, 1, 42, -1, maxBound}, the first 1000
values of `randoms` at Int, Double, Bool and `randomRs (1,6)` at Int,
plus the `show` of each generator after 10 steps, byte-identical to
GHC with the installed random-1.2.1.2.

### Phase E - System.Directory, System.Process

New C primitives over POSIX, marshalled like M140's sockets (Text /
String crossing the C ABI, errors as `IOError` built by the M136
machinery with GHC's `ioe_*` fields and message text):

- **System.Directory**: `doesFileExist`, `doesDirectoryExist`,
  `listDirectory` (no `.`/`..`), `getDirectoryContents` (with them),
  `createDirectory`, `createDirectoryIfMissing` (with the parents
  flag), `removeFile`, `removeDirectory`, `renameFile`,
  `getCurrentDirectory`, `setCurrentDirectory`, `getHomeDirectory`.
  Listing order is the OS's (GHC does not sort); tests sort before
  printing.
- **System.Process**: `system` (via `/bin/sh -c`, as the Report-era
  API defines), `rawSystem`, `callProcess`, `callCommand`,
  `readProcess`, `readProcessWithExitCode`. Spawn with `posix_spawnp`
  and an argv vector - no shell except `system`/`callCommand`;
  stdin/stdout/stderr pipes drained without deadlock (both pipes read
  concurrently, the M127 scheduler parking on the fds); exit status
  mapped to `ExitSuccess`/`ExitFailure n`, a signal to
  `ExitFailure (-signo)` as GHC does; `callProcess` failures raise
  GHC's error text.
- Security: these spawn processes and touch the filesystem;
  `/security-review` on the branch is a gate (CLAUDE.md step 5).
  Argument vectors are passed through unmodified (no shell
  interpolation); NUL bytes inside a String argument are an
  `IOError`, not a truncation.

### Phase F - scout, review, docs, release

- Re-run `scripts/scout_repos.sh` on every round-two candidate that
  was blocked by an in-scope module; re-table repos-to-try.md.
- Adversarial review (the skill), then write-up, then release v1.16.

## Gates

Every phase: `scripts/run_gate.sh` green (unit, conformance, exec in
both GC modes, golden). New conformance programs live in
`tests/conformance/lib/` (or `tests/conformance/` / `multi/` per the
existing layout), each oracled with runghc; rejections use the
`expected.err` mechanism from M75.

Additionally:

- Phase A: a trace-ordering program with Report-fixed order; a strict
  map program that raises where the lazy one does not; toRational at
  every Real instance, including Double's exact binary value.
- Phase C: both differential suites and a 300-seed fuzz campaign
  (`run_fuzz_par.sh 300 6 1`) - the typechecker change is shared by
  every program; the `(->)` probe program; Printf over every format
  and flag combination listed, plus the three error texts.
- Phase D: the known-answer gate above.
- Phase E: exec tests in a fresh temp directory (create, list, rename,
  remove; spawn `/bin/echo`, `/bin/cat` with stdin, a non-zero exit, a
  missing executable); `/security-review` with no unresolved finding.
- Milestone: `run_own_soak.sh` with `AHC_OWN_VERIFY=1`, fuzz 300,
  `run_bench.sh`-style A/B bench delta against v1.15, adversarial
  review verdict recorded in the plan.

## Risks

- **Debug.Trace ordering** depends on evaluation order, which AHC's
  optimizer may change; mitigation above (Report-fixed order only in
  goldens).
- **The `(->)` unification change** touches every program's
  typechecking; mitigated by differential + fuzz gates in Phase C.
- **random-1.2 exactness** depends on AHC's Word64 wrap-around and
  bit operations being exact (M139 made them wrap like GHC); the
  known-answer gate catches any drift.
- **Process spawning on macOS vs Linux CI**: `posix_spawnp` exists on
  both; tests avoid platform-specific binaries beyond `/bin/sh`,
  `/bin/echo`, `/bin/cat`, `/usr/bin/env`.
- **The concurrent M143/M144 work** (a subagent on a separate
  worktree branch) edits `src/ahc-repl.adb`, `src/ahc-rename.adb` and
  possibly `lib/`; M142 avoids `ahc-rename.adb` and must rebase over
  M144's lib edits (if any) before its Phase F gate.
