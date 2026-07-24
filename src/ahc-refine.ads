--  Refinement-types extension, stage 1: runtime range checks
--  (docs/refinement-types-design-note.md).
--
--  Every binder with a declared signature (top-level sigs and `::`
--  expression annotations, via AHC.Kinds' Sig map) whose type spine
--  mentions a refined TCon gets an eta-wrapper:
--
--    f :: Int in 0 .. 9 -> Int in 0 .. 5
--    f = RHS
--  becomes
--    f = let $rv = RHS
--        in \d1..dm -> \a1..ak ->
--             check LO' HI' ($rv d1..dm (check LO HI a1) .. ak)
--
--  where m is the scheme's context length (the dictionary lambdas the
--  typechecker added) and `check` is the runtime primitive
--  ahc_prim_check_range, strict in the value but reached lazily: the
--  check fires when the refined value is first demanded, matching
--  call-by-need semantics. Recursive calls go through the wrapper, so
--  they are checked too.
--
--  Enforcement is at declared boundaries of the wrapped binder only;
--  refinements nested under type constructors ([Int in 0 .. 9]) and
--  on class-method signatures typecheck (erased) but are not checked
--  at run time in stage 1.
--
--  With Checks_Enabled False (ahc emit --unchecked, the release
--  policy from the design note), the pass is a no-op and refined
--  programs run at full speed on the unchecked base types.

with AHC.Contracts;
with AHC.Diagnostics;
with AHC.Core;
with AHC.Kinds;
with AHC.Names;
with AHC.Prelude_Core;

package AHC.Refine is

   --  Contracts: PRE/POST claim wrapping per
   --  docs/contracts-design-note.md; stripped with Checks_Enabled.
   --  Bag receives contract-discharge warnings (a predicate that
   --  can never hold). Claims proved True at compile time
   --  (AHC.Discharge) are dropped before the wrapper is built.
   procedure Insert_Checks
     (Table          : in out Names.Name_Table;
      M              : in out Core.Core_Module;
      Sigs           : Kinds.Sig_Maps.Map;
      Prims          : in out Prelude_Core.Prim_Maps.Map;
      Bag            : in out Diagnostics.Diagnostic_Bag;
      Checks_Enabled : Boolean := True;
      Contracts      : AHC.Contracts.Contract_Maps.Map :=
        AHC.Contracts.Contract_Maps.Empty_Map);

end AHC.Refine;
