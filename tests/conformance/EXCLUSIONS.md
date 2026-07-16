# Haskell 2010 Report features not exercised by this conformance subset

The suite covers what AHC implements; these Report features are known
gaps, excluded deliberately rather than tested weakly. Each entry is
the reason a conformance program does not exist for it.

| Report | Feature | Status |
|---|---|---|
| 5 | Multi-module programs, imports/exports | single-module compiler; only the `module M where` header parses |
| 6.4 | `Integer` bignum | `Int`/`Integer` are a C `long` |
| 6.4 | `Rational`, `toRational`/`fromRational` beyond Double literals | no runtime |
| 6.4.3 | `Floating`/`RealFrac` classes (`sqrt`, `pi`, trig, `floor`, ...) | error thunks |
| 6.3.4 | `Enum` beyond `Int` (`succ`, `pred`, Char/Double ranges, stepped `[a,b..c]`) | only `enumFrom`/`enumFromTo` at `Int` have runtimes |
| 11.1 | `deriving Show`, `deriving (Enum, Bounded, Ix, Read)` | only `Eq`/`Ord` derive |
| 11.4 | `showList` / `showsPrec` proper | `show` on a `String` prints a char list; nested-constructor parenthesization uses the source Prelude's heuristic |
| 9   | `words`, `lines`, `span`, `break`, `splitAt`, `unzip`, folds1 | not in the source Prelude yet |
| 3.14 | `fail`-desugared refutable do-binds at `Maybe`/`[]` | Monad runtimes cover `IO` and `[]` bind/return only |
| 4.4.3.1 | Pattern guards beyond boolean guards | boolean-only |
| ch. 4 | Class-hierarchy completeness (`Functor`/`Applicative` law programs, `Read`) | signatures wired, no runtime |

Runtime warnings differ by design: GHC's `-W` diagnostics are not
part of conformance (the oracle captures stdout only).
