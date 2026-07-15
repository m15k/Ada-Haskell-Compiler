with Ada.Strings.Unbounded;

with AHC.Builtins;
with AHC.Core;
with AHC.Diagnostics;
with AHC.Fixity;
with AHC.Lexer;
with AHC.Names;
with AHC.Parser;
with AHC.Rename;
with AHC.Source_Text;
with AHC.Syntax;
with AHC.Tokens;

with Test_Harness; use Test_Harness;

package body Test_Rename is

   use type AHC.Core.Var_Id;

   --  Run the pipeline through renaming and dump resolutions with
   --  identity serials: D[...] top/local binders per decl, P[...]
   --  pattern resolutions, E[...] expression resolutions, in arena
   --  order. A var minted by Install renders "name*" (builtin); other
   --  vars render "name:k" where k is the serial of that var's first
   --  occurrence in the dump, so alpha-identity is visible without
   --  depending on absolute ids. Constructors render "Name!".
   --  "!errors:N" appended on errors.
   function R (S : String) return String is
      use Ada.Strings.Unbounded;
      use AHC.Rename;

      Text   : constant AHC.Source_Text.Source :=
        AHC.Source_Text.Load_String ("t.hs", S);
      Table  : AHC.Names.Name_Table;
      Bag    : AHC.Diagnostics.Diagnostic_Bag;
      Stream : AHC.Tokens.Token_Vectors.Vector;
      Arena  : AHC.Syntax.Module_Arena;
      M      : AHC.Core.Core_Module;
      Env    : AHC.Builtins.Global_Env;
      Res    : AHC.Rename.Resolutions;

      Last_Builtin : AHC.Core.Var_Id;

      Next_Serial : Positive := 1;
      Out_Buf : Unbounded_String;

      --  Var_Id -> serial map (small linear table is fine for tests).
      type Pair is record
         V : AHC.Core.Var_Id;
         K : Positive;
      end record;
      Tbl  : array (1 .. 512) of Pair;
      Tlen : Natural := 0;

      function Serial (V : AHC.Core.Var_Id) return Positive is
      begin
         for I in 1 .. Tlen loop
            if Tbl (I).V = V then
               return Tbl (I).K;
            end if;
         end loop;
         Tlen := Tlen + 1;
         Tbl (Tlen) := (V, Next_Serial);
         Next_Serial := Next_Serial + 1;
         return Tbl (Tlen).K;
      end Serial;

      function Img (N : Positive) return String is
         T : constant String := N'Image;
      begin
         return T (2 .. T'Last);
      end Img;

      function Var_S (V : AHC.Core.Real_Var_Id) return String is
         Name : constant String := Table.Text (M.Info (V).Name);
      begin
         if V <= Last_Builtin then
            return Name & "*";
         end if;
         return Name & ":" & Img (Serial (V));
      end Var_S;

      procedure Emit_Res (R : Resolution) is
      begin
         case R.Kind is
            when Unresolved =>
               Append (Out_Buf, " ?");
            when Var_Res =>
               Append (Out_Buf, " " & Var_S (R.Var));
            when Data_Res =>
               Append (Out_Buf,
                       " " & Table.Text (M.Info (R.Con).Name) & "!");
         end case;
      end Emit_Res;
   begin
      AHC.Lexer.Scan (Text, Table, Bag, Stream);
      AHC.Parser.Parse_Module (Stream, Table, Bag, Arena);
      AHC.Fixity.Resolve_Module (Arena, Table, Bag);
      AHC.Builtins.Install (M, Table, Env);
      Last_Builtin := M.Last_Var;
      AHC.Rename.Resolve_Module (Arena, Table, Bag, M, Env, Res);

      Append (Out_Buf, "D[");
      for I in 1 .. Res.Decl_Var.Last_Index loop
         if Res.Decl_Var (I) /= AHC.Core.No_Var then
            Append (Out_Buf,
                    " " & Var_S (AHC.Core.Real_Var_Id
                                   (Res.Decl_Var (I))));
         end if;
      end loop;
      Append (Out_Buf, "] P[");
      for I in 1 .. Res.Pat_Res.Last_Index loop
         if Res.Pat_Res (I).Kind /= Unresolved then
            Emit_Res (Res.Pat_Res (I));
         end if;
      end loop;
      Append (Out_Buf, "] E[");
      for I in 1 .. Res.Expr_Res.Last_Index loop
         declare
            E : constant AHC.Syntax.Expr_Node :=
              Arena.Node (AHC.Syntax.Real_Expr_Id (I));
            use AHC.Syntax;
         begin
            if E.Kind in Var_E | Con_E then
               Emit_Res (Res.Expr_Res (I));
            end if;
         end;
      end loop;
      Append (Out_Buf, "]");

      if Bag.Has_Errors then
         Append (Out_Buf, "!errors:" & Bag.Error_Count'Image);
      end if;
      return To_String (Out_Buf);
   end R;

   procedure Run is
   begin
      Start_Suite ("Rename");

      Check_Equal
        (R ("f x = x"),
         "D[ f:1] P[ x:2] E[ x:2]",
         "parameter use resolves to its binder");

      Check_Equal
        (R ("f x = let x = 1 in x"),
         "D[ f:1] P[ x:2 x:3] E[ x:3]",
         "let binder shadows the parameter");

      Check_Equal
        (R ("g = map"),
         "D[] P[ g:1] E[ map*]",
         "unqualified builtin resolves");

      Check_Equal
        (R ("g = Prelude.map"),
         "D[] P[ g:1] E[ map*]",
         "Prelude-qualified builtin resolves");

      Check_Equal
        (R ("map x = x" & ASCII.LF & "g = map"),
         "D[ map:1] P[ x:2 g:3] E[ x:2 map:1]",
         "top-level definition shadows the builtin");

      Check_Equal
        (R ("f = nope"),
         "D[] P[ f:1] E[ ?]!errors: 1",
         "out of scope variable");

      Check_Equal
        (R ("f x x = x"),
         "D[ f:1] P[ x:2 x:3] E[ x:3]!errors: 1",
         "duplicate binder in one equation");

      Check_Equal
        (R ("f 0 = 1" & ASCII.LF & "f n = n"),
         "D[ f:1 f:1] P[ n:2] E[ n:2]",
         "equations of one function share a binder");

      Check_Equal
        (R ("f 0 = 1" & ASCII.LF & "g = 2" & ASCII.LF & "f n = n"),
         "D[ f:1 f:2] P[ g:3 n:4] E[ n:4]!errors: 2",
         "non-contiguous equations are an error");

      Check_Equal
        (R ("f 0 = 1" & ASCII.LF & "f a b = a"),
         "D[ f:1 f:1] P[ a:2 b:3] E[ a:2]!errors: 1",
         "arity mismatch between equations");

      Check_Equal
        (R ("f :: Int -> Int"),
         "D[] P[] E[]!errors: 1",
         "signature without a binding");

      Check_Equal
        (R ("data T = A | B Int" & ASCII.LF & "f (B n) = n"),
         "D[ f:1] P[ n:2 B!] E[ n:2]",
         "user constructor resolves in a pattern");

      Check_Equal
        (R ("g = C"),
         "D[] P[ g:1] E[ ?]!errors: 1",
         "unknown constructor");

      Check_Equal
        (R ("data T = A Int" & ASCII.LF & "f (A x y) = x"),
         "D[ f:1] P[ x:2 y:3 A!] E[ x:2]!errors: 1",
         "constructor pattern arity is checked");

      Check_Equal
        (R ("data R = MkR { fld :: Int }" & ASCII.LF
            & "get r = fld r"),
         "D[ get:1] P[ r:2] E[ fld:3 r:2]",
         "record field becomes a selector global");

      Check_Equal
        (R ("f y = do" & ASCII.LF
            & "  a <- y" & ASCII.LF
            & "  return a"),
         "D[ f:1] P[ y:2 a:3] E[ y:2 return* a:3]",
         "do-bind scopes over later statements");

      Check_Equal
        (R ("f = x where x = 1"),
         "D[] P[ f:1 x:2] E[ x:2]",
         "where binder visible in the right-hand side");

      Check_Equal
        (R ("class Sized a where" & ASCII.LF
            & "  size :: a -> Int" & ASCII.LF
            & "h = size"),
         "D[] P[ h:1] E[ size:2]",
         "class method resolves to its selector");

      Check_Equal
        (R ("f = M.x"),
         "D[] P[ f:1] E[ ?]!errors: 1",
         "unknown module qualifier");
   end Run;

end Test_Rename;
