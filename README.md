# AHC — Ada Haskell Compiler

A ground-up compiler for [Haskell 2010](https://www.haskell.org/onlinereport/haskell2010/)
written in Ada 2022, built around Design-by-Contract: preconditions,
postconditions, and type invariants verify the compiler's own internal
consistency in every development build. See `docs/adahc PRD.rtf` for the
full product requirements.

## Building

Requires [Alire](https://alire.ada.dev/) with a GNAT ≥ 13 toolchain
(`alr toolchain --select gnat_native gprbuild`).

```sh
alr build --validation   # all contracts enabled (default for development)
alr build --release      # contracts compiled out
./bin/ahc --version
```

## Testing

```sh
cd tests
alr build --validation
./bin/ahc_tests
```

The tests crate always builds with contracts enabled; some tests assert
that violated contracts actually raise `Assert_Failure`.

## Status

Phase 1 (frontend) is complete: lexer with the full literal grammar,
Report 10.3 layout engine, recursive-descent parser for the whole
Haskell 2010 surface, and Report 10.6 fixity resolution.
`ahc parse Foo.hs` prints a canonical AST dump. Next up: Phase 2, the
desugarer to a System-FC-like Core and the Hindley-Milner typechecker.

```sh
scripts/run_golden.sh          # golden lex/layout/parse expectations
scripts/run_differential.sh    # agree-with-GHC corpus check (needs ghc)
```

## Layout

```
src/          AHC.* packages (one spec/body pair per package)
src/ahc_main.adb   CLI driver (builds as ./bin/ahc)
tests/        nested Alire crate with the unit test runner
tests/golden/ golden lex/parse expectations
tests/corpus/ realistic modules for GHC-differential checks
scripts/      test harness scripts
```
