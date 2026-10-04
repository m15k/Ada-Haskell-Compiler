# M142 The library round - Implementation Plan

**Goal:** close the most frequent "module not found" blockers of real
GitHub Haskell code - Debug.Trace, Data.Map.Strict, toRational,
Control.Monad.State, Text.Printf, System.Random, System.Directory,
System.Process - each byte-identical to GHC 9.4.8.

**Architecture:** library modules are plain Haskell in `lib/`; a
runtime primitive is a wired global `prim*` (type in
`src/ahc-builtins.adb` via `Def_Global`, body bound to a C symbol in
`src/ahc-prelude_core.adb` via `BP`, C in `runtime/ahc_rts.c` +
extern in `runtime/ahc_rts.h`). One typechecker change (a function
type unifies with `(->)` applied to two arguments) unlocks Printf.
Spec: `docs/specs/2026-10-03-m142-library-round.md`.

## Global constraints

- Oracle: GHC 9.4.8, `~/.ghcup/bin/runghc`. Conformance = byte-
  identical stdout (`scripts/run_conformance.sh` DISCARDS stderr);
  anything that must match on stderr is an exec test
  (`scripts/run_exec.sh` captures `2>&1`).
- Lib conformance programs are FLAT files `tests/conformance/lib_*.hs`
  + `.out` (there is no `tests/conformance/lib/` directory); oracle a
  new one with `runghc tests/conformance/lib_X.hs > tests/conformance/lib_X.out`.
- `prelude/` and `lib/` are gate inputs: never edit them while a
  suite runs. Never rebuild `bin/ahc` while a suite runs.
- Gate = `./scripts/run_gate.sh` → `GATE ok` (unit, conformance,
  exec, exec-own, golden). Run it unpiped with a long timeout.
- A new wired primitive renumbers entity ids in the Core goldens:
  regenerate with `./scripts/run_golden.sh --update` and verify the
  diff is renumber-only by stripping `_[0-9]+` before comparing
  (CLAUDE.md). A golden diff beyond renumbering is a defect.
- macOS has no `timeout(1)`. `grep -q` on compiler output SIGPIPEs it:
  capture to a file first.
- Concurrent work: a subagent is doing M143/M144 on a separate
  worktree branch (REPL, `src/ahc-rename.adb`, possibly `lib/`). M142
  must NOT edit `src/ahc-rename.adb`; before the Phase F gate, merge
  that branch if it has landed, and re-run the gate.
- Commits: conventional prefix, lowercase sentence subject, body says
  what and why, trailer `Co-Authored-By: Claude Opus 5.5
  <noreply@anthropic.com>`.

## Files

| File | Responsibility |
|---|---|
| `lib/Debug/Trace.hs` | new: trace family over `primTraceStr` |
| `lib/Data/Map.hs` | add the missing lazy API + Functor instance |
| `lib/Data/Map/Strict.hs` | new: value-strict variants, same `Map` |
| `src/ahc-builtins.adb` | `Def_Global` for every new prim |
| `src/ahc-prelude_core.adb` | `BP` bindings; `Real_Cl` branch in `Install_Bodies` |
| `runtime/ahc_rts.c`, `runtime/ahc_rts.h` | C primitives (trace, toRational, global refs, clock, directory, process) |
| `src/ahc-codegen.adb` | emit `ahc_ratio_tag` initialisation |
| `lib/Data/Functor/Identity.hs` | new |
| `lib/Control/Monad/State.hs`, `lib/Control/Monad/State/Strict.hs` | new |
| `src/ahc-typechecker.adb` | Unify: TFun vs TApp; canonicalise `(->) a b` back to TFun |
| `src/ahc-elaborate.adb` | `Solve_Ev` head walk: TFun → Arrow_TC |
| `src/ahc-kinds.adb` | canonicalise a syntactic `(->) a b` to TFun |
| `lib/Numeric.hs` | `floatToDigits` (base 10), `showFFloat`, `showEFloat`, `showGFloat` |
| `lib/Text/Printf.hs` | new |
| `lib/System/Random.hs`, `lib/System/Random/SplitMix.hs` | new |
| `lib/System/Directory.hs`, `lib/System/Process.hs` | new |
| `tests/conformance/lib_*.hs`, `tests/exec/*.hs` | regression programs |
| `tests/conformance/EXCLUSIONS.md`, `docs/MANUAL.md`, `docs/repos-to-try.md`, `CHANGES.md`, `README.md` | write-up |

---

## Phase A - Debug.Trace, Data.Map.Strict, toRational

**Result (landed 2ba0f67, 808a00c, 726c95d; reworked by the review round):** Debug.Trace forces the whole message first, strips NULs with GHC's warning, writes once, and traceIO is a real IO primitive (`primTraceIO`); Data.Map is containers-0.6.7's algorithm in lib/Data/Map/Internal.hs with containers' key identity, error texts and the everyday API, Data.Map.Strict forcing every stored value (lib_map_api.hs); toRational landed as planned.

### Task A1: Debug.Trace

**Files:** Create `lib/Debug/Trace.hs`, `tests/exec/debug_trace.hs` +
`.out`. Modify `src/ahc-builtins.adb`, `src/ahc-prelude_core.adb`,
`runtime/ahc_rts.c`, `runtime/ahc_rts.h`.

**Interfaces:** Produces `primTraceStr :: String -> ()` (forcing the
result writes the string and a newline to stderr, unbuffered).

- [x] **Step 1: the primitive.** In `src/ahc-builtins.adb`, beside
      `primHPutStr` (~:1176):

```ada
      --  Debug.Trace (M142): forcing the result writes the string and
      --  a newline to C stderr, unbuffered, as GHC's trace does.
      Ignore := Def_Global
        ("primTraceStr", Mono (FN (String_T2, TC (Env.Unit_TC))));
```

      In `src/ahc-prelude_core.adb` beside `BP ("primHPutStr", ...)`
      (~:1552): `BP ("primTraceStr", "ahc_prim_trace_str");`.
      In `runtime/ahc_rts.h` beside `ahc_prim_h_put_str`:
      `extern AhcNode *ahc_prim_trace_str;`. In `runtime/ahc_rts.c`
      beside `p_h_put_str` (~:5905), modelled on `io_h_put_str`'s
      `put_list` - but PURE (one argument, returns unit, not an IO
      action):

```c
/* Debug.Trace (M142): print a String to stderr when forced. */
static AhcNode *p_trace_str(AhcNode *s) {
  put_list(s, stderr);
  fputc('\n', stderr);
  fflush(stderr);
  return ahc_unit();
}
```

      and in init beside `ahc_prim_h_put_str = mk_prim2(...)`:
      `ahc_prim_trace_str = mk_prim1(p_trace_str);`. (Use the exact
      unit constructor and `mk_prim1` names the file already uses -
      check `grep -n "mk_prim1\|ahc_unit\|AHC_UNIT" runtime/ahc_rts.c`.)

- [x] **Step 2: the module.**

```haskell
module Debug.Trace
  ( trace, traceShow, traceShowId, traceId, traceM, traceShowM
  , traceIO
  ) where

-- Debug.Trace (M142). `trace msg x` writes msg to stderr when the
-- application is forced, then returns x. Ordering against stdout
-- follows evaluation order, exactly as GHC's.

trace :: String -> a -> a
trace msg x = case primTraceStr msg of () -> x

traceId :: String -> String
traceId s = trace s s

traceShow :: Show a => a -> b -> b
traceShow v = trace (show v)

traceShowId :: Show a => a -> a
traceShowId v = trace (show v) v

traceM :: Monad m => String -> m ()
traceM msg = trace msg (return ())

traceShowM :: (Show a, Monad m) => a -> m ()
traceShowM v = traceM (show v)

traceIO :: String -> IO ()
traceIO msg = case primTraceStr msg of () -> return ()
```

- [x] **Step 3: regression test** `tests/exec/debug_trace.hs` (an
      exec test, because conformance discards stderr). Stdout is set
      unbuffered so the interleaving in the `2>&1` capture is the
      evaluation order, identically under GHC:

