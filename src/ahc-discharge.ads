--  Compile-time contract discharge: a fuel-bounded constant
--  evaluator over Core. A contract predicate whose body reduces to
--  True with its parameters OPAQUE holds on every call, so its
--  runtime claim can be dropped; one that reduces to False can
--  never hold, which is worth a compile-time warning. Anything the
--  evaluator cannot decide keeps its runtime check - opaque values
--  poison every path that consumes them, so an argument-dependent
--  predicate can never be discharged by mistake.

with AHC.Core;
with AHC.Names;
with AHC.Prelude_Core;

package AHC.Discharge is

   type Verdict is (Proved_True, Proved_False, Unknown);

   --  Evaluate the body of the contract predicate bound to Pred
   --  (a $pre$f / $post$f top-level), with every leading lambda
   --  parameter - dictionary and value alike - opaque.
   function Try_Claim
     (Table : Names.Name_Table;
      M     : Core.Core_Module;
      Prims : Prelude_Core.Prim_Maps.Map;
      Pred  : Core.Real_Var_Id) return Verdict;

end AHC.Discharge;
