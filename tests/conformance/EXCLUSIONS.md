# Haskell 2010 Report features not exercised by this conformance subset

The suite covers what AHC implements; these Report features are known
gaps, excluded deliberately rather than tested weakly. Each entry is
the reason a conformance program does not exist for it.

| Report | Feature | Status |
|---|---|---|
| 5 | Module system corners | multi-module programs WORK (imports with qualified/as/hiding/lists, export lists incl. `T(..)`/`C(..)`, abstract types, cycle/ambiguity/not-exported errors); not covered: restricting the implicit Prelude import and same-named type synonyms in two modules. Code generation, C compilation and linking are separate and per-module (content-hash object cache; scripts/run_separate.sh); the FRONTEND stays whole-program by design - no interface files - which is what gives Report program-wide instance coherence for free |
| 6.4 | `Rational` literals | `Data.Ratio.Rational` works (exact bignum fractions, `%`, arithmetic, GHC-format Show) but a FLOAT literal at Rational (`2.5 :: Rational`) has no `fromRational`; `Int` overflow promotes rather than wrapping, which Report 6.4 leaves undefined |
| lib | `Data.Complex`/`Data.Array`/`Text.Read` are monomorphic subsets | Complex is at Double, Array at Int indices (list-backed, O(n) reads), Read covers Int/Integer/Bool/lists/pairs; GHC-oracle programs annotate accordingly |
| 6.4.3 | `RealFrac` results at `Integer` | `Integral`/`Floating`/`RealFrac` are real classes (instances Int/Integer and Double; fromIntegral/(^)/(^^) polymorphic), but floor/ceiling/round/truncate return `Integer` rather than `Integral b => b` (GHC defaults `b` there anyway); `properFraction` and `RealFloat` (beyond a monomorphic atan2) are absent |
| 6.3.4 | `Enum` at Char/Double (`['a'..'z']`) | `Enum` is complete at `Int` (incl. stepped ranges, succ/pred, to/fromEnum); other types have no runtime |
| 11.1 | `deriving (Enum, Bounded, Ix, Read)` | `Eq`/`Ord`/`Show` derive |
| 3.14 | ~~`fail` at `Maybe`/`[]`~~ WORKS | refutable do-binds fail to Nothing / skip per the Report (ch03_14_faildo.hs); IO's fail errors, as GHC's does |
| ch. 4 | Class-hierarchy corners | `Functor`/`Applicative` (pure/`<*>`/`*>`/`<*`/`<$>`, ch04_applicative.hs) and `Read` work at Maybe/[]/IO; `Monad` does NOT have `Applicative` as superclass (the 2010 shape - `return` and `pure` are separate but agree) |

| lib | `Data.Char` classification is ASCII-only | GHC's predicates are Unicode-aware; conformance programs stay in ASCII |
| lib | `Data.List.foldl'` is `foldl` | AHC has no `seq`; observable results agree, strictness does not |
| lib | `Data.Bits` is monomorphic at `Int` | GHC's is `Bits a`-polymorphic; AHC's is often MORE permissive at defaulting boundaries, GHC-oracle tests annotate |
| lib | `Data.Ix` uses are not defaultable | AHC's Report-4.3.4 defaulting covers Prelude classes only; annotate `range (3, 7) :: [Int]` |
| lib | `System.IO` handles | only stdin/stdout are real; no openFile/hClose, `readFile` reads whole files |
| lib | `Control.Monad.guard` / MonadPlus | no MonadPlus class |

Runtime warnings differ by design: GHC's `-W` diagnostics are not
part of conformance (the oracle captures stdout only).
