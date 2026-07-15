--  Hindley-Milner type inference over Core (Algorithm W flavor) with
--  type classes: PRD Epic 2's centerpiece.
--
--  Unification variables are union-find cells in the Infer_State,
--  mutated only through `in out` parameters (PRD 4.2). The PRD's
--  occurs-check promise is the *precondition* of Bind_Meta - the only
--  operation that could create a cyclic type - so validation builds
--  check it exactly once per binding; Unify tests it first and turns
--  a violation into a Type_Occurs_Check diagnostic, so the contract
--  can only fire on a compiler bug, never on user code.
--
--  Binding groups are formed by Tarjan SCC over the top-level bindings'
--  free variables and checked in topological order; let-polymorphism
--  uses Remy-style levels; the monomorphism restriction (Report 4.5.5)
--  and standard defaulting (Report 4.3.4) are implemented. Wanted
--  constraints reduce to head-normal form against the instance table
--  (superclass closure for givens, bounded recursion for instance
--  contexts).

with AHC.Builtins;
with AHC.Core;
with AHC.Diagnostics;
with AHC.Kinds;
with AHC.Names;

package AHC.Typechecker is

   --  True when every top-level binder has a scheme and every local
   --  binder a meta-free type: the PRD's "every Core node has a type".
   function Fully_Typed (M : Core.Core_Module) return Boolean;

   procedure Check_Module
     (Table : in out Names.Name_Table;
      Bag   : in out Diagnostics.Diagnostic_Bag;
      M     : in out Core.Core_Module;
      Env   : in out Builtins.Global_Env;
      Sigs  : Kinds.Sig_Maps.Map)
     with Post => Bag.Has_Errors or else Fully_Typed (M);

end AHC.Typechecker;
