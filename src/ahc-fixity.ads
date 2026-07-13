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

with AHC.Diagnostics;
with AHC.Names;
with AHC.Syntax;

package AHC.Fixity is

   function Chain_Free (Arena : Syntax.Module_Arena) return Boolean;

   procedure Resolve_Module
     (Arena : in out Syntax.Module_Arena;
      Table : in out Names.Name_Table;
      Bag   : in out Diagnostics.Diagnostic_Bag)
     with Post => Chain_Free (Arena);

end AHC.Fixity;
