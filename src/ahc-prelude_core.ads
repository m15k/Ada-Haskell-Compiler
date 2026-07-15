--  Runtime bodies for the wired-in Prelude signature (Phase 3).
--
--  Phase 4 will compile real Prelude source; until then this package
--  hand-builds Core for the value vocabulary (map, foldr, (++), ...)
--  and constructs dictionary bodies for every builtin or derived
--  instance that AHC.Elaborate did not already materialize, using a
--  small set of runtime primitives:
--
--    - structural equality/comparison prims cover Eq and Ord for all
--      first-order values (including user ADTs, hence derived Eq/Ord),
--    - Int/Integer arithmetic and show prims cover Num/Show/Enum at
--      the defaultable types,
--    - IO prims cover Monad IO; the list monad is built in Core.
--
--  Methods with no sensible runtime yet become error thunks, so using
--  them fails loudly at run time, never silently.
--
--  The prim variables minted here are mapped to C symbols by
--  AHC.CodeGen via the Prim_Map.

with Ada.Containers.Hashed_Maps;

with AHC.Builtins;
with AHC.Core;
with AHC.Names;
with AHC.Rename;

package AHC.Prelude_Core is

   --  Prim var -> C runtime symbol.
   package Prim_Maps is new Ada.Containers.Hashed_Maps
     (Core.Real_Var_Id, Names.Name_Id,
      Hash => Rename.Var_Hash, Equivalent_Keys => Core."=",
      "=" => Names."=");

   procedure Install_Bodies
     (Table : in out Names.Name_Table;
      M     : in out Core.Core_Module;
      Env   : in out Builtins.Global_Env;
      Prims : in out Prim_Maps.Map);

end AHC.Prelude_Core;
