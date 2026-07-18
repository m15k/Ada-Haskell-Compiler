# Plan: An AHC Standard Library

**Status:** M47-M53 SHIPPED, including enablers E4 and E5 - the
roadmap below is implemented except the deferred section.
**Target:** the useful subset of the Haskell 2010 *Library Report*
(Part II), delivered as ordinary Haskell modules compiled by AHC.

## 1. The central insight

Multi-module compilation (v1.0, M43-M44) changed what "standard
library" means for this compiler. Before it, library code had to be
wired into `AHC.Builtins` or hand-built as Core in
`AHC.Prelude_Core`. Now a library module is a plain `.hs` file with
an export list, found by the driver, compiled through the full
pipeline like user code - exactly the architecture the source
Prelude proved at Phase 4, with the module system providing the
namespacing the Prelude never had.

So this is mostly a *Haskell-writing* project, not a
compiler-hacking one. The compiler work is a short list of enablers;
everything else is `.hs` files plus GHC-oracle tests.

## 2. Compiler enablers (small, ordered)

| # | Enabler | Why | Size |
|---|---|---|---|
| E1 | **Library search path**: the driver resolves `import Data.List` by looking in the root file's directory, then `lib/` beside the compiler (and `$AHC_LIB` when set) | today `Module_Path` searches only beside the root file | small (driver) |
| E2 | **Input prims**: `getLine`, `getContents`, `readFile`, `getArgs`, `getProgName` | AHC has zero input capability today - output only | small (RTS + builtins sigs + `Bind_Name`) |
| E3 | **Monad dictionary completion**: real `return`/`fail` entries for IO and `[]`, and a `Maybe` Monad runtime | `Control.Monad` and do-notation over `Maybe` need them | small (Prelude_Core) |
| E4 | **Class defaults for builtin classes** (from EXCLUSIONS): populate `Default_Binds` for Show/Eq/Ord so library instances can define the minimal method set | library modules define many instances; writing all three Show methods each time does not scale | medium (Builtins + typechecker default pass interaction) |
| E5 | **`module M` re-exports** (from EXCLUSIONS) | lets `Prelude` eventually re-export `Data.List` subsets instead of duplicating them | medium (rename export filter) - *deferred until it hurts* |

E1-E3 unblock everything in section 3; E4 improves ergonomics but
nothing hard-depends on it; E5 is optional polish.

## 3. Module roadmap

Milestones continue the project numbering. Every module ships with
GHC-oracle conformance programs (`tests/conformance/lib/`) - the
same byte-identical standard as the rest of the suite - and its
exclusions documented.

### M47 - infrastructure
E1 search path; `lib/` tree; harness extension (a lib conformance
runner that compiles against `lib/`); one seed module end to end.

### M48 - pure data modules (no new runtime at all)
- **`Data.Maybe`** - maybe, fromMaybe, isJust/isNothing, listToMaybe,
  maybeToList, catMaybes, mapMaybe (move the Prelude's helpers here;
  Prelude keeps its Report-mandated subset).
- **`Data.Tuple`** - fst, snd, curry, uncurry, swap.
- **`Data.Bool`** - bool, (&&), (||), not, otherwise.
- **`Data.Ord`** - comparing, Down (needs a newtype + Ord instance -
  exercises deriving across module boundaries).
- **`Data.List`** - the flagship: sort/sortBy (merge sort),
  insert/insertBy, nub/nubBy, delete/(\\\\)/union/intersect,
  group/groupBy, partition, find, findIndex/elemIndex/elemIndices,
  isPrefixOf/isSuffixOf/isInfixOf, transpose, intercalate/
  intersperse, subsequences, permutations, zip3/zipWith3/unzip3,
  scanl/scanr/scanl1/scanr1, iterate', tails/inits, maximumBy/
  minimumBy, foldl'-equivalent (strictness caveat documented).
- **`Data.Char`** - isUpper/isLower/isAlpha/isDigit/isSpace/
  isAlphaNum/isPunctuation (ASCII table in pure Haskell),
  toUpper/toLower, digitToInt/intToDigit, ord/chr (re-exported
  prims).

### M49 - Control.Monad (needs E3)
when, unless, void, forever, mapM/forM, sequence, replicateM(_),
filterM, foldM, zipWithM(_), (>=>), (<=<), join, guard (at the
supported monads: IO, [], Maybe). Also `Data.Functor` basics
((<$>), fmap at the supported functors).

### M50 - system modules (needs E2)
- **`System.Environment`** - getArgs, getProgName.
- **`System.IO`** - getLine, getContents, readFile, interact,
  putStr/putStrLn/print re-exports; handles beyond
  stdin/stdout/stderr documented as excluded.
- **`System.Exit`** - exitSuccess, exitFailure, exitWith (prim).

### M51 - numeric text + indexing
- **`Numeric`** - showHex/showOct/showBin, readHex/readOct/readDec
  (pure), showFFloat/showEFloat over the existing Double formatter.
- **`Data.Bits`** at Int - .&., .|., xor, shiftL/R, complement,
  testBit, popCount (a handful of trivial C prims).
- **`Data.Ix`** - range, index, inRange for Int/Char/tuples.

### Deferred (blocked, documented)
- **`Data.Ratio`** - blocked on a Rational runtime (pair-of-Integer
  arithmetic; a natural follow-on to bignum but its own project).
- **`Data.Complex`** - blocked on Floating as a class.
- **`Data.Array`** - possible list-backed, but honest O(n) indexing;
  defer until someone needs it.
- **Read instances** - a parser library in disguise; out of scope.

## 4. Testing and conformance discipline

Unchanged from v1.0 practice, which is the point:

1. Every library function lands with a conformance program whose
   golden is GHC's output (`runghc` against the same source using
   GHC's real library - so the oracle tests our *implementations*
   against the canonical ones, not against themselves).
2. Anything we cannot match byte-for-byte goes to EXCLUSIONS.md
   with the reason, never silently weakened.
3. `Data.List`'s laziness contracts get explicit programs
   (`take 3 (cycle [1,2])`, `head (sort ...)` is NOT lazy - match
   GHC's actual strictness where observable).

## 5. Sequencing and effort

E1 -> M48 is the high-value core (Data.List alone is most of what
users miss day-to-day) and needs no runtime work at all. E2/E3 are
each an afternoon. Rough shape: M47+M48 first (one stretch), then
M49/M50 in either order, M51 last. Each milestone is independently
shippable and keeps the full suite green, per house rules.
