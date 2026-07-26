# The AHC Manual

*A complete guide to the Ada Haskell Compiler: every decision, and
the theory behind it, explained from the ground up.*

This manual assumes you are smart but not a compiler engineer. Every
piece of theory is introduced when it is first needed, in plain
language, before the decision that depends on it. If you read it
front to back you will understand why every part of AHC is the way
it is. If you want one thing, the table of contents and the glossary
(chapter 17) will get you there.

---

## Table of contents

1.  [Orientation: what a compiler is, and AHC's shape](#1-orientation)
2.  [Why Ada, and what contracts bought us](#2-why-ada)
3.  [Reading Haskell: lexing, layout, parsing, operators](#3-reading-haskell)
4.  [Names: the renamer and the module system](#4-names)
5.  [Types, part one: kinds and Hindley-Milner inference](#5-types-part-one)
6.  [Types, part two: type classes are just records](#6-type-classes)
7.  [Desugaring: shrinking Haskell to eight shapes](#7-desugaring)
8.  [Laziness: thunks, graph reduction, and the runtime](#8-laziness)
9.  [Code generation: from Core to C](#9-code-generation)
10. [Numbers: Int, Integer, and Double](#10-numbers)
11. [Show: why printing was hard](#11-show)
12. [The refinement-types extension](#12-refinement-types)
13. [The optimizer: making it faster without changing it](#13-the-optimizer)
14. [Testing: GHC as the oracle](#14-testing)
15. [The standard library](#15-the-standard-library)
16. [War stories: the bugs and what they taught](#16-war-stories)
17. [Glossary](#17-glossary)
18. [Map of the source tree](#18-source-map)

---

## 1. Orientation

### What a compiler actually does

A compiler is a translator with strong opinions. It takes text a
human wrote and produces something a machine can run, and along the
way it checks that the text *means* something. AHC translates
Haskell source code into C, then hands that C to `clang` to make a
native executable.

No compiler does this in one leap. AHC is a **pipeline** of small
translations, each one taking the program in one representation and
producing it in a slightly more digested one:

    source text
      -> tokens               (lexer:      characters -> words)
      -> laid-out tokens      (layout:     indentation -> braces)
      -> syntax tree          (parser:     words -> structure)
      -> resolved tree        (fixity:     operator precedence)
      -> named tree           (renamer:    names -> unique ids)
      -> kinded environment   (kinds:      types of types checked)
      -> Core                 (desugarer:  40 constructs -> 8)
      -> typed Core           (typechecker: every expression typed)
      -> Core with evidence   (elaborator: class magic made explicit)
      -> checked Core         (refine:     refinement checks inserted)
      -> smaller Core         (optimizer:  simplification)
      -> C source             (codegen:    Core -> C)
      -> native executable    (clang + the AHC runtime)

Each stage lives in one Ada package (`src/ahc-lexer.adb`,
`src/ahc-parser.adb`, and so on), and each is testable on its own —
`ahc lex`, `ahc parse`, `ahc core`, `ahc check`, `ahc emit` let you
stop the pipeline at any point and look at what it produced - and
`ahc repl` runs the whole thing interactively, compile-and-run over
the object cache with no second evaluator
(`docs/repl-design-note.md`).

**The decision** to use many small stages instead of a few big ones
was made at the very start and never regretted. Small stages mean
each one can state precisely what it guarantees about its output —
which is where Ada's contracts come in (chapter 2) — and each can be
tested against golden files independently. When something breaks,
the broken stage identifies itself.

### The two representations that matter

You will see two tree-shaped data structures mentioned constantly:

**The syntax tree** (`src/ahc-syntax.ads`) mirrors what the
programmer wrote. It has around forty different node shapes because
Haskell has around forty surface constructs: `if`, `case`, `do`,
list comprehensions, `where`, guards, sections, records, and so on.

**Core** (`src/ahc-core.ads`) is the compiler's internal language.
It has only *eight* expression shapes: variable, literal,
constructor, application, lambda, let, case — that's it (plus a
recursive-let flag). Everything Haskell can express, Core can
express with those eight, just more verbosely. Chapter 7 explains
how the shrinking works and why it is the single best decision in
the compiler.

### The one file to read first

`prelude/Prelude.hs` is ordinary Haskell — `map`, `filter`, `sum`,
the `Show` instances for tuples. AHC compiles this file through its
own full pipeline before it compiles your program. The compiler
eats its own cooking. When you understand that this file is not
special in any way — no magic, just Haskell that happens to be
loaded first — you understand the spirit of the whole project.

---

## 2. Why Ada

### The bet

The project's founding bet was: **a compiler is exactly the kind of
program that Ada's Design-by-Contract features are good at keeping
honest.**

A compiler is a long chain of data transformations where each stage
assumes things about its input ("every operator chain has been
resolved", "every name has been bound", "this dictionary has exactly
seven fields"). In most compilers those assumptions live in
comments and in the authors' heads. When one is silently violated,
the symptom appears three stages later as a baffling crash or, worse,
silently wrong output.

Ada lets you write the assumptions *in the code*, as machine-checked
contracts:

- a **precondition** (`Pre =>`) says "you may only call me if this
  is true" — checked at every call;
- a **postcondition** (`Post =>`) says "when I return, this will be
  true" — checked at every return;
- a **type invariant** says "values of this type always satisfy
  this" — checked whenever a value crosses the type's boundary.

In AHC's *validation* build every contract is live; in the *release*
build they compile away to nothing. You develop with a net and ship
without the weight.

### Did the bet pay off? Concretely, yes

These are real incidents from the project's history where a contract
caught a bug at the moment of introduction rather than three stages
later:

- **`Chain_Free`** — the fixity stage's postcondition promises "no
  unresolved operator chains survive me." When the refinement-types
  extension later added *expressions inside types* (`Int satisfying
  (\n -> n * n < 200)`), nobody remembered that the fixity stage
  never walks types. The postcondition failed instantly, naming the
  exact gap. Without it, the bug would have surfaced as a weird
  crash in the renamer.
- **`Mk_Dict`'s arity precondition** — a class dictionary must have
  exactly as many fields as the class has methods. When the `Show`
  class grew a third method (chapter 11), this contract fired at
  every construction site that hadn't been updated — a complete,
  automatic to-do list.
- **`Fun_D`'s "at least one pattern" rule** — when `(op) = e`
  bindings were added to the parser, the first attempt represented
  them as zero-argument function equations. The tree's own
  well-formedness contract rejected that, which forced the
  *correct* representation (a variable binding) instead of a hack.
- **The occurs check** (chapter 5) is written as a precondition on
  the one operation that could create an infinite type — the PRD's
  marquee example of a compiler invariant as a contract.

### The arena pattern

Every tree in AHC — syntax and Core both — is stored as an **arena**:
a growable array of node records, where nodes refer to each other by
**integer index**, not by pointer. A node id is a distinct integer
type per category (`Expr_Id`, `Pat_Id`, `Type_Id`...), so using an
expression id where a pattern id belongs is a *compile-time* error in
the Ada code. Id zero means "absent"; real ids start at one.

Why this instead of pointers, which is what most compilers use?

1. **Contracts become cheap.** "This node's children exist" is just
   `Child_Id <= Last_Node` — an integer comparison, checkable in a
   precondition on the arena's `Add` operation. Every single node
   ever added to any tree in AHC passed a well-formedness check at
   the moment of its creation.
2. **Category confusion is impossible.** Distinct integer types per
   node category means the type system polices the tree's shape.
3. **Memory is trivial.** One arena owns a whole module's tree;
   dropping the arena frees everything. No lifetime puzzles.

### The tree invariant (learn this one — it bit us twice)

A rule that emerged from two painful bugs: **Core expressions must
form a tree, never a DAG.** That is: no expression node may be
referenced from two places.

Why? Because later stages *rewrite nodes based on how they were
visited*. The typechecker attaches "evidence" (chapter 6) to each
place an overloaded function is *used*. If one node is shared by two
uses, it gets rewritten twice — the second rewrite corrupts the
first. This exact bug shipped in the pattern-match compiler (which
shared a "failure" node between case branches to avoid duplication)
and lay dormant for sixteen milestones until the conformance suite
exercised nested `Maybe` patterns. The fix — clone a fresh node per
reference — is now a named helper (`Fresh_Ref`) and a rule applied
everywhere new Core is built by hand.

---

## 3. Reading Haskell

### Lexing: characters into words

The lexer (`src/ahc-lexer.adb`) groups characters into **tokens**:
identifiers, keywords, operators, literals, punctuation. Haskell's
lexical grammar has a few famous corners the lexer handles in full:
nested block comments (`{- {- -} -}` is one comment), the
distinction between constructor names (`Just`) and variable names
(`just`) being purely a matter of the first letter's case, and
numeric literals in three radices (`255`, `0xFF`, `0o777`).

Every identifier is **interned**: stored once in a name table and
referred to by integer id afterwards. Comparing two names is then an
integer comparison, and the same id means the same spelling
everywhere.

### Layout: the whitespace algorithm

Haskell mostly has no braces or semicolons — indentation *is* the
block structure:

    main = do
      putStrLn "one"
      putStrLn "two"

Under the hood, Haskell defines this by translation: there is a
precise algorithm (the Report's **section 10.3, the "L function"**)
that inserts invisible braces and semicolons based on column
positions, turning the code above into
`main = do { putStrLn "one" ; putStrLn "two" }`. The parser then
only ever deals with the braced form.

AHC implements L faithfully as a streaming transformation between
the lexer and parser (`src/ahc-layout.adb`). Two things make it
genuinely tricky:

**The parse-error rule.** L has one clause that says: if the parser
hits an error and closing an implicit block would fix it, close the
block. This makes the layout algorithm and the parser *mutually
recursive* — layout needs to know when the parser is stuck. AHC
wires this as a callback: the parser, on failure, asks the layout
engine to close a block and retries. This is what makes one-liners
like `let x = 1 in x` work: the `in` is a parse error inside the
`let` block, which triggers the close.

**Lookahead vs. layout.** The parser sometimes reads ahead several
tokens to decide what it is looking at (is `x <- foo` a pattern bind
or an expression?). Those look-ahead tokens have already been
processed by the layout engine — so when a parse error then needs a
block closed, the layout engine's queue is stale. The fix (a late
war story, chapter 16) exploits a theorem about L: *within a single
source line, the algorithm never consults its indentation stack*, so
the parser may safely synthesize the close itself for same-line
tokens. Correct-but-subtle code like a nested
`let x = 1 in let y = 2 in y` inside a `do` block depends on this.

**Why an explicit layout stage at all?** Some compilers fuse layout
into the parser. Keeping it separate means it can be tested alone
(`ahc lex --layout` shows exactly which invisible tokens were
inserted, and golden tests pin them) and its central invariant —
every implicit open brace is matched by exactly one close — is an
Ada type invariant on the layout stream, checked continuously.

### Parsing: recursive descent, by hand

The parser (`src/ahc-parser.adb`) is **hand-written recursive
descent**: one Ada function per grammar rule, each consuming tokens
and building syntax-tree nodes. The alternative was a parser
generator (a tool that compiles a grammar file into a parser).

**Why hand-written?** Three reasons. Error messages: you control
exactly what gets said when parsing fails. The parse-error layout
rule: it needs the parser to expose its failure points, which is
natural in hand-written code and painful through a generator.
And extensibility: the refinement-types extension later added three
contextual keywords (`in`, `satisfying`, `mod` — see chapter 12);
each was a few lines in a hand-written parser and would have been a
grammar-conflict headache in a generated one.

### Fixity: operators after the fact

Here is a subtlety most people never think about: when the parser
sees `a + b * c`, it *cannot know* how to group it, because in
Haskell, programs can declare their own operators with their own
precedences (`infixl 6 +`) — and the declaration might come *after*
the use, or in another module.

So AHC's parser doesn't even try. It produces a **flat chain** node:
"the operands were `a`, `b`, `c` and the operators between them were
`+`, `*`" — no grouping. A separate stage (`src/ahc-fixity.adb`)
runs after the whole module is parsed, when all fixity declarations
are known, and rewrites every chain into a properly-shaped tree
using each operator's declared precedence and associativity.

The postcondition of that stage — no flat chain survives — is the
`Chain_Free` contract from chapter 2. Fixity information also
travels between modules through the module registry (chapter 4), so
a custom operator's `infixr 3` declaration is honored by importers.

---

## 4. Names

### The renamer: every name becomes a unique number

Consider:

    f x = let x = 1 in x

There are two different `x`s. Textual names are ambiguous; compilers
need each *binding* to have its own identity. The renamer
(`src/ahc-rename.adb`) walks the tree and assigns every binding a
fresh integer id — a **unique variable id** — and resolves every use
to the id of the binding it refers to, following Haskell's scoping
rules (inner shadows outer).

**The decision**: unique integer ids, minted once, never reused.
The main alternative in the literature is "de Bruijn indices"
(naming variables by how many binders away they are), which makes
some proofs easier but makes every code transformation reindex
everything. With globally unique ids, a transformation can move code
freely and *variable capture is impossible by construction* — there
is simply no way for two different variables to collide, because
they are different integers. This paid off in the optimizer
(chapter 13), which moves code around with zero capture logic.

Resolution results are stored in **side tables** indexed by node id
(`Resolutions` in the renamer), not written into the tree — the
syntax tree stays a faithful record of what the programmer wrote.

### Modules: who can see what

Until late in the project AHC compiled one file. The module system
(Report chapter 5) changed the renamer's world: now `import
Data.List (sort)` means `sort` is visible here, and a name defined
in another module but *not exported* must be invisible.

The design has three pieces:

**Whole-program frontend.** The driver finds every `import`,
locates each module's file (`A.B.C` → `A/B/C.hs`, searched beside
your file, then `$AHC_LIB`, then the compiler's `lib/`), orders them
so dependencies come first (a cycle is an error), and runs each
through the front half of the pipeline into *one shared Core
program*. This is exactly the mechanism the Prelude had always used;
modules generalized it. Interface files were deliberately left out:
the whole-program frontend is what gives Report-exact program-wide
instance coherence for free. (Code *generation* is a different
story — since the separate-compilation milestone each module emits
its own C file and cached object; chapter 9.)

**A registry of interfaces.** As each module is renamed, it deposits
its *exports* — the names its export list admits, with their ids —
into a registry (`src/ahc-modules.ads`). `T(..)` in an export list
drags the type's constructors and field selectors along; `C(..)`
drags a class's methods.

**Layered lookup.** When the renamer resolves a name inside module
M, it looks in order: local scopes → M's own top level → the
*imports'* registry entries (if two different imports supply the
same name, that's the Report's "ambiguous name" error, reported at
the use site) → a frozen **snapshot** of the built-ins and Prelude.
The snapshot matters: it means a module defining its own `reverse`
cannot accidentally shadow the Prelude's `reverse` for *other*
modules — they resolve against the snapshot, not against a shared
mutable table.

**Restricting the Prelude.** The snapshot fallback is exactly the
Report's *implicit* `import Prelude` — and Report 5.6.1 says an
*explicit* `import Prelude ...` replaces it. AHC implements this:
`import Prelude hiding (lookup)` frees the name for your own
definition, `import Prelude (print, map)` narrows the Prelude to a
list, `import Prelude ()` empties it, and `import qualified
Prelude` forces qualification. Mechanically the explicit import
just becomes an ordinary import view filtered from the Base
snapshot (the same machinery as any `hiding`/only-list), and the
renamer's final snapshot fallback switches off. Two details are
easy to get wrong and are pinned by conformance tests: `hiding`
filters the import's *qualified* names too (`Prelude.map` is out of
scope under `hiding (map)` — GHC agrees), and builtin *syntax* —
`()`, `[]`, `:`, tuples — can never be hidden, because it is
grammar, not a Prelude export.

A pleasing historical note: the parser had supported the *entire*
module-header grammar — export lists, `qualified`, `as`, `hiding` —
since the first month of the project, unused, because "parse the
whole Haskell 2010 surface" was a phase-one goal. When modules were
finally implemented, the parser needed zero changes; when the
Prelude-restriction corner was finally implemented (the last item
of the polish plan), the *import machinery* needed zero changes —
only where the fallback applies.

---

## 5. Types, part one

### What type checking is for

A type checker answers one question relentlessly: *does this
expression make sense?* `length "hello"` makes sense; `length 5`
does not, because `length` wants a list. The value of answering this
before running the program is that whole categories of crashes
become impossible.

Haskell goes further than most languages: you almost never have to
*write* the types. The compiler infers them. `f x = x + 1` — the
compiler works out for itself that `f` takes a number and returns a
number. The algorithm that does this is the heart of the compiler.

### Kinds: the types of types

Before checking expressions, AHC checks *types themselves*
(`src/ahc-kinds.adb`). Just as `5` has type `Int`, the type `Int`
has a **kind**, written `*` — "a complete type." `Maybe` on its own
is not a complete type — it needs an argument (`Maybe Int` is
complete) — so its kind is `* -> *`: "give me a type, I'll give you
a type." Kind checking catches nonsense like `Maybe Maybe` the same
way type checking catches `length 5`. AHC infers kinds with a tiny
version of the same machinery used for types, and (per the Report)
defaults any leftover ambiguity to `*`.

The kinds stage is also where every type the programmer *wrote*
(signatures, annotations) is converted from surface syntax into
Core's type representation, expanding type synonyms along the way.
After this stage, the typechecker never sees surface types at all —
one converter, one set of rules.

### Hindley-Milner in plain language

The inference algorithm is called **Algorithm W** over the
**Hindley-Milner** type system. Strip the names away and it is
three ideas:

**Idea 1 — unknowns.** When the compiler doesn't know a type yet, it
makes up a placeholder, a **metavariable** — think "type to be
determined, call it ?1". Checking `f x = x + 1`, it starts with
`x :: ?1`.

**Idea 2 — unification.** Every use of an expression generates an
equation. `x + 1` means "?1 must be the same type as what `+`
accepts." **Unification** is the solver: given two types that must
be equal, it either fills in metavariables to make them equal, or
reports a type error. Unify `?1 -> Bool` with `Int -> ?2` and you
learn `?1 = Int`, `?2 = Bool`.

There is one trap: unifying `?1` with `[?1]` ("this type equals a
list of itself") would create an infinite type. The **occurs check**
refuses it — before assigning a metavariable, check that it doesn't
occur inside the type it's being assigned. In AHC this is *the*
showcase contract: a precondition on `Bind_Meta`, the single
operation that could ever create a cycle. It is checked exactly
once per assignment, at the only place it could go wrong.

**Idea 3 — generalization.** After checking `id x = x`, the compiler
has `id :: ?1 -> ?1` with `?1` never pinned down. That is not an
error — it means `id` works *for any* type. Generalization converts
the leftover metavariable into a **forall**: `id :: forall a. a -> a`.
Each *use* of `id` then gets its own fresh copy of `a`
(**instantiation**), which is why `id 5` and `id "hi"` can coexist.
This is called **let-polymorphism** because it happens at `let` and
top-level bindings.

Two engineering details worth knowing:

- **Binding groups.** Mutually recursive functions must be inferred
  *together* (checking one alone would prematurely fix the other's
  type). AHC finds the groups with a standard graph algorithm
  (Tarjan's strongly-connected components) and generalizes each
  group as a unit, sharing one context.
- **Levels.** To know *which* metavariables may be generalized (only
  ones invented inside this binding, not ones from an outer scope),
  each metavariable carries the nesting depth at which it was born —
  a technique due to Rémy that replaces an expensive scan with an
  integer comparison.

### Two Report rules people find weird

**The monomorphism restriction** (Report 4.5.5): a binding without
arguments and without a signature (`x = ...` rather than
`f a = ...`) is *not* generalized. The rule exists to prevent a
value you expect to be computed once from being secretly recomputed
at every use (polymorphism can force that, for reasons that will
make sense after chapter 6). AHC implements it exactly, because the
test oracle is GHC and GHC implements it exactly. Amusingly, during
development a test "failure" here turned out to be the *test* being
wrong — AHC was correctly rejecting a program that the test author
assumed was fine, and GHC agreed with AHC.

**Defaulting** (Report 4.3.4): `print (2 + 3)` never says what type
`2` is. The Report's rule: if the ambiguity involves only numeric
classes, try `Integer`, then `Double`, and use the first that fits.
This is why `print (2+3)` prints an arbitrary-precision `Integer`
answer in both GHC and AHC. AHC's defaulting covers the Prelude's
classes; a limitation, discovered late, is that a user-defined class
in a constraint (`Data.Ix`'s `range (3, 7)`) blocks defaulting and
needs an annotation — and the honest footnote is that GHC required
annotations on the very same test lines.

---

## 6. Type classes

### The problem classes solve

`+` works on `Int` and on `Double`. `show` works on almost
everything. But those implementations are completely different
machine code. How can one function name mean different things at
different types, *and* still be type-checked honestly?

Haskell's answer is the **type class**. A class is an interface:

    class Show a where
      show :: a -> String

An **instance** provides the implementation for one type:

    instance Show Bool where
      show True  = "True"
      show False = "False"

And a constraint in a signature — `print :: Show a => a -> IO ()` —
says "works for any `a` *that has a Show instance*."

### The translation: there is no magic

The single most important thing to understand about AHC's class
implementation — and GHC's, this is the standard technique — is the
**dictionary translation**:

> A class is a record type. An instance is a value of that record.
> A constraint is a hidden extra argument.

Concretely, `Show` becomes a record ("dictionary") with three
fields — `show`, `showsPrec`, `showList`. The instance for `Bool`
is one concrete record whose `show` field holds the Bool-printing
function. And `print :: Show a => a -> IO ()` secretly compiles to
a *two*-argument function: the dictionary comes first.

    print dict x = putStrLn ((dict's show field) x)

When you write `print True`, the compiler *finds* the `Show Bool`
dictionary and inserts it: `print showBoolDict True`. All the
"magic" of overloading is just the compiler passing records around
on your behalf. In AHC you can watch it happen: `ahc core` prints
the translated program, dictionaries and all — look for `$d`
variables (dictionaries) and `sel$` functions (field selectors).

Everything else about classes falls out of this picture:

- **Superclasses** (`class Eq a => Ord a`): the Ord dictionary
  contains an Eq dictionary as its first field.
- **Default methods**: a class can supply fallback method bodies;
  an instance that omits a method gets the default, wired to the
  instance's own dictionary (a small knot: the dictionary is defined
  in terms of itself, which lazy evaluation handles gracefully).
- **`deriving`**: the compiler writes the instance for you. Derived
  `Eq`/`Ord` use a generic structural comparison in the runtime;
  derived `Show` generates real per-constructor code (chapter 11).
- **Instances are global**: the Report says instances flow to every
  module regardless of import lists, which is exactly what AHC's
  single global instance table does naturally.

### Where the dictionaries get inserted

This was the hardest engineering in the compiler (milestone 16, and
the source of the tree-invariant rule). Inference discovers, at each
use of an overloaded function, a **wanted** constraint — "I need a
`Show` dictionary for whatever type this turns out to be." Each
wanted remembers the exact tree node it arose at (its **site**).
Solving a wanted has three outcomes: it matches an in-scope
constraint from a signature (use that hidden parameter), it matches
an instance (use that instance's dictionary, possibly recursively —
`Show [Int]` needs `Show Int` for the elements), or it stays
unsolved and becomes part of the binding's own signature. After
everything is solved, a rewriting pass returns to every site and
splices in the dictionary argument.

That "splice at the site" step is why shared nodes are forbidden
(chapter 2): a node reachable from two sites collects two splices.

### Why AHC typechecks Core, not Haskell

A structural decision worth explaining: GHC typechecks the *big*
surface language and desugars afterwards; AHC desugars *first*
(chapter 7) and typechecks the eight-construct Core. The tradeoff:
AHC's typechecker is a few hundred lines instead of a few thousand,
at the cost of error messages pointing at desugared code. The
mitigation: every Core node keeps the source position of the
construct it came from, and generated names start with `$` so the
type printer can hide them. For this project's goals — a verifiable,
comprehensible compiler — the small typechecker wins decisively.

---

## 7. Desugaring

### The idea: a small core language

Haskell's forty constructs are conveniences. Each is definable in
terms of a smaller set — the Report itself gives the translations.
The desugarer (`src/ahc-desugar.adb`) applies them, by the book:

| You write | It becomes |
|---|---|
| `if c then a else b` | `case c of True -> a; False -> b` |
| `do x <- m; k` | `m >>= (\x -> k)` |
| `[f x | x <- xs, p x]` | `concatMap`/`filter` calls (Report 3.11) |
| `\x y -> e` | nested one-argument lambdas |
| `where` bindings | a `let` |
| `[1 .. 10]` | `enumFromTo 1 10` |
| `x { field = v }` (record update) | a `case` that rebuilds the record |
| the literal `5` | `fromInteger 5` (that's how literals are overloaded!) |
| guards | nested cases with fall-through |

The payoff is compounding: every stage after this point — the
typechecker, the optimizer, code generation — handles eight shapes
instead of forty. When pattern guards were added late in the project
(Report 3.13: guards like `| Just v <- lookup k m`), the change was
parser + desugarer only; the typechecker and everything downstream
did not know it happened.

### The pattern-match compiler

The biggest single piece of desugaring is compiling **pattern
matching**. You write:

    unwrap (Just (Just n)) = n
    unwrap (Just Nothing)  = -1
    unwrap Nothing         = -2

Core's `case` can only inspect *one* constructor level at a time. The
desugarer's match compiler turns multi-equation, nested-pattern
definitions into decision trees of simple cases:

    case arg of
      Just t  -> case t of
                   Just n  -> n
                   Nothing -> -1
      Nothing -> -2

Two design points:

**Join points.** When a pattern fails, control "falls through" to
the next equation. Naively you would copy the next equation's code
into every failure position — exponential blowup. Instead the
fall-through code is bound once in a `let` (a **join point**, named
`$fail` or `$k`) and failure positions just reference it. (And each
reference is a *fresh* node — this is where the tree-invariant bug
lived.)

**A matrix-shaped design.** The compiler is structured around an
explicit matrix of patterns-by-equations (the classic
Wadler/Peyton-Jones scheme) so that a future exhaustiveness checker
("warning: you forgot the `Nothing` case") could be added without
restructuring. That promise was eventually collected on:
`AHC.Exhaustive` runs Maranget's *usefulness* algorithm over every
function's equations and every case expression. The idea is one
question asked two ways: "is there a value this row matches that no
earlier row does?" Ask it of an imaginary all-wildcard row after
your clauses - if the answer is yes, some value falls through
(non-exhaustive). Ask it of each real clause against its
predecessors - if the answer is no, that clause can never fire
(redundant). The algorithm walks columns: a wildcard against a
*complete* set of constructors (every constructor of the type
appears) splits into one sub-problem per constructor; anything
else drops to the rows that keep matching. Guards are handled
conservatively - a guarded clause only counts as covering things
when one of its guards is a literal `otherwise`/`True` - and
literals never form a complete set (there is always another
integer). Warnings fire for the module you are compiling, not for
the Prelude or libraries, and the pinned test corpus agrees
line-for-line with GHC's own checker.

### Laziness discipline in the translations

Several translations have to be careful *not to evaluate things*.
`let (a, b) = e` must not touch `e` until `a` or `b` is demanded, so
it becomes selector thunks (Report 4.4.3.2: `a = fst e`,
`b = snd e` morally). A literal pattern `f 0 = ...` becomes an
equality *test* (`== 0`), not a match, because numeric literals are
overloaded. These fine points are exactly what the GHC-oracle test
suite is good at pinning down (chapter 14).

---

## 8. Laziness

### Call-by-need, honestly explained

In most languages, `f (expensive ())` computes `expensive ()`
first. Haskell does not. Haskell evaluates an expression only when
its value is *demanded* — by pattern matching on it, printing it, or
doing arithmetic with it. Until then it is carried around as an
unevaluated packet. Three consequences define the language:

1. `take 3 [1 ..]` works — the infinite list is only ever three
   cells demanded.
2. `let x = error "boom" in 5` is `5` — the error never fires
   because `x` is never demanded.
3. And crucially, **need**, not just laziness: when a value *is*
   demanded, it is computed once and the result remembered. Ten
   uses of `x` cost one computation.

### The machine: graph reduction

The runtime (`runtime/ahc_rts.c`, about a thousand lines of C)
represents every value as a **node** in a heap graph. A node is a
tag plus payload:

- `THUNK` — an unevaluated computation: a C function pointer plus
  the values it captured. The packet from above.
- `FUN` — a function value (closure): code pointer + captured
  environment.
- `CON` — a constructor cell: a tag (which constructor) and its
  field pointers. Lists are chains of these.
- `INT`, `DOUBLE`, `CHAR`, `BIGINT` — plain values.
- `IND` — an indirection, "the value is over there" (see below).
- `BLACKHOLE` — "being evaluated right now."

**Evaluation** (`ahc_eval`) takes a node and drives it to a value:
if it's a thunk, run its code — and then **update in place**: the
thunk node is overwritten with an indirection to the result. That
overwrite is the "need" in call-by-need — the memoization. The
`BLACKHOLE` tag is set while a thunk runs, so a computation that
demands *itself* (`let x = x + 1 in x`) is detected as `<<loop>>`
instead of hanging.

Functions are **curried**: every function takes exactly one
argument. `f a b` is `(f a) b` — applying `f` yields a new closure
holding `a`, which is then applied to `b`. Simple, uniform, and
slower than a real compiler's multi-argument calling convention;
AHC chose uniformity.

### Two decisions about the runtime

**Garbage collection: Boehm, not homemade.** Graph reduction
allocates constantly and abandons nodes constantly; a garbage
collector is mandatory. AHC links the Boehm-Demers-Weiser
*conservative* collector — it scans memory for things that look like
pointers, requiring zero cooperation from our generated code. A
precise homemade GC would be faster and its own multi-month project;
Boehm is one linker flag (and the runtime falls back to plain
`malloc` — never freeing — when Boehm isn't installed, which is fine
for short programs). This was the right scope call, with one scar
(the stack-size story, chapter 16).

**Deep chains and the big stack.** Evaluating a value built by a
million-step `foldl` means a million-deep chain of thunks, each
demanding the next — which AHC evaluates by *C recursion*, one stack
frame per link. A million frames overflows the default 8MB C stack; the
symptom was a segfault *after* printing the right answer. The fix:
generated executables link with a 512MB stack. GHC solves this
properly with its own growable evaluation stack machine; AHC's
one-linker-flag version covers practical programs and is honest
about being a shortcut.

**Opting out: `seq`.** The Report's one escape hatch from laziness
is `seq :: a -> b -> b` — force the first argument to weak head
normal form, yield the second. In the runtime it is exactly that
(`ahc_eval(a); return b;`), and everything else is source built on
it: `f $! x` forces the argument before the call, and
`Data.List.foldl'` keeps its accumulator evaluated
(`let z' = f z x in z' `seq` ...`), so the million-thunk chain
above never forms — the fold runs in constant space and the
benchmark suite measures the difference (`b_strictfold` vs
`b_sumfold`). WHNF matters: `seq [undefined] x` forces only the
list's first constructor, never its elements — forcing is one
layer, not deep evaluation.

### Where laziness shaped other features

Once you know evaluation happens at *demand*, several AHC design
choices become inevitable rather than quirky:

- Refinement checks (chapter 12) fire when the checked value is
  demanded, not when it's passed. An unused out-of-range argument
  never fails — exactly like `error` in an unused argument.
- `case e of _ -> body` does not evaluate `e` (a wildcard demands
  nothing) — the optimizer relies on this to delete such cases.
- Dropping a `let` binding nobody uses is always safe — an
  undemanded thunk is invisible.

---

## 9. Code generation

### Why C

The final stage (`src/ahc-codegen.adb`) prints C source. The PRD
considered LLVM; C won because it removes an entire dependency and
toolchain, is debuggable with ordinary tools, and `clang -O1`
cleans up the generated code enough. The generated file is
self-contained: it includes the runtime header and is compiled
together with `ahc_rts.c` (`scripts/ahc-build.sh` does the two-step).

### Closure conversion

C has no nested functions, but Core is full of lambdas that capture
surrounding variables. **Closure conversion** bridges the gap: every
lambda is *lifted* to a top-level C function taking an environment
array, and creating the lambda becomes allocating a `FUN` node
pairing that function with an array of its captured values. The
codegen computes each lambda's free variables to know what to
capture.

Everything lazy gets the same treatment: an expression in a lazy
position becomes a lifted thunk function plus a `THUNK` node
capturing its free variables.

A few mechanical notes: top-level values become C globals
initialized at program start (CAFs — "constant applicative forms");
`let` and `case` compile to GNU C *statement expressions* (a clang
extension that lets a block yield a value), with recursive `let`
handled by allocating first and patching environments after;
constructors compile to calls into generic runtime "worker"
machinery rather than per-constructor functions.

### The prims boundary

Primitives — arithmetic, `putStrLn`, `getLine`, the check
functions — are C functions in the runtime. The compiler-side
registry is a simple map from variable id to C symbol name
(`Prim_Maps` in `src/ahc-prelude_core.ads`); codegen emits the
symbol when it sees the variable. Adding a primitive is therefore
three small steps: write the C function, declare a typed name for
it in `AHC.Builtins`, bind name to symbol in `AHC.Prelude_Core`.
This boundary stayed stable from milestone 17 to the end.

### The FFI: foreign import ccall

The prims boundary is compiler-internal; the **FFI** (Report
chapter 8) is the same idea opened to user programs:

    foreign import ccall unsafe "labs" c_labs :: Int -> Int
    foreign import ccall getenv :: String -> IO (Ptr Char)

Each declaration names a C symbol (defaulting to the Haskell name),
gives it a Haskell type, and becomes an ordinary global — no
binding generators, no `hsc2hs`, no `Storable` instances. The
pipeline treats it with three small touches that mirror existing
machinery: the renamer mints a bodiless global whose signature is
the declared type (the `Sig_D` channel, so kinds and the
typechecker need no special cases); the desugarer derives a
*marshalling spec* from the scheme into `Core_Module.Foreigns`;
codegen emits, in the owning module's C unit, an extern prototype
plus a wrapper that evaluates and unboxes each argument, calls the
C function, and boxes the result. The wrapper node substitutes at
occurrences exactly like a prim.

The v1 marshallable types, and what they become in C:

| Haskell            | C              | notes                        |
|--------------------|----------------|------------------------------|
| `Int`              | `long`         | bignum-range values die clean |
| `Double`           | `double`       |                              |
| `Char`             | `long`         | the code point               |
| `Bool`             | `int`          | 0/1                          |
| `()`               | `void`         | result position only         |
| `String`           | `const char *` | copied both ways, O(n)       |
| `Ptr a`            | `void *`       | phantom `a`; `Eq`/`Ord`      |

`nullPtr :: Ptr a` and `peekCString :: Ptr Char -> IO String` make
nullable C results (like `getenv`) expressible. Direct `String` and
`Bool` marshalling is an AHC convenience beyond GHC's FFI (GHC
requires `withCString`/`CInt` there); `Int`/`Double`/`Char`/`Ptr`
match GHC's model under `Int = long`.

Two rules keep it honest. **Types must match the C definition**
under the table above — declaring `int isalpha(int)` as
`Int -> Int` reads garbage high bits; keep to `long`-, `double`-
and pointer-shaped C functions until fixed-width `CInt`-style types
land. **An `Int` that has silently promoted to bignum dies at the
boundary** (`FFI: Int argument out of range`) rather than
truncating.

An IO-typed import gets the world-passing shape — the wrapper packs
its arguments and returns a `FUN` that performs the call only when
the world token arrives — so effect ordering is exactly `getLine`'s.
A pure import calls eagerly at saturation; a nullary pure import is
a CAF, evaluated once.

Linking against more than libc: pass `AHC_CFLAGS`/`AHC_LDFLAGS` to
`scripts/ahc-build.sh`, or put the flags in the source itself —

    {-# OPTIONS_AHC_LINK -lcurl #-}

`ahc emit` collects those into `OUT.build/link_flags` and the build
script appends them at link time (GHC just warns on the unknown
pragma, so the source still oracle-compiles). Compile flags are part
of the object-cache key, so changing them never reuses a stale
object. The Boehm collector is non-moving and conservative:
`AhcNode` pointers handed to C stay put, and pointers C hands back
need no pinning ceremony.

### The FFI: foreign export ccall, and AHC as a library

The other direction — C (or anything speaking the C ABI) calling
compiled Haskell:

    foreign export ccall square :: Int -> Int
    square x = x * x

    foreign export ccall "hs_fib" fib :: Int -> Int

An export names one of the module's own top-level bindings. If the
binding has no signature, the export type becomes its signature (so
the body is checked against it); if it has one, the binding's own
signature wins and drives the marshalling, which keeps the C
prototype honest by construction. The same type table applies, with
one caller-facing difference: an exported `String` result comes
back as a malloc'd `char *` the C caller frees. The generated entry
function marshals C arguments to nodes, builds the application
spine, evaluates (or runs the IO action through the world token),
and unboxes — a bignum-promoted `Int` result dies cleanly, exactly
like an argument would. The exported C name must be a plain C
identifier that isn't a C keyword; exporting Haskell's `double`
without a `"c_name"` is caught in the frontend, not by clang.

`--lib` turns the whole program into an embeddable library:

    scripts/ahc-build.sh --lib MathLib.hs mathlib.a

produces a static archive (runtime object included) and
`mathlib.a.build/ahc_exports.h` — prototypes for every export,
`extern "C"`-guarded for C++, plus `void ahc_lib_init(void)`, which
replaces `main()`: it runs the RTS init and every unit's
initializer in dependency order. The embedding contract is one
honest sentence: **call `ahc_lib_init` once, then call exports from
that same thread — the runtime is single-threaded and
non-reentrant.** The host controls the stack in library mode (there
is no 512 MB link trick), so deeply lazy structures may need the
host's stack raised. `scripts/run_export.sh` keeps the round trip
green: it builds `tests/export/MathLib.hs`, compiles a C `main`
against the header, and diffs the output.

### The layered Prelude

Where do `map` and `sum` come from? Three layers, and knowing them
explains most of `src/ahc-builtins.adb` and
`src/ahc-prelude_core.adb`:

1. **Builtins** — things that must exist before any Haskell is
   compiled: the class hierarchy, primitive types, and *type
   signatures* for wired-in values.
2. **Prelude source** (`prelude/Prelude.hs`) — ordinary Haskell,
   compiled first into the same program. Most Prelude functions
   live here. Anything defined here automatically *overrides* a
   hand-built version.
3. **Prelude_Core** — hand-built Core for the things source can't
   express: dictionary bodies wiring class methods to C primitives,
   and the derived-instance generators.

The project's arc consistently moved code *up* this list — from
hand-built Core toward ordinary Haskell — because Haskell in
`prelude/` or `lib/` is checked by the compiler itself, while
hand-built Core is only checked by the arena contracts.

### Separate compilation

For most of the project's life the compiler emitted ONE C file for
the entire program — prelude, libraries, and your code — and clang
recompiled all of it on every build. Measurement showed why that
mattered: the whole AHC pipeline (parse through optimized Core)
takes about a third of a second for the full mini-Lisp interpreter,
while clang on the 30,000-line monolith takes over five. Ninety-four
percent of every rebuild was the C compiler redoing work it had
already done.

The fix is a split with a principle on each side. **Code generation
is separate**: the program is emitted as one C file per module plus
a shared header, and every emitted name is *stable* — a global's C
symbol is mangled from its module and source name (never an arena
id), and locals and lifted functions are numbered per module,
counters reset at each unit boundary. Stability is the load-bearing
property: it makes a module's generated text a pure function of its
own code, so `ahc-build.sh` can cache each compiled object under a
hash of its C text and skip clang entirely for anything unchanged.
The cache is content-addressed, not timestamp-based — editing a
comment recompiles *nothing*, because comments never survive to the
generated C. A real edit to one module recompiles exactly one
object (`scripts/run_separate.sh` proves all of this on every run),
and interpreter rebuilds dropped from about six seconds to about
one.

**The frontend deliberately stays whole-program.** Types, classes
and instances are still resolved with every module in view — there
are no interface files. That is not laziness but a trade: the
Report requires instances to be coherent program-wide, and a
whole-program frontend gets that by construction, with no
orphan-instance rules, no interface-consistency checking, no
recompilation-avoidance bugs — the classic sharp edges of the
interface-file world — at a cost of ~0.3 seconds per build.

---

## 10. Numbers

### Int and Integer: two promises

Haskell has two integer types with different promises. `Int` is
fixed-width and fast; the Report explicitly says its overflow
behavior is *undefined*. `Integer` is arbitrary-precision — it never
overflows, ever; `product [1 .. 25]` is a 26-digit number and
Haskell just gives it to you.

For most of the project both were a C `long` and `product [1 .. 25]`
quietly gave the wrong answer (and a 30-digit *literal* crashed the
compiler with an Ada overflow — a latent bug found only when bignum
work began). The bignum milestone fixed this with a design worth
understanding because one idea does all the work:

**The canonical-form invariant.** A number that fits in a C `long`
is *always* stored as a plain `INT` node. The big representation
(`BIGINT`: a sign plus an array of 32-bit digit "limbs") appears
*only* for values beyond `long` range, and every operation that
produces a big result immediately demotes it back to `INT` if it
fits. Consequence: there is exactly one representation for every
value. Equality, ordering, printing, and hashing never face "is
`5`-as-INT equal to `5`-as-BIGINT?" — the situation cannot occur.

With that invariant, the implementation became small:

- The existing arithmetic primitives got a **fast path with an
  overflow check** (the compiler intrinsic `__builtin_add_overflow`
  and friends): stay in `long` arithmetic until it would overflow,
  then spill into limb arithmetic. Programs that never exceed 64
  bits pay one branch.
- Because `Num Int` and `Num Integer` had always shared their
  primitive functions, **no dictionary changed** — the shared prims
  just became promoting. `Int` overflow therefore *promotes* rather
  than wrapping. That differs from GHC (which wraps), but the Report
  leaves overflow undefined, so both are conformant — and an exact
  answer beats silent corruption. The conformance suite simply never
  probes Int wraparound.
- Division is the classic hard part of bignum. AHC uses binary long
  division (shift-and-subtract) — the simplest correct algorithm,
  quadratic but fine for a teaching compiler. `div`/`mod` floor
  toward negative infinity and `quot`/`rem` truncate toward zero,
  per Report 6.4.2 — negative-operand cases are pinned by oracle
  tests because they are easy to get wrong (`div (-7) 2` is `-4`,
  not `-3`).
- Printing peels nine decimal digits at a time (divide by 10^9);
  parsing big literals happens in the *runtime* (`ahc_mk_big_str`) —
  codegen routes any literal that might not fit a `long` there,
  counting digits conservatively, which is safe *because of the
  canonical invariant*: the runtime parser demotes small values
  right back.

### Double: the show problem

Floating-point arithmetic is easy — the C `double` does it. The hard
part, discovered when `sqrt` arrived, is *printing*. GHC prints the
**shortest decimal string that reads back as exactly the same
number**: `sqrt 2` is `1.4142135623730951` (17 digits), `0.1 + 0.2`
is `0.30000000000000004`. A naive `%.15g` format truncates both.
And GHC switches to scientific notation outside `0.1 <= |x| < 10^7`
(`1.0e7`, not `10000000.0`).

AHC reproduces this exactly: try printing at 1 significant digit,
re-parse, compare bit-for-bit; if it doesn't round-trip, try 2, up
to 17; then reformat the digits under GHC's fixed-vs-scientific
rule. Byte-identical output was non-negotiable because the entire
test methodology (chapter 14) depends on it.

Two more Double decisions: `round` is round-half-to-EVEN (`round 2.5`
is `2`, `round 3.5` is `4`) — the Report says so, and C's `rint`
under default rounding mode provides it; and — as of the numeric
tower milestone — `Integral`, `Floating` and `RealFrac` are **real
classes** with real dictionaries. `Integral` (superclasses Num and
Ord) has instances at both `Int` and `Integer`, and here the
canonical bignum representation (chapter 10 above) pays a dividend:
both instances bind the *same* promoting runtime primitives, and
`toInteger` is the identity function. `Floating` and `RealFrac`
have their instances at `Double`, wrapping the same C math
primitives the old monomorphic vocabulary used — so `sqrt` didn't
change at runtime, it changed *type*: `Floating a => a -> a`, an
overloaded method a user instance could now implement.
`fromIntegral` stopped being a wired special case and became two
lines of ordinary Prelude source (`fromInteger . toInteger`),
properly polymorphic at last, and `(^)`/`(^^)` joined it (exact
`2 ^ 100` via bignum). One deliberate simplification: the
`RealFrac` results (`floor` and friends) land at `Integer` rather
than being polymorphic in a second `Integral` type variable — which
is where GHC's defaulting sends them anyway, so oracle outputs
agree. `atan2` (RealFloat territory) stays monomorphic.

---

## 11. Show

### Why printing deserved its own milestone

`show` looks trivial and is not, for one reason: **strings are
lists**. `String` = `[Char]`. So the generic instance
`Show a => Show [a]` would print `"abc"` as `['a','b','c']` — which
AHC did, for thirteen milestones.

The Report's fix is elegant and worth understanding. The `Show`
class has a *third* method:

    class Show a where
      show      :: a -> String
      showsPrec :: Int -> a -> String -> String
      showList  :: [a] -> String -> String

`showList` answers: "how should a *list of you* be printed?" The
default prints brackets and commas. But the `Char` instance
*overrides* it to print one quoted string literal. And the list
instance's `show` *delegates to its element's* `showList`. So
`show "abc"` → list instance → Char's `showList` → `"abc"`. The
dispatch happens through the dictionary (chapter 6): the list
dictionary contains its element dictionary and calls through it.
Type-directed behavior with zero special cases in the compiler.

### Precedence, or why `Just (-5)` has parentheses

`showsPrec` carries a precedence number so nested values
parenthesize exactly when needed: `Just (-5)` and `Just (Left 3)`
get parens, `Just 5` doesn't. The convention: constructor
application binds at precedence 10; fields are shown at 11; negative
numbers parenthesize above 6. Before this existed AHC used a
string-inspection heuristic ("does the printed form contain a
space?") — it worked until it didn't, and the real mechanism
replaced it.

The odd-looking type `String -> String` (called `ShowS`) is a
performance idiom: functions that *prepend* to a string compose in
constant time, where naive `++` chains are quadratic. AHC uses the
real type for fidelity.

### deriving Show

`deriving Show` generates a real `showsPrec` per data type at
compile time: a case over the constructors, fields at precedence 11,
record syntax with braces when the type has field labels
(`Pt {px = 1, py = -2}`). The generator (in `AHC.Prelude_Core`)
resolves each field's `Show` dictionary statically and recursively —
a `Box (Maybe [Int])` field chains the Maybe and list dictionaries —
and maps type variables positionally to the derived instance's
dictionary parameters. The alternative (a runtime "generic show"
walking any value) fails because constructor *names* don't exist at
runtime — only numeric tags do. Generating real code was the only
honest path.

---

## 12. Refinement types

### The idea, from the original observation

The extension began with your observation: Ada can define types GHC
cannot. Ada's type system is organized around **value constraint**
(`type Percent is range 0 .. 100` — checked on every assignment);
GHC's is organized around polymorphism, and its value-constraint
axis is simply unoccupied (a `newtype` + smart constructor enforces
nothing internally and forfeits arithmetic). An Ada-implemented
Haskell compiler was uniquely positioned to put Ada's axis into
Haskell's surface. All four planned stages were built:

    type Percent  = Int in 0 .. 100                  -- range
    type Nat      = Int satisfying (\n -> n >= 0)    -- predicate
    type Clock    = Int mod 12                       -- wraparound
    type Latitude = Double in -90.0 .. 90.0          -- float range
    data Port     = Port (Int in 1 .. 65535)         -- in fields

### Decision 1: refinements are erased for typechecking

The load-bearing choice, made *before* the base compiler was even
finished (two rules were planted in Phase 2, years of milestones
early): a refined type unifies freely with its base. `Percent` *is*
`Int` to the typechecker — the refinement is a decoration
(`Refine` slot on the type-constructor node) that unification is
defined to ignore (`Same_Con_Erased`).

Why erase, when "real" refinement systems (Liquid Haskell) prove
constraints statically with an SMT solver? Because erasure preserves
what makes the feature *usable*: all arithmetic still works
(`p * 2` on a `Percent` needs no ceremony), no smart constructors,
no proof obligations, and — decisively for this codebase — the
typechecker needed **zero changes** across all four stages. The
trade: checks happen at runtime, like Ada's own `Dynamic_Predicate`,
not at compile time. That is Ada's model, faithfully transplanted.

### Decision 2: checks are wrappers at declared boundaries

Where do checks happen? At every *declared* boundary: a signature's
arguments and result, a `::` annotation, and (stage four) a
constructor's fields. The mechanism: a late pass (`src/ahc-refine.adb`)
wraps each such binding in an eta-wrapper — a function that applies
the check to each refined position and delegates to the original.
Dictionary parameters thread through untouched; recursive calls go
through the wrapper, so they're checked too.

And because of laziness (chapter 8), the check is itself a thunk:
it fires when the value is *demanded*. `countdown 7` on a
`Digit -> [Int]` prints `[7,5,3,` and *then* dies when the lazy
list's next element is demanded and turns out to be `-1`. A checked
value that is never used never fails. This is the only semantics
consistent with call-by-need, and it is pinned by oracle tests.

### Decision 3: contracts vs. coercions

Stage three (`Int mod 12`) forced a distinction that became the
extension's cleanest idea. A range or predicate refinement is a
**contract**: it *checks* and dies on violation. But wraparound
arithmetic cannot be a check — under erasure, `+` is plain Int `+`,
so the only place wrapping can happen is the boundary. So a modular
refinement is a **coercion**: values crossing an `Int mod 12`
boundary are *normalized* into `[0, 12)` (mathematical mod, never
negative — `(25 :: Clock)` is `1`).

The distinction has a visible consequence: `--unchecked` (the
release-mode flag, mirroring Ada's suppressed-checks policy) strips
contracts but **keeps** modular normalization — because removing a
check changes only failure behavior, but removing a coercion would
change *answers*. Exactly as Ada's release mode drops assertions
but keeps modular arithmetic.

### Decision 4: predicates are compiled Haskell

`Int satisfying (\n -> n * n < 200)` contains an arbitrary
expression *inside a type*. Rather than invent a restricted
predicate language, AHC compiles the predicate as a **hidden
top-level function** `$pred :: Int -> Bool` — minted during kind
checking, given its body by the desugarer, and then flowing through
the *normal* typechecker and dictionary machinery. That last part is
the payoff: a predicate like `even` has a class constraint
(`Integral`), and it is solved by the ordinary elaboration path with
zero special cases. The check primitive just applies the compiled
function. (This is also what forced the fixity stage to walk types —
the `Chain_Free` war story.)

Assorted smaller calls: `satisfying` and `mod` are *contextual*
keywords (still usable as ordinary names; `mod` is special only when
an integer literal follows, so `x `mod` 2` and type variables named
`mod` still work); stacking two refinements on one type is rejected;
float-range bounds keep their *lexemes* so `Double in 0.0 .. 3.0e2`
prints back exactly as written; constructor-site checks (stage four)
rewrite every use of a refined-field constructor, which covers
partial application (`map Port ports`) and record update for free,
while field *reads* trust the invariant established at construction.

### Function contracts: Ada's Pre and Post

Refinements constrain *values*; the second half of the Ada
extension constrains *functions*. A refinement can say "this Int is
in 1..65535" but never "the result lies between the first two
arguments" — that is a relation across a call, Ada's `Pre`/`Post`
territory, and it arrives as pragmas
(`docs/contracts-design-note.md`, `examples/contracts.hs`):

    {-# PRE  clamp \lo hi x -> lo <= hi             #-}
    {-# POST clamp \lo hi x r -> lo <= r && r <= hi #-}
    clamp :: Int -> Int -> Int -> Int

The implementation is pleasingly small because it hides inside
machinery you have already read about. The lexer skips pragmas as
comments (the layout engine never sees them) but records where they
were; each PRE/POST is then re-lexed and *re-parsed as an ordinary
top-level binding* — `$pre$clamp = \lo hi x -> lo <= hi` — spliced
into the module by synthesizing two tokens (`$pre$clamp`, `=`) in
front of the pragma's own expression tokens. From that moment the
contract IS ordinary Haskell: the renamer scopes it, the
typechecker checks it against a signature *derived* from clamp's
own (its type variables, its class context, its argument spine,
then `Bool`), and a type error in a contract points into the
pragma, because the fragment is lexed over a copy of the file with
everything else blanked out — every span is a real position.

At the wrapping stage (the same `AHC.Refine` pass that inserts
refinement checks) a contracted function becomes

    f = \x1..xn -> claim (pre x1..xn) "precondition of 'f' violated"
                     (let r = BODY x1..xn
                      in claim (post x1..xn r) "postcondition..." r)

`claim` forces its Boolean when the RESULT is demanded — the only
honest notion of "on entry" laziness allows. Nothing is checked for
a call whose result is never used; the result is let-shared, so the
postcondition inspects exactly the value the caller receives; and a
postcondition that mentions an argument the function itself never
forced will force it — contracts observe, and that is their one
semantic footprint. Purity pays a dividend here: Ada needs `'Old`
to see pre-call values through mutation, while a Haskell
postcondition just names the arguments — they cannot have changed.

Contracts on polymorphic functions work because everything rides
the dictionary machinery: `{-# POST maxOf \x y r -> r >= x #-}` on
`maxOf :: Ord a => ...` produces a contract with the same `Ord a`
context, and the wrapper threads the same dictionary parameters to
the body, the pre and the post. `--unchecked` strips every claim —
Ada's assertion policy, shared with ranges and `satisfying` — and
GHC ignores the pragmas entirely (a stderr warning), so a
contract-carrying program is still ordinary portable Haskell that
simply runs unchecked elsewhere. The conformance suite exploits
exactly that: a program whose contracts hold is byte-identical
under both compilers.

The story closes with the other half of Ada's policy: **what the
compiler can prove, the runtime need not check**. Before the
wrapper is built, each claim's body is evaluated once at compile
time by a fuel-bounded constant evaluator (`AHC.Discharge`) with
the function's parameters *opaque*. A claim that reduces to True
regardless of its arguments — `\x -> True`, but also
`2 + 2 == 4` and `even 4 && 10 > 3`, evaluated straight through
the dictionary machinery — is discharged: the claim vanishes from
the generated code, and a function whose pre AND post both
discharge gets no wrapper at all. A claim that reduces to False
can never hold, which earns a compile-time warning (the runtime
check stays, so a demanded call still fails with the standard
message). Everything else keeps its check. Opaqueness makes
unsoundness impossible by construction: an argument-dependent
predicate like `lo <= hi` gets stuck the moment it consumes an
opaque parameter, so the discharge can only ever be incomplete,
never wrong. `scripts/run_discharge.sh` pins all three behaviors
against the generated C.

### Both halves, on a whole program

`examples/cal/` (ahccal, a calendar utility) is this chapter's
worked tour: four refinement kinds on the values, Pre/Post
contracts on the functions, and no hand-written validation code
anywhere — every failure it can produce comes from a check the
compiler inserted. It is also where the reason the two halves are
*two* is easiest to feel: `type Day = Int in 1 .. 31` bounds one
value and therefore cannot rule out February 31st, because that
day's legality depends on the month and the year. Only
`{-# PRE mkDate \y m d -> d <= daysInMonth y m #-}` can say it.

Building it measured two things worth knowing. Refined type
synonyms work in constructor fields (`data Date = Date Year Month
Day` checks every construction site), which until then only inline
field refinements had pinned. And discharge does not fire for a
contract on a function whose signature carries refinements, even
when the claim is argument-free — the identical claim discharges on
an unrefined helper. That is incompleteness rather than
unsoundness, and it is the first measurement of the evaluator's
reach taken on a real program instead of a fragment.

---

## 13. The optimizer

### The rule: never change what a program does

An optimizer transforms code to be faster while provably changing
nothing observable. Under call-by-need "nothing observable" includes
**sharing** — if a computation would have run once, the optimized
program must not run it twice — and **strictness** — if a value
would never have been demanded, the optimized program must not
demand it (it might be `error`!). Every transform in
`src/ahc-optimizer.adb` was chosen to be *exactly* safe under those
two constraints:

- **Atom inlining**: `let x = v in body` where `v` is a variable,
  literal, or constructor reference. Atoms carry no computation, so
  substituting them duplicates no work. Anything bigger stays
  let-bound — `let x = expensive in x + x` is *never* inlined.
- **Beta-to-let**: `(\x -> body) arg` becomes `let x = arg in body`.
  This looks like a non-optimization until you remember a `let`
  binding *is* a thunk — so this is sharing-exact, and it exposes
  the let to the other transforms.
- **Dead-binding elimination**: an unused non-recursive `let`
  binding is an undemanded thunk; laziness says nobody can tell it
  existed.
- **Case-of-known-constructor**: `case Just e of Just x -> body`
  becomes `let x = e in body` — the match is decided at compile
  time. This collapses much of what the pattern-match compiler and
  dictionary machinery generate.
- **Default-only case elision**: `case e of _ -> body` is just
  `body`, because a wildcard demands nothing (chapter 8).
- **Used-once let inlining**: `let x = e in body` where `x` occurs
  exactly once in `body` and that occurrence is *not under a
  lambda* substitutes `e` at the use site. One occurrence means the
  thunk would have been forced at most once anyway, so sharing is
  exact; the under-a-lambda bar is load-bearing, because a lambda's
  body can run many times and each run would re-evaluate the moved
  expression. The win is twofold: the thunk allocation vanishes,
  and an expression moved into *scrutinee* position is evaluated
  directly instead of being built as a heap closure first — which
  is why this transform, added last, was measured as the largest
  single win (dictionary-heavy inner loops are full of used-once
  lets that the pattern-match compiler and elaborator generate).

The simplifier rebuilds expressions bottom-up (always fresh nodes —
the tree invariant, held by construction this time; used-once
inlining *moves* the right-hand side, which preserves it) and
repeats until nothing changes, with a hard cap of eight rounds as
the termination guarantee. It runs only in the build path — `ahc
core` still shows the honest desugarer output — and `--no-opt`
disables it. Measured effect (`scripts/run_bench.sh`, best-of-5
interleaved wall time, opt vs `--no-opt`): 2.10x on a strict fold,
1.91x on `Data.List.sort` over 30k elements, 1.28x on a 40k-entry
`Data.Map` build-and-fold, and ~1.0x on call-dominated (`fib`) and
bignum-primitive-dominated workloads, whose time is spent where the
simplifier doesn't reach. The strongest evidence it changes nothing
is that all 74 GHC-oracle conformance programs are byte-identical
with it on.

---

## 14. Testing

### The philosophy: don't grade your own homework

A compiler bug's worst form is *silently wrong output*. Tests the
compiler author writes have a blind spot: the author's
misunderstanding of Haskell goes into the test's expected output
too. AHC's answer, and the single most valuable methodology decision
of the project: **GHC is the oracle**. The conformance suite
(`tests/conformance/`, 74 programs pinned to Report sections)
stores as its expected output *whatever GHC 9.4.8 prints* for the
same source, and AHC must reproduce it **byte for byte** —
`scripts/run_conformance.sh --oracle` regenerates the expectations
from GHC.

Byte-for-byte sounds fanatical and is the point: it forced the
shortest-round-trip Double printer, the `showsPrec` parenthesization,
base's exact `permutations` ordering, floored division on negative
bignums. Every "close enough" would have hidden a divergence.

The discipline has a second half: what AHC *cannot* match goes into
`tests/conformance/EXCLUSIONS.md` **with a reason** — never a
weakened test. The exclusions file is therefore an honest,
always-current statement of the compiler's boundaries. (It has also
served as the project's to-do list: entries for pattern guards,
bignum, multi-module compilation, class defaults and `module M`
re-exports were all eventually implemented and struck off.)

When the suite was first built it immediately found five real bugs
in a compiler that already passed hundreds of its own tests —
record selectors that had never been implemented at all, the
shared-join-point evidence bug, the layout-lookahead bug, `(op) = e`
not parsing, Show escape handling. That week is the argument for
oracle testing in one sentence: *the compiler passed its own tests
and failed the truth.*

### The harnesses

| Harness | Question it answers |
|---|---|
| `tests/` (219 unit tests) | do individual stages do what their authors think, including *contract-violation tests* that assert bad inputs are rejected? |
| `scripts/run_golden.sh` | did any stage's output change unexpectedly? (pinned lex/layout/parse/core/check output; regenerate deliberately, review the diff) |
| `scripts/run_differential.sh` / `_types.sh` | do AHC and GHC agree on what *parses* and what *typechecks*? |
| `scripts/run_exec.sh` | do compiled programs print what they printed yesterday? |
| `scripts/run_conformance.sh` | do compiled programs print what **GHC** prints? |
| `scripts/run_examples.sh` | does the dogfood program (`examples/lisp`, a mini-Lisp interpreter - chapter 16) behave identically compiled by AHC and by GHC? |
| `scripts/run_separate.sh` | is per-module code generation deterministic and the object cache minimal? (no-change/comment rebuilds: zero objects; one-module edits: exactly one) |
| `scripts/run_bench.sh` | does the optimizer actually pay for itself? (five workloads in `tests/bench/`, each built with and without `--no-opt`, outputs verified identical, then timed — warmup plus interleaved best-of-5, so thermal drift and cache state hit both sides equally) |
| `scripts/run_fuzz.sh` | what do the hand-written tests miss? (`tests/fuzz/Gen.hs` generates seeded random well-typed programs from a menu pre-verified on both compilers; AHC-compiled output is byte-diffed against GHC per seed; divergences are saved and delta-debug-shrunk automatically; deep parallel campaigns via `run_fuzz_par.sh` — usage, triage, and the menu rule in `docs/fuzzer-guide.md`) |
| `scripts/run_repl.sh` | does the REPL behave? (pinned `tests/repl/*.in` transcripts through `ahc repl` — prompts, results, error-and-recovery, `:load` semantics — in a fixed scratch dir so diagnostic paths stay deterministic) |
| `scripts/run_discharge.sh` | did compile-time contract discharge do exactly what it may? (trivially-true claims absent from the generated C, argument-dependent claims present, provably-false claims warn and stay) |

The layering matters: goldens catch *change*, the oracle catches
*wrongness*, unit tests catch *stage-local* regressions, and the
differentials catch front-end drift on programs that never run.
Every milestone in the project ended with all of them green — that
rule ("each milestone independently shippable, full suite green")
was house law from the beginning.

### The fuzzer: don't hand-pick your homework either

Every hand-written test still embeds one author's imagination of
where bugs live, and the project's history says that imagination is
the weak link: each dogfood round (the Lisp interpreter, the
Data.Map port, the examples) found a real compiler bug the suite
had missed. `scripts/run_fuzz.sh` automates that discovery. A
seeded generator (`tests/fuzz/Gen.hs`, deterministic — the same
seed always yields the same program) emits random *well-typed*
Haskell 2010 programs; each is compiled by AHC and interpreted by
GHC, stdout byte-diffed. Two design rules make a divergence
meaningful. First, the generator's menu was pre-verified: every
construct and library function it can emit was pinned
byte-identical on both compilers before entering the menu, so
"AHC rejects a generated program" is a finding, not noise. Second,
known-undefined territory is avoided by construction — Int
arithmetic stays far from overflow (the Report leaves it
undefined; AHC promotes), text stays ASCII, and no partial
function is ever emitted (division is guarded, `maximum` gets a
consed head, recursion is structural). Divergences are saved to
`tests/fuzz-failures/` and shrunk automatically by delta debugging
(`scripts/shrink_fuzz.py`); the survivors of a shrink are small
enough to diagnose by hand, and each confirmed bug is then pinned
as a permanent conformance test. The very first campaign paid for
the harness: its third seed exposed a new corner of the
layout-vs-lookahead bug farm (chapter 16) that the entire
hand-written suite had never touched.

---

## 15. The standard library

### The insight that made it cheap

Once multi-module compilation existed, "standard library" stopped
meaning compiler work. A library module is a plain `.hs` file in
`lib/`, found by the driver's search path, compiled by AHC through
its own pipeline, namespaced by its own export list. The entire
compiler-side cost of the library milestones was: a search path,
about a dozen new primitives (input, exit, bit operations), and
dictionary bodies for `Monad Maybe` and the three `Functor`s.
Everything else — all of `Data.List`, `Control.Monad`, `Numeric` —
is Haskell.

The oracle methodology extends beautifully here: the same test
program resolves `import Data.List` to AHC's `lib/` when compiled
by AHC, and to *GHC's real base library* when run by the oracle. So
AHC's library implementations are verified against the canonical
ones, function by function — including behavioral fine points like
base's exact `permutations` production order and sort stability
(AHC's simple stable mergesort provably matches base's clever one
*because* stability makes the answer unique).

Notable corners: `Data.Ix` and `Text.Read` are full type classes
defined in library modules — proof the class machinery works from
userland; `Data.Ratio` builds exact fractions on the bignum layer
(and needed one new compiler rule: a library type may *shadow a
builtin* type constructor, the type-level mirror of shadowing
Prelude values, which is how `Rational` took its proper name over
the wired-in placeholder); infix constructors (`:%`, `:+`) exercised
a parser path dormant since phase one and taught `deriving Show`
infix layout;
`System.IO` gave AHC its first-ever input (`getLine`, `readFile`,
with the generated C `main` now capturing `argc`/`argv`; `isEOF`
arrived later, the day the mini-Lisp REPL needed to see end-of-file
coming - the first library addition driven by a real program rather
than by the Report; file HANDLES arrived later still: `Handle` is
an abstract source type over an index into a runtime registry of
`FILE` pointers — never a raw pointer, so a closed handle fails
cleanly — with `openFile`/`hClose` and the `h*` family as eight
integer-only prims, and `withFile`, `writeFile`, `appendFile`,
`hPrint` as ordinary Haskell on top); `Data.Map` is a weight-balanced search tree
(Adams' algorithm, the same family as GHC's containers) whose
observable behavior - toList order, Show format, union bias - is
oracled against the real containers library, written because the
interpreter's environments asked for it (and whose first compile
found two more compiler bugs - chapter 16); and
`Data.Ord`'s `Down` defines only `compare` - the other six `Ord`
methods come from the builtin-class default machinery (enabler E4),
which builds Report default methods against the instance's own
dictionary knot whenever a user instance omits them; an Ord
instance can even define only `<=`, with `compare` itself defaulting
through the superclass Eq dictionary.

---

## 16. War stories

Each of these cost real debugging time and produced a rule now
followed everywhere in the codebase.

**The finalized-temporary loop (Ada).** `for X of F(Y).Component`
iterates over a *copy* that Ada finalizes before the loop body runs
— the loop silently executes zero times. This silently dropped
signature contexts in the kinds stage. Rule: always bind a
function-call result to a named constant before `for ... of` over
its components.

**The shared-node evidence bug.** Chapter 2's tree invariant. The
match compiler shared one failure-continuation node between case
alternatives; the evidence rewriter (chapter 6) rewrote it once per
alternative; nested `Maybe` matches applied a dictionary twice and
crashed with "applied a non-function" — sixteen milestones after
the code was written. Found by the conformance suite on day one.
Rule: Core is a tree; every reference is a fresh node (`Fresh_Ref`),
including in hand-built dictionary code (`Fresh_Copy`).

**Layout vs. lookahead.** One-line nested `let ... in` failed *only
inside do-blocks*, and only near end-of-file — parser lookahead had
drained tokens past the point where the layout engine needed to
close a block. The fix leaned on a property of the layout algorithm
(within one line it never consults its stack) to let the parser
close blocks itself, and, at end-of-file, *relocate* an
already-queued virtual brace. Rule: when two streaming algorithms
are mutually recursive, buffering in one is a bug farm in the other.
The rule proved itself again on the differential fuzzer's third
seed (chapter 14): the same lookahead, drained through a one-line
`let` inside an *explicit-brace* case alternative, left the let's
implicit context open and the case's real `}` unmatched. That fix
was structural rather than compensating: the bind-vs-expression
scan now stops at the first token a pattern cannot contain
(`let`, `case`, `if`, lambda, ...), so lookahead can no longer
open a layout context at all — the answer is known before the
hazard is reachable.

**The six-hour wedge (and what a fuzzer owes its harness).** The
first deep fuzz campaign — 10,000 seeds, budgeted at an hour — was
found six hours later with three GHC *oracle* processes pegged at
100% CPU. Nothing was broken: the harness was patiently waiting on
programs that would never finish. The generator's totality
discipline guaranteed structural recursion, so every program
*terminated* — but it emitted the recursive call inline at each use
site, so a body containing `min (f xs) (f xs)` costs 2^n, and one
seed managed 3^n. A second seed found the other flavour: a Double
range `[v, v+1.5 .. v+4.5]` where `v ≈ 1.16e29`, at which
magnitude the step falls below one ULP, `v + 1.5 == v`, and the
range is an infinite list. Both fixes were structural — let-bind
the recursive call so k uses share one thunk, clamp any construct
whose cost depends on a *value's* magnitude — but the important
one was in the harness: every external step now runs under a time
limit. Rule: **termination is not tractability**, and a test
harness that can block forever on its own input has no business
being trusted to run unattended. Give every subprocess a deadline
before you give it a workload.

**The stolen body.** The REPL's first real session typed
`import Data.Map` then `nub "abracadabra"` and died on a missing
global named `filter`. The wired Prelude attaches its bodies by
looking names up in the *live* flat environment — which
Data.Map's own `filter` had overwritten by the time the
attachment ran, so the wired variable that every other module's
references pointed at was left without a body. Nothing
hand-written had ever imported a shadowing module and exercised
the shadowed name's Prelude version in the same program. Fixing
it (resolve wired names through the immutable Base snapshot)
immediately exposed a sibling: `Prelude.filter` with a local
`filter` in scope resolved to the LOCAL one, because the
implicit-Prelude qualified path also consulted the mutable
own-module map first. Rule: a name-keyed table over a mutable
namespace is a time bomb — attach identities to snapshots taken
at the moment the identity was minted, never to whatever the
name means later.

**The stack-overflow-after-success.** `print (sum [1 .. 1000000])`
printed the correct answer and *then* segfaulted — a
guard-page fault inside `malloc`, from a million-deep evaluation
recursion unwinding into Boehm bookkeeping. Diagnosed with `lldb`
after a wrong first theory; fixed with a 512MB link-time stack.
Rule: in a graph reducer, evaluation depth is program-data-sized;
size the stack for data, not code.

**The worktree disaster.** To A/B-test against an older commit, an
`alr build` was run in a *git worktree of the same crate* — and
Alire's shared build cache resolved both checkouts to the same
output paths, overwriting the main `bin/ahc` **while the test suite
was executing it**. Processes wedged in uninterruptible kernel
state; the damage cascaded until every new process exec on the
machine hung, and only a reboot cleared it. Rules: never build a
worktree of an open Alire crate; stale `alire/*.lock` files after
killed builds must be deleted; and attribution tests belong in a
*copied* directory, not a cache-sharing worktree.

**Scripted-edit no-ops.** Twice, a Python-driven bulk edit silently
did nothing because its search text had drifted (`MkT` vs `T`; a
README paragraph edited in a failed `&&` chain and then "verified"
by an assertion-free script). One of them shipped a stale README in
a tagged commit. Rule: every scripted replace asserts its anchor
exists, and every scripted edit is verified by grep afterwards.

**Shell quoting in commit messages.** A backtick inside a
double-quoted `git commit -m` string was command-substituted by
zsh, mangling a pushed commit message (left as-is; history is not
rewritten for cosmetics). Rule: commit messages go through
`git commit -F file`.

**The constraint that nobody would claim.** Building `Data.Map`
(the interpreter's second gift: its environments wanted a real map)
produced "ambiguous type variable" on code as ordinary as a
multi-equation `where`-helper calling `insert`. The chain took
three reproductions to isolate: a *single*-equation helper worked;
a *multi*-equation one failed. Why? Multi-equation functions go
through the match compiler, which builds join points - inner `let`
bindings - and a class constraint born inside one is tagged as
*owned* by that join binder. When the constraint floated out to
become part of the helper's inferred type, the generalizer's
bookkeeping only attached constraints to their owner - and the
join point wasn't it. The constraint joined the helper's printed
type correctly but its *evidence* was never wired, and the residual
was reported as ambiguous. Invisible for twenty-odd milestones
because top-level functions all carry signatures, whose given-based
discharge ignores ownership entirely - only signatureless local
helpers (which Haskell 2010 can't even annotate, lacking scoped
type variables) walk the broken path, and the Prelude had quietly
avoided it by lifting its helpers to top level. Fix: when a binding
group closes, its unsolved constraints re-home to the enclosing
binding. Rule: evidence bookkeeping must follow *lexical*
containment, not binder identity - and a library port is a better
typechecker test than a typechecker test.

**The imported synonym that read the wrong street's house numbers.**
The first *program* written against the finished compiler - a
mini-Lisp interpreter in `examples/lisp`, built precisely to shake
out what the test suite couldn't - fell over on its very first
compile: `type Env = [(String, Value)]`, imported across a module
boundary, produced "cyclic type synonym". The cause: a synonym was
recorded as a pointer into the *defining module's* syntax arena
(chapter 4), and an importing module happily dereferenced that
pointer into its *own* arena - like following house numbers from a
different street. Whatever type expression happened to live at that
id was expanded instead, sometimes forever (hence "cyclic"). No
conformance test had ever imported a user synonym from another
module; the wired-in `String` dodged the path because it caches a
converted Core rhs. The fix follows `String`'s precedent: at the
declaration, the kind checker now converts every synonym's rhs to
Core once (its parameters becoming real Core type variables) and
expansion substitutes into that cached form - imported synonyms
never touch the foreign arena again. Rule, and the reason the
example exists: **arena ids are meaningless outside their arena**,
and only a real program exercises the seams between features that
the per-feature tests each cover alone.

---

## 17. Glossary

**Arena** — tree storage as an array of nodes addressed by integer
ids instead of pointers. *Chapter 2.*

**Bignum / limb** — arbitrary-precision integer; a limb is one
32-bit digit of one. *Chapter 10.*

**Binding group** — a set of mutually recursive definitions that
must be type-inferred together. *Chapter 5.*

**CAF** — constant applicative form; a top-level value (not
function), compiled to an initialized C global. *Chapter 9.*

**Call-by-need** — evaluate only when demanded, remember the result.
Haskell's evaluation strategy. *Chapter 8.*

**Canonical form** — the invariant that every value has exactly one
representation (small integers are always `INT` nodes, never
one-limb bignums). *Chapter 10.*

**Closure / closure conversion** — a function value packaged with
the variables it captured; the transformation that lifts nested
functions to top level with explicit environments. *Chapter 9.*

**Constraint** — the `Show a =>` part of a type: a requirement that
a dictionary exists. *Chapter 6.*

**Contract (Ada)** — a machine-checked pre/postcondition or
invariant. *Chapter 2.*

**Core** — the compiler's eight-construct internal language.
*Chapters 1, 7.*

**Defaulting** — the Report 4.3.4 rule resolving ambiguous numeric
types to `Integer` then `Double`. *Chapter 5.*

**Desugaring** — translating surface conveniences into Core.
*Chapter 7.*

**Dictionary** — the record of functions that implements a class
constraint at a specific type; passed as a hidden argument.
*Chapter 6.*

**Erasure** — treating refined types as their base types during
unification. *Chapter 12.*

**Evidence** — the dictionary argument inserted at a use site of an
overloaded function. *Chapter 6.*

**Fixity** — an operator's precedence and associativity; resolved in
a separate stage because operators are user-definable. *Chapter 3.*

**Generalization / instantiation** — turning leftover unknowns into
"for all" types at bindings; stamping fresh copies at uses.
*Chapter 5.*

**Graph reduction** — evaluation by rewriting a heap of nodes,
updating each thunk with its value. *Chapter 8.*

**Hindley-Milner / Algorithm W** — the type system and inference
algorithm: unknowns + unification + generalization. *Chapter 5.*

**Indirection / black hole** — "value is over there" node written
when a thunk finishes; "in progress" marker that catches
self-referential loops. *Chapter 8.*

**Interning** — storing each distinct name once and using integer
ids thereafter. *Chapter 3.*

**Join point** — a let-bound continuation shared by several failure
paths in compiled pattern matches, to avoid code duplication.
*Chapter 7.*

**Kind** — the type of a type; `*` is a complete type, `* -> *`
awaits an argument. *Chapter 5.*

**Layout** — Haskell's indentation-to-braces algorithm (Report
10.3). *Chapter 3.*

**Metavariable** — a type unknown, filled in by unification.
*Chapter 5.*

**Monomorphism restriction** — no-argument bindings without
signatures are not generalized (Report 4.5.5). *Chapter 5.*

**Occurs check** — the refusal to solve `?a = [?a]`, preventing
infinite types; a precondition in AHC. *Chapter 5.*

**Oracle** — an external source of truth for tests; here, GHC.
*Chapter 14.*

**Refinement** — a value constraint attached to a type: range,
predicate, or modulus. *Chapter 12.*

**Renaming** — resolving every name to a unique integer id.
*Chapter 4.*

**ShowS** — the `String -> String` prepend-function idiom for
efficient string building. *Chapter 11.*

**Thunk** — an unevaluated computation stored as a heap node.
*Chapter 8.*

**Unification** — the solver that makes two types equal by filling
in metavariables, or fails. *Chapter 5.*

---

## 18. Source map

Where to look for anything, in pipeline order:

| File | What lives there |
|---|---|
| `src/ahc.ads` | root package, version |
| `src/ahc-source_text.*` | file loading, offsets |
| `src/ahc-names.*` | the intern table |
| `src/ahc-diagnostics.*` | errors, spans, the diagnostic bag |
| `src/ahc-tokens.*` / `ahc-lexer.*` | tokens and the lexer |
| `src/ahc-layout.*` | Report 10.3, the balanced-braces invariant |
| `src/ahc-syntax.*` (+`-printer`) | the surface tree arena |
| `src/ahc-parser.adb` | recursive-descent parser, contextual keywords |
| `src/ahc-fixity.*` | operator-chain resolution, `Chain_Free` |
| `src/ahc-rename.*` | unique ids, scopes, module visibility |
| `src/ahc-modules.*` | the module interface registry |
| `src/ahc-kinds.*` | kind inference, surface→Core type conversion, refinement validation |
| `src/ahc-desugar.adb` | all of chapter 7, incl. the match compiler and selector generation |
| `src/ahc-core.*` (+`-printer`) | Core arena, refinement table, `Mk_Dict` |
| `src/ahc-typechecker.adb` | Algorithm W, classes, evidence |
| `src/ahc-elaborate.adb` | instance dictionaries, default-method knots |
| `src/ahc-refine.adb` | refinement wrappers, constructor-site sweep |
| `src/ahc-optimizer.*` | the simplifier |
| `src/ahc-builtins.*` | wired-in types, classes, primitive signatures |
| `src/ahc-prelude_core.*` | hand-built dictionary bodies, prim bindings, deriving Show |
| `src/ahc-codegen.adb` | closure conversion, C emission |
| `src/ahc_main.adb` | the driver: module discovery, pipeline order, CLI |
| `runtime/ahc_rts.{h,c}` | nodes, eval, GC hookup, all primitives, bignum |
| `prelude/Prelude.hs` | the self-compiled Prelude |
| `lib/**` | the standard library (chapter 15) |
| `tests/`, `scripts/` | the eleven harnesses (chapter 14) |
| `docs/refinement-types-design-note.md` | the extension's original design + as-built record |
| `docs/stdlib-plan.md` | the library plan + status |
| `CHANGES.md` | the release history |

*End of manual.*
