# Design note: Function Contracts (Ada Pre/Post as pragmas)

**Status:** IMPLEMENTED (M73). See examples/contracts.hs for the
worked tour; tests/exec/contracts.hs and ext_contracts.hs pin the
semantics.

AHC already has one Ada-inspired verification extension: refinement
types (`docs/refinement-types-design-note.md`) attach checkable
predicates to VALUES at type boundaries. This note designs the
second and final piece: Ada's function-level `Pre`/`Post` contracts,
which state relations refinements structurally cannot -
*between* a function's arguments, and between its arguments and its
result.

```haskell
{-# PRE  clamp \lo hi x -> lo <= hi                #-}
{-# POST clamp \lo hi x r -> lo <= r && r <= hi    #-}
clamp :: Int -> Int -> Int -> Int
clamp lo hi x = max lo (min hi x)
```

A refinement can say "this Int is in 1..65535". Only a contract can
say "the result lies between the first two arguments".

## 1. Why pragmas

Four alternatives were considered:

- **Type-level syntax** (naming arguments in the signature, like
  dependent-type notation `(lo :: Int) -> ...`). Rejected: it
  rewrites Haskell 2010's type grammar, the one part of the surface
  the refinement extension was carefully designed NOT to disturb
  beyond a type's own position.
- **`{-# ANN ... #-}`**. Rejected: ANN is a REAL GHC pragma whose
  payload GHC typechecks - our shapes would make contract-carrying
  source fail under the oracle.
- **Structured comments** (`-- pre: ...`). Rejected: invisible to
  the lexer's error machinery, no spans, un-Haskell.
- **Custom pragmas `{-# PRE #-}` / `{-# POST #-}`**. Chosen: GHC
  emits only an ignorable `Unrecognised pragma` *warning* (stderr;
  every harness compares stdout), so contract-carrying source runs
  unmodified under the oracle - the same property that made
  refinement predicates testable. And it is faithful to the source
  of the idea: Ada attaches contracts to the *declaration*, not to
  the types.

Form: `{-# PRE fname expr #-}` and `{-# POST fname expr #-}`, at
most one of each per function, anywhere at the module's top level
(attachment is by name, not adjacency). The expression is an
ordinary Haskell lambda over the function's arguments - the
POST lambda takes one extra final parameter, the result.

## 2. Semantics under laziness (the load-bearing decision)

Ada checks `Pre` at the call and `Post` at the return. Neither
notion survives laziness intact: at "the call", arguments are
unevaluated thunks, and forcing them to check a predicate would
CHANGE the program (a contract must observe, never alter). The
design follows the rule every refinement check already obeys:
**checks fire at demand time.**

For `f` with signature arity n and compiled body `B`:

    f = \x1 .. xn ->
          claim (preF x1 .. xn)  "precondition of 'f' violated"
            (let r = B
             in claim (postF x1 .. xn r)
                  "postcondition of 'f' violated" r)

where `claim b msg v` is a runtime primitive: when the RESULT is
demanded, force `b`; die with `msg` if False; otherwise yield `v`.
Consequences, all deliberate:

- **Nothing happens until the result is demanded.** An unused call
  to `f` checks nothing - exactly like an unused refined argument.
- **Pre fires before the body's own evaluation**, post after -
  Ada's order, transplanted to demand time.
- **The result is shared**: `r` is let-bound once, so the value the
  postcondition inspects IS the value the caller receives; the
  post-predicate forces `r` only as deep as it looks.
- **Contracts observe**: a postcondition that mentions an argument
  the function itself never forced WILL force it. That is what
  observation means, and it is the one semantic footprint;
  documented, not hidden.
- **Partial applications check nothing** until saturated - the
  claims sit under all n lambdas.
- **Composition with refinements**: contracts wrap OUTSIDE the
  refinement eta-wrappers (a refined signature's own checks run as
  part of evaluating `B`). Deterministic and documented.

**The purity dividend**: Ada needs `'Old` because arguments mutate
before the postcondition runs. Haskell's cannot - a postcondition
simply names the arguments. The Haskell contract story is strictly
simpler than Ada's here, which is a pleasing thing to be able to
write down.

**The policy**: `--unchecked` / `AHC_UNCHECKED=1` strips both
claims - exactly Ada's assertion policy, exactly like ranges and
`satisfying`. Contracts are contracts, never semantics (contrast
`mod` types, which survive `--unchecked` because wraparound is
arithmetic).

## 3. Typing

Contract expressions are ordinary typechecked Haskell, exactly like
`satisfying` predicates. Each becomes a hidden top-level:

    $pre$clamp  :: Int -> Int -> Int -> Bool
    $post$clamp :: Int -> Int -> Int -> Int -> Bool

The signatures are DERIVED from `f`'s own signature: its type
variables and class context, the arrow spine for the arguments,
`-> Bool` (POST inserts the result type before Bool). So a
contract on a polymorphic function is itself polymorphic, and may
use exactly the class methods `f`'s context provides - a contract
needing `Ord a` on a function whose context lacks it is a type
error, reported at the pragma's span with the normal machinery.
(v1 scope: if that bites, add the constraint to `f` or make the
function monomorphic; contract-private contexts are future work.)

Errors caught at compile time, each with the pragma's own span:
unknown function name; duplicate PRE/POST for one name; a
contracted name with no type signature (the arity and types come
from the signature - house style already demands signatures);
arity/type mismatches in the lambda (ordinary type errors).

## 4. Implementation plan

