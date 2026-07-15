with Ada.Strings.Unbounded;

with AHC.Builtins;
with AHC.Core.Printer;
with AHC.Desugar;
with AHC.Diagnostics;
with AHC.Fixity;
with AHC.Kinds;
with AHC.Lexer;
with AHC.Names;
with AHC.Parser;
with AHC.Rename;
with AHC.Source_Text;
with AHC.Syntax;
with AHC.Tokens;

with Test_Harness; use Test_Harness;

package body Test_Desugar is

   --  Pipeline through desugaring; dump Core with the _<id> suffixes
   --  stripped (names only), LF -> '|'. "!errors:N" on errors.
   function DS (S : String) return String is
      use Ada.Strings.Unbounded;

      Text   : constant AHC.Source_Text.Source :=
        AHC.Source_Text.Load_String ("t.hs", S);
      Table  : AHC.Names.Name_Table;
      Bag    : AHC.Diagnostics.Diagnostic_Bag;
      Stream : AHC.Tokens.Token_Vectors.Vector;
      Arena  : AHC.Syntax.Module_Arena;
      M      : AHC.Core.Core_Module;
      Env    : AHC.Builtins.Global_Env;
      Res    : AHC.Rename.Resolutions;
      Sigs   : AHC.Kinds.Sig_Maps.Map;
      Annos  : AHC.Kinds.Anno_Maps.Map;
      Out_Buf : Unbounded_String;
   begin
      AHC.Lexer.Scan (Text, Table, Bag, Stream);
      AHC.Parser.Parse_Module (Stream, Table, Bag, Arena);
      AHC.Fixity.Resolve_Module (Arena, Table, Bag);
      AHC.Builtins.Install (M, Table, Env);
      AHC.Rename.Resolve_Module (Arena, Table, Bag, M, Env, Res);
      AHC.Kinds.Check_Module (Arena, Res, Table, Bag, M, Env, Sigs,
                              Annos);
      if not Bag.Has_Errors then
         AHC.Desugar.Desugar_Module
           (Arena, Res, Table, Bag, M, Env, Sigs, Annos);
         declare
            D : constant String := AHC.Core.Printer.Dump (M, Table);
            I : Positive := D'First;
         begin
            while I <= D'Last loop
               if D (I) = ASCII.LF then
                  if I /= D'Last then
                     Append (Out_Buf, "|");
                  end if;
                  I := I + 1;
               elsif D (I) = '_'
                 and then I < D'Last
                 and then D (I + 1) in '0' .. '9'
               then
                  I := I + 1;
                  while I <= D'Last and then D (I) in '0' .. '9' loop
                     I := I + 1;
                  end loop;
               else
                  Append (Out_Buf, D (I));
                  I := I + 1;
               end if;
            end loop;
         end;
      end if;
      if Bag.Has_Errors then
         Append (Out_Buf, "!errors:" & Bag.Error_Count'Image);
      end if;
      return To_String (Out_Buf);
   end DS;

   procedure Run is
   begin
      Start_Suite ("Desugar");

      Check_Equal
        (DS ("inc x = x + 1"),
         "(bindrec (inc (lam x (app (app (var +) (var x))"
         & " (app (var fromInteger) (int ""1""))))))",
         "operators apply; integer literals go through fromInteger");

      Check_Equal
        (DS ("f = if b then 1 else 2 where b = True"),
         "(bindrec (f (letrec ((b (con True))) (case (var b)"
         & " (alt (con True) (app (var fromInteger) (int ""1"")))"
         & " (alt _ (app (var fromInteger) (int ""2"")))))))",
         "if becomes a Bool case; where becomes letrec");

      Check_Equal
        (DS ("f = do" & ASCII.LF
             & "  x <- act" & ASCII.LF
             & "  ret x" & ASCII.LF
             & "act = ret 1" & ASCII.LF
             & "ret = return"),
         "(bindrec (f (app (app (var >>=) (var act)) (lam x (app"
         & " (var ret) (var x))))))"
         & "|(bindrec (act (app (var ret) (app (var fromInteger)"
         & " (int ""1"")))))"
         & "|(bindrec (ret (var return)))",
         "do-bind with a variable pattern becomes >>= and a lambda");

      Check_Equal
        (DS ("s = [ x | x <- xs, x ] where xs = []"),
         "(bindrec (s (letrec ((xs (con []))) (app (app (var"
         & " concatMap) (lam x (case (var x) (alt (con True) (app"
         & " (app (con :) (var x)) (con []))) (alt _ (con [])))))"
         & " (var xs)))))",
         "comprehension: concatMap over generator, guard to Bool case");

      Check_Equal
        (DS ("f (Just x) = x" & ASCII.LF & "f Nothing = 0"),
         "(bindrec (f (lam $a (let (($fail (app (var error) (str"
         & " ""non-exhaustive patterns in function"")))) (let (($k"
         & " (let (($k (var $fail))) (case (var $a) (alt (con"
         & " Nothing) (app (var fromInteger) (int ""0""))) (alt _"
         & " (var $k)))))) (case (var $a) (alt (con Just x) (var x))"
         & " (alt _ (var $k))))))))",
         "multi-equation function with join-point fallthrough");

      Check_Equal
        (DS ("f n | n < 0 = 0" & ASCII.LF
             & "    | otherwise = n"),
         "(bindrec (f (lam n (case (app (app (var <) (var n)) (app"
         & " (var fromInteger) (int ""0""))) (alt (con True) (app"
         & " (var fromInteger) (int ""0""))) (alt _ (case (var"
         & " otherwise) (alt (con True) (var n)) (alt _ (app (var"
         & " error) (str ""non-exhaustive guards"")))))))))",
         "guards chain through Bool cases");

      Check_Equal
        (DS ("f 0 = 1" & ASCII.LF & "f n = n"),
         "(bindrec (f (lam $a (let (($fail (app (var error) (str"
         & " ""non-exhaustive patterns in function"")))) (let (($k"
         & " (let (($k (var $fail))) (let ((n (var $a))) (var n)))))"
         & " (case (app (app (var ==) (var $a)) (app (var"
         & " fromInteger) (int ""0""))) (alt (con True) (app (var"
         & " fromInteger) (int ""1""))) (alt _ (var $k))))))))",
         "literal patterns become equality tests");

      Check_Equal
        (DS ("(a, b) = t where t = (1, 2)"),
         "(bindrec ($pb (letrec ((t (app (app (con (,)) (app (var"
         & " fromInteger) (int ""1""))) (app (var fromInteger) (int"
         & " ""2""))))) (var t))))"
         & "|(bindrec (a (case (var $pb) (alt (con (,) a b) (var a))"
         & " (alt _ (app (var error) (str ""irrefutable pattern"
         & " failed""))))))"
         & "|(bindrec (b (case (var $pb) (alt (con (,) a b) (var b))"
         & " (alt _ (app (var error) (str ""irrefutable pattern"
         & " failed""))))))",
         "pattern binding uses the selector translation");

      Check_Equal
        (DS ("f = g (2 *) (`div` 2)" & ASCII.LF & "g = g"),
         "(bindrec (f (app (app (var g) (lam $x (app (app (var *)"
         & " (app (var fromInteger) (int ""2""))) (var $x)))) (let"
         & " (($y (app (var fromInteger) (int ""2"")))) (lam $x (app"
         & " (app (var div) (var $x)) (var $y)))))))"
         & "|(bindrec (g (var g)))",
         "left and right sections become lambdas");

      Check_Equal
        (DS ("x = (1 :: Int)"),
         "(bindrec (x (let (($ann (app (var fromInteger) (int"
         & " ""1"")))) (var $ann))))",
         "expression signature becomes an annotated let binder");
   end Run;

end Test_Desugar;
