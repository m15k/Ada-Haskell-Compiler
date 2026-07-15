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

Phases 1, 2 and 3 are complete: AHC compiles and runs Haskell programs.

```sh
scripts/ahc-build.sh Foo.hs   # Haskell -> C -> native executable
./Foo
```

Backend: `ahc emit` generates C over the AHC runtime
(`runtime/ahc_rts.{h,c}`) - call-by-need graph reduction with
update-in-place thunks, curried closures, generic constructor workers,
dictionary field selectors, and IO as world-passing actions - linked
against the Boehm-Demers-Weiser GC (plain malloc fallback). Covered at
runtime today: Int arithmetic/comparison, Bool/Char/String/list Show,
user ADTs with derived Eq/Ord (generic structural prims), user classes
with default methods, lazy infinite structures, do-notation IO.
Double/Rational arithmetic, tuple/Maybe Show and Integer bignum remain
error thunks until Phase 4's real Prelude.

Frontend: lexer with the full literal grammar, Report 10.3 layout
engine, recursive-descent parser for the whole Haskell 2010 surface,
Report 10.6 fixity resolution (`ahc parse`).

Middle end: renamer over a wired-in Prelude signature, kind inference,
desugaring to a System-FC-like Core (`ahc core`), Hindley-Milner
typechecking with type classes, the monomorphism restriction and
Report 4.3.4 defaulting (`ahc check`), and instance-dictionary
elaboration through the contract-checked Mk_Dict constructor.
Call-site dictionary application lands with Phase 3 code generation,
along with the C backend and Boehm GC runtime.

```sh
scripts/run_golden.sh              # golden lex/layout/parse/core/check
scripts/run_differential.sh        # parse-level GHC agreement
scripts/run_differential_types.sh  # type-level GHC agreement
scripts/run_exec.sh                # compile-and-run output goldens
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
