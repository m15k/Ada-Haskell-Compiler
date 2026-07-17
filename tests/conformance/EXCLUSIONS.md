# Haskell 2010 Report features not exercised by this conformance subset

The suite covers what AHC implements; these Report features are known
gaps, excluded deliberately rather than tested weakly. Each entry is
the reason a conformance program does not exist for it.

| Report | Feature | Status |
|---|---|---|
| 5 | Module system corners | multi-module programs WORK (imports with qualified/as/hiding/lists, export lists incl. `T(..)`/`C(..)`, abstract types, cycle/ambiguity/not-exported errors); not covered: `module M` re-exports, restricting the implicit Prelude import, same-named type synonyms in two modules, and separate compilation (AHC compiles the program whole) |
| 6.4 | `Rational`, `toRational`/`fromRational` beyond Double literals | no runtime (`Integer` IS arbitrary-precision now; `Int` overflow promotes rather than wrapping, which Report 6.4 leaves undefined) |
| 6.4.3 | `Floating`/`RealFrac` as CLASSES | the full vocabulary (pi, exp/log/sqrt, `**`, logBase, trig, hyperbolics, floor/ceiling/round/truncate, fromIntegral) works, monomorphic at Double/Int |
| 6.3.4 | `Enum` at Char/Double (`['a'..'z']`) | `Enum` is complete at `Int` (incl. stepped ranges, succ/pred, to/fromEnum); other types have no runtime |
| 11.1 | `deriving (Enum, Bounded, Ix, Read)` | `Eq`/`Ord`/`Show` derive |
| 11.4 | class defaults for builtin classes | a user-written `Show` instance defining only `show` gets error thunks for `showsPrec`/`showList` (the Report's class defaults); library and derived instances define all three |
| 3.14 | `fail`-desugared refutable do-binds at `Maybe`/`[]` | Monad runtimes cover `IO` and `[]` bind/return only |
| ch. 4 | Class-hierarchy completeness (`Functor`/`Applicative` law programs, `Read`) | signatures wired, no runtime |

Runtime warnings differ by design: GHC's `-W` diagnostics are not
part of conformance (the oracle captures stdout only).
