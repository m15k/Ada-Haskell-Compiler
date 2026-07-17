--  Operator-chain resolution (Report 10.6). The parser leaves operator
--  applications as flat Op_Chain_E / Con_Chain_P nodes because fixity
--  declarations may appear after uses anywhere in the same scope; this
--  pass builds scoped fixity environments (module top level, each
--  let/where/class/instance block) and rewrites every chain into nested
--  applications, diagnosing same-precedence ambiguity ("a == b == c")
--  and illegal prefix-minus mixes ("a ^ -b").
--
--  Base environment: the Haskell 2010 Prelude fixities (imports are not
--  resolved in Phase 1); unknown operators default to infixl 9.
--  Qualified operators resolve by their unqualified name.
--
--  The postcondition delivers the PRD promise: no flat chain survives
--  into later phases.

with Ada.Containers.Hashed_Maps;

with AHC.Diagnostics;
with AHC.Names;
with AHC.Syntax;

package AHC.Fixity is

   function Chain_Free (Arena : Syntax.Module_Arena) return Boolean;

   type Fixity_Info is record
      Assoc : Syntax.Assoc_Kind := Syntax.Assoc_Left;
      Prec  : Natural := 9;
   end record;

   function Name_Hash
     (N : Names.Name_Id) return Ada.Containers.Hash_Type
   is (Ada.Containers.Hash_Type (N));

   package Fixity_Maps is new Ada.Containers.Hashed_Maps
     (Key_Type        => Names.Name_Id,
      Element_Type    => Fixity_Info,
      Hash            => Name_Hash,
      Equivalent_Keys => Names."=");

   --  Base seeds the outermost scope beneath the Prelude defaults
   --  (fixities of imported operators); Tops receives this module's
   --  top-level fixity declarations for the module registry.
   procedure Resolve_Module
     (Arena : in out Syntax.Module_Arena;
      Table : in out Names.Name_Table;
      Bag   : in out Diagnostics.Diagnostic_Bag;
      Base  : Fixity_Maps.Map := Fixity_Maps.Empty_Map;
      Tops  : access Fixity_Maps.Map := null)
     with Post => Bag.Has_Errors or else Chain_Free (Arena);
   --  Error recovery can orphan chain nodes, hence the escape hatch;
   --  on a clean parse no flat chain survives.

end AHC.Fixity;
