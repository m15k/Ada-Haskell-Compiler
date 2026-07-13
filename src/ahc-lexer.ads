--  Character scanner: source text to raw token stream (Report 2.2-2.6).
--
--  Produces no layout-virtual tokens; AHC.Layout inserts those. Every
--  token carries its line, its tab-aware column, and a First_On_Line
--  marker (comments and whitespace ignored), which is exactly the input
--  the Report 10.3 layout algorithm needs.
--
--  Lexical errors are reported into the bag and yield an Error_Token;
--  scanning resumes at the next character, so one bad character cannot
--  hide the rest of the file.

with Ada.Containers;

with AHC.Diagnostics;
with AHC.Names;
with AHC.Source_Text;
with AHC.Tokens;

package AHC.Lexer is

   use type Ada.Containers.Count_Type;
   use type Tokens.Token_Kind;

   procedure Scan
     (Text   : Source_Text.Source;
      Table  : in out Names.Name_Table;
      Bag    : in out Diagnostics.Diagnostic_Bag;
      Result : out Tokens.Token_Vectors.Vector)
     with Post => Result.Length >= 1
                  and then Result.Last_Element.Kind = Tokens.End_Of_File;

end AHC.Lexer;
