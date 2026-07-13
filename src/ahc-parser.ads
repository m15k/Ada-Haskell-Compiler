--  Recursive descent parser: layout-processed token stream to untyped
--  AST (Report chapters 3-5 grammar, Haskell 2010).
--
--  The parser drives AHC.Layout and is the only component allowed to
--  invoke its parse-error(t) rule: whenever a declaration block or an
--  expression cannot continue and the innermost layout context is
--  implicit, the parser asks the stream to close it and retries.
--
--  Errors accumulate in the bag; recovery is per declaration (skip to
--  the next semicolon or block end at the same depth), so one bad
--  declaration does not hide the rest of the module.

with AHC.Diagnostics;
with AHC.Names;
with AHC.Syntax;
with AHC.Tokens;

package AHC.Parser is

   procedure Parse_Module
     (Raw   : Tokens.Token_Vectors.Vector;
      Table : in out Names.Name_Table;
      Bag   : in out Diagnostics.Diagnostic_Bag;
      Arena : in out Syntax.Module_Arena)
     with Pre => not Raw.Is_Empty
                 and then Raw.Last_Element.Kind = Tokens.End_Of_File;

   use type Tokens.Token_Kind;

end AHC.Parser;