```haskell
import Debug.Trace
import System.IO

fact :: Int -> Int
fact n = trace ("fact " ++ show n) (if n <= 1 then 1 else n * fact (n - 1))

main :: IO ()
main = do
  hSetBuffering stdout NoBuffering
  putStrLn "start"
  let x = traceShowId (fact 4)
  x `seq` putStrLn ("x = " ++ show x)
  traceM "in IO"
  traceShowM [1, 2, 3 :: Int]
  traceIO "traceIO"
  putStrLn (traceId "returned")
  print (traceShow (42 :: Int) True)
```

      Oracle: `runghc tests/exec/debug_trace.hs > tests/exec/debug_trace.out 2>&1`.
      Then `./scripts/ahc-build.sh tests/exec/debug_trace.hs /tmp/claude-501/dt && /tmp/claude-501/dt 2>&1 | diff - tests/exec/debug_trace.out`
      must be empty. If AHC's optimizer reorders a trace that the
      Report does not order, rewrite that line of the test to force
      order with `seq` and record the case in EXCLUSIONS (spec: do not
      chase evaluator artifacts).
- [x] **Step 4: goldens** - `./scripts/run_golden.sh`; if rc=1, verify
      renumber-only (strip `_[0-9]+`), then `--update`.
- [x] **Step 5: commit** `feat(lib): debug.trace, printing to stderr when the traced value is forced`

### Task A2: Data.Map completions and Data.Map.Strict

**Files:** Modify `lib/Data/Map.hs`; create `lib/Data/Map/Strict.hs`,
`tests/conformance/lib_map_strict.hs` + `.out`.

- [x] **Step 1: Data.Map gains the missing lazy API** (export list and
      bodies). Bodies, written over the existing `insert`, `lookup`,
      `delete`, `foldrWithKey`, `fromList`:

```haskell
insertWithKey :: Ord k => (k -> a -> a -> a) -> k -> a -> Map k a -> Map k a
insertWithKey f k = insertWith (f k) k

adjustWithKey :: Ord k => (k -> a -> a) -> k -> Map k a -> Map k a
adjustWithKey f k = adjust (f k) k

alter :: Ord k => (Maybe a -> Maybe a) -> k -> Map k a -> Map k a
alter f k m = case f (lookup k m) of
  Nothing -> delete k m
  Just v  -> insert k v m

update :: Ord k => (a -> Maybe a) -> k -> Map k a -> Map k a
update f k m = case lookup k m of
  Nothing -> m
  Just v  -> case f v of
    Nothing -> delete k m
    Just v' -> insert k v' m

fromListWith :: Ord k => (a -> a -> a) -> [(k, a)] -> Map k a
fromListWith f = foldl (\m (k, v) -> insertWith f k v m) empty

fromListWithKey :: Ord k => (k -> a -> a -> a) -> [(k, a)] -> Map k a
fromListWithKey f = foldl (\m (k, v) -> insertWith (f k) k v m) empty

mapWithKey :: (k -> a -> b) -> Map k a -> Map k b
mapWithKey _ Tip = Tip
mapWithKey f (Bin s k v l r) = Bin s k (f k v) (mapWithKey f l) (mapWithKey f r)

unionsWith :: Ord k => (a -> a -> a) -> [Map k a] -> Map k a
unionsWith f = foldl (unionWith f) empty

foldr' :: (a -> b -> b) -> b -> Map k a -> b
foldr' f z m = foldrWithKey (\_ v acc -> acc `seq` f v acc) z m

foldl' :: (b -> a -> b) -> b -> Map k a -> b
foldl' f z m = foldlWithKey (\acc _ v -> let a' = f acc v in a' `seq` a') z m

instance Functor (Map k) where
  fmap = map
```

      `insertWith` already stores `f new old` (containers' order);
      `fromListWith f [(k,a),(k,b)]` must give `f b a` - the test
      pins it. Check `foldlWithKey`'s argument order at
      `lib/Data/Map.hs:230` before using it; if it differs from
      containers' `(a -> k -> b -> a)`, adapt the lambda, not the
      export.
- [x] **Step 2: Data.Map.Strict** - same type; strict where containers
      is:

```haskell
module Data.Map.Strict
  ( Map, empty, singleton, null, size, member, notMember
  , lookup, findWithDefault, insert, insertWith, insertWithKey, delete
  , adjust, adjustWithKey, alter, update
  , union, unionWith, unionsWith, fromList, fromListWith
  , fromListWithKey, fromDistinctAscList
  , toList, toAscList, keys, elems
  , map, mapWithKey, filter, foldrWithKey, foldlWithKey, foldr', foldl'
  , keysSet
  ) where

-- Value-strict variants (M142): the SAME Map type as Data.Map, so the
-- two mix freely, as in containers. Strict = WHNF of the stored value.

import Prelude hiding (lookup, map, filter, null)
import Data.Map hiding (singleton, insert, insertWith, insertWithKey,
                        adjust, adjustWithKey, alter, update,
                        fromList, fromListWith, fromListWithKey,
                        map, mapWithKey, unionWith, unionsWith)
import qualified Data.Map as L

singleton :: k -> a -> Map k a
singleton k v = v `seq` L.singleton k v

insert :: Ord k => k -> a -> Map k a -> Map k a
insert k v m = v `seq` L.insert k v m

insertWith :: Ord k => (a -> a -> a) -> k -> a -> Map k a -> Map k a
insertWith f k new m = case L.lookup k m of
  Nothing  -> insert k new m
  Just old -> insert k (f new old) m

insertWithKey :: Ord k => (k -> a -> a -> a) -> k -> a -> Map k a -> Map k a
insertWithKey f k = insertWith (f k) k

adjust :: Ord k => (a -> a) -> k -> Map k a -> Map k a
adjust f k m = case L.lookup k m of
  Nothing -> m
  Just v  -> insert k (f v) m

adjustWithKey :: Ord k => (k -> a -> a) -> k -> Map k a -> Map k a
adjustWithKey f k = adjust (f k) k

alter :: Ord k => (Maybe a -> Maybe a) -> k -> Map k a -> Map k a
alter f k m = case f (L.lookup k m) of
  Nothing -> L.delete k m
  Just v  -> insert k v m

update :: Ord k => (a -> Maybe a) -> k -> Map k a -> Map k a
update f k m = case L.lookup k m of
  Nothing -> m
  Just v  -> case f v of
    Nothing -> L.delete k m
    Just v' -> insert k v' m

fromList :: Ord k => [(k, a)] -> Map k a
fromList = foldl (\m (k, v) -> insert k v m) L.empty

fromListWith :: Ord k => (a -> a -> a) -> [(k, a)] -> Map k a
fromListWith f = foldl (\m (k, v) -> insertWith f k v m) L.empty

fromListWithKey :: Ord k => (k -> a -> a -> a) -> [(k, a)] -> Map k a
fromListWithKey f = foldl (\m (k, v) -> insertWith (f k) k v m) L.empty

map :: (a -> b) -> Map k a -> Map k b
map f = mapWithKey (\_ v -> f v)

mapWithKey :: (k -> a -> b) -> Map k a -> Map k b
mapWithKey f m = let r = L.mapWithKey (\k v -> f k v) m
                 in L.foldrWithKey (\_ v acc -> v `seq` acc) r r

unionWith :: Ord k => (a -> a -> a) -> Map k a -> Map k a -> Map k a
unionWith f a b = L.foldrWithKey (\k v m -> insertWith f k v m) b a

unionsWith :: Ord k => (a -> a -> a) -> [Map k a] -> Map k a
unionsWith f = foldl (unionWith f) L.empty
```

      `unionWith f a b` must equal containers' (left-biased: on a
      shared key the result is `f (a's value) (b's value)`) - the test
      pins it against GHC; adjust the fold direction to match if not.
- [x] **Step 3: regression** `tests/conformance/lib_map_strict.hs`:

