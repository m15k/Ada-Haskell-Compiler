with Ada.Strings.Unbounded;

with AHC.Builtins;
with AHC.Core;
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

package body Test_Kinds is

   use type AHC.Core.Class_Id;
   use type AHC.Core.Kind_Id;

   --  Pipeline through kind checking; dump "T::kind" for user tycons
   --  (Dict$ internals skipped) and "class C::kind" for user classes,
   --  '|'-separated, plus "!errors:N".
   function K (S : String) return String is
      use Ada.Strings.Unbounded;
      use AHC.Core;

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
      Preds  : AHC.Kinds.Pred_Vectors.Vector;

      Last_Builtin_Class : AHC.Core.Class_Id;

      Out_Buf : Unbounded_String;

      function Kind_S (Id : Real_Kind_Id) return String is
         N : constant Kind_Node := M.Node (Id);
      begin
         case N.Kind is
            when Star_K =>
               return "*";
            when KFun_K =>
               return "(" & Kind_S (N.KFrom) & "->" & Kind_S (N.KTo)
                 & ")";
            when KMeta_K =>
               return "?";
         end case;
      end Kind_S;
   begin
      AHC.Lexer.Scan (Text, Table, Bag, Stream);
      AHC.Parser.Parse_Module (Stream, Table, Bag, Arena);
      AHC.Fixity.Resolve_Module (Arena, Table, Bag);
      AHC.Builtins.Install (M, Table, Env);
      Last_Builtin_Class := M.Last_Class;
      AHC.Rename.Resolve_Module (Arena, Table, Bag, M, Env, Res);
      AHC.Kinds.Check_Module (Arena, Res, Table, Bag, M, Env, Sigs,
                              Annos, Preds);

      for I in 1 .. M.Last_TyCon loop
         declare
            Info : constant TyCon_Info :=
              M.Info (Real_TyCon_Id (I));
            Name : constant String := Table.Text (Info.Name);
         begin
            if not Info.Is_Builtin
              and then (Name'Length < 5
                        or else Name (1 .. 5) /= "Dict$")
            then
               if Length (Out_Buf) > 0 then
                  Append (Out_Buf, "|");
               end if;
               Append (Out_Buf, Name & "::");
               if Info.TC_Kind = No_Kind then
                  Append (Out_Buf, "?");
               else
                  Append (Out_Buf,
                          Kind_S (Real_Kind_Id (Info.TC_Kind)));
               end if;
            end if;
         end;
      end loop;

      for I in 1 .. M.Last_Class loop
         if I > Last_Builtin_Class then
            declare
               Info : constant Class_Info :=
                 M.Info (Real_Class_Id (I));
            begin
               if Length (Out_Buf) > 0 then
                  Append (Out_Buf, "|");
               end if;
               Append (Out_Buf,
                       "class " & Table.Text (Info.Name) & "::");
               if Info.Var_Kind = No_Kind then
                  Append (Out_Buf, "?");
               else
                  Append (Out_Buf,
                          Kind_S (Real_Kind_Id (Info.Var_Kind)));
               end if;
            end;
         end if;
      end loop;

      if Bag.Has_Errors then
         Append (Out_Buf, "!errors:" & Bag.Error_Count'Image);
      end if;
      return To_String (Out_Buf);
   end K;

   procedure Run is
   begin
      Start_Suite ("Kinds");

      Check_Equal (K ("data W = W"), "W::*", "nullary data type");

      Check_Equal (K ("data Pair a b = P a b"),
                   "Pair::(*->(*->*))", "two type parameters");

      Check_Equal (K ("data T f = T (f Int)"),
                   "T::((*->*)->*)",
                   "higher kind inferred from application");

      Check_Equal (K ("data T f a = T (f a)"),
                   "T::((*->*)->(*->*))",
                   "kind flows between parameters");

      Check_Equal (K ("data P a = P" & ASCII.LF & "x = P :: P Int"),
                   "P::(*->*)",
                   "unused parameter defaults to *");

      Check_Equal
        (K ("type S = Int" & ASCII.LF & "data U = U S"),
         "U::*", "synonym expands in constructor field");

      Check_Equal
        (K ("type C = C" & ASCII.LF & "f :: C" & ASCII.LF & "f = f"),
         "!errors: 1", "cyclic synonym is caught");

      Check_Equal
        (K ("type P a = [a]" & ASCII.LF
            & "f :: P -> Int" & ASCII.LF & "f x = 0"),
         "!errors: 1", "unsaturated synonym is an error");

      Check_Equal
        (K ("f :: Int Int" & ASCII.LF & "f = f"),
         "!errors: 1", "over-applied type constructor");

      Check_Equal
        (K ("class Sized a where" & ASCII.LF
            & "  size :: a -> Int"),
         "class Sized::*", "class variable kind defaults to *");

      Check_Equal
        (K ("class Wrap w where" & ASCII.LF
            & "  wrap :: a -> w a"),
         "class Wrap::(*->*)",
         "class variable kind inferred from method signature");

      Check_Equal
        (K ("data B a = B a" & ASCII.LF
            & "instance Eq (B a)"),
         "B::(*->*)", "instance head is kind-checked");

      Check_Equal
        (K ("data B a = B a" & ASCII.LF
            & "f :: Eq a => B a -> Bool" & ASCII.LF
            & "f (B x) = x == x"),
         "B::(*->*)", "context in a signature converts");
   end Run;

end Test_Kinds;
