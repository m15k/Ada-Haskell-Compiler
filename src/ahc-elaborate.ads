--  Dictionary elaboration (Phase 2, M15): materialize the dictionary
--  value for every user instance declaration as a top-level Core
--  binding
--
--    $dCT = \d1 .. dn ->            -- one param per context constraint
--             MkDict$C sup1 .. supk impl1 .. implm
--
--  Superclass dictionaries are solved against the instance table with
--  the context parameters as given evidence; method implementations
--  come from the instance's desugared Method_Binds (falling back to
--  the class default, which is also lifted to a top-level binding).
--  Dictionary construction goes through Core.Mk_Dict, whose
--  precondition pins the field count: the PRD dictionary-arity
--  contract.
--
--  Call-site dictionary application (rewriting constrained variable
--  occurrences into selector-and-dictionary applications) is the entry
--  task of Phase 3's code generation and is not performed here; type
--  checking is complete without it.

with AHC.Builtins;
with AHC.Core;
with AHC.Diagnostics;
with AHC.Names;

package AHC.Elaborate is

   --  Every user instance with method bindings has its dictionary
   --  global bound at top level.
   function All_Dictionaries_Built (M : Core.Core_Module) return Boolean;

   procedure Elaborate_Dictionaries
     (Table : in out Names.Name_Table;
      Bag   : in out Diagnostics.Diagnostic_Bag;
      M     : in out Core.Core_Module;
      Env   : in out Builtins.Global_Env;
      Inst_Origins : Diagnostics.Origin_Vectors.Vector :=
        Diagnostics.Origin_Vectors.Empty_Vector)
     with Post => Bag.Has_Errors or else All_Dictionaries_Built (M);

end AHC.Elaborate;