The guiding fact: the `satisfying` pipeline already solved the hard
parts - hidden predicate top-levels (`Pending_Pred`: binder +
syntax expr, collected then desugared), demand-time check prims
(`p_check_pred`), and in-place eta-wrapping in `AHC.Refine`
(`Insert_Checks` with `Checks_Enabled`). Contracts add a surface
(pragmas) and a wrapper shape, reusing everything else.

### M73a - pragma capture and parsing

- **Lexer**: `Skip_Block_Comment` currently swallows `{-# ... #-}`
  untokenized. On seeing `{-#`, still skip to the matching close
  (layout never sees pragma tokens - no interaction with the
  layout engine, which is the point), but record the span in a new
  side table `Pragma_Spans` returned by `Scan` (new defaulted out
  parameter; existing callers untouched).
- **New package `AHC.Contracts`**: for each recorded span whose
  first word is PRE or POST, re-lex the interior as a fragment and
  parse it with a new small parser entry `Parse_Expression` (the
  recursive-descent machinery exposed on a token stream), into the
  SAME module arena. Token spans get the fragment's base offset
  added back, so every later diagnostic lands on the real source
  position. Output: `Contract_Decl = (Kind : Pre|Post,
  Fn : Name_Id, Expr : Syntax.Expr_Id, Span)`. Unknown pragma
  words remain comments, as today.
- **Fixity for free**: fragments are parsed into the arena BEFORE
  `Fixity.Resolve_Module` runs, so operator chains inside
  contracts resolve with the module's own fixities, no new code.
- **Rename**: one added pass resolving each contract expression
  with the module's scope (the same expression-resolution walk the
  renamer applies everywhere; contract lambdas bind their own
  parameters). Errors: unknown `Fn`, duplicates.
- Verify: unit tests (capture; fragment spans; duplicate/unknown
  errors); `ahc parse` unaffected.

### M73b - hidden top-levels

- **Desugar**: mirroring the `Pending_Pred` flow, each contract
  becomes a top-level bind `$pre$f` / `$post$f` whose scheme is
  derived from `Sigs (f)` (tyvars + context + spine -> Bool; POST
  inserts the result type). The typechecker then checks them like
  any binding - contract type errors need zero new machinery.
- **Driver**: thread a per-module `Contract_Maps` (f-binder ->
  pre/post binder) alongside `Preds`, multi-module like everything
  else (a module contracts only its own functions).
- Verify: `ahc check` prints `$pre$clamp :: ...` schemes; type
  errors in contracts point at pragma spans.

### M73c - the wrap, the prim, the policy

- **Runtime**: one new primitive `p_check_claim(b, msg, v)` (force
  `b`; `ahc_die(msg)` on False; else `v`) - the 3-argument sibling
  of `p_check_pred`. Messages are compile-time strings:
  `precondition of 'clamp' violated`.
- **Refine**: `Insert_Checks` gains the contract map; for each
  contracted binder it rebuilds the binding as the Section-2
  wrapper (the same in-place `Replace_Element` eta-wrap idiom as
  constructor-site checks; every embedded reference a fresh node -
  the tree invariant has taken three scalps, it gets no fourth).
  `Checks_Enabled => False` skips contract wraps entirely.
- Verify: exec tests for violations (message + nonzero exit, the
  `satisfying` violation-test pattern) and for `--unchecked`
  stripping; a CONFORMANCE program whose contracts hold - GHC
  ignores the pragmas, so byte-identical stdout proves
  contract-carrying source stays oracle-portable; the separate-
  compilation harness confirms a contract edit recompiles one
  object. MANUAL section (chapter 12 grows from "refinement types"
  to "refinements and contracts"), README, CHANGES.

### v1 scope, stated up front

Top-level functions with signatures only (no local/where
functions, no contracts on constructors - refined fields already
cover construction); at most one PRE and one POST per function;
contract contexts inherited from the function's signature. Each is
a documented line in EXCLUSIONS-style honesty, none is
architectural.

## 5. Compile-time discharge (M81)

A contract whose predicate reduces to True with its parameters
OPAQUE holds on every call - checking it at runtime buys nothing.
`AHC.Discharge` is a fuel-bounded constant evaluator over
elaborated Core (closures and environments over the existing
arena, eager arguments, lazy branches, two-pass letrec for the
dictionary globals, method-selector projection through known
dictionaries, and literal folding for the Int primitives): each
claim's body is evaluated once at compile time, and

- **Proved True**: the claim is dropped before the wrapper is
  built - both dropped means no wrapper at all, zero overhead;
- **Proved False**: the contract can NEVER hold, which is a
  compile-time warning ("this precondition can never hold"); the
  runtime check stays, so a demanded call still fails with the
  standard message;
- **Unknown**: the runtime check stays. Opaque parameters poison
  every path that consumes them, so an argument-dependent
  predicate (`\lo hi x -> lo <= hi`) can never be discharged by
  mistake - unsoundness is impossible by construction, only
  incompleteness.

`scripts/run_discharge.sh` pins all three behaviors against the
generated C (claims present or absent by grep), and
ext_contracts_discharge.hs pins that discharge never changes
observable behavior - GHC ignores the pragmas, so the oracle
comparison covers the discharged program for free. The same
policy as Ada: what the compiler can prove, the runtime need not
check.

## 6. What this completes

With contracts, the Ada-extension story closes symmetrically:
refinement types carry Ada's subtype constraints to Haskell values;
contracts carry Ada's subprogram contracts to Haskell functions;
both are ordinary typechecked Haskell predicates underneath, both
fire at demand time because laziness demands it, and both strip
under the release policy. The compiler that borrowed Ada's
discipline for its own implementation ends up lending Ada's
discipline to the programs it compiles.
