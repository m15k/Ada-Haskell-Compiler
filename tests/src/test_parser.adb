with AHC.Diagnostics;
with AHC.Lexer;
with AHC.Names;
with AHC.Parser;
with AHC.Source_Text;
with AHC.Syntax.Printer;
with AHC.Tokens;

with Test_Harness; use Test_Harness;

package body Test_Parser is

   --  Parse S; return the printer dump with LFs turned into '|' (and
   --  the trailing newline dropped), plus "!errors:N" on any errors.
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
      Start_Suite ("Parser");

      Check_Equal
        (P ("f x = x"),
         "(module)|(fun f (pats (pvar x)) (var x))",
         "simple function equation");

      Check_Equal
        (P ("f, g :: Int -> Int"),
         "(module)|(sig ( f g ) (-> (tcon Int) (tcon Int)))",
         "multi-var type signature");

      Check_Equal
        (P ("(+++) :: [a] -> [a] -> [a]"),
         "(module)|(sig ( +++ ) (-> (tlist (tvar a))"
         & " (-> (tlist (tvar a)) (tlist (tvar a)))))",
         "parenthesized operator signature");

      Check_Equal
        (P ("xs +++ ys = xs"),
         "(module)|(fun +++ (pats (pvar xs) (pvar ys)) (var xs))",
         "infix operator equation");

      --  The critical layout interaction: 'in' on the same line must
      --  close the let block via the parse-error(t) rule.
      Check_Equal
        (P ("f = let x = 1 in x"),
         "(module)|(patbind (pvar f) (let (binds (patbind (pvar x)"
         & " (int 1))) (var x)))",
         "let/in on one line uses layout parse-error close");

      Check_Equal
        (P ("f = (1 +) . (+ 2) $ map (*2) [1,2]"),
         "(module)|(patbind (pvar f) (opchain (lsec (int 1) +) ."
         & " (rsec + (int 2)) $ (app (app (var map) (rsec * (int 2)))"
         & " (list (int 1) (int 2)))))",
         "sections and operator chain stay flat");

      Check_Equal
        (P ("f = \x -> if x then 0 else - x"),
         "(module)|(patbind (pvar f) (lam (pats (pvar x)) (if (var x)"
         & " (int 0) (neg (var x)))))",
         "lambda, if, unary minus");

      Check_Equal
        (P ("g r = r { field = 1, other = 2 }"),
         "(module)|(fun g (pats (pvar r)) (recupd (var r)"
         & " (field (int 1)) (other (int 2))))",
         "record update");

      Check_Equal
        (P ("g = C { field = 1 }"),
         "(module)|(patbind (pvar g) (reccon (con C) (field (int 1))))",
         "record construction");

      Check_Equal
        (P ("f (Just x) ~(a, b) l@[c] = x"),
         "(module)|(fun f (pats (pcon Just (pvar x)) (plazy (ptuple"
         & " (pvar a) (pvar b))) (pas l (plist (pvar c)))) (var x))",
         "nested patterns: con, lazy, as, tuple, list");

      Check_Equal
        (P ("x = 'a' : ""bc"""),
         "(module)|(patbind (pvar x) (opchain (char 97) : (str ""bc"")))",
         "cons operator chain with literals");

      Check_Equal
        (P ("f = a `div` b"),
         "(module)|(patbind (pvar f) (opchain (var a) div (var b)))",
         "backticked operator");

      Check_Equal
        (P ("f = (negate, (-), 3 - 4)"),
         "(module)|(patbind (pvar f) (tuple (var negate) (var -)"
         & " (opchain (int 3) - (int 4))))",
         "minus as operator reference and infix");

      --  Error recovery: a broken declaration must not eat the rest.
      Check_Equal
        (P ("f = ]" & ASCII.LF & "g = 2"),
         "(module)|(patbind (pvar g) (int 2))!errors: 1",
         "recovery after a bad declaration");

      Check_Equal
        (P ("f = x where" & ASCII.LF & "  y = 1"),
         "(module)|(patbind (pvar f) (var x) (where (patbind (pvar y)"
         & " (int 1))))",
         "where attaches to the binding");
   end Run;

end Test_Parser;