```haskell
import qualified Data.Map as L
import qualified Data.Map.Strict as M
import Control.Exception

main :: IO ()
main = do
  let m = M.fromListWith (++) [(1 :: Int, "a"), (2, "b"), (1, "c")]
  print m
  print (M.toList (M.alter (fmap (++ "!")) 2 m), M.update (const Nothing) 1 m)
  print (M.unionWith (++) m (M.fromList [(1, "z"), (3, "y")]))
  print (M.foldr' (\v n -> length v + n) 0 m, M.foldl' (\n v -> n + length v) 0 m)
  print (M.mapWithKey (\k v -> show k ++ v) m, fmap length m)
  print (L.size (L.insert 9 undefined m))         -- lazy: fine
  r <- try (evaluate (M.insert 9 undefined m))     -- strict: raises
  putStrLn (either (\e -> "strict: " ++ takeWhile (/= '\n') (show (e :: ErrorCall))) (const "lazy?!") r)
  print (M.insertWithKey (\k a b -> show k ++ a ++ b) 1 "N" m)
  print (L.unionsWith (+) [L.fromList [(1 :: Int, 1 :: Int)], L.fromList [(1, 2), (2, 3)]])
```

      Oracle with runghc; must be byte-identical.
- [x] **Step 4: verify** `./scripts/run_conformance.sh` (lib_map,
      lib_map_strict and every Data.Map user still ok).
- [x] **Step 5: commit** `feat(lib): data.map.strict, and the rest of data.map's everyday api`

### Task A3: toRational has a runtime

**Files:** Modify `src/ahc-prelude_core.adb` (Install_Bodies, ~:1695
onward), `src/ahc-builtins.adb` (nothing if the wired Real instances
stay), `runtime/ahc_rts.c`/`.h`, `src/ahc-codegen.adb` (~:1566-1580),
`tests/conformance/EXCLUSIONS.md`. Create
`tests/conformance/lib_to_rational.hs` + `.out`.

**Interfaces:** Produces C `ahc_ratio_tag` (int, -1 until codegen sets
it) and the prims behind `toRational` at Int, Integer, Double, Float.

- [x] **Step 1: the ratio tag reaches the runtime.** `src/ahc-codegen.adb`
      already finds `:%`'s tag (`Ratio_Tag`, ~:1566-1580). Emit, in
      the root unit's init (where `main` is called), the line
      `ahc_ratio_tag = <Ratio_Tag>;` when `Ratio_Tag >= 0`. Declare
      `extern int ahc_ratio_tag;` in `ahc_rts.h` and `int
      ahc_ratio_tag = -1;` in `ahc_rts.c`. Build a Rational node
      exactly as `ahc_mk_ratlit` does (same constructor layout: two
      fields, numerator then denominator), using tag
      `ahc_ratio_tag >= 0 ? ahc_ratio_tag : 1` - without Data.Ratio
      a Rational can only flow into `fromRational`, whose C
      (`p_from_rational_d`, ~:1685) reads the two fields regardless
      of tag.
- [x] **Step 2: the C primitives** (in `ahc_rts.c`, beside
      `p_from_rational_d`):
      - `p_to_rational_int(n)`: `n :% 1` (n evaluated; Int and Integer
        share the bignum-aware int representation - check `AHC_INT`
        vs bignum tags in `ahc_mk_int`).
      - `p_to_rational_double(x)`: the EXACT binary value. Use
        `frexp(x, &e)` → `m = ldexp(frac, 53)` as a 53-bit integer and
        `e -= 53`; if `e >= 0` the result is `(m << e) :% 1`, else
        strip common factors of two (`while (m even && e < 0) { m >>= 1; e++; }`)
        and return `m :% (1 << -e)` built with the runtime's bignum
        shift for large `-e` (find the bignum shift helper used by
        `p_shift_l`/`primShiftL`). Zero gives `0 :% 1`. NaN and
        infinity: match GHC (`toRational (1/0 :: Double)` is
        `179769313486231590772930519078902473361797697894230657273430081157732675805500963132708477322407536021120113879871393357658789768814416622492847430639474124377767893424865485276302219601246094119453082952085005768838150682342462881473913110540827237163350510684586298239947245938479716304835356329624224137216 % 1`
        - i.e. GHC decodes the IEEE bits; reproduce by treating the
        bits the same way `decodeFloat` does: mantissa 2^52, exponent
        972 for +Inf; take the oracle output as the spec and make the
        test include `1/0` and `0/0`).
      - Float: widen to double first (exact), as GHC's `toRational`
        on Float is exact on the float's value - the test includes
        `0.1 :: Float` (= `13421773 % 134217728`).
- [x] **Step 3: the dictionaries.** In `Install_Bodies`
      (`src/ahc-prelude_core.adb`, the branch chain ending at the
      `else Give_Dict (..., Errs (Cl))` ~:2236), add before the `else`:

```ada
                  elsif Cl_Id = Env.Real_Cl then
                     --  toRational (M142): exact, as GHC. Int and
                     --  Integer are n :% 1; Double and Float the exact
                     --  binary value. Was "no runtime yet".
                     Give_Dict
                       (Real_Instance_Id (II),
                        [ (if Inst.Head in Env.Double_TC | Env.Float_TC
                           then Prim_Ref ("primToRationalD")
                           else Prim_Ref ("primToRationalI")) ]);
```

      using the file's existing idiom for a dictionary whose single
      method is a primitive (copy the shape of the nearest one-method
      branch, e.g. how `Fractional Double`'s `fromRational` binds
      `P_FromRatD` at ~:1852), and bind the two prims with `BP` +
      their `Def_Global` types `Int -> Rational`-shaped (the method
      scheme is `a -> Rational`; give each a Mono type at its head:
      `primToRationalI :: Integer -> Rational` used for Int too only
      if Int and Integer share representation - otherwise add a third
      prim for Int).
      The fixed-width source instances (`prelude/Prelude.hs:1082..1446`,
      `toRational a = toRational (toInteger ...)`) then work with no
      edit.
- [x] **Step 4: regression** `tests/conformance/lib_to_rational.hs`:

```haskell
import Data.Ratio
import Data.Int
import Data.Word

main :: IO ()
main = do
  print (toRational (7 :: Int), toRational (-12345678901234567890 :: Integer))
  print (toRational (0.1 :: Double), toRational (0.5 :: Double), toRational (0 :: Double))
  print (toRational (-2.75 :: Double), toRational (1.0e-300 :: Double))
  print (toRational (0.1 :: Float))
  print (toRational (1/0 :: Double))
  print (toRational (200 :: Int8), toRational (maxBound :: Word64))
  print (realToFrac (1.5 :: Double) :: Double, realToFrac (3 :: Int) :: Double)
  print (numerator (toRational (0.75 :: Double)), denominator (toRational (0.75 :: Double)))
```

      and a second program WITHOUT `import Data.Ratio`,
      `tests/conformance/lib_realtofrac_noratio.hs`:

```haskell
main :: IO ()
main = do
  print (realToFrac (2.5 :: Double) :: Double)
  print (realToFrac (7 :: Int) :: Double, realToFrac (7 :: Integer) :: Float)
  print (fromRational (toRational (0.1 :: Double)) :: Double)
```

      Oracle both. Strike the clause in `tests/conformance/EXCLUSIONS.md`
      (lib 23/24 row) that begins "Found in passing: the wired
      `Rational` that `toRational` returns has no Show/Eq/Num instance"
      - replace with a pointer to these two programs.
- [x] **Step 5: verify** goldens (renumber-only, then `--update`),
      `./scripts/run_conformance.sh`.
- [x] **Step 6: commit** `fix(runtime): toRational has a runtime at int, integer, double and float`

**Gate (Phase A):** `./scripts/run_gate.sh` → `GATE ok`, with
`debug_trace` (exec, both GC modes), `lib_map_strict`,
`lib_to_rational`, `lib_realtofrac_noratio` among the passing
programs; golden diff renumber-only.

---

## Phase B - Control.Monad.State

