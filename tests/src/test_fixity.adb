with AHC.Diagnostics;
with AHC.Fixity;
with AHC.Lexer;
with AHC.Names;
with AHC.Parser;
with AHC.Source_Text;
with AHC.Syntax.Printer;
with AHC.Tokens;

with Test_Harness; use Test_Harness;

package body Test_Fixity is

   --  Full pipeline: lex, parse, resolve fixities, dump.
   function P (S : String) return String is
      Text   : constant AHC.Source_Text.Source :=
        AHC.Source_Text.Load_String ("t.hs", S);
      Table  : AHC.Names.Name_Table;
      Bag    : AHC.Diagnostics.Diagnostic_Bag;
      Stream : AHC.Tokens.Token_Vectors.Vector;
      Arena  : AHC.Syntax.Module_Arena;
   begin
      AHC.Lexer.Scan (Text, Table, Bag, Stream);
      AHC.Parser.Parse_Module (Stream, Table, Bag, Arena);
      AHC.Fixity.Resolve_Module (Arena, Table, Bag);
      declare
         D : String := AHC.Syntax.Printer.Dump (Arena, Table);
         Last : Natural := D'Last;
      begin
         if Last >= D'First and then D (Last) = ASCII.LF then
            Last := Last - 1;
         end if;
         for I in D'First .. Last loop
            if D (I) = ASCII.LF then
               D (I) := '|';
            end if;
         end loop;
         return D (D'First .. Last)
           & (if Bag.Has_Errors
              then "!errors:" & Bag.Error_Count'Image else "");
      end;
   end P;

   procedure Run is
   begin
      Start_Suite ("Fixity");

      Check_Equal
        (P ("a = 1 + 2 * 3"),
         "(module)|(patbind (pvar a) (app (app (var +) (int 1))"
         & " (app (app (var *) (int 2)) (int 3))))",
         "precedence: * binds tighter than +");

      Check_Equal
        (P ("a = 1 - 2 - 3"),
         "(module)|(patbind (pvar a) (app (app (var -) (app (app (var -)"
         & " (int 1)) (int 2))) (int 3)))",
         "left associativity");

      Check_Equal
        (P ("a = 1 : 2 : []"),
         "(module)|(patbind (pvar a) (app (app (con :) (int 1))"
         & " (app (app (con :) (int 2)) (con []))))",
         "right associativity of cons");

      Check_Equal
        (P ("e = -x * y"),
         "(module)|(patbind (pvar e) (neg (app (app (var *) (var x))"
         & " (var y))))",
         "prefix minus binds looser than *");

      Check_Equal
        (P ("e = -x + y"),
         "(module)|(patbind (pvar e) (app (app (var +) (neg (var x)))"
         & " (var y)))",
         "prefix minus at same precedence as +");

      Check_Equal
        (P ("infixr 7 <+>" & ASCII.LF & "h = 1 <+> 2 <+> 3"),
         "(module)|(infixr 7 <+>)|(patbind (pvar h) (app (app (var <+>)"
         & " (int 1)) (app (app (var <+>) (int 2)) (int 3))))",
         "local fixity declaration applies");

      Check_Equal
        (P ("f (x : y : zs) = x"),
         "(module)|(fun f (pats (pcon : (pvar x) (pcon : (pvar y)"
         & " (pvar zs)))) (var x))",
         "pattern cons chain resolves right");

      Check_Equal
        (P ("a = 1 == 2 == 3"),
         "(module)|(patbind (pvar a) (app (app (var ==) (app (app"
         & " (var ==) (int 1)) (int 2))) (int 3)))!errors: 1",
         "non-associative adjacency is an error");

      Check_Equal
        (P ("a = 2 ^ -3"),
         "(module)|(patbind (pvar a) (app (app (var ^) (int 2))"
         & " (neg (int 3))))!errors: 1",
         "prefix minus under higher precedence is an error");

      Check_Equal
        (P ("infixr 7 <+>" & ASCII.LF & "b = 2 <+> 3 * 4"),
         "(module)|(infixr 7 <+>)|(patbind (pvar b) (app (app (var <+>)"
         & " (int 2)) (app (app (var *) (int 3)) (int 4))))!errors: 1",
         "mixed associativity at equal precedence is an error");

      Check_Equal
        (P ("f = a `div` b `mod` c"),
         "(module)|(patbind (pvar f) (app (app (var mod) (app (app"
         & " (var div) (var a)) (var b))) (var c)))",
         "backticked Prelude operators use table fixities");
   end Run;

end Test_Fixity;
