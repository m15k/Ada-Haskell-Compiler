--  Kind inference and surface-type conversion (Phase 2, Report 4.6).
--
--  Runs after renaming. Assigns kinds to user type constructors and
--  class variables (metas defaulting to * per Report 4.6), and converts
--  every user-written type into the Core type arena, expanding
--  synonyms, checking saturation and kind correctness, and producing:
--
--    - Con_Scheme for every user data constructor,
--    - schemes for record-field selector globals,
--    - Method_Scheme + selector Var_Scheme for user class methods,
--    - Head_Vars/Context for user instances,
--    - a Var -> Scheme map for every user type signature.
--
--  After this pass the typechecker never sees surface types.

with Ada.Containers.Hashed_Maps;
with Ada.Containers.Vectors;

with AHC.Builtins;
with AHC.Core;
with AHC.Diagnostics;
with AHC.Names;
with AHC.Rename;
with AHC.Syntax;

package AHC.Kinds is

   package Sig_Maps is new Ada.Containers.Hashed_Maps
     (Core.Real_Var_Id, Core.Scheme_Id,
      Hash => Rename.Var_Hash, Equivalent_Keys => Core."=",
      "=" => Core."=");

   --  Converted schemes for expression/pattern type annotations,
   --  keyed by the surface type node.
   function Type_Hash
     (T : Syntax.Type_Id) return Ada.Containers.Hash_Type
   is (Ada.Containers.Hash_Type (T));

   package Anno_Maps is new Ada.Containers.Hashed_Maps
     (Syntax.Type_Id, Core.Scheme_Id,
      Hash => Type_Hash, Equivalent_Keys => Syntax."=", "=" => Core."=");

   --  Predicate refinements (stage 2): kind checking mints the hidden
   --  binder `$pred :: BASE -> Bool` (its signature goes into Sigs)
   --  but cannot desugar the predicate expression, so each pending
   --  pair is turned into a real top-level binding by the desugarer -
   --  predicates are then typechecked and dictionary-elaborated like
   --  any other Haskell.
   type Pending_Pred is record
      Binder : Core.Real_Var_Id;
      Expr   : Syntax.Expr_Id;
   end record;

   package Pred_Vectors is new Ada.Containers.Vectors
     (Positive, Pending_Pred);

   procedure Check_Module
     (Arena : Syntax.Module_Arena;
      Res   : Rename.Resolutions;
      Table : in out Names.Name_Table;
      Bag   : in out Diagnostics.Diagnostic_Bag;
      M     : in out Core.Core_Module;
      Env   : in out Builtins.Global_Env;
      Sigs  : in out Sig_Maps.Map;
      Annos : in out Anno_Maps.Map;
      Preds : in out Pred_Vectors.Vector);

end AHC.Kinds;