**Result (landed 983215d; reworked by the review round):** Control.Monad.State is the LAZY StateT (transformers' irrefutable matches), Control.Monad.State.Strict a distinct strict StateT (lib_monad_state_lazy.hs). The IO-loop memory growth (10^6 get/put steps ~1.3-1.5GB under both) is the runtime's, not the library's.

### Task B1: Data.Functor.Identity

**Files:** Create `lib/Data/Functor/Identity.hs`.

```haskell
module Data.Functor.Identity (Identity (..)) where

newtype Identity a = Identity { runIdentity :: a }

instance Functor Identity where
  fmap f (Identity a) = Identity (f a)

instance Applicative Identity where
  pure = Identity
  Identity f <*> Identity a = Identity (f a)

instance Monad Identity where
  return = Identity
  Identity a >>= k = k a

instance Show a => Show (Identity a) where
  showsPrec d (Identity a) =
    showParen (d >= 11) (showString "Identity " . showsPrec 11 a)

instance Eq a => Eq (Identity a) where
  Identity a == Identity b = a == b
```

(GHC 9.4 shows `Identity 3` as `Identity 3` - the record syntax is NOT
shown; the test pins it.)

### Task B2: Control.Monad.State

**Files:** Create `lib/Control/Monad/State.hs`,
`lib/Control/Monad/State/Strict.hs`,
`tests/conformance/lib_monad_state.hs` + `.out`.

```haskell
module Control.Monad.State
  ( StateT (..), State, runState, evalState, execState
  , evalStateT, execStateT, state, withState, mapState
  , get, put, modify, modify', gets, lift, liftIO
  , module Control.Monad
  ) where

-- mtl's State without the MonadState class (M142): Haskell 2010 has no
-- multi-parameter classes, so get/put/modify are plain functions on
-- StateT. Code written against `MonadState s m =>` does not compile
-- (EXCLUSIONS); code that uses State / StateT directly does.

import Control.Monad
import Data.Functor.Identity

newtype StateT s m a = StateT { runStateT :: s -> m (a, s) }

type State s = StateT s Identity

instance Monad m => Functor (StateT s m) where
  fmap f (StateT g) = StateT (\s -> g s >>= \(a, s') -> return (f a, s'))

instance Monad m => Applicative (StateT s m) where
  pure a = StateT (\s -> return (a, s))
  StateT mf <*> StateT mx = StateT (\s -> do
    (f, s1) <- mf s
    (x, s2) <- mx s1
    return (f x, s2))

instance Monad m => Monad (StateT s m) where
  return = pure
  StateT m >>= k = StateT (\s -> m s >>= \(a, s') -> runStateT (k a) s')

state :: Monad m => (s -> (a, s)) -> StateT s m a
state f = StateT (return . f)

runState :: State s a -> s -> (a, s)
runState m s = runIdentity (runStateT m s)

evalState :: State s a -> s -> a
evalState m s = fst (runState m s)

execState :: State s a -> s -> s
execState m s = snd (runState m s)

evalStateT :: Monad m => StateT s m a -> s -> m a
evalStateT m s = runStateT m s >>= \(a, _) -> return a

execStateT :: Monad m => StateT s m a -> s -> m s
execStateT m s = runStateT m s >>= \(_, s') -> return s'

withState :: (s -> s) -> State s a -> State s a
withState f m = modify f >> m

mapState :: ((a, s) -> (b, s)) -> State s a -> State s b
mapState f m = StateT (\s -> Identity (f (runState m s)))

get :: Monad m => StateT s m s
get = StateT (\s -> return (s, s))

put :: Monad m => s -> StateT s m ()
put s = StateT (\_ -> return ((), s))

modify :: Monad m => (s -> s) -> StateT s m ()
modify f = StateT (\s -> return ((), f s))

modify' :: Monad m => (s -> s) -> StateT s m ()
modify' f = StateT (\s -> let s' = f s in s' `seq` return ((), s'))

gets :: Monad m => (s -> a) -> StateT s m a
gets f = StateT (\s -> return (f s, s))

lift :: Monad m => m a -> StateT s m a
lift m = StateT (\s -> m >>= \a -> return (a, s))

liftIO :: IO a -> StateT s IO a
liftIO = lift
```

`lib/Control/Monad/State/Strict.hs`:

```haskell
module Control.Monad.State.Strict (module Control.Monad.State) where
-- mtl's Strict variant differs only in pair strictness; AHC ships the
-- same StateT (the difference is unobservable without bottoms in the
-- state pair - documented in EXCLUSIONS).
import Control.Monad.State
```

- [x] **Regression** `tests/conformance/lib_monad_state.hs`:

```haskell
import Control.Monad.State

counter :: State Int Int
counter = do
  modify (+ 1)
  x <- get
  put (x * 10)
  gets (* 2)

push :: Int -> State [Int] ()
push x = modify (x :)

pop :: State [Int] (Maybe Int)
pop = do
  s <- get
  case s of
    []       -> return Nothing
    (x : xs) -> put xs >> return (Just x)

labels :: [String] -> State Int [(Int, String)]
labels = mapM (\w -> do n <- get; put (n + 1); return (n, w))

loop :: StateT Int IO ()
loop = do
  n <- get
  when (n < 3) $ do
    liftIO (putStrLn ("tick " ++ show n))
    put (n + 1)
    loop

main :: IO ()
main = do
  print (runState counter 4)
  print (evalState (mapM_ push [1, 2, 3] >> replicateM 4 pop) [])
  print (evalState (labels (words "a b c")) 100)
  print (execState (forM_ [1 .. 10] (\i -> modify' (+ i))) 0)
  s <- execStateT loop 0
  print s
  r <- evalStateT (do { lift (putStrLn "lifted"); gets length }) "abc"
  print r
```

- [x] **Verify** oracle + `./scripts/run_conformance.sh`.
- [x] **Commit** `feat(lib): control.monad.state without the monadstate class`
- [x] EXCLUSIONS: a lib row for Control.Monad.State - `MonadState`/
      `MonadIO` classes absent (no multi-parameter classes in Haskell
      2010); `lift` is StateT-only; `.Strict` is the same type.

**Gate (Phase B):** `./scripts/run_gate.sh` → `GATE ok`, with
`lib_monad_state` passing.

---

## Phase C - instances over (->), then Text.Printf

**Result (landed d465e74, 6b7bf7a; reworked by the review round):** Text.Printf is now base-4.17's code transcribed (modifier parser + field formatter per argument), so Char-as-integer, length-modifier narrowing, `#`-of-zero, precision-clears-zero and `*` arguments all match; floatToDigits honours non-10 bases (lib_float_to_digits.hs). `main = printf ...` needs main's result left unforced (tests/exec/printf_io_result.hs).

### Task C1: a function type unifies with (->) applied

**Files:** Modify `src/ahc-typechecker.adb` (Unify, ~:240-366;
Zonk_With ~:211-214; Subst_TyVars ~:397-400), `src/ahc-elaborate.adb`
(Solve_Ev head walk ~:103-121), `src/ahc-kinds.adb` (App_T
conversion ~:518-522). Create `tests/conformance/ch04_03_fun_instances.hs`
+ `.out`.

**Interfaces:** none new; behaviour: `k a b ~ (a -> b)` binds `k :=
(->)`.

- [x] **Step 1: Unify.** Before `case NA.Kind is` (~:340), add:

```ada
         --  `a -> b` IS `(->) a b` (Report 4.1.2): AHC keeps a
         --  dedicated TFun node, so a type-constructor variable
         --  applied to two arguments meets a function type here.
         --  Rewrite the TFun as the TApp spine and decompose (M142:
         --  instance Cat (->), instance PT (a -> r), Functor ((->) r)).
         if NA.Kind = TFun_T and then NB.Kind = TApp_T then
            Unify (Arrow_Spine (NA.From, NA.To), ZB, Span);
            return;
         elsif NA.Kind = TApp_T and then NB.Kind = TFun_T then
            Unify (ZA, Arrow_Spine (NB.From, NB.To), Span);
            return;
         end if;
```

      with a local helper above Unify:

```ada
      function Arrow_Spine (A, B : Type_Id) return Real_Type_Id is
         Arr : constant Real_Type_Id := M.Add (Type_Node'
           (Kind => TCon_T, Con => Real_TyCon_Id (Env.Arrow_TC),
            Refine => No_Refinement));
         F : constant Real_Type_Id := M.Add (Type_Node'
           (Kind => TApp_T, T_Fun => Arr, T_Arg => Real_Type_Id (A)));
      begin
         return M.Add (Type_Node'
           (Kind => TApp_T, T_Fun => F, T_Arg => Real_Type_Id (B)));
      end Arrow_Spine;
```

      (match the field names exactly to `src/ahc-core.ads:157-174`.)
- [x] **Step 2: canonicalise back.** Wherever a TApp node is rebuilt -
      `Zonk_With` and `Subst_TyVars` in the typechecker, and the
      `App_T` case of `Convert` in Kinds - if the rebuilt node is
      `TApp (TApp (TCon Arrow_TC, x), y)`, emit `TFun (x, y)` instead.
      This keeps inferred schemes, error messages ("Int -> Int", not
      "(->) Int Int") and the arity/FFI code (refine.adb:290/393/563,
      ahc_main.adb:819/847/855, desugar.adb:1659-1695/1862/1913/1992),
      which peel TFun only, unchanged.
- [x] **Step 3: elaborate.** In `Solve_Ev`'s head walk add
      `when TFun_T => Head := Env.Arrow_TC; exit;` (the superclass and
      default-method evidence path; without it an arrow instance's
      superclass dictionary is `$dMISSING`).
- [x] **Step 4: regression** `tests/conformance/ch04_03_fun_instances.hs`:

```haskell
class Cat k where
  idC  :: k a a
  comp :: k b c -> k a b -> k a c

instance Cat (->) where
  idC = \x -> x
  comp f g = \x -> f (g x)

class Cat k => Arr k where
  arr :: (a -> b) -> k a b

instance Arr (->) where
  arr f = f

newtype Reader r a = Reader (r -> a)

class Fn f where
  fmapF :: (a -> b) -> f a -> f b

instance Fn ((->) r) where
  fmapF = (.)

class Collect r where
  collect :: [String] -> r

instance Collect [c] where   -- [c] ~ String at use sites
  collect = undefined

instance (Show a, Collect r) => Collect (a -> r) where
  collect acc = \a -> collect (show a : acc)

newtype Out = Out [String]
instance Collect Out where
  collect = Out . reverse

run :: Out -> [String]
run (Out xs) = xs

main :: IO ()
main = do
  print (idC (5 :: Int))
  print (comp (+ 1) (* 2) (10 :: Int))
  print (arr show (comp idC (+ 1) (41 :: Int)))
  print (fmapF (* 3) (+ 1) (4 :: Int))
  print (run (collect [] (1 :: Int) True 'x'))
```

      Oracle with runghc (it must compile under plain GHC 9.4 - drop
      the `Collect [c]` instance if GHC rejects it as unused/overlap;
      it is there to mirror Printf's shape).
- [x] **Step 5: verify** `./scripts/run_gate.sh`,
      `./scripts/run_differential.sh`,
      `./scripts/run_differential_types.sh`,
      `./scripts/run_fuzz_par.sh 300 6 1` (all ok).
- [x] **Step 6: commit** `feat(types): a function type unifies with (->) applied to two arguments, so instances over (->) resolve`

### Task C2: Numeric gains floatToDigits and the show*Float family

**Files:** Modify `lib/Numeric.hs`; create
`tests/conformance/lib_numeric_float.hs` + `.out`.

Printf's `%f/%e/%g` are base's `showFFloat`/`showEFloat`/`showGFloat`,
which round GHC's SHORTEST decimal digits (`floatToDigits 10`). AHC's
`show :: Double` already prints GHC's shortest representation (the
conformance suite pins it), so the digits are recovered from it:

```haskell
-- floatToDigits 10 x for x >= 0: the shortest digits ds and exponent e
-- with x = 0.ds * 10^e, recovered from show's shortest representation
-- (which GHC also derives from floatToDigits).
floatToDigits :: Integer -> Double -> ([Int], Int)
floatToDigits _ 0 = ([0], 0)
floatToDigits _ x =
  let s = show x
      (mant, ex) = break (== 'e') s
      e10 = case ex of { ('e' : n) -> read n; _ -> 0 } :: Int
      (ip, fp) = break (== '.') mant
      fd = drop 1 fp
      digits = map digitToInt (ip ++ fd)
      lead = length (takeWhile (== 0) digits)
      ds0 = drop lead digits
      ds = reverse (dropWhile (== 0) (reverse ds0))
      e = length ip + e10 - lead
  in (if null ds then [0] else ds, e)
```

then `showEFloat`, `showFFloat`, `showGFloat` (and `showFFloatAlt`,
`showGFloatAlt`) transcribed from GHC 9.4's `GHC.Float.formatRealFloatAlt`
and `roundTo` (base-4.17 `libraries/base/GHC/Float.hs`): copy the
algorithm structure exactly (FFExponent / FFFixed / FFGeneric with
`Maybe Int` precision and the `alt` flag), adapting only `floatToDigits`
to the function above. Negative numbers: `'-' : ...` of the absolute
value, as GHC.

- [x] **Regression** `tests/conformance/lib_numeric_float.hs`: every
      combination of {showEFloat, showFFloat, showGFloat} ×
      {Nothing, Just 0, Just 2, Just 10} × {0, 1, 0.1, 123.456,
      1.0e-4, 9.999999, 1.0e21, -2.5, 5.0e-324, 1.7976931348623157e308}
      printed one per line (`putStrLn (showFFloat p x "")`).
- [x] **Commit** `feat(lib): numeric's showffloat, showefloat and showgfloat, rounding ghc's shortest digits`

### Task C3: Text.Printf

**Files:** Create `lib/Text/Printf.hs`,
`tests/conformance/lib_printf.hs` + `.out`,
`tests/exec/printf_errors.hs` + `.out`.

```haskell
module Text.Printf
  ( printf, hPrintf, PrintfType, HPrintfType, PrintfArg (..)
  , UPrintf (..), IsChar (..)
  ) where

import System.IO
import Numeric (showEFloat, showFFloat, showGFloat, showHex, showOct)
import Data.Char (intToDigit, toUpper)

-- base's shape (M142): printf's result type selects the instance -
-- String, IO a, or a function taking one more argument.

data UPrintf = UInteger Integer | UChar Char | UString String
             | UDouble Double

class PrintfArg a where
  toUPrintf :: a -> UPrintf

instance PrintfArg Int     where toUPrintf = UInteger . toInteger
instance PrintfArg Integer where toUPrintf = UInteger
instance PrintfArg Double  where toUPrintf = UDouble
instance PrintfArg Float   where toUPrintf = UDouble . realToFrac
instance PrintfArg Char    where toUPrintf = UChar
instance IsChar c => PrintfArg [c] where
  toUPrintf = UString . map toChar
-- Int8..Word64: one instance each, `toUPrintf = UInteger . toInteger`.

class IsChar c where
  toChar   :: c -> Char
  fromChar :: Char -> c

instance IsChar Char where
  toChar c = c
  fromChar c = c

class PrintfType r where
  spr :: String -> [UPrintf] -> r

instance IsChar c => PrintfType [c] where
  spr fmt args = map fromChar (uprintf fmt (reverse args))

instance PrintfType (IO a) where
  spr fmt args = putStr (uprintf fmt (reverse args)) >> return undefined

instance (PrintfArg a, PrintfType r) => PrintfType (a -> r) where
  spr fmt args = \a -> spr fmt (toUPrintf a : args)

printf :: PrintfType r => String -> r
printf fmt = spr fmt []

class HPrintfType r where
  hspr :: Handle -> String -> [UPrintf] -> r

instance HPrintfType (IO a) where
  hspr h fmt args = hPutStr h (uprintf fmt (reverse args)) >> return undefined

instance (PrintfArg a, HPrintfType r) => HPrintfType (a -> r) where
  hspr h fmt args = \a -> hspr h fmt (toUPrintf a : args)

hPrintf :: HPrintfType r => Handle -> String -> r
hPrintf h fmt = hspr h fmt []
```

`uprintf :: String -> [UPrintf] -> String` is the format interpreter:
parse `%` [flags `-+ 0#`] [width | `*`] [`.` precision | `.*`]
conversion; conversions `d i u` (UInteger, decimal), `x X o b`
(UInteger, base 16/16-upper/8/2, `#` adds `0x`/`0X`/`0`/`0b`), `c`
(UChar), `s` (UString; precision truncates), `e E f F g G` (UDouble via
`showEFloat`/`showFFloat`/`showGFloat` with precision default 6, `#`
alt forms, `E/G` upper-case the exponent), `v` (the argument's default:
`d` for integers, `c` for Char, `s` for String, `g` for Double), `%%`.
Padding: right-justify to width with spaces; `-` left-justifies; `0`
pads with zeros after the sign; `+`/space prefix non-negative numbers.
Errors - exact base texts, raised with `error` (base:
`perror s = errorWithoutStackTrace ("printf: " ++ s)`):
`printf: bad formatting char 'q'`,
`printf: argument list ended prematurely`,
`printf: formatting string ended prematurely`.
A type mismatch (`%d` given a String) is
`printf: bad formatting char 'd'` - verify each text against runghc.

- [x] **Regression** `tests/conformance/lib_printf.hs` - one line per
      case, built with `printf ... :: String` so the output is stdout:

```haskell
import Text.Printf

main :: IO ()
main = do
  printf "%d %i %5d|%-5d|%05d %+d % d\n" (42 :: Int) (7 :: Int) (3 :: Int) (3 :: Int) (-3 :: Int) (5 :: Int) (5 :: Int)
  printf "%x %X %o %b %#x %#o\n" (255 :: Int) (255 :: Int) (8 :: Int) (5 :: Int) (255 :: Int) (8 :: Int)
  printf "%s|%10s|%-10s|%.2s\n" "abc" "right" "left" "truncate"
  printf "%c%c %%\n" 'o' 'k'
  printf "%f %.2f %8.3f %-8.1f| %e %.3E %g %G\n" (3.14159 :: Double) (2.5 :: Double) (1.0 :: Double) (9.99 :: Double) (1234.5 :: Double) (0.000123 :: Double) (0.0001 :: Double) (1.0e7 :: Double)
  printf "%v %v %v %v\n" (1 :: Int) 'c' "str" (2.5 :: Double)
  printf "%*d|%-*d|%.*f\n" (6 :: Int) (1 :: Int) (4 :: Int) (2 :: Int) (3 :: Int) (3.14159 :: Double)
  let s = printf "%d-%s" (1 :: Int) "x" :: String
  putStrLn s
  printf "%d %d\n" (123456789012345678901234567890 :: Integer) (-1 :: Integer)
```

- [x] **Regression** `tests/exec/printf_errors.hs` (exec: the error
      text is on stderr): catches each of the three errors with
      `Control.Exception.catch` on `ErrorCall` after `evaluate (length
      (printf ... :: String))`, printing the message. Oracle with
      `runghc ... > .out 2>&1`.
- [x] **Verify** conformance + exec.
- [x] **Commit** `feat(lib): text.printf, in base's shape`

**Gate (Phase C):** `./scripts/run_gate.sh` → `GATE ok`; both
differential suites green; `./scripts/run_fuzz_par.sh 300 6 1` → 300
ok; `ch04_03_fun_instances`, `lib_numeric_float`, `lib_printf`,
`printf_errors` passing.

---

## Phase D - System.Random, exactly random-1.2

### Task D0: install the oracle package

- [x] `~/.ghcup/bin/cabal update` then
      `~/.ghcup/bin/cabal install --lib random-1.2.1.2 --package-env default`
      (installs splitmix too). Verify: `echo 'import System.Random
      main = print (fst (randomR (1,6 :: Int) (mkStdGen 42)))' > /tmp/claude-501/r.hs && ~/.ghcup/bin/runghc /tmp/claude-501/r.hs`.
      Record the exact versions installed (`ghc-pkg list random
      splitmix --user`) in `tests/conformance/README` (create the
      section "Oracle packages" if absent).
- [x] `~/.ghcup/bin/cabal get random-1.2.1.2 splitmix-<installed>`
      into `/private/tmp/claude-501/random-src/` - the SOURCE every
      algorithm below is transcribed from. Cite the function name in
      a comment above each transcription.

### Task D1: SplitMix

**Files:** Create `lib/System/Random/SplitMix.hs`,
`tests/conformance/lib_splitmix.hs` + `.out`.

Transcribe from splitmix's `System/Random/SplitMix.hs`: `SMGen` (two
Word64: seed, gamma), `mkSMGen`, `nextWord64`, `nextWord32`, `nextInt`,
`splitSMGen`, `mix64`, `mix64variant13`, `mixGamma`, `goldenGamma =
0x9e3779b97f4a7c15`, `shiftXor`, `shiftXorMultiply`, `popCount`-based
gamma fix-up, and `instance Show SMGen` (`SMGen <seed> <gamma>` - copy
its exact showsPrec). All arithmetic is AHC Word64 (wraps like GHC,
M139); shifts via `Data.Bits.shiftR`/`shiftL`, `xor`, `popCount`.

