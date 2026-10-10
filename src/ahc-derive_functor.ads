--  Stock DeriveFunctor, DeriveFoldable and DeriveTraversable (M148).
--
--  The renamer mints such a derived instance source-like (From_Source,
--  Stock_Derive set, head = the data type over all but its last
--  parameter). This pass, run after desugaring and before type
--  checking, synthesizes its one defining method - fmap, foldr or
--  traverse - as ordinary Core over the constructors' field types,
--  following GHC's documented algorithm (User's Guide, "Deriving
--  Functor instances"). The typechecker then checks that code against
--  the method's scheme, and AHC.Elaborate builds the dictionary as for
--  any source instance: superclasses, Foldable's other methods from
--  the class defaults, traverse's Applicative dictionary parameter.

with AHC.Builtins;
with AHC.Core;
with AHC.Diagnostics;
with AHC.Names;

package AHC.Derive_Functor is

   procedure Synthesize
     (Table : in out Names.Name_Table;
      Bag   : in out Diagnostics.Diagnostic_Bag;
      M     : in out Core.Core_Module;
      Env   : Builtins.Global_Env);

end AHC.Derive_Functor;
