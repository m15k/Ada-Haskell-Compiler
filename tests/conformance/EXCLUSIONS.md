# Haskell 2010 Report features not exercised by this conformance subset

The suite covers what AHC implements; these Report features are known
gaps, excluded deliberately rather than tested weakly. Each entry is
the reason a conformance program does not exist for it.

| Report | Feature | Status |
|---|---|---|
| 5 | Module system corners | multi-module programs WORK (imports with qualified/as/hiding/lists, export lists incl. `T(..)`/`C(..)`, abstract types, cycle/ambiguity/not-exported errors); restricting the implicit Prelude import WORKS per Report 5.6.1 (`hiding`, only-lists, `import Prelude ()`, `qualified` - the explicit import replaces the implicit one, filters the qualified view too, and builtin syntax `()`/`[]`/`:`/tuples stays in scope; ext_prelude_*.hs conformance + bad_prelude_*.hs both-reject differentials). Still flat, and a clean compile ERROR where GHC would accept: same-named type SYNONYMS in two modules ("type 'T' is defined more than once") and same-named data CONSTRUCTORS in two modules ("constructor 'C' is defined more than once") - both namespaces are program-global, so qualified imports cannot disambiguate them; rename the colliding declaration. Code generation, C compilation and linking are separate and per-module (content-hash object cache; scripts/run_separate.sh); the FRONTEND stays whole-program by design - no interface files - which is what gives Report program-wide instance coherence for free |
| 6.4 | `Rational` literals | `Data.Ratio.Rational` works (exact bignum fractions, `%`, arithmetic, GHC-format Show) but a FLOAT literal at Rational (`2.5 :: Rational`) has no `fromRational`; `Int` overflow promotes rather than wrapping, which Report 6.4 leaves undefined |
| lib | `Data.Array`/`Text.Read` are monomorphic subsets | `Ratio a` and `Complex a` are POLYMORPHIC as of the polish milestones (lib_poly_ratio_complex.hs); Array stays at Int indices (list-backed, O(n) reads) and Read at Int/Integer/Bool/lists/pairs; float literals at Ratio still lack fromRational |
| 6.4.3 | `RealFrac` results at `Integer` | `Integral`/`Floating`/`RealFrac` are real classes (instances Int/Integer and Double; fromIntegral/(^)/(^^) polymorphic), but floor/ceiling/round/truncate return `Integer` rather than `Integral b => b` (GHC defaults `b` there anyway); `properFraction` works (result at Integer), and `RealFloat` is a real class at Double (isNaN/isInfinite/isNegativeZero/atan2 - ch06_04_realfloat.hs); decodeFloat/encodeFloat and radix introspection are absent |
| 6.3.4 | ~~`Enum` at Char/Double~~ WORKS | `['a'..'z']`, succ/pred/to/fromEnum at Char; Double numeric enumeration with GHC's k-indexed stepping and the half-step limit (ch06_03_enum_char_double.hs); Bool/Ordering enum now ride the enumeration-derive machinery (`[False ..]` works) |
| 11.1 | deriving covers ENUMERATIONS for Enum/Bounded/Ix/Read | `Eq`/`Ord`/`Show` derive for all shapes (ch11_01_derives.hs pins the enumeration derives); non-nullary deriving Enum/Bounded/Ix/Read is not rejected but yields error stubs (GHC rejects at compile time); deriving Read for non-enumerations is unimplemented |
| 3.14 | ~~`fail` at `Maybe`/`[]`~~ WORKS | refutable do-binds fail to Nothing / skip per the Report (ch03_14_faildo.hs); IO's fail errors, as GHC's does |
| ch. 4 | Class-hierarchy corners | `Functor`/`Applicative` (pure/`<*>`/`*>`/`<*`/`<$>`, ch04_applicative.hs) and `Read` work at Maybe/[]/IO; `Monad` does NOT have `Applicative` as superclass (the 2010 shape - `return` and `pure` are separate but agree) |

| lib | `Data.Char` classification is ASCII-only | GHC's predicates are Unicode-aware; conformance programs stay in ASCII |
| lib | ~~`Data.List.foldl'` is `foldl`~~ WORKS | `seq` is a real primitive (force to WHNF), `($!)` builds on it, and `foldl'` keeps its accumulator evaluated (ch06_02_seq.hs values; tests/exec/seq_strict.hs pins the forcing itself) |
| lib | `Data.Bits` is monomorphic at `Int` | GHC's is `Bits a`-polymorphic; AHC's is often MORE permissive at defaulting boundaries, GHC-oracle tests annotate |
| lib | `Data.Ix` uses are not defaultable | AHC's Report-4.3.4 defaulting covers Prelude classes only; annotate `range (3, 7) :: [Int]` |
| lib | ~~`System.IO` handles~~ WORK | openFile/hClose/withFile, hPutStr/hPutStrLn/hPutChar/hPrint, hGetLine/hGetChar/hGetContents/hIsEOF/hFlush, writeFile/appendFile, stdin/stdout/stderr, IOMode with GHC's derived instances (ch07_io_handles.hs; error paths in tests/exec/handle_*.hs). Two documented divergences: `hGetContents` is STRICT (GHC's is lazy with semi-closed handles - portable programs must not touch a handle after it anyway), and `hClose` on a std stream flushes instead of closing (closing stdout would break the runtime's own writers) |
| lib | `Control.Monad.guard` / MonadPlus | no MonadPlus class |

Runtime warnings differ by design: GHC's `-W` diagnostics are not
part of conformance (the oracle captures stdout only).
