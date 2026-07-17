--  Core-to-Core simplification (the PRD's AHC.Optimizer).
--
--  Every transform preserves call-by-need semantics exactly:
--
--    - atom inlining: `let x = v in b` for v a variable, literal or
--      constructor reference - atoms carry no work, so no sharing is
--      lost; each occurrence gets a fresh node (Core stays a tree)
--    - beta-to-let: `(\x -> b) e` becomes `let x = e in b` - a let
--      binding IS a thunk, so this is sharing-exact
--    - dead bindings: an unused non-recursive binding is an unforced
--      thunk, discardable in pure Core
--    - case-of-known-constructor / literal: the scrutinee's
--      constructor is syntactically visible, so the match decides
--      now; field thunks bind by let, keeping laziness
--    - default-only case: `case e of _ -> b` is b (Haskell wildcard
--      matches do not force the scrutinee)
--
--  The simplifier rebuilds expressions bottom-up (fresh nodes
--  always) and iterates to a fixpoint under a round cap; Rounds
--  reports how many passes ran. It runs on the merged program right
--  before code generation and is off for `ahc core` dumps, which
--  document the desugarer.

with AHC.Core;

package AHC.Optimizer is

   Max_Rounds : constant := 8;

   procedure Optimize
     (M : in out Core.Core_Module; Rounds : out Natural)
     with Post => Rounds <= Max_Rounds;

end AHC.Optimizer;
