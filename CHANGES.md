# AHC Changelog

## v1.4.1 (2026-07-25)

The dogfood patch (M85-M86): two new example programs, no
compiler changes. ajson (examples/json) - a JSON parser and
pretty-printer with a Data.Map --stats mode, leaning on v1.4's
exact-literal and Burger-Dybvig show machinery. microhm
(examples/hm) - a miniature Hindley-Milner inferencer, the
compiler's typechecker in ~350-line miniature with the real
Bind_Meta occurs-check obligation restated as a live contract;
the STUDY-GUIDE's Station 6 companion. BOTH came up
byte-identical under AHC and GHC on their first builds - the
first dogfood programs in the project's history to do so. The
examples harness now runs 13 tests across three programs.

The third dogfood program (M86): examples/hm - microhm, a
miniature Hindley-Milner inferencer (Algorithm W,
let-polymorphism, occurs check, Data.Map substitution
composition) - the compiler's typechecker in ~350-line miniature,
compiled by that machinery, byte-identical under both compilers
on the first AHC build (the second program in a row). The unifier
states the REAL typechecker's obligations as contracts: bindVar
carries the Bind_Meta occurs-check precondition as a {-# PRE #-},
live and demanded on every unification in the test suite. Doubles
as the STUDY-GUIDE's Station 6 companion. Exercises previously
un-dogfooded ground: map-valued Data.Map workloads, deep mutual
recursion, threaded fresh-name supplies.

The second dogfood program (M85): examples/json - ajson, a JSON
parser and pretty-printer in the AHC subset, byte-identical
compiled by AHC or interpreted by GHC across parse/pretty, error
reporting, and a Data.Map --stats mode (goldens in the examples
harness). It leans on everything v1.4 built: numbers are
fromRational of the exact decimal ratio, output goes through the
Burger-Dybvig show, \uXXXX escapes round-trip as code points with
ASCII-only IO. First dogfood in the project's history to come up
byte-identical on the FIRST build - the exactness release doing
its job.

## v1.4 (2026-07-25)

The exactness release (M82-M83). Float literals became exact
decimal ratios end to end - `0.1 :: Rational` is `1 % 10`, every
Double literal keeps its strtod-exact value through one correctly
rounded conversion, and the oldest EXCLUSIONS entry fell.
Non-nullary deriving is rejected at compile time instead of
compiling to runtime stubs. Double's show now generates shortest
round-trip digits by GHC's exact Burger-Dybvig algorithm, not
printf rounding. The fuzzer's menu grew seven type families and
its first 10,000-seed campaign ran - after teaching two hard
lessons (a harness must time-limit every subprocess; a generator
must emit TRACTABLE programs, not merely terminating ones) it
found four compiler bugs down to a floored-mod overflow that
surfaced three layers up as a mis-reduced Rational. All fixed,
all pinned. Conformance suite: 69 -> 74 programs, byte-identical
to GHC 9.4.8. A CI workflow exists but is parked pending GitHub
billing (workflow_dispatch only). docs/fuzzer-guide.md documents
campaign practice; docs/STUDY-GUIDE.md gives newcomers the
guided path through the codebase.

Fuzzer menu expansion + the first deep campaign (M83):

- **The menu grew** (docs/fuzzer-guide.md documents usage, triage
  and the menu rule): records (construction, update, selectors), a
  fielded ADT exercising the pattern matrix and derived Eq/Ord/Show
  with negative fields, Either, Rational (exact literals, %,
  numerator/denominator, guarded / and recip, fromRational),
  exponent-form Double literals, sin/cos/log/exp, and
  multi-binding let. Every construct was pinned byte-identical on
  both compilers before entering the menu, per the standing rule.
- **The harness can no longer be wedged.** Every external step
  (generate, oracle, build, run) runs under a time limit, with two
  new outcomes: SLOW-ORACLE (skip - an expensive program) and
  SLOW-AHC (a finding). This was not theoretical: the first deep
  campaign was discovered six hours in with three ORACLE processes
  pegged at 100% CPU, the harness patiently waiting on programs
  that would never finish. scripts/run_fuzz_par.sh splits a range
  across parallel jobs over a compiled generator (~20x faster than
  interpreting it per seed).
- **The generator now emits TRACTABLE programs**, not merely
  terminating ones - two disciplines, both learned from that
  wedge. The recursive call is let-bound and the generator hands
  out the variable, so k uses share one thunk (inlining "(f xs)"
  at k sites is k^depth; a 3^n body was the hang). And any
  construct whose cost depends on a value's MAGNITUDE is clamped:
  a Double range's step falls below one ULP at large magnitudes
  (v + 1.5 == v), making the range an infinite list.
- **Three compiler bugs found, fixed and pinned** (suite: 70 ->
  74 programs):
  - **show, shortest-round-trip digits**: four seeds printed a
    different last digit from GHC on bit-IDENTICAL values. GHC
    picks digits by Burger-Dybvig; AHC derived them from printf's
    correctly-rounded decimal, which agrees except on boundary
    cases where two renderings both round-trip. The runtime now
    implements GHC's floatToDigits exactly, over the existing
    bignum limbs (ch11_04_show_double_digits.hs).
  - **show, denormals**: the new digit generator took the
    asymmetric boundary case at the minimum exponent. A denormal's
    neighbours are evenly spaced - only a power-of-two significand
    ABOVE the minimum exponent is asymmetric - so values below
    2^-1022 printed one digit too many (ch11_04_show_denormal.hs).
  - **mod, large positives**: the textbook floored-mod idiom
    ((x`rem`y)+y)`rem`y OVERFLOWS when both operands are large
    positives, wrapping negative. 7.4e18 `mod` 8.2e18 surfaced as
    a wrong gcd and a mis-reduced Rational, layers above the
    arithmetic (ch06_04_mod_large.hs). div was already correct;
    add/sub/mul use __builtin_*_overflow.

CI + correctness mop-up (M82):

- **Non-nullary deriving Enum/Bounded/Ix/Read is rejected at
  compile time** ("all constructors must be nullary") instead of
  compiling to runtime error stubs - AHC no longer accepts what
  GHC rejects here (bad_derive_nonnullary.hs pins the agreement;
  the single-constructor Bounded/Ix products GHC additionally
  accepts stay honestly unimplemented).
- **Float literals are exact decimal ratios** (Report 6.4):
  codegen emits an exact numerator/denominator pair (Ratio-shaped
  node) when Data.Ratio is in the program; the wired Rational
  placeholder expands like a nullary synonym in unification once
  `type Rational` exists; Data.Ratio gains the real source
  fromRational, and Fractional Double's fromRational converts the
  pair with ONE round-to-nearest-even. `0.1 :: Rational` is
  `1 % 10`; every Double literal keeps its strtod-exact value.
  The oldest EXCLUSIONS entry is struck
  (ch06_04_rational_literals.hs, suite: 70).
- **GitHub Actions CI** (.github/workflows/ci.yml): ubuntu runner
  with Alire/GNAT and ghcup GHC 9.4.8, both build profiles, 219
  unit tests, all eleven harnesses, 50 fuzz seeds, on every push
  and PR. First cross-platform dividend arrived before the first
  run: the 512MB-stack link flag was Darwin-only syntax;
  ahc-build.sh now gates it per OS.

## v1.3 (2026-07-24)

The verification-and-tooling release: the five-item post-v1.2
roadmap, complete. A differential fuzzer that generates random
well-typed programs and byte-compares AHC against GHC per seed
(M76); real `seq`, `($!)` and an honest `foldl'` (M77); the full
System.IO file-handle API (M78); `ahc repl`, compile-and-run over
the object cache with no second evaluator (M79-M80); and
compile-time contract discharge - what the compiler can prove,
the runtime need not check (M81). The new tooling immediately paid
its way: the fuzzer and the REPL's first sessions found FIVE real
compiler bugs the hand-written suite had never touched (a
layout-vs-lookahead corner, Integer->Double rounding drift,
negative-zero show, wired-body theft by name shadowing, and
implicit-Prelude qualified resolution) - every one fixed and
pinned. Conformance suite: 62 -> 69 programs, all byte-identical
to GHC 9.4.8; eleven test harnesses; 300-seed fuzz campaigns
green.

Compile-time contract discharge (M81 - the roadmap's last item):

- **What the compiler can prove, the runtime need not check** -
  Ada's policy, transplanted. AHC.Discharge is a fuel-bounded
  constant evaluator over elaborated Core (closures over the
  existing arena, eager arguments, lazy branches, two-pass letrec
  for dictionary globals, selector projection through known
  dictionaries, Int primitive folding). Every contract claim is
  evaluated once at compile time with its parameters OPAQUE:
  proved True -> the claim is dropped before the wrapper is built
  (both dropped means no wrapper, zero overhead); proved False ->
  "this precondition can never hold" warning, check kept; Unknown
  -> check kept. Opaque parameters poison every consuming path, so
  argument-dependent predicates can never discharge by mistake -
  incompleteness is possible, unsoundness is not.
- Install_Bodies now runs BEFORE Insert_Checks (the evaluator
  reduces through the wired dictionaries, which must exist).
- Proved three ways: scripts/run_discharge.sh greps the generated
  C (trivially-true claims absent, argument-dependent present,
  provably-false warns and stays); ext_contracts_discharge.hs
  pins unchanged observable behavior under the GHC oracle
  (suite: 69); tests/exec/contract_never.hs pins that a
  never-holding contract still fails at demand time with the
  standard message.

The REPL (M79 design note, M80 implementation):

- **`ahc repl`**: compile-and-run over the M63 object cache
  (docs/repl-design-note.md). The REPL adds NO second evaluator -
  every entry becomes a real program built by the real pipeline
  and run by the real runtime, so every conformance guarantee
  carries over. Session state is two generated modules: Repl
  (accumulated imports + declarations, validated and rolled back
  on error - a bad entry never poisons the session) and Main
  (`it = <expr>` plus a runner chosen by the inferred type: IO
  actions run, everything else prints). Line classification uses
  the real parser, not a regex. Commands: :type, :load (GHCi's
  reset-on-load), :reload, :clear, :help, :quit. Pinned
  transcripts in tests/repl/ via scripts/run_repl.sh.
- **The REPL's first session found compiler bug four**: with
  Data.Map imported, `nub` died on a missing global.
  Install_Bodies attached wired Prelude bodies by bare-name
  lookup in the MUTABLE flat env, which any module re-defining
  the name (Data.Map's filter) had clobbered - the wired var was
  left bodiless. Wired bodies now resolve through the Base
  snapshot. The same session's pinning exposed bug five:
  `Prelude.filter` with a local `filter` defined resolved to the
  LOCAL one (the implicit-Prelude qualified path consulted the
  own-module map first); it now goes straight to the Base
  snapshot. Both pinned in ch05_wired_shadowing.hs (suite: 68).

System.IO file handles (M78):

- **The full practical handle API**: openFile/hClose/withFile,
  hPutStr/hPutStrLn/hPutChar/hPrint, hGetLine/hGetChar/
  hGetContents/hIsEOF/hFlush, writeFile/appendFile, and
  stdin/stdout/stderr as first-class handles. IOMode is an
  ordinary source enumeration deriving exactly GHC's instances
  (Eq, Ord, Show, Enum - GHC has no Bounded IOMode, verified the
  hard way).
- **The runtime deals only in integers**: a Handle is an index
  into a small registry of FILE pointers (std streams pre-seeded
  at 0..2), so an operation on a closed handle dies with a clean
  message instead of touching freed memory; the Handle type is
  ABSTRACT in source (constructor unexported), so the only handles
  in circulation come from openFile. Eight new prims; everything
  else - withFile, writeFile, hPutStrLn, hPrint - is ordinary
  Haskell in lib/System/IO.hs.
- Two documented divergences (EXCLUSIONS): hGetContents is strict
  (GHC's lazy semi-closed-handle behavior means portable programs
  must not touch the handle afterward regardless), and hClose on a
  std stream flushes rather than closes. ch07_io_handles.hs pins
  the whole surface byte-identical (suite: 67);
  tests/exec/handle_errors.hs and handle_missing.hs pin the error
  paths.

Real seq + strictness (M77):

- **`seq` is a primitive**: force to WHNF, yield the second
  argument (p_seq in the runtime; wired global with scheme
  `a -> b -> b`; the Report fixity `infixr 0` was already in the
  table waiting). `($!)` is built on it in the wired Prelude.
- **`Data.List.foldl'` is honest**: the accumulator is forced at
  every step (`let z' = f z x in z' `seq` ...`) instead of being a
  renamed `foldl` - the EXCLUSIONS row is gone. WHNF semantics
  pinned: `seq [undefined] x` forces the spine's first constructor
  only.
- Verified three ways: ch06_02_seq.hs (GHC-oracle values),
  tests/exec/seq_strict.hs (the forcing itself: output order and
  the forced error - p_error now flushes stdout before dying so
  effects precede the die message), and the fuzzer's menu grew seq
  and foldl' productions.
- **The extended fuzz campaign found bug three (seed 17): negative
  zero**. `-0.0 == 0.0` is True, so fmt_double's equality-based
  zero fast path printed "0.0" for negative zero; showsPrec's
  parenthesization tested `v < 0`, also blind to -0.0. Show now
  honors the sign bit, and parenthesization keys off the formatted
  leading '-' (covering -0.0 and -Infinity, excluding NaN, exactly
  GHC's behavior). Pinned as ch06_04_negative_zero.hs (suite: 66).
- Measured honestly (scripts/run_bench.sh): foldl' is about
  strictness, not speed - on a 2M-element sum that fits in memory
  the strict fold pays ~30% for the per-element force
  (b_strictfold 2.46s vs b_sumfold 1.86s, optimized); its win is
  the space guarantee, not wall time. Both benches stay in the
  suite so the trade-off remains visible.

Differential fuzzer (M76):

- **scripts/run_fuzz.sh + tests/fuzz/Gen.hs**: a seeded generator
  of random well-typed Haskell 2010 programs (deterministic 64-bit
  LCG; runs under GHC, base-only) whose every construct and library
  function was first pinned byte-identical on both compilers, so a
  divergence is always a real finding. Each seed's program is
  compiled by AHC and interpreted by GHC and the stdout compared
  byte for byte; divergences are saved to tests/fuzz-failures/ and
  auto-shrunk by delta debugging (scripts/shrink_fuzz.py: drop main
  statements and whole definitions while the same divergence
  reproduces). Known-undefined territory is avoided by
  construction: Int arithmetic stays small, text stays ASCII,
  partial functions are never emitted.
- **First blood, seed 3**: a single-line `let ... in` inside an
  explicit-brace case alternative inside a do block produced
  spurious "'}' without matching explicit '{'" errors. Root cause:
  the do-statement bind/expression lookahead (Arrow_Ahead) drained
  tokens through the layout engine WITHOUT the parser's
  parse-error(t) feedback, so the let's implicit context was never
  closed. Fix: the scan now stops at the first token a pattern
  cannot contain (let/case/if/do/lambda/...), which both answers
  the question early and keeps lookahead from opening layout
  contexts at all. Pinned as ch10_03_lookahead_let.hs.
- **Seed 57: Integer->Double rounding**. `fromIntegral` on a
  bignum accumulated per-limb (`v * 2^32 + limb`), rounding at
  every step; values a few bits past 53 drifted by ulps from GHC
  (1.610269053685309e26 vs the correct ...095e26). The runtime now
  takes the top 53 bits and applies ONE round-to-nearest-even with
  a proper round/sticky pair - GHC's integerToDouble semantics.
  Pinned as ch06_04_integer_to_double.hs (suite: 64, including
  2^64±1, 2^53+1, and 10^300).

## v1.2 (2026-07-23)

The polish-and-depth release: every milestone of docs/polish-plan.md
(M64-M75) shipped. Correctness debt first (cross-module diagnostic
spans, a join-point sharing fix found while testing fail-at-Maybe),
then GHC-compat breadth (Applicative, Enum at Char/Double, deriving
Enum/Bounded/Ix/Read for enumerations, properFraction + RealFloat),
the architectural payoffs (polymorphic Ratio a and Complex a,
Data.Set), the contracts extension (Ada's Pre/Post as pragmas -
refinements govern values, contracts govern functions, closing the
Ada story), and finally a measured optimizer round (up to 2.1x) and
the module-system corners. Conformance suite: 51 -> 62 programs,
all byte-identical to GHC 9.4.8. Nothing planned remains unbuilt.

Module-system corners (M75 - the polish plan's last item):

- **Restricting the implicit Prelude import** (Report 5.6.1): an
  explicit `import Prelude ...` now replaces the implicit one.
  `hiding` frees names for local definitions, only-lists narrow,
  `import Prelude ()` empties, `qualified` forces qualification.
  The explicit import reuses the ordinary import-view filter over
  the Base snapshot; the renamer's snapshot fallback switches off
  when one is present. Pinned by conformance (ext_prelude_*.hs -
  suite now 62) and both-reject differentials (bad_prelude_*.hs):
  hiding filters the QUALIFIED view too, and builtin syntax
  (`()`, `[]`, `:`, tuples) can never be hidden - it is grammar.
- **Same-named synonyms/constructors across modules**: both
  namespaces are program-global; a collision is a clean
  compile-time error ("defined more than once") where GHC would
  disambiguate by module. Documented in EXCLUSIONS row 5 - the
  honest remaining flatness, never silent misresolution.

Measurement-driven optimizer round (M74):

- **Benchmark harness** scripts/run_bench.sh: five workloads in
  tests/bench/ (fib, strict fold over 2M ints, Data.List.sort on
  30k LCG-random elements, factorial-2000 bignum, 40k-entry
  Data.Map build-and-fold), each built with and without --no-opt,
  outputs verified identical, then timed with warmup plus
  interleaved best-of-5 so noise hits both sides equally. An
  initial sequential timing "found" a 24% fib regression that the
  interleaved harness dissolved entirely - the harness was
  hardened before the optimizer was touched, which is the point
  of measurement-driven.
- **Used-once let inlining**: a non-recursive let binding whose
  variable occurs exactly once, not under a lambda, is substituted
  at its use site (the rhs MOVES, preserving the tree invariant).
  One occurrence means the thunk was forced at most once anyway -
  sharing-exact; the lambda bar prevents turning one evaluation
  into many. Measured: 2.10x on the fold (was 1.58x), 1.91x on
  sort (was 1.19x), 1.28x on Map (was 1.11x), ~1.0x on
  call-dominated fib and prim-dominated bignum. All 59 conformance
  programs remain byte-identical with the optimizer on.

Function contracts (M72-M73, docs/contracts-design-note.md):

- **Ada's Pre/Post as pragmas**: {-# PRE f expr #-} /
  {-# POST f expr #-}. Each becomes a hidden top-level binding
  parsed from the pragma's own tokens (spans point into the
  pragma, so contract type errors land exactly there), typechecked
  against a signature DERIVED from f's own - tyvars, class
  context, argument spine, Bool. AHC.Refine wraps the function:
  forcing the result forces the precondition, then the body, then
  the postcondition against the let-shared result. Undemanded
  calls check nothing (demand time, like every refinement check);
  polymorphic functions get polymorphic contracts with the
  dictionaries threaded through; --unchecked strips all claims
  (Ada's assertion policy); one new runtime prim (check_claim).
- Compile-time errors: unknown function, duplicate PRE/POST,
  missing type signature, PRE on a value binding, and ordinary
  type errors at pragma spans.
- GHC ignores the pragmas (stderr warning only), so contracted
  source stays portable: ext_contracts.hs runs byte-identical
  under both compilers (suite now 59); tests/exec/contracts.hs
  pins the violation messages and demand-time semantics;
  examples/contracts.hs is the worked tour (clamp, a
  self-specifying integer sqrt, sorted-precondition binary search,
  polymorphic maxOf, laziness demo).

Track C - the architectural payoffs (M70-M71):

- **Polymorphic Ratio a and Complex a** (M70): data Ratio a with
  Integral-context instances and type Rational = Ratio Integer;
  data Complex a with RealFloat-context Num and polar family. The
  last monomorphic library shapes die, expressible only because
  the tower is real classes (M62/M69). Two rename rules extended:
  a type SYNONYM may shadow a builtin TyCon (symmetric with the
  data rule), and a visible synonym outranks the shadowed builtin
  at use sites. Suite entry lib_poly_ratio_complex.hs; existing
  ratio/complex tests unchanged and identical.
- **Data.Set + Map roundout** (M71): the weight-balanced tree
  without values (member/insert/delete/union/difference/
  intersection/filter/map, fromDistinctAscList's comparison-free
  balanced build), byte-identical to real containers (lib_set.hs);
  Map gains filter, foldlWithKey, keysSet, fromDistinctAscList.
  Set's constructors are SBin/STip: the renamer's constructor
  namespace is flat across modules (the M75 item), and Data.Map
  owns Bin/Tip. Suite now 58 programs.

properFraction + RealFloat (M69):

- **properFraction** joins RealFrac (result at Integer, where
  GHC's defaulting lands): truncation toward zero with the exact
  fractional remainder, body as Prelude source (dblPF_). The
  method's type is the tower's first pair-returning dict field.
- **RealFloat** is a real class (superclasses RealFrac, Floating)
  at Double/Float: isNaN, isInfinite, isNegativeZero (three new
  IEEE prims), and atan2 moves home from its monomorphic exile.
  Defaulting extended (print (isNaN (0/0)) just works).
- ch06_04_realfloat.hs byte-identical to GHC (computed NaN/
  Infinity/negative zero, both atan2 quadrant cases, destructured
  properFraction); suite now 56 programs. Track B of the polish
  plan is complete.

Enum at Char/Double + the deriving family (M67-M68):

- **Enum at Char and Double** (M67): real dictionaries with every
  method body as Prelude source. Char rides ord/chr (['a'..'z'],
  stepped, succ/pred, to/fromEnum); Double follows GHC's numeric
  enumeration - +1 chains with the Report 6.3.4 half-step limit,
  and K-INDEXED stepping (n + k*delta) for enumFromThen(To), probed
  empirically: the chained recurrence accumulates rounding where
  GHC's per-element rounding prints 0.4. The Enum Double/Float
  instances had never been registered; now they are.
- **deriving Enum, Bounded, Ix, Read for enumerations** (M68):
  constructor-tag arithmetic end to end - succ/pred/toEnum/
  fromEnum/all four enumFroms, minBound/maxBound, range/index/
  inRange/rangeSize, and Read via a maximal-munch token matcher
  (readsEnum_ in Text.Read) against a generated constructor table.
  Ix and Read derives target SOURCE classes - the deriving
  machinery finds any registered class. Bonus: the wired
  Bool/Ordering Enum instances ride the same branch, so [False ..]
  works. Suite now 55 programs (ch06_03_enum_char_double,
  ch11_01_derives).

Polish track A + Applicative (M64-M66, docs/polish-plan.md):

- **Fixed: cross-module diagnostic spans** (M64). Diagnostics carry
  an origin tag; the driver renders each against its own module's
  source. The fromRational warning now reports
  lib/Data/Ratio.hs:45:1 (the instance) instead of a meaningless
  root-file position; type errors in imported modules report the
  right file.
- **Fixed: refutable do-binds with multi-position patterns** (M65).
  The fail dictionaries were already complete (Maybe -> Nothing,
  [] -> skip), but Ds_Do passed the fail CALL as Match_One's
  failure continuation instead of a let-bound join-point variable -
  so a pattern like (x : y : _) failing at the second cons shared
  one `fail` node between failure positions and the evidence
  rewriter applied the dictionary twice ("applied a non-function").
  The tree invariant's third strike. Pinned by ch03_14_faildo.hs;
  EXCLUSIONS' stale 3.14 row corrected.
- **Applicative** (M66): an ordinary source Prelude class over the
  wired Functor - pure, <*>, liftA2 (with defaults for liftA2/
  *>/<*), plus <$> in the Prelude - instances at Maybe, [] and IO.
  First source class with a SUPERCLASS (the default methods reach
  fmap through sup$Applicative$1) and first []-headed source
  instances; both just worked. ch04_applicative.hs byte-identical
  to GHC. Suite now 53 programs.

## v1.1 (2026-07-21)

Everything after v1.0: the complete standard library (including the
formerly-deferred quartet and Data.Map), the mini-Lisp dogfood
program and the three compiler bugs it found, exhaustiveness and
redundancy warnings, the numeric tower as real classes, and
separate compilation. The deliberately-unbuilt list is empty.

Separate compilation (M63):

- **Per-module code generation with stable symbols**: `ahc emit`
  writes OUT.build/ with one C file per module plus a shared
  header. Globals are mangled from (module, source name) - never
  an arena id - and locals/lifted functions are numbered per unit,
  so a module's generated text depends only on its own code.
  Elaborated instance dictionaries are attributed to the module
  that declared the instance; the wired prelude and prim bodies
  form the Prelude unit. Per-unit init functions run in dependency
  order from main().
- **Content-addressed object cache**: ahc-build.sh compiles each
  unit (and the runtime) to an object keyed by the hash of its
  generated text and reuses it across builds. No-change and
  comment-only rebuilds compile ZERO objects; a semantic edit to
  one module recompiles exactly one. Interpreter rebuilds: ~6s ->
  ~1s (the frontend is ~0.3s; clang on the old monolith was 94% of
  every build).
- **The frontend stays whole-program by design** (no interface
  files): Report program-wide instance coherence holds by
  construction. Documented in EXCLUSIONS.
- New harness scripts/run_separate.sh pins the cache behavior;
  outputs remain byte-identical everywhere (same Core, partitioned
  emission).

The numeric tower as real classes (M62):

- **Integral** (superclasses Num, Ord) with instances at Int and
  Integer: quot/rem/div/mod stop being fake Num-constrained
  globals and become methods; the canonical bignum representation
  means both instances bind the same promoting prims and
  `toInteger` is the identity.
- **Floating** and **RealFrac** (superclass Fractional) with
  instances at Double: the whole vocabulary (pi, exp/log/sqrt,
  `**`, logBase, trig, hyperbolics; truncate/round/ceiling/floor
  at Integer results, where GHC's defaulting lands anyway) moves
  from monomorphic globals into real dictionaries. Same runtime
  prims - sqrt changed type, not behavior. atan2 stays monomorphic
  (RealFloat territory).
- **fromIntegral is ordinary Prelude source** (`fromInteger .
  toInteger`), fully polymorphic at last; **(^)/(^^)** added
  (exact `2 ^ 100` via bignum; the fast-exponentiation helper is a
  constraint-carrying where-binding - the M59 typechecker fix in
  action); even/odd/gcd/lcm generalized to Integral.
- Report 4.3.4 defaulting extended to the new classes
  (`print (floor 2.5)`, `print (sqrt 2)` default as GHC does).
- New conformance program ch06_04_tower.hs (52 lines of
  polymorphic tower use) byte-identical to GHC; suite now 51.

Exhaustiveness warnings (M61) and Data.List lookup (M60):

- **AHC.Exhaustive** - Maranget-style usefulness analysis over
  function equations and case alternatives: "non-exhaustive
  patterns in function 'f'" / "in case expression", and "redundant
  pattern" for clauses that can never fire. Handles constructors
  (incl. tuples, lists, records), literals (never a complete set),
  and guards (a clause counts as covering only when unguarded or
  carrying an otherwise/True alternative; guarded predecessors
  never shadow). Root module only - library and Prelude matches
  are vetted. Agrees line-for-line with GHC's
  -Wincomplete-patterns / -Woverlapping-patterns on the pinned
  corpus (tests/golden/check_matches).
- **Data.List now re-exports lookup**, matching base.

Data.Map (M59):

- **lib/Data/Map.hs** - a weight-balanced binary search tree
  (Adams' algorithm, the same family as GHC's containers):
  insert/delete/lookup/union/unionWith/fromList/adjust and friends,
  Show/Eq instances - observable behavior matches containers
  exactly and the conformance test oracles against the real thing.
  The mini-Lisp interpreter's environments now use it (Map under
  AHC, containers under GHC, still byte-identical).
- **Fixed: qualified type names.** `Map.Map` in a signature never
  consulted the qualifier - the renamer's type lookup now mirrors
  the value path (qualified-through-import resolves only in that
  module's exports, Report 5.3); same for qualified synonyms.
- **Fixed: constraints from where-helpers.** A wanted constraint
  arising inside an inner let - notably the match compiler's join
  points, i.e. ANY multi-equation where-helper - kept the inner
  binder as its owner, so the enclosing group's context never
  claimed it ("ambiguous type variable" on perfectly ordinary
  code). Unsolved wanteds now float to the enclosing binding when
  a group closes. Pinned by conformance where_context.hs (also
  covers superclass discharge: an Eq wanted met by an Ord given).
  The suite is now 50 programs.

Dogfooding (M58):

- **examples/lisp** - a mini-Lisp interpreter (REPL + batch) written
  in Haskell 2010 and compiled by AHC itself: exact numeric tower
  (bignum Integer / Rational / Double), closures, letrec via lazy
  knot-tying, boot prelude written in mini-Lisp. Verified
  byte-identical to the same source compiled by GHC
  (`scripts/run_examples.sh`, GHC-oracle goldens).
- **Fixed: cross-module type synonyms.** A synonym imported from
  another module expanded a syntax-arena id against the importing
  module's arena (garbage; typically "cyclic type synonym"). Kind
  checking now caches each synonym's converted Core rhs at its
  declaration and expansion substitutes into the cached form;
  failed (cyclic) synonyms are poisoned to report exactly once.
  Found by the interpreter's first compile.
- **System.IO.isEOF** - new primitive, needed by the REPL to see
  end-of-file coming (AHC's `getLine` errors at EOF, as does GHC's).
- New multi-module conformance case pinning cross-module synonyms
  (nullary and parametric); the suite is now 48 programs.

The standard library (docs/stdlib-plan.md), complete - every
milestone including everything the plan originally deferred:

- **Library modules** compiled by AHC through its own module system
  (`lib/`, resolved root-dir -> `$AHC_LIB` -> `lib/`): Data.List
  (base's exact production orders), Data.Char, Data.Maybe, Data.Ord,
  Data.Tuple, Data.Bool, Control.Monad + Data.Functor
  (Monad-polymorphic over IO/[]/Maybe), System.IO /
  System.Environment / System.Exit (input at last: getLine,
  getContents, readFile, interact, getArgs), Numeric, Data.Bits at
  Int, Data.Ix as an ordinary source class.
- **The formerly-deferred quartet** (M54-M57): Data.Ratio (exact
  fractions over bignum, GHC's `1 % 2` Show), Data.Complex at Double
  (new atan2 prim), Data.Array (Int-indexed, list-backed), Text.Read
  (a source Read class; GHC's exact `Prelude.read: no parse`).
- **Compiler enablers**: builtin-class default methods (E4 - a Show
  instance defining only `show` gets Report-correct
  showsPrec/showList; Ord defaults reach Eq through the superclass),
  `module M` re-exports (E5), derived Show for infix constructors,
  and a rename rule letting a library type take a builtin TyCon's
  name (how `Rational` claimed its own).
- Conformance suite grown 39 -> 48 programs, all byte-identical to
  GHC 9.4.8.

## v1.0 (2026-07-17)

First release. A Haskell 2010 compiler written in Ada 2022, built
around Design-by-Contract: the compiler's internal consistency is
enforced by preconditions, postconditions and type invariants in
every development build.

Everything in the PRD, including both stretch goals:

- **Full pipeline to native code**: lexer, Report 10.3 layout,
  recursive-descent parser for the whole Haskell 2010 surface,
  fixity resolution, renamer, kind inference, pattern-matrix
  desugarer, Algorithm W with type classes / monomorphism
  restriction / defaulting, dictionary elaboration with call-site
  evidence, Core-to-Core optimizer, C code generation over a
  call-by-need graph-reduction runtime with the Boehm GC.
- **A Prelude written in Haskell and compiled by AHC itself**,
  including Show instances as ordinary context-parametrized code.
- **Report-complete Show** (showsPrec/showList, string literals,
  escapes, GHC-exact Double formatting), **deriving Eq/Ord/Show**,
  pattern guards, stepped enumerations, Floating/RealFrac at Double.
- **Arbitrary-precision Integer**: hand-rolled limb arithmetic with
  a canonical small-int representation; product [1..25] prints what
  GHC prints.
- **Multi-module programs** (Report ch. 5): import/export lists,
  qualified/as/hiding, abstract types, cycle detection - compiled
  whole-program.
- **Ada-style refinement types** (the design-note extension, all
  four stages): ranges on Int and Double, arbitrary boolean
  predicates on any nullary type, modular wraparound arithmetic -
  erased for unification, enforced at signatures, annotations and
  constructor fields, with `--unchecked` mirroring Ada's release
  policy.
- **A 39-program Haskell 2010 conformance suite whose goldens are
  GHC 9.4.8's output** - AHC reproduces them byte-for-byte - plus
  219 unit tests, five golden/differential/execution harnesses, and
  documented exclusions (tests/conformance/EXCLUSIONS.md).
