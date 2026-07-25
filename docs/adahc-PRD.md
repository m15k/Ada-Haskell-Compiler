**Product Requirements Document (PRD)**

Project Name: Ada Haskell Compiler (AHC)

Document Version: 1.1 **Date:** July 2026

**1. Executive Summary**

The **Ada Haskell Compiler (AHC)** is a new, ground-up implementation of
a Haskell compiler written entirely in Ada 2022. The objective is to
create a highly reliable, formally verifiable, and robust compiler for
the Haskell 2010 specification. By leveraging Ada\'s powerful type
system, Design-by-Contract (DbC) features, and strict memory management,
AHC aims to eliminate entire classes of bugs typical in compiler
development (such as memory leaks, null pointer dereferences, and
invariant violations during type inference).

**2. Goals and Objectives**

- Compliance: Implement the Haskell 2010 Language Report specifications
  as faithfully as possible.

- **Compiler Reliability:** Utilize Ada 2022\'s advanced features
  (contracts, subtypes, variant records) to mathematically guarantee the
  internal consistency of the compiler\'s intermediate representations.

- **Maintainability:** Create a highly readable and self-documenting
  compiler codebase using Ada\'s descriptive syntax.

- **Safety-Critical Functional Programming:** Pave the way for
  functional programming to be adopted in high-integrity systems by
  providing a compiler toolchain built on high-integrity foundations.

**3. Scope**

3.1. In-Scope

- Language Standard: Haskell 2010.

- **Evaluation Model:** Lazy evaluation (Call-by-need) and graph
  reduction.

- **Type System:** Hindley-Milner type inference, Type Classes, and
  Monads as defined in Haskell 2010.

- **Standard Library:** A core subset of the Haskell 2010 `Prelude` to
  ensure basic usability.

- **Code Generation:** Compilation to a standard intermediate
  representation (e.g., LLVM IR or C) to leverage existing optimizers
  and backends.

- **Ada Implementation:** Strict adherence to Ada 2022 standards.

**3.2. Out-of-Scope**

- GHC Extensions: Advanced extensions like Template Haskell, Type
  Families, Multi-parameter type classes (unless strictly necessary),
  and Linear Types are deferred to future versions.

