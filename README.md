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

All four phases are complete: AHC compiles and runs Haskell programs
against a Prelude written in Haskell and compiled by AHC itself, and
adds an Ada-style refinement-types extension.

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

Standard library: `prelude/Prelude.hs` is compiled through the full
pipeline ahead of every user module - list/tuple/Maybe/Either
functions with signatures, the Either type, and Show instances for
tuples, Maybe and Either as ordinary context-parametrized Haskell
instances, elaborated to dictionary functions like any user code.
The class hierarchy, numeric primitives and IO remain wired in
AHC.Builtins / AHC.Prelude_Core.

Extension - Ada-style refinement types
(`docs/refinement-types-design-note.md`): ranges `type Percent = Int
in 0 .. 100`, predicates `type Nat = Int satisfying (\n -> n >= 0)`
/ `Color satisfying isWarm` (any nullary base type; predicates are
ordinary typechecked Haskell compiled to hidden top-level functions,
so class-constrained predicates like `even` just work), and modular
types `type Clock = Int mod 12` with Ada-style wraparound - values
crossing a declared boundary normalize into `[0, N)`, so
`(25 :: Clock)` is 1 and incrementing a `Byte` past 255 wraps to 0.
Refined types are erased for unification (transparent arithmetic, no
smart constructors); ranges and predicates are lazily-fired checks
at signature and annotation boundaries, and `ahc emit --unchecked`
(or `AHC_UNCHECKED=1 scripts/ahc-build.sh`) compiles the checks out,
mirroring Ada's release-mode contract policy - modular wrapping is
arithmetic semantics, not a check, so it is always applied.

Remaining gaps: Double/Rational arithmetic and Integer bignum (Int is
a C long), the Integral class proper, pattern guards, multi-module
imports, exhaustiveness warnings, and Show for String prints as a
char list (needs the Report's showList method).

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