- [x] **Known-answer regression** `lib_splitmix.hs`: for seeds
      `[0, 1, 42, -1, maxBound]` (as Word64 `fromIntegral`), print the
      first 20 `nextWord64` values, the two halves of `splitSMGen`
      after 3 steps (`show`), and 20 `nextInt`. Oracle with runghc
      (import `System.Random.SplitMix` from the installed splitmix).

### Task D2: System.Random

**Files:** Create `lib/System/Random.hs`,
`tests/conformance/lib_random.hs` + `.out`,
`tests/exec/random_io.hs` + `.out`. Modify `src/ahc-builtins.adb`,
`src/ahc-prelude_core.adb`, `runtime/ahc_rts.c`/`.h` (two prims).

API (random-1.2 surface): `StdGen`, `mkStdGen`, `newStdGen`,
`getStdGen`, `setStdGen`, `getStdRandom`, `initStdGen`, `RandomGen
(next, genWord64, genWord32, split, genRange)` class with
`instance RandomGen StdGen`, `Random (random, randomR, randoms,
randomRs)` with instances Int, Integer, Word, Int8..Int64,
Word8..Word64, Char, Bool, Double, Float; `uniform`, `uniformR`
(pure, at the same types), `randomIO`, `randomRIO`.

- `newtype StdGen = StdGen { unStdGen :: SMGen }`,
  `mkStdGen n = StdGen (mkSMGen (fromIntegral n))`,
  `instance Show StdGen` exactly as random 1.2 derives it
  (`StdGen {unStdGen = SMGen 123 456}`).
