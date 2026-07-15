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
with AHC.Typechecker;

with Test_Harness; use Test_Harness;

package body Test_Typechecker is

   use type AHC.Core.Scheme_Id;

   --  Full pipeline through typechecking; output "name :: type" per
   --  top binder ('$'-generated ones skipped), '|'-joined, plus
   --  "!errors:N".
   function TC (S : String) return String is
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
         AHC.Typechecker.Check_Module (Table, Bag, M, Env, Sigs);
         if not Bag.Has_Errors then
            for G of M.Top_Binds loop
               for B of G.Binds loop
                  declare
                     Info : constant AHC.Core.Var_Info :=
                       M.Info (B.Binder);
                     Name : constant String := Table.Text (Info.Name);
                  begin
                     if Info.Var_Scheme /= AHC.Core.No_Scheme
                       and then Name (Name'First) /= '$'
                     then
                        if Length (Out_Buf) > 0 then
                           Append (Out_Buf, "|");
                        end if;
                        Append
                          (Out_Buf,
                           Name & " :: "
                           & AHC.Core.Printer.Pretty_Scheme
                               (M, Table,
                                AHC.Core.Real_Scheme_Id
                                  (Info.Var_Scheme)));
                     end if;
                  end;
               end loop;
            end loop;
         end if;
      end if;
      if Bag.Has_Errors then
         Append (Out_Buf, "!errors:" & Bag.Error_Count'Image);
      end if;
      return To_String (Out_Buf);
   end TC;

   procedure Run is
   begin
      Start_Suite ("Typechecker");

      Check_Equal
        (TC ("compose f g x = f (g x)"),
         "compose :: (a -> b) -> (c -> a) -> c -> b",
         "higher-order inference");

      Check_Equal
        (TC ("len [] = 0" & ASCII.LF
             & "len (_ : xs) = 1 + len xs"),
         "len :: Num b => [a] -> b",
         "recursive function over lists");

      Check_Equal
        (TC ("isEven 0 = True" & ASCII.LF
             & "isEven n = isOdd (n - 1)" & ASCII.LF
             & "isOdd 0 = False" & ASCII.LF
             & "isOdd n = isEven (n - 1)"),
         "isEven :: (Num a, Eq a) => a -> Bool"
         & "|isOdd :: (Num a, Eq a) => a -> Bool",
         "mutual recursion in one SCC");

      Check_Equal
        (TC ("f x = let i y = y in (i 1, i True)"),
         "f :: Num b => a -> (b, Bool)",
         "let-polymorphism: i used at two types");

      --  The same binding as a pattern binding is restricted (MR)
      --  and rejected, exactly as GHC does.
      Check_Equal
        (TC ("f x = let i = \y -> y in (i 1, i True)"),
         "!errors: 1",
         "monomorphism restriction rejects dual-typed use");

      --  MR: the pattern binding is monomorphic and defaults;
      --  the function binding stays polymorphic.
      Check_Equal
        (TC ("g = \x -> x + 1"),
         "g :: Integer -> Integer",
         "monomorphism restriction with defaulting");
      Check_Equal
        (TC ("g x = x + 1"),
         "g :: Num a => a -> a",
         "function binding is generalized");

      Check_Equal
        (TC ("f :: (a -> b) -> [a] -> [b]" & ASCII.LF
             & "f = map"),
         "f :: (a -> b) -> [a] -> [b]",
         "signature accepted");

      Check_Equal
        (TC ("f :: a -> a" & ASCII.LF & "f x = 0"),
         "!errors: 1",
         "too-general signature rejected");

      Check_Equal
        (TC ("selfapp x = x x"),
         "!errors: 1",
         "occurs check rejects self-application");

      Check_Equal
        (TC ("x = True + 1"),
         "!errors: 2",
         "no Num instance for Bool");

      Check_Equal
        (TC ("x = undefined == undefined"),
         "!errors: 1",
         "ambiguous non-defaultable constraint");

      Check_Equal
        (TC ("total = 1 + 2" & ASCII.LF & "main = print total"),
         "total :: Integer|main :: IO ()",
         "numeric defaulting via print");

      Check_Equal
        (TC ("data Color = Red | Green deriving (Eq, Show)" & ASCII.LF
             & "same = Red == Green"),
         "same :: Bool",
         "derived Eq instance participates");

      Check_Equal
        (TC ("class Pretty a where" & ASCII.LF
             & "  pretty :: a -> String" & ASCII.LF
             & "instance Pretty Bool where" & ASCII.LF
             & "  pretty b = if b then ""y"" else ""n""" & ASCII.LF
             & "p = pretty True"),
         "p :: [Char]",
         "user class, instance, and method use");

      Check_Equal
        (TC ("class Pretty a where" & ASCII.LF
             & "  pretty :: a -> String" & ASCII.LF
             & "instance Pretty Bool where" & ASCII.LF
             & "  pretty b = if b then 1 else 2"),
         "!errors: 2",
         "ill-typed instance method body");

      Check_Equal
        (TC ("f :: Eq a => a -> a -> Bool" & ASCII.LF
             & "f x y = x == y"),
         "f :: Eq a => a -> a -> Bool",
         "signature context discharges the wanted");

      Check_Equal
        (TC ("f :: Ord a => a -> a -> Bool" & ASCII.LF
             & "f x y = x == y"),
         "f :: Ord a => a -> a -> Bool",
         "superclass given discharges Eq via Ord");

      Check_Equal
        (TC ("swap (a, b) = (b, a)"),
         "swap :: (a, b) -> (b, a)",
         "tuple constructor scheme");
   end Run;

end Test_Typechecker;
