with Ada.Containers.Hashed_Maps;
with Ada.Containers.Vectors;

with AHC.Core;
with AHC.Diagnostics;
with AHC.Lexer;
with AHC.Names;
with AHC.Rename;
with AHC.Source_Text;
with AHC.Syntax;

--  Function contracts (docs/contracts-design-note.md): Ada's
--  Pre/Post as pragmas.
--
--      {-# PRE  clamp \lo hi x -> lo <= hi             #-}
--      {-# POST clamp \lo hi x r -> lo <= r && r <= hi #-}
--
--  Collect turns each recognized pragma into an ORDINARY top-level
--  binding `$pre$clamp = <lambda>` parsed into the module's own
--  arena - so the rename/typecheck/desugar pipeline handles
--  contracts with no special cases. The driver later derives the
--  binding's signature from the contracted function's own
--  (tyvars + context + argument spine -> Bool; POST inserts the
--  result type), and AHC.Refine wraps the function per the design
--  note. GHC sees only an ignorable pragma warning, so
--  contract-carrying source stays oracle-portable.
package AHC.Contracts is

   type Contract_Kind is (Pre_C, Post_C);

   type Contract_Decl is record
      Kind      : Contract_Kind := Pre_C;
      Fn_Name   : Names.Name_Id := Names.No_Name;
      Bind_Name : Names.Name_Id := Names.No_Name;  --  $pre$f / $post$f
      Span      : Diagnostics.Source_Span;
   end record;

   package Contract_Vectors is new Ada.Containers.Vectors
     (Positive, Contract_Decl);

   --  Parse this module's PRE/POST pragmas into Arena as hidden
   --  top-level bindings; append what was declared to Out_C.
   --  Unknown pragma words are ignored (they stay comments).
   procedure Collect
     (Text  : Source_Text.Source;
      Spans : Lexer.Span_Vectors.Vector;
      Table : in out Names.Name_Table;
      Bag   : in out Diagnostics.Diagnostic_Bag;
      Arena : in out Syntax.Module_Arena;
      Out_C : in out Contract_Vectors.Vector);

   --  After the frontend: contracted function -> its contract
   --  binders, consumed by AHC.Refine.
   type Contract_Binds is record
      Pre_V, Post_V : Core.Var_Id := Core.No_Var;
   end record;

   package Contract_Maps is new Ada.Containers.Hashed_Maps
     (Core.Real_Var_Id, Contract_Binds,
      Hash => Rename.Var_Hash, Equivalent_Keys => Core."=");

end AHC.Contracts;