- Every `randomR`/`uniformR`/`random` algorithm is TRANSCRIBED from
  random-1.2.1.2's `System/Random/Internal.hs` and `System/Random.hs`
  (the `UniformRange` instances: `unsignedBitmaskWithRejectionRM`,
  `signedBitmaskWithRejectionRM`, the `Integer` algorithm
  `boundedExclusiveIntegralM`, `uniformDouble01M` /
  `uniformDoublePositive01M`, the Bool and Char instances, and
  `Random`'s `random = randomR (minBound, maxBound)` vs the Double
  `random = randomR (0, 1)` - whatever 1.2.1.2 actually does).
  The StatefulGen monad machinery is NOT reproduced: write each
  algorithm directly as a pure `g -> (a, g)` function over StdGen,
  preserving the exact sequence of `genWord64`/`genWord32` calls.
- Global generator: random-1.2 keeps it in an IORef created with
  `unsafePerformIO`; AHC has no unsafePerformIO, so add one primitive:
  `primGlobalRef :: Int -> IO (IORef a)` - returns the IORef in slot
  N, creating it (holding unit) on first call; the slots are a small
  static C array registered as GC roots the same way CAF globals are
  (read how `ahc_rts.c` roots CAFs for BOTH collectors - Boehm and
  `AHC_GC=own`; the own collector's permanent constraints are in the
  auto-memory note `ahc-collector.md` - an unrooted slot is a
  live-data-loss bug). System.Random uses slot 0 holding
  `Maybe StdGen`.
