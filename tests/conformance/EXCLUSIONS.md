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
| 6.3.4 | `Enum` at Char/Double (`['a'..'z']`) | `Enum` is complete at `Int` (incl. stepped ranges, succ/pred, to/fromEnum); other types have no runtime |
| 11.1 | `deriving (Enum, Bounded, Ix, Read)` | `Eq`/`Ord`/`Show` derive |
| 11.4 | class defaults for builtin classes | a user-written `Show` instance defining only `show` gets error thunks for `showsPrec`/`showList` (the Report's class defaults); library and derived instances define all three |
| 3.14 | `fail`-desugared refutable do-binds at `Maybe`/`[]` | Monad runtimes cover `IO` and `[]` bind/return only |
| 4.4.3.1 | Pattern guards beyond boolean guards | boolean-only |
| ch. 4 | Class-hierarchy completeness (`Functor`/`Applicative` law programs, `Read`) | signatures wired, no runtime |

Runtime warnings differ by design: GHC's `-W` diagnostics are not
part of conformance (the oracle captures stdout only).