- **Garbage Collector Implementation:** AHC will rely on an existing,
  proven C/C++ garbage collector (like the Boehm GC or GHC\'s RTS)
  linked during the final compilation phase, rather than writing a new
  GC in Ada for this initial release.

- **Interactive Environment (REPL):** The initial focus is on a batch
  compiler (AOT), not a GHCi equivalent.

**4. Technical Requirements**

4.1. Respecting Haskell 2010

The compiler must correctly parse, type-check, and execute standard
Haskell constructs:

1.  **Algebraic Data Types (ADTs):** Correctly map Haskell ADTs into
    internal representations.

2.  **Pattern Matching:** Exhaustiveness checking and efficient
    compilation of complex nested patterns.

3.  **Type Classes:** Resolution of dictionaries at compile-time.

4.  **Purity and Laziness:** Ensure side-effects are strictly contained
    within the `IO` Monad and thunks are correctly managed and updated
    upon evaluation.

**4.2. Utilizing Ada 2022**

The core differentiator of this compiler is *how* it is built. The Ada
2022 standard will be utilized in the following ways:

1.  **Design by Contract (DbC):**

    - *Pre/Post-conditions:* Applied to critical functions like AST
      transformations and Type Unification. For example,
      `Post => Type_Check'Result.Is_Valid` ensuring no invalid type
      nodes leak out of the inference engine.

    - *Type Invariants:* Applied to Abstract Syntax Tree (AST) nodes to
      ensure tree integrity (e.g., ensuring a `Let` binding always has
      at least one declaration).

<!-- -->

1.  **Advanced Typing and Variant Records:**

    - Haskell\'s AST and Core language will be modeled using Ada\'s
      variant records (discriminated records). This perfectly mirrors
      Algebraic Data Types in a memory-safe, strictly bounded way.

    - *Subtypes:* Extensive use of subtypes with dynamic predicates to
      catch boundary errors at compile-time or run-time of the compiler
      itself.

<!-- -->

1.  **Ada 2022 Iterator Interfaces and Map/Reduce:**

    - Utilize new Ada 2022 container features to elegantly handle list
      comprehensions and environment/symbol table mappings.

<!-- -->

1.  **Parallelism:**

    - Use Ada\'s tasking and Ada 2022 parallel block constructs to
      parallelize independent compilation phases, such as parsing
      multiple modules concurrently or parallelizing independent
      branches of code generation.

**5. System Architecture**

The compiler will follow a standard multi-pass architecture, strictly
segregated using Ada packages.

1.  **Lexer/Scanner (`AHC.Lexer`):**

    - Converts source characters into tokens. Handles Haskell\'s layout
      (off-side) rule using an explicit state machine with Ada contracts
      ensuring the layout stack never underflows.

<!-- -->

1.  **Parser (`AHC.Parser`):**

    - Produces the initial untyped AST. Built using a recursive descent
      approach or generated via an Ada-compatible parser generator
      (e.g., Wisent), outputting to strongly-typed Ada variant records.

<!-- -->

1.  **Desugarer (`AHC.Desugar`):**

    - Translates complex Haskell 2010 constructs (list comprehensions,
      `do` notation) into a simplified core language (System FC-like).

<!-- -->

1.  **Typechecker (`AHC.Typechecker`):**

    - *The most critical component.* Implements Algorithm W
      (Hindley-Milner). Ada\'s `in out` parameters and contracts will
      track the Substitution environment, preventing accidental state
      mutations.

<!-- -->

1.  **Optimizer (`AHC.Optimizer`):**

    - Performs transformations on the Core AST (inlining, strictness
      analysis, dead code elimination).

<!-- -->

1.  **Code Generator (`AHC.CodeGen`):**

    - Translates the optimized Core AST into LLVM IR (via Ada bindings
      to LLVM) or standard C code for final compilation.

**6. Milestones and Phases**

- Phase 1: Foundation (Months 1-3)

  - Define the core Ada variant records for the Haskell AST.

  - Implement Lexer (with layout rule) and Parser.

<!-- -->

- **Phase 2: The Core Engine (Months 4-7)**

  - Implement the Desugarer and the Hindley-Milner Typechecker.

  - Heavy integration of Ada contracts to verify unification logic.

<!-- -->

- **Phase 3: Code Generation & Execution (Months 8-11)**

  - Implement graph reduction/thunk allocation strategy.

  - Develop the LLVM IR or C backend.

  - Link against a standard garbage collector.

<!-- -->

- **Phase 4: Standard Library & Refinement (Month 12+)**

  - Flesh out the `Prelude`.

  - Implement Monadic IO support.

**7. Agile Execution Plan (Epics, Features, Stories, Tasks)**

Epic 1: Frontend - Parsing and Syntax

Goal: Successfully read Haskell source text and convert it into a
strictly verified internal Abstract Syntax Tree (AST).

- **Feature 1.1: Lexical Analysis & Layout Rule**

  - *Story:* As a compiler developer, I need the lexer to accurately
    process Haskell\'s indentation-based layout so that explicit braces
    and semicolons are correctly inferred.

    - **Task 1.1.1:** Define Ada enumerated types for all Haskell 2010
      tokens.

    - **Task 1.1.2:** Implement the basic character scanner (keywords,
      operators, literals).

    - **Task 1.1.3:** Implement the off-side rule state machine for
      layout tracking.

    - **Task 1.1.4:** Write Ada pre/post-conditions ensuring the layout
      tracking stack never underflows or leaks memory.

<!-- -->

- **Feature 1.2: AST Definition & Parsing**

  - *Story:* As the compiler, I need a memory-safe, tree-like structure
    to represent the user\'s code for further processing.

    - **Task 1.2.1:** Design the untyped AST using Ada 2022
      discriminated variant records.

    - **Task 1.2.2:** Build a recursive descent parser for expressions
      (handling operator precedence).

    - **Task 1.2.3:** Build parser routines for module declarations,
      imports, and data type definitions.

**Epic 2: Core Semantic Analysis - Type System**

Goal: Implement the Hindley-Milner type system with Type Classes,
utilizing Ada\'s contracts to mathematically guarantee the absence of
type-inference bugs within the compiler.

- **Feature 2.1: Desugaring to Core**

  - *Story:* As the compiler engine, I want to reduce Haskell\'s
    syntactic sugar into a smaller \"Core\" language to vastly simplify
    the typechecking and optimization phases.

    - **Task 2.1.1:** Define the System-FC-like \"Core AST\" using Ada
      variant records.

    - **Task 2.1.2:** Implement translation of `do` notation into `>>=`
      and `>>` operators.

    - **Task 2.1.3:** Implement translation of List Comprehensions into
      `map`, `filter`, and `concat`.

<!-- -->

- **Feature 2.2: Hindley-Milner Type Inference (Algorithm W)**

  - *Story:* As a Haskell programmer, I expect the compiler to infer my
    types accurately without requiring explicit annotations, unless
    there is an ambiguity.

    - **Task 2.2.1:** Implement the Type Environment (context) using Ada
      2022 Maps.

    - **Task 2.2.2:** Implement the Unification algorithm. *Crucial:*
      Apply Ada contracts (`Post => ...`) to guarantee that unified
      types do not contain circular references (occurs check).

    - **Task 2.2.3:** Implement instantiation and generalization
      (let-polymorphism) of types.

<!-- -->

- **Feature 2.3: Type Classes Implementation**

  - *Story:* As a Haskell programmer, I need to use ad-hoc polymorphism
    (Type Classes) like `Eq` and `Show`.

    - **Task 2.3.1:** Implement instance resolution logic during
      typechecking.

    - **Task 2.3.2:** Implement the dictionary-passing translation
      (converting type class constraints into implicit dictionary
      arguments in the Core language).

**Epic 3: Back End - Code Generation and Execution**

Goal: Translate the typed Core AST into executable machine code,
correctly handling Haskell\'s lazy evaluation strategy.

- **Feature 3.1: Graph Reduction Engine**

  - *Story:* As the execution environment, I need to represent
    unevaluated expressions (thunks) and update them with their results
    once evaluated to ensure laziness is efficient.

    - **Task 3.1.1:** Define the internal representation for thunks and
      evaluated values (WHNF).

    - **Task 3.1.2:** Design the update mechanism for graph reduction in
      the target output language.

<!-- -->

- **Feature 3.2: LLVM / C Code Generation**

  - *Story:* As a user, I want my compiled code to run natively and fast
    on my operating system.

    - **Task 3.2.1:** Write the Ada package that traverses the Core AST
      and emits equivalent C code (or LLVM IR).

    - **Task 3.2.2:** Map Haskell primitive types (`Int`, `Char`) to
      native types.

    - **Task 3.2.3:** Implement tail-call optimization generation in the
      output code.

<!-- -->

- **Feature 3.3: Runtime and Garbage Collection**

  - *Story:* As a lazy functional program, I generate a lot of
    short-lived objects and need automated memory management to avoid
    crashing.

    - **Task 3.3.1:** Integrate and link the Boehm-Demers-Weiser
      conservative GC into the final executable.

    - **Task 3.3.2:** Implement the runtime boundary for the `IO` monad
      (handling the real-world state token).

**8. Risks & Mitigations**

  ------------------------------------ -------- ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  Risk                                 Impact   Mitigation
  Complexity of Type Classes           High     Start with a simplified dictionary-passing translation before attempting optimizations. Rely on strict Ada contracts to ensure dictionary passing maintains arity.
  **Garbage Collection Integration**   High     Do not write a GC in Ada initially. Use an established C-based GC (Boehm) and focus on generating correct allocation calls from the Ada backend.
  **Performance of Compiler**          Medium   The heavy use of Ada contracts might slow down the compiler. Mitigation: Use Ada\'s pragma system to disable certain heavy runtime checks in \"Release\" mode, leaving them on only for debug/test builds.
  **Haskell Layout Rule Edge Cases**   Low      Thoroughly test the lexer against the standard Haskell test suites early in Phase 1.
  ------------------------------------ -------- ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

**9. Success Metrics**

- Test Suite Pass Rate: 100% pass rate on a defined subset of the
  official Haskell 2010 test suite.

- **Zero-Defect Internal State:** Zero instances of internal compiler
  crashes (segmentation faults, unhandled exceptions) during the
  compilation of valid or invalid Haskell code, guaranteed by Ada\'s
  strong typing and constraint checking.