- Seeding (`initStdGen`, first `getStdGen`): random-1.2 seeds from the
  clock/entropy - nondeterministic. Add `primClockNanos :: IO Int`
  (`clock_gettime(CLOCK_REALTIME)` in nanoseconds) unless an
  equivalent prim exists (`grep -n "clock_gettime\|getCPUTime"
  runtime/ahc_rts.c src/ahc-builtins.adb` first and reuse it).
- [x] **Known-answer regression** `lib_random.hs` (stdout,
      deterministic): for seeds `[0, 1, 42, -1, maxBound :: Int]`:
      `take 1000 (randoms g :: [Int])`, `take 1000 (randoms g ::
      [Double])`, `take 1000 (randoms g :: [Bool])`, `take 1000
      (randomRs (1, 6 :: Int) g)`, `take 100 (randomRs ('a','z') g)`,
      `take 100 (randomRs (-10^30, 10^30 :: Integer) g)`,
      `take 100 (randomRs (-1.5, 2.5 :: Double) g)`, and `show` of
      the generator after 10 `split`/`random` steps. Print sums and
      the first/last 5 elements of each list rather than all 1000 to
      keep the golden readable - but sum ALL of them, so any drift
      anywhere shows.
- [x] **Property regression** `tests/exec/random_io.hs`: `randomRIO
      (1, 6)` 1000 times all in range; two `newStdGen` give different
      first values; `setStdGen (mkStdGen 7) >> getStdGen` shows the
      same as `mkStdGen 7`; prints only booleans, so the `.out` is
      deterministic (oracle with runghc).
- [x] **Commit** `feat(lib): system.random, bit-for-bit random-1.2 on splitmix`

**Gate (Phase D):** `./scripts/run_gate.sh` → `GATE ok` (exec-own
exercises the new GC roots), `lib_splitmix` and `lib_random`
byte-identical, `random_io` passing, plus
`AHC_OWN_VERIFY=1 ./scripts/run_own_soak.sh --quick` → PASS (new
roots).

**Phase D results:** `run_gate.sh` → unit/conformance/exec/exec-own/
golden all rc=0, `GATE ok`. `lib_splitmix` (82 lines) and
`lib_random` (229 lines: 5 seeds x 26 list summaries, reversed and
degenerate ranges, uniform/uniformR, pairs/triples, genWord*R, split,
plus two user generators that rely on RandomGen's defaults, one via
`next`/`genRange`) byte-identical to random-1.2.1.2/splitmix-0.1.3.2
FIRST RUN. `random_io` passes under both collectors; a global-slot
churn program matches GHC under `AHC_GC=own` + `AHC_OWN_VERIFY=1` at
64KB/256KB/4MB floors. Own soak (`AHC_OWN_VERIFY=1 --quick`): `OWN SOAK: PASS`. Deviations: (1)
`primGlobalRef :: Int -> a -> IO (IORef a)` takes the initial value
instead of creating the cell holding unit - reading a unit cell at
`Maybe StdGen` would rely on constructor-tag coincidence; (2) the
seed prim is `primEntropySeed` (getentropy), not `primClockNanos`:
splitmix's `initialSeed` on unix/macOS IS `splitmix_init` = OS
entropy, and CLOCK_REALTIME is microsecond-grained on Darwin (two
`initStdGen` in a row came out equal); (3) Float draws match but
compute at double precision (AHC's Float is a double); IO functions
are at IO, not MonadIO. Golden diff renumber-only (stripped-id
comparison identical for core_class_dict/core_exprs/core_patterns).

---

## Phase E - System.Directory, System.Process

**Result (landed 6b7bf7a; reworked by the review round):** System.Directory has the package's renameFile/createDirectoryIfMissing/setCurrentDirectory texts and the passwd HOME fallback (lib_directory_errors.hs); System.Process captures per stream (readProcess inherits stderr), feeds stdin lazily, keeps every pipe end close-on-exec at fd >= 3, raises GHC's decoding/null-command/waitForProcess errors and releases everything on every throw path (tests/exec/process_streams.hs). The security pass below is still owed.

All primitives raise `IOError` through the runtime's existing
`exc_throw_io(type, loc, desc, path)` (`ahc_rts.c:3019`, errno type via
`ioe_type_of_errno`), so `show` of the error matches GHC's
`<path>: <loc>: <type text> (<strerror>)` - each error text is pinned
by an exec test oracled against runghc. Strings cross into C as
`Text` via `primTextPack` (the M140 pattern: `lib/Network/Socket.hs:41`,
C reads `u.bytes.len` + `text_bytes`). A NUL byte inside a path or
argument raises `IOError` (`InvalidArgument`) instead of truncating:
check `memchr(bytes, 0, len)` before building the C string.

### Task E1: System.Directory

**Files:** Create `lib/System/Directory.hs`,
`tests/exec/directory_ops.hs` + `.out`. Modify builtins, prelude_core,
`ahc_rts.c`/`.h`.

Prims (all `IO`): `primDirExists :: Text -> IO Bool` (stat + S_ISDIR),
`primFileExists :: Text -> IO Bool` (stat + !S_ISDIR),
`primListDir :: Text -> IO [Text]` (opendir/readdir, ALL entries
including `.` and `..`, OS order), `primMkDir :: Text -> IO ()`
(mkdir 0777), `primRmFile`, `primRmDir`, `primRename :: Text -> Text ->
IO ()`, `primGetCwd :: IO Text`, `primSetCwd :: Text -> IO ()`,
`primGetEnv`-based `getHomeDirectory` (reuse System.Environment's prim
for `HOME`). Haskell side:

```haskell
listDirectory :: FilePath -> IO [FilePath]
listDirectory p = fmap (filter (\n -> n /= "." && n /= "..")) (getDirectoryContents p)

createDirectoryIfMissing :: Bool -> FilePath -> IO ()
createDirectoryIfMissing parents p
  | parents   = mapM_ mkIfMissing (prefixes p)
  | otherwise = mkIfMissing p
  where
    mkIfMissing d = do
      e <- doesDirectoryExist d
      if e then return () else createDirectory d
    prefixes q = [ take n q | n <- [1 .. length q], n == length q || q !! n == '/', take n q /= "" ]
```

GHC's `loc` strings (e.g. `removeLink`, `getDirectoryContents:openDirStream`,
`createDirectory`) are whatever runghc prints - copy them from the
oracle output into the C `exc_throw_io` calls.

- [x] **Regression** `tests/exec/directory_ops.hs`: creates
      `m142_tmp/a/b` with `createDirectoryIfMissing True`, writes a
      file, `doesFileExist`/`doesDirectoryExist` on file/dir/missing,
      `sort <$> listDirectory`, `renameFile`, `removeFile`,
      `removeDirectory` (non-empty: caught IOError printed with
      `show`), `getCurrentDirectory` (prints only `isSuffixOf "m142_tmp"`
      after `setCurrentDirectory`), cleans up. Run from the test's own
      temp directory; the `.out` is runghc's.
- [x] **Commit** `feat(lib): system.directory over posix`

### Task E2: System.Process

**Files:** Create `lib/System/Process.hs`, `tests/exec/process_ops.hs`
+ `.out`. Modify builtins, prelude_core, `ahc_rts.c`/`.h`.

