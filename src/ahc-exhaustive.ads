with Ada.Containers.Vectors;

with AHC.Builtins;
with AHC.Core;
with AHC.Diagnostics;
with AHC.Names;
with AHC.Rename;
with AHC.Syntax;

--  Maranget-style usefulness analysis over one match group (a
--  function's equations or a case expression's alternatives),
--  producing warnings: non-exhaustive patterns, and redundant
--  clauses. Purely advisory - never errors, never changes code.
package AHC.Exhaustive is

   --  One clause: its column patterns, whether it matches whenever
   --  its patterns do (unguarded, or guards include an
   --  otherwise/True alternative), and its span for reporting.
   type Row_Rec is record
      Pats  : Syntax.Pat_Id_Vectors.Vector;
      Total : Boolean := True;
      Span  : Diagnostics.Source_Span := (Start => 1, Stop => 1);
   end record;

   package Row_Vectors is new Ada.Containers.Vectors
     (Positive, Row_Rec);

   procedure Check_Match
     (Arena : Syntax.Module_Arena;
      Res   : Rename.Resolutions;
      Table : in out Names.Name_Table;
      Bag   : in out Diagnostics.Diagnostic_Bag;
      M     : Core.Core_Module;
      Env   : Builtins.Global_Env;
      Rows  : Row_Vectors.Vector;
      What  : String;
      Span  : Diagnostics.Source_Span);

end AHC.Exhaustive;
