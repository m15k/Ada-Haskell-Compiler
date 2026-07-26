# microhm - the third dogfood program

A miniature Hindley-Milner type inferencer: the compiler's most
intricate machinery (its typechecker) in ~350-line miniature,
compiled by that machinery. Reads lambda-calculus terms, one per
line, and prints principal types:

    $ ./microhm tests/basics.in
    \f g x. f (g x)   :: (a -> b) -> (c -> a) -> c -> b
    ...

The language: `\x y. e`, application, `let x = e in e` (with
LET-POLYMORPHISM - `let id = \x. x in id id` generalizes where
`\f. if f true then f 1 else f 2` correctly cannot),
`if/then/else`, integers, `true`/`false`. Errors - occurs check,
mismatches, unbound variables, parse errors with column offsets -
print in place of the type.

Two things make it more than an exercise:

1. **It is the STUDY-GUIDE's Station 6 companion**: Algorithm W,
   unification, substitution composition, generalization and
   instantiation, in a page - read this before the real
   1,700-line typechecker and the big one reads like a scaled-up
   acquaintance.
2. **The unifier states the real typechecker's obligations as
   contracts.** The PRD's marquee verification claims are the Ada
   Bind_Meta occurs-check precondition; microhm's `bindVar`
   carries the same obligation as a `{-# PRE #-}` pragma, checked
   at demand time on every unification in the test suite (and the
   fresh-supply monotonicity rides along as a POST). GHC ignores
   the pragmas, so the program stays byte-identical under both
   compilers - which the goldens enforce.

Like every example: identical behavior compiled by AHC or
interpreted by GHC; goldens are GHC's output.