One C primitive does the work:
`primRunProcess :: Text -> [Text] -> Bool -> Maybe Text -> IO (Int, Text, Text)`
- program, arguments, `useShell`, stdin input (Nothing = inherit
stdin, stdout and stderr; Just s = pipe all three, feed s, capture both
outputs). Implementation: build argv (`/bin/sh -c <cmd>` when
`useShell`), `posix_spawn_file_actions` for the pipes, `posix_spawnp`;
when capturing, a `poll()` loop that writes stdin (closing it when
done) and drains stdout and stderr together until both reach EOF -
the standard no-deadlock shape; then `waitpid`. Exit status: normal
exit → the code; killed by signal n → `-n` (GHC's `ExitFailure (-n)`).
Spawn failure (ENOENT) → `exc_throw_io` with GHC's text for a missing
executable (copy from the oracle). This blocks the scheduler while the
child runs (a deliberate simplification over the spec's "scheduler
parking": the process API is used at program edges; documented in
EXCLUSIONS - green threads do not progress during `readProcess`).

Haskell side (`ExitCode` from `System.Exit`):

```haskell
system :: String -> IO ExitCode
system cmd = do
  (c, _, _) <- primRunProcess (primTextPack cmd) [] True Nothing
  return (toExit c)

rawSystem :: String -> [String] -> IO ExitCode
rawSystem p as = do
  (c, _, _) <- primRunProcess (primTextPack p) (map primTextPack as) False Nothing
  return (toExit c)

callProcess :: FilePath -> [String] -> IO ()
callProcess p as = do
  r <- rawSystem p as
  case r of
    ExitSuccess   -> return ()
    ExitFailure n -> ioError (userError ("callProcess: " ++ unwords (p : as) ++ " (exit " ++ show n ++ "): failed"))

callCommand :: String -> IO ()
readProcess :: FilePath -> [String] -> String -> IO String
readProcessWithExitCode :: FilePath -> [String] -> String -> IO (ExitCode, String, String)

toExit :: Int -> ExitCode
toExit 0 = ExitSuccess
toExit n = ExitFailure n
```

`callCommand` and `readProcess`'s failure texts: copy runghc's exact
output (`readCreateProcess: <cmd> (exit 1): failed`) - the
`callProcess` text above is the expected shape, verify it.

- [x] **Regression** `tests/exec/process_ops.hs`: `system "echo hi"`,
      `rawSystem "/bin/echo" ["a b", "c"]` (one argv element with a
      space - proves no shell), `readProcess "/bin/cat" [] "piped\n"`,
      `readProcessWithExitCode "/bin/sh" ["-c", "echo out; echo err 1>&2; exit 3"] ""`,
      a 200 KB stdin through `/bin/cat` (deadlock check),
      `callProcess "/usr/bin/false" []` caught and shown, a missing
      executable caught and shown, `system "kill -9 $$"` →
      `ExitFailure (-9)`. Stdout unbuffered; `.out` from runghc 2>&1.
- [x] **Commit** `feat(lib): system.process over posix_spawn, with no shell unless asked`
- [ ] **Security pass:** run `/security-review` on the branch (it
      spawns processes and touches the filesystem - CLAUDE.md step 5).
      Every finding is fixed or explicitly accepted in this plan file
      with a reason.

**Gate (Phase E):** `./scripts/run_gate.sh` → `GATE ok` (exec and
exec-own run both new exec tests); `/security-review` with no
unresolved finding; `./scripts/run_tsan.sh` green (new C code).

---

## Phase F - scout, review, write-up, release

### Task F1: repos

- [ ] Re-run `scripts/scout_repos.sh try <repo>` for every round-two
      candidate whose blocker was an in-scope module (the list is in
      `docs/repos-to-try.md` "What usually blocks a repo" and the
      scout's own notes; search the scout cache `/tmp/ahc-scout/` and
      `git log -p docs/repos-to-try.md` for the names). Every repo
      that now AGREES / AGREES-BANNER is tabled with its command;
      each new failure is a finding for F2.

### Task F2: adversarial review

- [ ] Run the `adversarial-review` skill over `git diff v1.15..HEAD`.
      Targets: trace ordering under the optimizer, Map.Strict
      strictness holes (a function that should force but stores a
      thunk), toRational at subnormals/NaN/negative zero, Printf flag
      combinations, random-1.2 exactness at range edges (`randomR
      (x, x)`, reversed ranges `(6, 1)`, `minBound/maxBound`), GC
      rooting of the global-ref slots under `AHC_GC=own`, process
      pipes (large output on stderr only, a child that closes stdin
      early, EINTR), NUL bytes in paths/args.
- [ ] Findings land as one commit `fix: N defects an adversarial review of M142 found`.

### Task F3: merge M143/M144, gate, docs, release

- [ ] If the M143/M144 branch has landed, merge it; resolve any lib/
      conflicts by keeping both sides' intent.
- [ ] Docs: EXCLUSIONS rows (Debug.Trace ordering note if any,
      Control.Monad.State's class-free API, System.Process blocking
      the scheduler, Random's nondeterministic entry points), MANUAL
      library chapter, repos-to-try (strike closed blockers, add
      repos), CHANGES v1.16, README release history.
- [ ] Version: `src/ahc.ads` 1.16, `alire.toml` 1.16.0, rebuild,
      `./scripts/check_version.sh v1.16` → `VERSION ok`.
- [ ] Release commit, annotated tag, push, `gh release create` - ONLY
      after the user approves the release.

**Gate (milestone):** `./scripts/run_gate.sh` → `GATE ok` on the
rebuilt compiler; both differential suites; `AHC_OWN_VERIFY=1
./scripts/run_own_soak.sh` → PASS; `./scripts/run_fuzz_par.sh 300 6 1`
→ 300 ok; bench A/B against v1.15 (interleaved best-of-5, release
builds) recorded in CHANGES; `/security-review` clean; adversarial
review verdict GO recorded here.

---

## Self-review

**Spec coverage.** Debug.Trace → A1; Data.Map.Strict → A2;
toRational → A3; Control.Monad.State (+ Identity) → B1/B2; instances
over (->) → C1; Text.Printf → C2 (its float formatting prerequisite)
+ C3; System.Random → D0-D2 (oracle install, known-answer gate);
System.Directory → E1; System.Process → E2 (+ security review);
scout/review/release → F1-F3. Out-of-scope modules are untouched.

**Deviations from the spec, stated.** (1) Lib conformance programs
are flat `tests/conformance/lib_*.hs`, not a `lib/` subdirectory - the
existing layout. (2) Debug.Trace and Printf's error texts are verified
by EXEC tests, because the conformance runner discards stderr. (3)
System.Process blocks the scheduler while a child runs instead of
parking on the fds; recorded in EXCLUSIONS. (4) Phase C adds
`floatToDigits`/`show*Float` to Numeric - Printf's `%f/%e/%g` need
them and they did not exist. (5) `(->)` is not added to the renamer's
builtin-syntax list (that file belongs to the concurrent M144 work);
under an explicit `import Prelude (...)`, `(->)` in an instance head
stays unresolved - noted for F2.

**Placeholders.** Steps that say "copy from the oracle output" or
"transcribe from the 1.2.1.2 source" name the exact source and the
exact functions; the transcription target is GHC's own code, which
this plan must not paraphrase from memory.

**Consistency.** Prim names: `primTraceStr`, `primToRationalI`,
`primToRationalD`, `primGlobalRef`, `primClockNanos`, `primDirExists`,
`primFileExists`, `primListDir`, `primMkDir`, `primRmFile`,
`primRmDir`, `primRename`, `primGetCwd`, `primSetCwd`,
`primRunProcess` - each introduced once with its type. `ahc_ratio_tag`
is introduced in A3 and used only there.

**Gate audit.** Every phase ends in `run_gate.sh` (unit, conformance,
exec both GC modes, golden). Frontend change (C1) adds both
differentials + fuzz. New GC roots (D2) add the own-collector soak.
New C spawning code (E) adds TSan and the security review. The
milestone gate adds soak, fuzz, bench, review.
