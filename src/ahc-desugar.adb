with Ada.Containers.Vectors;

with Ada.Containers.Hashed_Sets;

with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with AHC.Exhaustive;
with AHC.Source_Text;

package body AHC.Desugar is

   use AHC.Syntax;
   use Rename;
   use type Core.Var_Id;
   use type Core.Expr_Kind;

   package Var_Sets is new Ada.Containers.Hashed_Sets
     (Core.Real_Var_Id, Rename.Var_Hash,
      Equivalent_Elements => Core."=", "=" => Core."=");
   use type Core.DataCon_Id;
   use type Names.Name_Id;

   procedure Desugar_Module
     (Arena : Syntax.Module_Arena;
      Res   : Rename.Resolutions;
      Table : in out Names.Name_Table;
      Bag   : in out Diagnostics.Diagnostic_Bag;
      M     : in out Core.Core_Module;
      Env   : in out Builtins.Global_Env;
      Sigs  : in out Kinds.Sig_Maps.Map;
      Annos : Kinds.Anno_Maps.Map;
      Preds : Kinds.Pred_Vectors.Vector :=
        Kinds.Pred_Vectors.Empty_Vector;
      Warn_Matches : Boolean := False;
      Ctx : Sites.Site_Context := Sites.No_Context)
   is
      --  A guarded right-hand side is "total" when some alternative
      --  is an unconditional otherwise/True guard - those clauses
      --  count for exhaustiveness like unguarded ones.
      function Rhs_Total (R : Syntax.Rhs) return Boolean is
      begin
         if not R.Guarded then
            return True;
         end if;
         for G of R.Guards loop
            if Natural (G.Quals.Length) = 1 then
               declare
                  SN : constant Stmt_Node :=
                    Arena.Node (G.Quals (1));
               begin
                  if SN.Kind = Expr_S then
                     declare
                        EN : constant Expr_Node :=
                          Arena.Node (SN.Expr);
                     begin
                        if (EN.Kind = Var_E
                            and then Table.Text
                              (Names.Real_Name_Id (EN.Name.Name))
                              = "otherwise")
                          or else
                            (EN.Kind = Con_E
                             and then Table.Text
                               (Names.Real_Name_Id (EN.Name.Name))
                               = "True")
                        then
                           return True;
                        end if;
                     end;
                  end if;
               end;
            end if;
         end loop;
         return False;
      end Rhs_Total;

      ------------------------------------------------------------------
      --  Core building helpers
      ------------------------------------------------------------------

      --  A desugarer temporary is MONOMORPHIC (From_Pattern_Binding
      --  puts its let group under the typechecker's no-generalization
      --  rule). It is used at exactly one type by construction, and
      --  generalizing it is wrong: a case scrutinee bound here and
      --  instantiated once per alternative gave every binder-free
      --  alternative a fresh copy of the scrutinee's class constraint
      --  - `case fromException se of Just e -> h e; Nothing -> ...`
      --  reported "ambiguous type variable in constraint" (M138).
      function Fresh
        (Prefix : String; Span : Diagnostics.Source_Span)
         return Core.Real_Var_Id
      is (M.Mint_Var ((Name => Table.Intern (Prefix), Span => Span,
                       Is_Global => False, From_Pattern_Binding => True,
                       others => <>)));

      function VarE
        (V : Core.Real_Var_Id; Span : Diagnostics.Source_Span)
         return Core.Real_Expr_Id
      is (M.Add (Core.Expr_Node'(Kind => Core.Var_C, Span => Span,
                                 V => V)));

      function ConE
        (DC : Core.Real_DataCon_Id; Span : Diagnostics.Source_Span)
         return Core.Real_Expr_Id
      is (M.Add (Core.Expr_Node'(Kind => Core.Con_C, Span => Span,
                                 Con => DC)));

      function App1
        (F, A : Core.Real_Expr_Id; Span : Diagnostics.Source_Span)
         return Core.Real_Expr_Id
      is (M.Add (Core.Expr_Node'(Kind => Core.App_C, Span => Span,
                                 Fun => F, Arg => A)));

      function App2
        (F, A, B : Core.Real_Expr_Id; Span : Diagnostics.Source_Span)
         return Core.Real_Expr_Id
      is (App1 (App1 (F, A, Span), B, Span));

      function Lam
        (V : Core.Real_Var_Id; B : Core.Real_Expr_Id;
         Span : Diagnostics.Source_Span) return Core.Real_Expr_Id
      is (M.Add (Core.Expr_Node'(Kind => Core.Lam_C, Span => Span,
                                 Binder => V, Lam_Body => B)));

      function Let1
        (V : Core.Real_Var_Id; RHS, B : Core.Real_Expr_Id;
         Span : Diagnostics.Source_Span; Rec : Boolean := False)
         return Core.Real_Expr_Id
      is
         Binds : Core.Bind_Vectors.Vector;
      begin
         Binds.Append (Core.Bind_Pair'(Binder => V, Rhs => RHS));
         return M.Add (Core.Expr_Node'
           (Kind => Core.Let_C, Span => Span, Is_Rec => Rec,
            Binds => Binds, Let_Body => B));
      end Let1;

      function Global (V : Core.Var_Id; Span : Diagnostics.Source_Span)
        return Core.Real_Expr_Id
      is (VarE (Core.Real_Var_Id (V), Span));

      --  `seq A B`, the builtin found by name as EmptyCase finds it
      --  (M150: bang patterns and strict bindings).
      function Seq_E
        (A, B : Core.Real_Expr_Id; Span : Diagnostics.Source_Span)
         return Core.Real_Expr_Id
      is
         Seq_C : constant Builtins.Var_Maps.Cursor :=
           Env.Values.Find (Table.Intern ("seq"));
      begin
         return App2
           (Global (Core.Var_Id (Builtins.Var_Maps.Element (Seq_C)), Span),
            A, B, Span);
      end Seq_E;

      --  Body_E under `seq f` for each strict binding F of a group,
      --  first binding outermost (M150): `let !x = e in b` forces x
      --  before b.
      --  A strict binding's pattern without its bang: GHC's message
      --  names `Just a` for `!(Just a) = ...` (M150 review); inner
      --  bangs stay.
      function Unbanged (P : Real_Pat_Id) return Real_Pat_Id is
        (if Arena.Node (P).Kind = Bang_P then Arena.Node (P).Bang_Pat
         else P);

      function Force_All
        (Forces : Core.Var_Id_Vectors.Vector;
         Body_E : Core.Real_Expr_Id;
         Span   : Diagnostics.Source_Span) return Core.Real_Expr_Id
      is
         Result : Core.Real_Expr_Id := Body_E;
      begin
         for I in reverse 1 .. Forces.Last_Index loop
            declare
               F_Ref : constant Core.Real_Expr_Id :=
                 VarE (Core.Real_Var_Id (Forces.Element (I)), Span);
            begin
               Result := Seq_E (F_Ref, Result, Span);
            end;
         end loop;
         return Result;
      end Force_All;

      function Str_Lit
        (S : String; Span : Diagnostics.Source_Span)
         return Core.Real_Expr_Id
      is (M.Add (Core.Expr_Node'
           (Kind => Core.Lit_C, Span => Span,
            Lit => (Kind => Core.L_String,
                    Text => Names.Name_Id (Table.Intern (S))))));

      --  The parser's MultiWayIf rewrite (M148): one alternative whose
      --  pattern is the unspellable variable `mwif$`.
      function Is_Multi_Way_If (N : Expr_Node) return Boolean is
      begin
         if N.Kind /= Case_E or else Natural (N.Alts.Length) /= 1 then
            return False;
         end if;
         declare
            P : constant Pat_Node := Arena.Node (Arena.Node (N.Alts (1)).Pat);
         begin
            return P.Kind = Var_P and then Table.Text (P.Var) = "mwif$";
         end;
      end Is_Multi_Way_If;

      function Error_Call
        (Msg : String; Span : Diagnostics.Source_Span)
         return Core.Real_Expr_Id
      is (App1 (Global (Env.Error_V, Span), Str_Lit (Msg, Span), Span));

      --  The enclosing top-level binding (M149): set by Ds_Group at
      --  depth 1 and by instance-method desugaring.
      Current_Top : Unbounded_String;
      Group_Depth : Natural := 0;

      --  The source text of Span, with a pattern's surrounding `~` and
      --  one layer of parentheses removed: GHC names a failed let or
      --  lazy pattern by its text ("Just y").
      function Pat_Text (Span : Diagnostics.Source_Span) return String is
         --  GHC names a failed let or lazy pattern by its pretty-printed
         --  form (M149 review), not the source as written: comments
         --  dropped, whitespace runs to one space, none inside brackets
         --  or before a comma, one after it; tuple parentheses and `~`
         --  kept; only an outermost pair of parentheses that match each
         --  other (a parenthesised pattern) dropped. Literals verbatim.
         Raw : constant String :=
           (if Sites.Enabled (Ctx) then Ctx.Src.Slice (Span.Start, Span.Stop)
            else "");
         R : Unbounded_String;
         I : Natural := Raw'First;
         Pending_Space : Boolean := False;
         Quote : constant Character := Character'Val (39);

         function Sym (C : Character) return Boolean is
           (C in '!' | '#' | '$' | '%' | '&' | '*' | '+' | '.' | '/' | '<'
               | '=' | '>' | '?' | '@' | '\' | '^' | '|' | '-' | '~' | ':');

         procedure Put (C : Character) is
            Last : constant Character :=
              (if Length (R) > 0 then Element (R, Length (R)) else ' ');
         begin
            if Pending_Space and then Length (R) > 0
              and then Last not in '(' | '[' | '{'
              and then C not in ')' | ']' | '}' | ','
            then
               Append (R, ' ');
            end if;
            Pending_Space := False;
            Append (R, C);
            if C = ',' then
               Pending_Space := True;
            end if;
         end Put;
      begin
         while I <= Raw'Last loop
            declare
               C : constant Character := Raw (I);
            begin
               if C = '{' and then I < Raw'Last and then Raw (I + 1) = '-' then
                  --  a (nested) block comment
                  declare
                     Depth : Natural := 0;
                  begin
                     loop
                        exit when I > Raw'Last;
                        if I < Raw'Last and then Raw (I) = '{'
                          and then Raw (I + 1) = '-'
                        then
                           Depth := Depth + 1;
                           I := I + 2;
                        elsif I < Raw'Last and then Raw (I) = '-'
                          and then Raw (I + 1) = '}'
                        then
                           Depth := Depth - 1;
                           I := I + 2;
                           exit when Depth = 0;
                        else
                           I := I + 1;
                        end if;
                     end loop;
                     Pending_Space := True;
                  end;
               elsif C = '-' and then I < Raw'Last and then Raw (I + 1) = '-'
                 and then (I + 2 > Raw'Last or else not Sym (Raw (I + 2))
                           or else Raw (I + 2) = '-')
               then
                  --  a line comment
                  while I <= Raw'Last and then Raw (I) /= ASCII.LF loop
                     I := I + 1;
                  end loop;
                  Pending_Space := True;
               elsif C = '"'
                 or else (C = Quote and then I + 2 <= Raw'Last
                          and then (Raw (I + 2) = Quote
                                    or else Raw (I + 1) = '\'))
               then
                  --  a string or character literal, verbatim
                  Put (C);
                  I := I + 1;
                  while I <= Raw'Last and then Raw (I) /= C loop
                     if Raw (I) = '\' and then I < Raw'Last then
                        Append (R, Raw (I));
                        I := I + 1;
                     end if;
                     Append (R, Raw (I));
                     I := I + 1;
                  end loop;
                  if I <= Raw'Last then
                     Append (R, Raw (I));
                     I := I + 1;
                  end if;
               elsif C in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
                  Pending_Space := True;
                  I := I + 1;
               else
                  Put (C);
                  I := I + 1;
               end if;
            end;
         end loop;
         declare
            T : constant String := To_String (R);
            F : Natural := T'First;
            L : Natural := T'Last;
            Depth : Integer := 0;
         begin
            --  An extent can end past a `)` the pattern does not open
            --  (`~(Just z)`'s inner pattern): drop unbalanced ones.
            for K in F .. L loop
               if T (K) = '(' then
                  Depth := Depth + 1;
               elsif T (K) = ')' then
                  Depth := Depth - 1;
               end if;
            end loop;
            while Depth < 0 and then L >= F and then T (L) = ')' loop
               L := L - 1;
               Depth := Depth + 1;
            end loop;
            --  An outermost pair that matches each other and is not a
            --  tuple's.
            if F < L and then T (F) = '(' and then T (L) = ')' then
               declare
                  D : Natural := 0;
                  Pairs : Boolean := True;
                  Comma : Boolean := False;
               begin
                  for K in F .. L loop
                     if T (K) in '(' | '[' then
                        D := D + 1;
                     elsif T (K) in ')' | ']' then
                        D := D - 1;
                        if D = 0 and then K < L then
                           Pairs := False;
                        end if;
                     elsif T (K) = ',' and then D = 1 then
                        Comma := True;
                     end if;
                  end loop;
                  if Pairs and then not Comma then
                     F := F + 1;
                     L := L - 1;
                  end if;
               end;
            end if;
            return T (F .. L);
         end;
      end Pat_Text;

      --  A construct's full extent, recorded by the parser (M149);
      --  its own span when none was recorded.
      function Ext_E (E : Syntax.Expr_Id; Span : Diagnostics.Source_Span)
        return Diagnostics.Source_Span
      is (if Arena.Expr_Extents.Contains (Positive (E))
          then Arena.Expr_Extents.Element (Positive (E)) else Span);

      function Ext_P (P : Syntax.Pat_Id) return Diagnostics.Source_Span
      is (if Arena.Pat_Extents.Contains (Positive (P))
          then Arena.Pat_Extents.Element (Positive (P))
          else Arena.Node (P).Span);

      function Ext_D (D : Syntax.Decl_Id) return Diagnostics.Source_Span
      is (if Arena.Decl_Extents.Contains (Positive (D))
          then Arena.Decl_Extents.Element (Positive (D))
          else Arena.Node (D).Span);

      --  The construct a lazy pattern's failure is reported at: GHC
      --  names the enclosing lambda, equation group or case (M149).
      Match_Context : Diagnostics.Source_Span;
      Have_Context  : Boolean := False;

      --  The Prelude's located entities (M149), resolved once: Plain
      --  (No_Var when the Prelude lacks it) and its located variant.
      type Located_Pair is record
         Plain, Located : Core.Var_Id := Core.No_Var;
      end record;
      Located_Vars : array (Sites.Located_Index) of Located_Pair;
      Located_Known : Boolean := False;

      function Prelude_Var (Name : String) return Core.Var_Id is
         C : constant Builtins.Var_Maps.Cursor :=
           Env.Values.Find (Table.Intern (Name));
      begin
         return (if Builtins.Var_Maps.Has_Element (C)
                 then Core.Var_Id (Builtins.Var_Maps.Element (C))
                 else Core.No_Var);
      end Prelude_Var;

      --  A reference to V at Span: V itself, or - when V is one of the
      --  Prelude's located entities and this module builds sites - its
      --  located variant applied to the site literal (M149).
      function Located_Ref
        (V : Core.Real_Var_Id; Span : Diagnostics.Source_Span;
         Shown : String := "")
         return Core.Real_Expr_Id
      is
      begin
         if not Sites.Enabled (Ctx) then
            return VarE (V, Span);
         end if;
         if not Located_Known then
            for I in Sites.Located_Index loop
               Located_Vars (I) :=
                 (Plain => Prelude_Var (Sites.Located_Plain (I)),
                  Located => Prelude_Var (Sites.Located_Name (I)));
            end loop;
            Located_Known := True;
         end if;
         for I in Sites.Located_Index loop
            if Located_Vars (I).Plain = Core.Var_Id (V)
              and then Located_Vars (I).Located /= Core.No_Var
            then
               declare
                  Key : constant String := Sites.Located_Stack_Key (I);
                  S : Sites.Site;
               begin
                  S.Ghc_Stack := To_Unbounded_String
                    (Sites.Call_Stack (Ctx, Key, Span, Shown));
                  --  (!!) has two stacks: "too large" above, "negative"
                  --  in the note field.
                  if Key = "!!/large" then
                     S.Note := To_Unbounded_String
                       (Sites.Call_Stack (Ctx, "!!/negative", Span, Shown));
                  end if;
                  S.Headline := To_Unbounded_String
                    (Sites.Located_Headline (I));
                  S.Span := Span;
                  S.Enclosing := Current_Top;
                  declare
                     Lit : constant Core.Real_Expr_Id :=
                       Str_Lit (Sites.Encode (Ctx, S), Span);
                     Fn : constant Core.Real_Expr_Id :=
                       VarE (Core.Real_Var_Id (Located_Vars (I).Located),
                             Span);
                  begin
                     return App1 (Fn, Lit, Span);
                  end;
               end;
            end if;
         end loop;
         return VarE (V, Span);
      end Located_Ref;

      --  Where a section's operator is (M149: GHC's call site for a
      --  located operator): after the `(` of `(op e)`, after the
      --  operand of `(e op)`, skipping blanks; a variable's own span.
      function Op_Span
        (N : Expr_Node; Span : Diagnostics.Source_Span)
         return Diagnostics.Source_Span
      is
         use type AHC.Source_Text.Byte_Offset;
         P : AHC.Source_Text.Byte_Offset;

         --  Past blanks and comments (M149 review: `( {- c -} !! 3)`).
         procedure Skip is
         begin
            loop
               exit when not Ctx.Src.In_Range (P);
               declare
                  C : constant Character := Ctx.Src.Char_At (P);
                  Next : constant Character :=
                    (if Ctx.Src.In_Range (P + 1) then Ctx.Src.Char_At (P + 1)
                     else ' ');
               begin
                  if C in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
                     P := P + 1;
                  elsif C = '{' and then Next = '-' then
                     declare
                        Depth : Natural := 0;
                     begin
                        loop
                           exit when not Ctx.Src.In_Range (P + 1);
                           if Ctx.Src.Char_At (P) = '{'
                             and then Ctx.Src.Char_At (P + 1) = '-'
                           then
                              Depth := Depth + 1;
                              P := P + 2;
                           elsif Ctx.Src.Char_At (P) = '-'
                             and then Ctx.Src.Char_At (P + 1) = '}'
                           then
                              Depth := Depth - 1;
                              P := P + 2;
                              exit when Depth = 0;
                           else
                              P := P + 1;
                           end if;
                        end loop;
                     end;
                  elsif C = '-' and then Next = '-' then
                     while Ctx.Src.In_Range (P)
                       and then Ctx.Src.Char_At (P) /= ASCII.LF
                     loop
                        P := P + 1;
                     end loop;
                  else
                     exit;
                  end if;
               end;
            end loop;
         end Skip;
      begin
         if not Sites.Enabled (Ctx) or else N.Kind = Var_E then
            return Span;
         end if;
         --  Both kinds start after the `(`: a right section's operator
         --  comes next, a left section is located at its body's start.
         P := Span.Start + 1;
         Skip;
         if not Ctx.Src.In_Range (P) then
            return Span;
         end if;
         return (Start => P, Stop => P + 1);
      end Op_Span;

      --  The render schema (M149): what the runtime needs to name a
      --  failing value's constructors, since a constructor node holds
      --  only its tag. Delimiters are control characters (constructor
      --  names may contain any operator symbol):
      --    schema := TYPE STX con { EOT con } ETX
      --    con    := NAME ENQ ARITY { ACK code }
      --    code   := i | d | f | c | z | s | l code | ? | schema
      --  (Int Double Float Char Integer String list unknown).
      Sch_Open  : constant Character := ASCII.STX;
      Sch_Close : constant Character := ASCII.ETX;
      Sch_Con   : constant Character := ASCII.EOT;
      Sch_Arity : constant Character := ASCII.ENQ;
      Sch_Field : constant Character := ASCII.ACK;

      function TyCon_Schema
        (TC : Core.TyCon_Id; Depth : Natural) return String;

      --  Schema size budget, in constructors + fields (M149 review: a
      --  30-constructor recursive type expanded to 33 MB of C, and a
      --  bigger one overflowed the compiler's stack). Set before each
      --  schema; exhausted, the rest is "?" - the renderer shows "..".
      Schema_Budget : Integer := 0;
      Schema_Budget_Max : constant := 48;

      function Type_Code (T : Core.Type_Id; Depth : Natural) return String is
         use type Core.Type_Kind;
         use type Core.TyCon_Id;
         use type Core.Type_Id;
      begin
         if T = Core.No_Type then
            return "?";
         end if;
         declare
            N : constant Core.Type_Node := M.Node (Core.Real_Type_Id (T));
         begin
            case N.Kind is
               when Core.TCon_T =>
                  declare
                     C : constant Core.TyCon_Id := Core.TyCon_Id (N.Con);
                  begin
                     return
                       (if C = Env.Int_TC then "i"
                        elsif C = Env.Double_TC then "d"
                        elsif C = Env.Float_TC then "f"
                        elsif C = Env.Char_TC then "c"
                        elsif C = Env.Integer_TC then "z"
                        elsif Depth > 0 then TyCon_Schema (C, Depth - 1)
                        else "?");
                  end;
               when Core.TApp_T =>
                  declare
                     F : constant Core.Type_Node := M.Node (N.T_Fun);
                     H : Core.Real_Type_Id := N.T_Fun;
                  begin
                     if F.Kind = Core.TCon_T
                       and then Core.TyCon_Id (F.Con) = Env.List_TC
                     then
                        declare
                           E : constant Core.Type_Node := M.Node (N.T_Arg);
                        begin
                           if E.Kind = Core.TCon_T
                             and then Core.TyCon_Id (E.Con) = Env.Char_TC
                           then
                              return "s";
                           end if;
                           return "l" & Type_Code (Core.Type_Id (N.T_Arg),
                                                   Depth);
                        end;
                     end if;
                     while M.Node (H).Kind = Core.TApp_T loop
                        H := M.Node (H).T_Fun;
                     end loop;
                     if M.Node (H).Kind = Core.TCon_T and then Depth > 0 then
                        return TyCon_Schema
                          (Core.TyCon_Id (M.Node (H).Con), Depth - 1);
                     end if;
                     return "?";
                  end;
               when others =>
                  return "?";
            end case;
         end;
      end Type_Code;

      function TyCon_Schema
        (TC : Core.TyCon_Id; Depth : Natural) return String
      is
         use type Core.TyCon_Id;
         use type Core.Type_Kind;
         use type Core.Type_Id;
         use type Core.Scheme_Id;
         R : Unbounded_String;
      begin
         if TC = Core.No_TyCon or else Schema_Budget <= 0 then
            return "?";
         end if;
         Schema_Budget := Schema_Budget - 1;
         declare
            TI : constant Core.TyCon_Info := M.Info (Core.Real_TyCon_Id (TC));
         begin
            --  A newtype is erased at run time: its value IS its field's
            --  (M149 review), so its schema is the field's.
            if TI.Is_Newtype and then not TI.Cons.Is_Empty then
               declare
                  DI : constant Core.DataCon_Info := M.Info (TI.Cons (1));
               begin
                  if DI.Con_Scheme /= Core.No_Scheme then
                     declare
                        T : constant Core.Type_Id :=
                          M.Node (Core.Real_Scheme_Id (DI.Con_Scheme)).S_Body;
                     begin
                        if T /= Core.No_Type
                          and then M.Node (Core.Real_Type_Id (T)).Kind
                                     = Core.TFun_T
                        then
                           return Type_Code
                             (Core.Type_Id
                                (M.Node (Core.Real_Type_Id (T)).From), Depth);
                        end if;
                     end;
                  end if;
                  return "?";
               end;
            end if;
            Append (R, Table.Text (Names.Real_Name_Id (TI.Name)) & Sch_Open);
            for CI in 1 .. TI.Cons.Last_Index loop
               declare
                  DI : constant Core.DataCon_Info := M.Info (TI.Cons (CI));
                  T : Core.Type_Id := Core.No_Type;
               begin
                  if CI > 1 then
                     Append (R, Sch_Con);
                  end if;
                  Append (R, Table.Text (Names.Real_Name_Id (DI.Name))
                          & Sch_Arity
                          & Ada.Strings.Fixed.Trim
                              (Natural'Image (DI.Arity), Ada.Strings.Left));
                  if DI.Con_Scheme /= Core.No_Scheme then
                     T := M.Node (Core.Real_Scheme_Id (DI.Con_Scheme)).S_Body;
                  end if;
                  for K in 1 .. DI.Arity loop
                     Schema_Budget := Schema_Budget - 1;
                     if T /= Core.No_Type
                       and then M.Node (Core.Real_Type_Id (T)).Kind
                                  = Core.TFun_T
                     then
                        Append (R, Sch_Field & Type_Code
                          (Core.Type_Id
                             (M.Node (Core.Real_Type_Id (T)).From), Depth));
                        T := Core.Type_Id (M.Node (Core.Real_Type_Id (T)).To);
                     else
                        Append (R, Sch_Field & "?");
                     end if;
                  end loop;
               end;
            end loop;
            Append (R, Sch_Close);
            return To_String (R);
         end;
      end TyCon_Schema;

      --  The type a pattern's top-level constructor belongs to, or
      --  No_TyCon (a variable, wildcard or literal).
      function Pat_TyCon (P : Syntax.Pat_Id) return Core.TyCon_Id is
         N : constant Pat_Node := Arena.Node (P);
      begin
         case N.Kind is
            when Con_P | Rec_P =>
               declare
                  R : constant Resolution := Res.Pat_Res (Positive (P));
               begin
                  if R.Kind = Data_Res then
                     return M.Info (R.Con).TyCon;
                  end if;
               end;
            when Lazy_P =>
               return Pat_TyCon (N.Lazy_Pat);
            when Bang_P =>
               return Pat_TyCon (N.Bang_Pat);
            when As_P =>
               return Pat_TyCon (N.As_Pat);
            when others =>
               null;
         end case;
         return Core.No_TyCon;
      end Pat_TyCon;

      --  The constructors patterns name, distinct, joined by RS.
      procedure Add_Handled (P : Syntax.Pat_Id; Into : in out Unbounded_String)
      is
         N : constant Pat_Node := Arena.Node (P);
      begin
         if N.Kind in Con_P | Rec_P then
            declare
               R : constant Resolution := Res.Pat_Res (Positive (P));
            begin
               if R.Kind = Data_Res then
                  declare
                     Nm : constant String :=
                       Table.Text (Names.Real_Name_Id (M.Info (R.Con).Name));
                  begin
                     if Ada.Strings.Fixed.Index
                          (ASCII.RS & To_String (Into) & ASCII.RS,
                           ASCII.RS & Nm & ASCII.RS) = 0
                     then
                        if Length (Into) > 0 then
                           Append (Into, ASCII.RS);
                        end if;
                        Append (Into, Nm);
                     end if;
                  end;
               end if;
            end;
         elsif N.Kind = As_P then
            Add_Handled (N.As_Pat, Into);
         elsif N.Kind = Bang_P then
            Add_Handled (N.Bang_Pat, Into);
         end if;
      end Add_Handled;

      Schema_Depth : constant := 3;

      function Handled_Of_One (P : Syntax.Pat_Id) return String is
         R : Unbounded_String;
      begin
         Add_Handled (P, R);
         return To_String (R);
      end Handled_Of_One;

      function Alts_Handled (Alts : Alt_Id_Vectors.Vector) return String is
         R : Unbounded_String;
      begin
         for A of Alts loop
            Add_Handled (Arena.Node (A).Pat, R);
         end loop;
         return To_String (R);
      end Alts_Handled;

      --  The schema of the values a pattern can see: its type's, or
      --  "?" for a variable, wildcard or literal.
      function Pat_Schema (P : Syntax.Pat_Id) return String is
         use type Core.TyCon_Id;
         TC : constant Core.TyCon_Id := Pat_TyCon (P);
         N : constant Pat_Node := Arena.Node (P);
      begin
         Schema_Budget := Schema_Budget_Max;
         --  Built-in lists and tuples (M149 review): a list renders
         --  through its own code, a tuple through its tuple type.
         if N.Kind = List_P or else TC = Env.List_TC then
            return "l?";
         elsif N.Kind = Tuple_P
           and then Natural (N.Items.Length) in 2 .. Builtins.Max_Tuple
         then
            return TyCon_Schema
              (Env.Tuple_TCs (Natural (N.Items.Length)), Schema_Depth - 1);
         end if;
         return (if TC = Core.No_TyCon then "?"
                 else TyCon_Schema (TC, Schema_Depth - 1));
      end Pat_Schema;

      function Alts_Schema (Alts : Alt_Id_Vectors.Vector) return String is
      begin
         for A of Alts loop
            declare
               Sch : constant String := Pat_Schema (Arena.Node (A).Pat);
            begin
               if Sch /= "?" then
                  return Sch;
               end if;
            end;
         end loop;
         return "?";
      end Alts_Schema;

      --  A function's failing value is its argument, or the tuple of
      --  its arguments: one schema per column, from the first equation
      --  whose pattern there names a constructor.
      function Unit_Schema (U : Binding_Unit) return String is
         Cols : Unbounded_String;
         Tup : constant String :=
           "(" & [1 .. Natural'Max (U.Arity - 1, 0) => ','] & ")";
         function Col (C : Positive) return String is
         begin
            for D of U.Equations loop
               declare
                  N : constant Decl_Node := Arena.Node (D);
               begin
                  if C <= N.Fun_Pats.Last_Index then
                     declare
                        Sch : constant String := Pat_Schema (N.Fun_Pats (C));
                     begin
                        if Sch /= "?" then
                           return Sch;
                        end if;
                     end;
                  end if;
               end;
            end loop;
            return "?";
         end Col;
      begin
         if U.Arity = 1 then
            return Col (1);
         elsif U.Arity not in 2 .. Builtins.Max_Tuple then
            return "?";
         end if;
         for C in 1 .. U.Arity loop
            Append (Cols, Sch_Field & Col (C));
         end loop;
         return Tup & Sch_Open & Tup & Sch_Arity
           & Ada.Strings.Fixed.Trim (Natural'Image (U.Arity), Ada.Strings.Left)
           & To_String (Cols) & Sch_Close;
      end Unit_Schema;

      function Unit_Handled (U : Binding_Unit) return String is
         R : Unbounded_String;
      begin
         if U.Arity = 1 then
            for D of U.Equations loop
               Add_Handled (Arena.Node (D).Fun_Pats (1), R);
            end loop;
         end if;
         return To_String (R);
      end Unit_Handled;

      --  \case / \cases (M149 review): the parser makes them a lambda
      --  over a case on its own binders (lc$, c1$ ..). The lambda notes
      --  its body's id, kind and extent; that case's failure then reads
      --  "\case" or "\cases" and spans the whole lambda, as GHC's.
      LC_Body : Natural := 0;
      LC_Kind : Unbounded_String;
      LC_Span : Diagnostics.Source_Span;

      function LC_Kind_Of (N : Expr_Node) return String is
         B : constant Expr_Node := Arena.Node (N.L_Body);
      begin
         if B.Kind /= Case_E then
            return "";
         end if;
         declare
            Sc : constant Expr_Node := Arena.Node (B.Scrutinee);
            First : constant Expr_Node :=
              (if Sc.Kind = Tuple_E and then not Sc.Items.Is_Empty
               then Arena.Node (Sc.Items.First_Element) else Sc);
         begin
            if First.Kind = Var_E then
               declare
                  T : constant String := Table.Text (First.Name.Name);
               begin
                  if T = "lc$" then
                     return "\case";
                  elsif T'Length > 2 and then T (T'First) = 'c'
                    and then T (T'Last) = '$'
                  then
                     return "\cases";
                  end if;
               end;
            end if;
         end;
         return "";
      end LC_Kind_Of;

      function Note_LC (N : Expr_Node; S : Diagnostics.Source_Span)
        return Boolean is
      begin
         LC_Body := Natural (N.L_Body);
         LC_Kind := To_Unbounded_String (LC_Kind_Of (N));
         LC_Span := S;
         return True;
      end Note_LC;

      function Case_Kind (E : Syntax.Expr_Id) return String is
        (if Natural (E) = LC_Body then To_String (LC_Kind) else "case");

      function Case_Span
        (E : Syntax.Expr_Id; Span : Diagnostics.Source_Span)
         return Diagnostics.Source_Span
      is (if Natural (E) = LC_Body then LC_Span else Ext_E (E, Span));

      --  GHC's text for a failed pattern in a do block's bind, which
      --  goes to `fail` (M149 review): located at the pattern.
      function Do_Fail_Text (P : Syntax.Pat_Id) return String is
        (if Sites.Enabled (Ctx)
         then "Pattern match failure in 'do' block at "
              & Sites.Ghc_Span (Ctx, Ext_P (P))
         else "pattern match failure in do block");

      --  The failing value a function's site reports: its one
      --  argument, the tuple of several (up to the widest tuple), or
      --  () when there are none or too many.
      function Args_Value
        (Vars : Core.Var_Id_Vectors.Vector;
         Span : Diagnostics.Source_Span) return Core.Real_Expr_Id
      is
         K : constant Natural := Natural (Vars.Length);
      begin
         if K = 1 then
            return VarE (Vars.First_Element, Span);
         elsif K in 2 .. Builtins.Max_Tuple then
            declare
               R : Core.Real_Expr_Id :=
                 ConE (Core.Real_DataCon_Id (Env.Tuple_DCs (K)), Span);
            begin
               for V of Vars loop
                  declare
                     A : constant Core.Real_Expr_Id :=
                       VarE (V, Span);
                  begin
                     R := App1 (R, A, Span);
                  end;
               end loop;
               return R;
            end;
         end if;
         return ConE (Core.Real_DataCon_Id (Env.Unit_DC), Span);
      end Args_Value;

      --  A pattern-match failure site (M149): primFailMatch with the
      --  site literal and the failing value. Ghc_Text is the whole
      --  shown text when GHC's wording is not "Non-exhaustive patterns
      --  in KIND". Without a site context, the plain error call.
      function Fail_Match
        (Kind    : String;
         Span    : Diagnostics.Source_Span;
         Value   : Core.Real_Expr_Id;
         Plain   : String;
         Handled : String := "";
         Ghc_Text : String := "";
         Schema  : String := "";
         Headline : String := "pattern match failure")
         return Core.Real_Expr_Id
      is
         S : Sites.Site;
      begin
         if not Sites.Enabled (Ctx) then
            return Error_Call (Plain, Span);
         end if;
         S.Ghc_Text := To_Unbounded_String
           (if Ghc_Text /= "" then Ghc_Text
            else Sites.Ghc_Span (Ctx, Span)
                 & ": Non-exhaustive patterns in " & Kind & ASCII.LF);
         S.Headline := To_Unbounded_String (Headline);
         S.Span := Span;
         S.Enclosing := Current_Top;
         S.Handled := To_Unbounded_String (Handled);
         S.Schema := To_Unbounded_String (Schema);
         declare
            Lit : constant Core.Real_Expr_Id :=
              Str_Lit (Sites.Encode (Ctx, S), Span);
            Fm : constant Core.Real_Expr_Id :=
              Global (Env.Fail_Match_V, Span);
            F1 : constant Core.Real_Expr_Id := App1 (Fm, Lit, Span);
         begin
            return App1 (F1, Value, Span);
         end;
      end Fail_Match;

      --  case Scrut of True -> Then_E; _ -> Else_E
      function Bool_Case
        (Scrut, Then_E, Else_E : Core.Real_Expr_Id;
         Span : Diagnostics.Source_Span) return Core.Real_Expr_Id
      is
         Alts : Core.Alt_Id_Vectors.Vector;
      begin
         Alts.Append (M.Add (Core.Alt_Node'
           (Kind => Core.Con_Alt, Span => Span, Alt_Body => Then_E,
            A_Con => Core.Real_DataCon_Id (Env.True_DC),
            Binders => Core.Var_Id_Vectors.Empty_Vector)));
         Alts.Append (M.Add (Core.Alt_Node'
           (Kind => Core.Default_Alt, Span => Span,
            Alt_Body => Else_E)));
         return M.Add (Core.Expr_Node'
           (Kind => Core.Case_C, Span => Span, Scrutinee => Scrut,
            Alts => Alts));
      end Bool_Case;

      function Nil (Span : Diagnostics.Source_Span)
        return Core.Real_Expr_Id
      is (ConE (Core.Real_DataCon_Id (Env.Nil_DC), Span));

      function Cons
        (H, T : Core.Real_Expr_Id; Span : Diagnostics.Source_Span)
         return Core.Real_Expr_Id
      is (App2 (ConE (Core.Real_DataCon_Id (Env.Cons_DC), Span),
                H, T, Span));

      ------------------------------------------------------------------
      --  Forward declarations
      ------------------------------------------------------------------

      function Ds_Expr (E : Real_Expr_Id) return Core.Real_Expr_Id;

      --  Forces receives, in order, the variables a strict binding of
      --  the group (`!p = e`, M150) makes the group's body force;
      --  wrap the body with Force_All.
      procedure Ds_Group
        (Decls  : Syntax.Decl_Id_Vectors.Vector;
         Into   : in out Core.Bind_Vectors.Vector;
         Forces : in out Core.Var_Id_Vectors.Vector);

      --  Wrap Body in the bindings needed to match Pat against Scrut;
      --  on failure the result is Fail (a variable reference to a
      --  Let-bound join point, so no duplication).
      function Match_One
        (Scrut : Core.Real_Var_Id;
         Pat   : Real_Pat_Id;
         Inner : Core.Real_Expr_Id;
         Fail  : Core.Real_Expr_Id) return Core.Real_Expr_Id;

      ------------------------------------------------------------------
      --  Pattern matching
      ------------------------------------------------------------------

      --  Core expressions must form a tree: the evidence machinery
      --  rewrites nodes per inferred occurrence, so a join-point
      --  reference embedded in several alternatives needs a fresh
      --  Var node per embedding.
      function Fresh_Ref
        (E : Core.Real_Expr_Id) return Core.Real_Expr_Id
      is
         N : constant Core.Expr_Node := M.Node (E);
      begin
         if N.Kind = Core.Var_C then
            return M.Add (N);
         end if;
         return E;
      end Fresh_Ref;

      type Pair is record
         Scrut : Core.Real_Var_Id;
         Pat   : Syntax.Pat_Id;
      end record;

      package Pair_Vectors is new Ada.Containers.Vectors
        (Positive, Pair);

      function Match_Seq
        (Pairs : Pair_Vectors.Vector;
         Inner : Core.Real_Expr_Id;
         Fail  : Core.Real_Expr_Id) return Core.Real_Expr_Id
      is
         Result : Core.Real_Expr_Id := Inner;
      begin
         --  Right to left, so the leftmost pattern tests outermost.
         for I in reverse 1 .. Pairs.Last_Index loop
            Result := Match_One
              (Pairs (I).Scrut, Real_Pat_Id (Pairs (I).Pat),
               Result, Fail);
         end loop;
         return Result;
      end Match_Seq;

      --  Variables bound anywhere inside a pattern (for lazy patterns
      --  and pattern bindings).
      --  Report 3.14 (and GHC's "failable" test): a bind whose pattern
      --  cannot fail needs no `fail` continuation. Variables,
      --  wildcards, lazy patterns, signatures, as-patterns over
      --  unfailable patterns, tuples of unfailable patterns, and a
      --  constructor of a SINGLE-constructor type applied to unfailable
      --  patterns are unfailable; everything else may fail. The
      --  continuation is `fail "..."` - a Monad-constrained value - and
      --  a desugarer temporary is monomorphic, so an unused one would
      --  leave its constraint ambiguous (M138): `_ <- act` in a do
      --  block reported "ambiguous type variable in constraint 'Monad'".
      function Unfailable (Pat : Pat_Id) return Boolean is
         N : constant Pat_Node := Arena.Node (Real_Pat_Id (Pat));
      begin
         case N.Kind is
            when Var_P | Wild_P | Lazy_P =>
               return True;
            when Sig_P =>
               return Unfailable (Pat_Id (N.Sig_Pat));
            when Bang_P =>
               --  A bang can diverge but never fails to match.
               return Unfailable (Pat_Id (N.Bang_Pat));
            when As_P =>
               return Unfailable (Pat_Id (N.As_Pat));
            when Tuple_P =>
               for P of N.Items loop
                  if not Unfailable (P) then
                     return False;
                  end if;
               end loop;
               return True;
            when Con_P | Rec_P =>
               declare
                  R : constant Resolution := Res.Pat_Res (Positive (Pat));
               begin
                  if R.Kind /= Data_Res then
                     return False;
                  end if;
                  if Natural (M.Info (Core.Real_TyCon_Id
                                        (M.Info (R.Con).TyCon)).Cons.Length)
                    /= 1
                  then
                     return False;
                  end if;
                  if N.Kind = Con_P then
                     for P of N.Con_Args loop
                        if not Unfailable (P) then
                           return False;
                        end if;
                     end loop;
                  else
                     for F of N.Rec_Fields loop
                        if not Unfailable (Pat_Id (F.Value)) then
                           return False;
                        end if;
                     end loop;
                  end if;
                  return True;
               end;
            when others =>
               return False;
         end case;
      end Unfailable;

      procedure Bound_Vars
        (Pat : Real_Pat_Id; Into : in out Core.Var_Id_Vectors.Vector)
      is
         N : constant Pat_Node := Arena.Node (Pat);

         procedure Add_Var (P : Real_Pat_Id) is
            R : constant Resolution := Res.Pat_Res (Positive (P));
         begin
            if R.Kind = Var_Res then
               Into.Append (R.Var);
            end if;
         end Add_Var;
      begin
         case N.Kind is
            when Var_P =>
               Add_Var (Pat);
            when As_P =>
               Add_Var (Pat);
               Bound_Vars (N.As_Pat, Into);
            when Con_P =>
               for P of N.Con_Args loop
                  Bound_Vars (P, Into);
               end loop;
            when Tuple_P | List_P =>
               for P of N.Items loop
                  Bound_Vars (P, Into);
               end loop;
            when Lazy_P =>
               Bound_Vars (N.Lazy_Pat, Into);
            when Bang_P =>
               Bound_Vars (N.Bang_Pat, Into);
            when Rec_P =>
               for F of N.Rec_Fields loop
                  Bound_Vars (F.Value, Into);
               end loop;
               --  RecordWildCards (M148): the `..` variables.
               if Res.Wild_Pat.Contains (Positive (Pat)) then
                  for W of Res.Wild_Pat.Element (Positive (Pat)) loop
                     Into.Append (W.Var);
                  end loop;
               end if;
            when Sig_P =>
               Bound_Vars (N.Sig_Pat, Into);
            when others =>
               null;
         end case;
      end Bound_Vars;

      --  Lazy / irrefutable translation (Report 3.12, 4.4.3.2): each
      --  variable of the pattern is bound to a selector over Scrut.
      function Bind_Lazily
        (Scrut : Core.Real_Var_Id;
         Pat   : Real_Pat_Id;
         Inner : Core.Real_Expr_Id;
         Span  : Diagnostics.Source_Span) return Core.Real_Expr_Id
      is
         Vars   : Core.Var_Id_Vectors.Vector;
         Result : Core.Real_Expr_Id := Inner;
      begin
         Bound_Vars (Pat, Vars);
         for V of Vars loop
            declare
               --  v = case scrut of pat -> v
               --  GHC names the failed pattern by its text (M149).
               Fail : constant Core.Real_Expr_Id :=
                 Fail_Match (Pat_Text (Ext_P (Pat)),
                             (if Have_Context then Match_Context
                              else Span),
                             VarE (Scrut, Span),
                             "irrefutable pattern failed",
                             Handled => Handled_Of_One (Pat),
                             Schema => Pat_Schema (Pat));
               Sel : constant Core.Real_Expr_Id := Match_One
                 (Scrut, Pat, VarE (V, Span), Fail);
            begin
               Result := Let1 (V, Sel, Result, Span);
            end;
         end loop;
         return Result;
      end Bind_Lazily;

      function Match_One
        (Scrut : Core.Real_Var_Id;
         Pat   : Real_Pat_Id;
         Inner : Core.Real_Expr_Id;
         Fail  : Core.Real_Expr_Id) return Core.Real_Expr_Id
      is
         N : constant Pat_Node := Arena.Node (Pat);
         Span : constant Diagnostics.Source_Span := N.Span;

         --  Literal patterns become equality tests (correct for
         --  overloaded numerics per Report 3.17.2).
         function Lit_Test
           (Lit_E : Core.Real_Expr_Id) return Core.Real_Expr_Id
         is
            Eq_Sel : constant Builtins.Var_Maps.Cursor :=
              Env.Values.Find (Table.Intern ("=="));
            Test : constant Core.Real_Expr_Id :=
              App2 (Global (Core.Var_Id
                      (Builtins.Var_Maps.Element (Eq_Sel)), Span),
                    VarE (Scrut, Span), Lit_E, Span);
         begin
            return Bool_Case (Test, Inner, Fresh_Ref (Fail), Span);
         end Lit_Test;

         function Is_Newtype_Con (DC : Core.Real_DataCon_Id)
           return Boolean
         is (M.Info (Core.Real_TyCon_Id (M.Info (DC).TyCon))
               .Is_Newtype);

         --  `case scrut of N x -> x`: the wrapped field of a newtype.
         --  Bound LAZILY by the callers, so demanding the field is
         --  the only thing that ever demands the wrapper - which is
         --  what makes a newtype constructor pattern irrefutable
         --  (Report 4.2.3), in both the positional and the record
         --  spelling.
         function Newtype_Projection (DC : Core.Real_DataCon_Id)
           return Core.Real_Expr_Id
         is
            X : constant Core.Real_Var_Id := Fresh ("$m", Span);
            Xs : Core.Var_Id_Vectors.Vector;
            PAlts : Core.Alt_Id_Vectors.Vector;
         begin
            Xs.Append (Core.Var_Id (X));
            PAlts.Append (M.Add (Core.Alt_Node'
              (Kind => Core.Con_Alt, Span => Span,
               Alt_Body => VarE (X, Span),
               A_Con => DC, Binders => Xs)));
            PAlts.Append (M.Add (Core.Alt_Node'
              (Kind => Core.Default_Alt, Span => Span,
               Alt_Body => Error_Call
                 ("impossible: newtype projection", Span))));
            return M.Add (Core.Expr_Node'
              (Kind => Core.Case_C, Span => Span,
               Scrutinee => VarE (Scrut, Span),
               Alts => PAlts));
         end Newtype_Projection;

         --  Match one sub-pattern against the newtype's field.
         function Newtype_Field_Match
           (DC : Core.Real_DataCon_Id;
            P  : Real_Pat_Id;
            Inner : Core.Real_Expr_Id;
            Fail  : Core.Real_Expr_Id) return Core.Real_Expr_Id
         is
            PN : constant Pat_Node := Arena.Node (P);
            R  : constant Resolution := Res.Pat_Res (Positive (P));
         begin
            if PN.Kind = Wild_P then
               return Inner;
            elsif PN.Kind = Var_P and then R.Kind = Var_Res then
               return Let1 (R.Var, Newtype_Projection (DC), Inner,
                            Span);
            else
               declare
                  B : constant Core.Real_Var_Id := Fresh ("$m", Span);
                  NPairs : Pair_Vectors.Vector;
               begin
                  NPairs.Append (Pair'(Scrut => B, Pat => P));
                  return Let1
                    (B, Newtype_Projection (DC),
                     Match_Seq (NPairs, Inner, Fail), Span);
               end;
            end if;
         end Newtype_Field_Match;

         function Con_Match
           (DC : Core.Real_DataCon_Id;
            Sub_Pats : Syntax.Pat_Id_Vectors.Vector)
            return Core.Real_Expr_Id
         is
            Binders : Core.Var_Id_Vectors.Vector;
            Pairs   : Pair_Vectors.Vector;
            Alts    : Core.Alt_Id_Vectors.Vector;
         begin
            --  A newtype constructor pattern is irrefutable at the
            --  wrapper (Report 4.2.3): N p matches iff p matches the
            --  coerced value, and matching never forces the wrapper
            --  itself. So: no case on Scrut -- the sub-pattern
            --  matches a LAZY projection, demanded only if the
            --  sub-pattern (or a use of its variable) demands it.
            --  This is what lets some/many's knot terminate on
            --  newtype-wrapped parsers, exactly as in GHC.
            if Is_Newtype_Con (DC)
              and then Natural (Sub_Pats.Length) = 1
            then
               declare
                  P1 : constant Syntax.Pat_Id := Sub_Pats (1);
               begin
                  return Newtype_Field_Match (DC, P1, Inner, Fail);
               end;
            end if;
            for P of Sub_Pats loop
               declare
                  PN : constant Pat_Node := Arena.Node (P);
                  R  : constant Resolution :=
                    Res.Pat_Res (Positive (P));
               begin
                  --  A variable sub-pattern becomes the alt binder
                  --  directly; anything else gets a fresh binder and a
                  --  recursive match.
                  if PN.Kind = Var_P and then R.Kind = Var_Res then
                     Binders.Append (R.Var);
                  else
                     declare
                        B : constant Core.Real_Var_Id :=
                          Fresh ("$m", Span);
                     begin
                        Binders.Append (B);
                        if PN.Kind /= Wild_P then
                           Pairs.Append
                             (Pair'(Scrut => B,
                                    Pat => Syntax.Pat_Id (P)));
                        end if;
                     end;
                  end if;
               end;
            end loop;
            Alts.Append (M.Add (Core.Alt_Node'
              (Kind => Core.Con_Alt, Span => Span,
               Alt_Body => Match_Seq (Pairs, Inner, Fail),
               A_Con => DC, Binders => Binders)));
            Alts.Append (M.Add (Core.Alt_Node'
              (Kind => Core.Default_Alt, Span => Span,
               Alt_Body => Fresh_Ref (Fail))));
            return M.Add (Core.Expr_Node'
              (Kind => Core.Case_C, Span => Span,
               Scrutinee => VarE (Scrut, Span), Alts => Alts));
         end Con_Match;
      begin
         case N.Kind is
            when Var_P =>
               declare
                  R : constant Resolution :=
                    Res.Pat_Res (Positive (Pat));
               begin
                  if R.Kind = Var_Res then
                     return Let1 (R.Var, VarE (Scrut, Span), Inner,
                                  Span);
                  end if;
                  return Inner;
               end;
            when Wild_P =>
               return Inner;
            when As_P =>
               declare
                  R : constant Resolution :=
                    Res.Pat_Res (Positive (Pat));
                  Rest : constant Core.Real_Expr_Id :=
                    Match_One (Scrut, N.As_Pat, Inner, Fail);
               begin
                  if R.Kind = Var_Res then
                     return Let1 (R.Var, VarE (Scrut, Span), Rest,
                                  Span);
                  end if;
                  return Rest;
               end;
            when Lazy_P =>
               return Bind_Lazily (Scrut, N.Lazy_Pat, Inner, Span);
            when Bang_P =>
               --  `!p` (M150): force the scrutinee, then match p.
               declare
                  S_Ref : constant Core.Real_Expr_Id := VarE (Scrut, Span);
                  Rest  : constant Core.Real_Expr_Id :=
                    Match_One (Scrut, N.Bang_Pat, Inner, Fail);
               begin
                  return Seq_E (S_Ref, Rest, Span);
               end;
            when Sig_P =>
               --  Kind-checked in AHC.Kinds; the annotation does not
               --  affect matching.
               return Match_One (Scrut, N.Sig_Pat, Inner, Fail);
            when Lit_Int_P =>
               return Lit_Test
                 (App1 (Global (Env.From_Integer_V, Span),
                        M.Add (Core.Expr_Node'
                          (Kind => Core.Lit_C, Span => Span,
                           Lit => (Core.L_Int, N.Text))), Span));
            when Neg_Int_P =>
               return Lit_Test
                 (App1 (Global (Env.Negate_V, Span),
                        App1 (Global (Env.From_Integer_V, Span),
                              M.Add (Core.Expr_Node'
                                (Kind => Core.Lit_C, Span => Span,
                                 Lit => (Core.L_Int, N.Text))), Span),
                        Span));
            when Lit_Float_P =>
               return Lit_Test
                 (App1 (Global (Env.From_Rational_V, Span),
                        M.Add (Core.Expr_Node'
                          (Kind => Core.Lit_C, Span => Span,
                           Lit => (Core.L_Float, N.Text))), Span));
            when Neg_Float_P =>
               return Lit_Test
                 (App1 (Global (Env.Negate_V, Span),
                        App1 (Global (Env.From_Rational_V, Span),
                              M.Add (Core.Expr_Node'
                                (Kind => Core.Lit_C, Span => Span,
                                 Lit => (Core.L_Float, N.Text))),
                              Span), Span));
            when Lit_Char_P =>
               return Lit_Test
                 (M.Add (Core.Expr_Node'
                    (Kind => Core.Lit_C, Span => Span,
                     Lit => (Kind => Core.L_Char,
                             Code => N.Char_Value))));
            when Lit_String_P =>
               return Lit_Test
                 (M.Add (Core.Expr_Node'
                    (Kind => Core.Lit_C, Span => Span,
                     Lit => (Core.L_String, N.Text))));
            when Con_P =>
               declare
                  R : constant Resolution :=
                    Res.Pat_Res (Positive (Pat));
               begin
                  if R.Kind /= Data_Res then
                     return Inner;
                  end if;
                  return Con_Match (R.Con, N.Con_Args);
               end;
            when Tuple_P =>
               declare
                  Count : constant Natural := Natural (N.Items.Length);
               begin
                  return Con_Match
                    (Core.Real_DataCon_Id (Env.Tuple_DCs (Count)),
                     N.Items);
               end;
            when List_P =>
               --  [p1, p2] = p1 : p2 : [].
               if N.Items.Is_Empty then
                  return Con_Match
                    (Core.Real_DataCon_Id (Env.Nil_DC),
                     Syntax.Pat_Id_Vectors.Empty_Vector);
               end if;
               declare
                  --  Build nested cons matches from the left.
                  function Go
                    (I : Positive; S : Core.Real_Var_Id)
                     return Core.Real_Expr_Id
                  is
                     Head_P : constant Real_Pat_Id := N.Items (I);
                     Tail_B : constant Core.Real_Var_Id :=
                       Fresh ("$t", Span);
                     Head_B : Core.Real_Var_Id;
                     Rest : Core.Real_Expr_Id;
                     Alts : Core.Alt_Id_Vectors.Vector;
                     Binders : Core.Var_Id_Vectors.Vector;
                     HN : constant Pat_Node := Arena.Node (Head_P);
                     HR : constant Resolution :=
                       Res.Pat_Res (Positive (Head_P));
                     Head_Direct : constant Boolean :=
                       HN.Kind = Var_P and then HR.Kind = Var_Res;
                  begin
                     if Head_Direct then
                        Head_B := HR.Var;
                     else
                        Head_B := Fresh ("$h", Span);
                     end if;

                     if I = N.Items.Last_Index then
                        --  Tail must be []: match Nil.
                        declare
                           NAlts : Core.Alt_Id_Vectors.Vector;
                        begin
                           NAlts.Append (M.Add (Core.Alt_Node'
                             (Kind => Core.Con_Alt, Span => Span,
                              Alt_Body => Inner,
                              A_Con =>
                                Core.Real_DataCon_Id (Env.Nil_DC),
                              Binders =>
                                Core.Var_Id_Vectors.Empty_Vector)));
                           NAlts.Append (M.Add (Core.Alt_Node'
                             (Kind => Core.Default_Alt, Span => Span,
                              Alt_Body => Fresh_Ref (Fail))));
                           Rest := M.Add (Core.Expr_Node'
                             (Kind => Core.Case_C, Span => Span,
                              Scrutinee => VarE (Tail_B, Span),
                              Alts => NAlts));
                        end;
                     else
                        Rest := Go (I + 1, Tail_B);
                     end if;

                     if not Head_Direct
                       and then HN.Kind /= Wild_P
                     then
                        Rest := Match_One (Head_B, Head_P, Rest, Fail);
                     end if;

                     Binders.Append (Head_B);
                     Binders.Append (Tail_B);
                     Alts.Append (M.Add (Core.Alt_Node'
                       (Kind => Core.Con_Alt, Span => Span,
                        Alt_Body => Rest,
                        A_Con => Core.Real_DataCon_Id (Env.Cons_DC),
                        Binders => Binders)));
                     Alts.Append (M.Add (Core.Alt_Node'
                       (Kind => Core.Default_Alt, Span => Span,
                        Alt_Body => Fresh_Ref (Fail))));
                     return M.Add (Core.Expr_Node'
                       (Kind => Core.Case_C, Span => Span,
                        Scrutinee => VarE (S, Span), Alts => Alts));
                  end Go;
               begin
                  return Go (1, Scrut);
               end;
            when Rec_P =>
               declare
                  R : constant Resolution :=
                    Res.Pat_Res (Positive (Pat));
               begin
                  if R.Kind /= Data_Res then
                     return Inner;
                  end if;
                  --  A newtype's record spelling is just as
                  --  irrefutable as its positional one: R { f = p }
                  --  must not force the wrapper either, and R {}
                  --  binds nothing at all.
                  if Is_Newtype_Con (R.Con) then
                     if N.Rec_Fields.Is_Empty then
                        --  `N{..}` (M148) binds the one field.
                        if Res.Wild_Pat.Contains (Positive (Pat))
                          and then not Res.Wild_Pat.Element
                                         (Positive (Pat)).Is_Empty
                        then
                           return Let1
                             (Core.Real_Var_Id
                                (Res.Wild_Pat.Element
                                   (Positive (Pat)).First_Element.Var),
                              Newtype_Projection (R.Con), Inner, Span);
                        end if;
                        return Inner;
                     end if;
                     return Newtype_Field_Match
                       (R.Con, N.Rec_Fields.First_Element.Value,
                        Inner, Fail);
                  end if;
                  --  Positional expansion: mentioned fields in place,
                  --  wildcards elsewhere.
                  declare
                     Info : constant Core.DataCon_Info :=
                       M.Info (R.Con);
                     Binders : Core.Var_Id_Vectors.Vector;
                     Pairs   : Pair_Vectors.Vector;
                     Alts    : Core.Alt_Id_Vectors.Vector;
                  begin
                     --  Every argument position: `C {}` on a
                     --  positional constructor has no field names
                     --  (M148 review: the arity came out 0).
                     for FI in 1 .. Info.Arity loop
                        declare
                           B : Core.Real_Var_Id := Fresh ("$f", Span);
                           Matched : Boolean := False;
                           Named : constant Boolean :=
                             FI <= Info.Field_Names.Last_Index;
                        begin
                           --  RecordWildCards (M148): a `..` field binds
                           --  its variable directly.
                           if Res.Wild_Pat.Contains (Positive (Pat)) then
                              for W of Res.Wild_Pat.Element (Positive (Pat))
                              loop
                                 if Named
                                   and then W.Field
                                     = Info.Field_Names.Element (FI)
                                 then
                                    B := Core.Real_Var_Id (W.Var);
                                 end if;
                              end loop;
                           end if;
                           for F of N.Rec_Fields loop
                              if Named
                                and then F.Field.Name
                                  = Info.Field_Names.Element (FI)
                              then
                                 declare
                                    PN : constant Pat_Node :=
                                      Arena.Node (F.Value);
                                    PR : constant Resolution :=
                                      Res.Pat_Res (Positive (F.Value));
                                 begin
                                    if PN.Kind = Var_P
                                      and then PR.Kind = Var_Res
                                    then
                                       B := PR.Var;
                                    else
                                       Pairs.Append
                                         (Pair'(Scrut => B,
                                                Pat => Syntax.Pat_Id
                                                         (F.Value)));
                                    end if;
                                    Matched := True;
                                 end;
                              end if;
                           end loop;
                           pragma Unreferenced (Matched);
                           Binders.Append (B);
                        end;
                     end loop;
                     Alts.Append (M.Add (Core.Alt_Node'
                       (Kind => Core.Con_Alt, Span => Span,
                        Alt_Body => Match_Seq (Pairs, Inner, Fail),
                        A_Con => R.Con, Binders => Binders)));
                     Alts.Append (M.Add (Core.Alt_Node'
                       (Kind => Core.Default_Alt, Span => Span,
                        Alt_Body => Fresh_Ref (Fail))));
                     return M.Add (Core.Expr_Node'
                       (Kind => Core.Case_C, Span => Span,
                        Scrutinee => VarE (Scrut, Span),
                        Alts => Alts));
                  end;
               end;
            when Con_Chain_P =>
               return Inner;   --  removed by fixity resolution
         end case;
      end Match_One;

      ------------------------------------------------------------------
      --  Right-hand sides: guards fall through to Fail
      ------------------------------------------------------------------

      function Ds_Rhs
        (R : Syntax.Rhs;
         Where_Ds : Syntax.Decl_Id_Vectors.Vector;
         Fail : Core.Real_Expr_Id;
         Span : Diagnostics.Source_Span) return Core.Real_Expr_Id
      is
         Result : Core.Real_Expr_Id;
      begin
         if R.Guarded then
            --  Report 3.13: each alternative is a qualifier chain; a
            --  failing qualifier falls through to the next
            --  alternative. The fall-through continuation is Let-bound
            --  per alternative so multiple qualifiers can reference it
            --  without duplicating code (fresh Var node per use).
            Result := Fresh_Ref (Fail);
            for I in reverse 1 .. R.Guards.Last_Index loop
               declare
                  G : constant Syntax.Guarded_Rhs := R.Guards (I);
                  GK : constant Core.Real_Var_Id :=
                    Fresh ("$gk", Span);
                  Acc : Core.Real_Expr_Id := Ds_Expr (G.G_Body);
                  Single_Bool : Boolean := False;
               begin
                  if Natural (G.Quals.Length) = 1 then
                     declare
                        QN : constant Stmt_Node :=
                          Arena.Node (G.Quals (1));
                     begin
                        Single_Bool := QN.Kind = Syntax.Expr_S;
                        if Single_Bool then
                           Result := Bool_Case
                             (Ds_Expr (QN.Expr), Acc, Result, Span);
                        end if;
                     end;
                  end if;
                  if not Single_Bool then
                     for QI in reverse 1 .. G.Quals.Last_Index loop
                        declare
                           QN : constant Stmt_Node :=
                             Arena.Node (G.Quals (QI));
                        begin
                           case QN.Kind is
                              when Syntax.Expr_S =>
                                 Acc := Bool_Case
                                   (Ds_Expr (QN.Expr), Acc,
                                    Fresh_Ref (VarE (GK, Span)),
                                    Span);
                              when Bind_S =>
                                 declare
                                    Scrut : constant Core.Real_Var_Id
                                      := Fresh ("$pg", Span);
                                    Rhs : constant Core.Real_Expr_Id :=
                                      Ds_Expr (QN.Bind_Expr);
                                    Matched : constant Core.Real_Expr_Id
                                      := Match_One
                                           (Scrut, QN.Bind_Pat, Acc,
                                            Fresh_Ref (VarE (GK, Span)));
                                 begin
                                    Acc := Let1
                                      (Scrut, Rhs, Matched, Span);
                                 end;
                              when Let_S =>
                                 declare
                                    Binds : Core.Bind_Vectors.Vector;
                                    Forces : Core.Var_Id_Vectors.Vector;
                                 begin
                                    Ds_Group (QN.Let_Binds, Binds, Forces);
                                    if not Binds.Is_Empty then
                                       declare
                                          Forced : constant
                                            Core.Real_Expr_Id :=
                                              Force_All (Forces, Acc, Span);
                                       begin
                                          Acc := M.Add
                                            (Core.Expr_Node'
                                               (Kind => Core.Let_C,
                                                Span => Span,
                                                Is_Rec => True,
                                                Binds => Binds,
                                                Let_Body => Forced));
                                       end;
                                    end if;
                                 end;
                           end case;
                        end;
                     end loop;
                     Result := Let1 (GK, Result, Acc, Span);
                  end if;
               end;
            end loop;
         else
            Result := Ds_Expr (R.Plain);
         end if;

         if not Where_Ds.Is_Empty then
            declare
               Binds : Core.Bind_Vectors.Vector;
               Forces : Core.Var_Id_Vectors.Vector;
            begin
               Ds_Group (Where_Ds, Binds, Forces);
               if not Binds.Is_Empty then
                  declare
                     --  `where !x = e` forces x before the guards.
                     Forced : constant Core.Real_Expr_Id :=
                       Force_All (Forces, Result, Span);
                  begin
                     Result := M.Add (Core.Expr_Node'
                       (Kind => Core.Let_C, Span => Span, Is_Rec => True,
                        Binds => Binds, Let_Body => Forced));
                  end;
               end if;
            end;
         end if;
         return Result;
      end Ds_Rhs;

      ------------------------------------------------------------------
      --  Statements: do blocks and comprehension qualifiers
      ------------------------------------------------------------------

      function Ds_Do
        (Stmts : Syntax.Stmt_Id_Vectors.Vector; From : Positive;
         Span : Diagnostics.Source_Span) return Core.Real_Expr_Id
      is
         N : constant Stmt_Node :=
           Arena.Node (Stmts (From));
      begin
         if From = Stmts.Last_Index then
            case N.Kind is
               when Syntax.Expr_S =>
                  return Ds_Expr (N.Expr);
               when others =>
                  Bag.Add (Diagnostics.Error, Diagnostics.Parse_Error,
                           N.Span,
                           "a do block must end with an expression");
                  return Error_Call ("malformed do block", Span);
            end case;
         end if;
         case N.Kind is
            when Syntax.Expr_S =>
               declare
                  Then_Sel : constant Builtins.Var_Maps.Cursor :=
                    Env.Values.Find (Table.Intern (">>"));
                  E : constant Core.Real_Expr_Id := Ds_Expr (N.Expr);
                  Rest : constant Core.Real_Expr_Id :=
                    Ds_Do (Stmts, From + 1, Span);
               begin
                  return App2
                    (Global (Core.Var_Id
                       (Builtins.Var_Maps.Element (Then_Sel)), Span),
                     E, Rest, Span);
               end;
            when Bind_S =>
               declare
                  Rest : constant Core.Real_Expr_Id :=
                    Ds_Do (Stmts, From + 1, Span);
                  PN : constant Pat_Node := Arena.Node (N.Bind_Pat);
                  PR : constant Resolution :=
                    Res.Pat_Res (Positive (N.Bind_Pat));
                  K : Core.Real_Expr_Id;
               begin
                  if PN.Kind = Var_P and then PR.Kind = Var_Res then
                     K := Lam (PR.Var, Rest, Span);
                  else
                     declare
                        X : constant Core.Real_Var_Id :=
                          Fresh ("$b", Span);
                        FV : constant Core.Real_Var_Id :=
                          Fresh ("$fail", Span);
                        --  An unfailable pattern gets an unreachable,
                        --  UNCONSTRAINED continuation (see Unfailable).
                        Fail_E : constant Core.Real_Expr_Id :=
                          (if Unfailable (Pat_Id (N.Bind_Pat))
                           then Error_Call
                             ("unreachable: irrefutable do bind", Span)
                           else App1 (Global (Env.Fail_V, Span),
                                      Str_Lit (Do_Fail_Text (N.Bind_Pat),
                                               Span),
                                      Span));
                        Saved : constant Diagnostics.Source_Span :=
                          Match_Context;
                        Saved_Have : constant Boolean := Have_Context;
                     begin
                        --  Match_One's contract: Fail must be a
                        --  VARIABLE reference to a join point, so
                        --  each failure position embeds a fresh Var
                        --  node (tree invariant). Passing the fail
                        --  CALL directly shared its `fail` node
                        --  between nested failure positions and the
                        --  evidence rewriter applied the dictionary
                        --  twice.
                        --  A lazy pattern inside reports the statement
                        --  (M149 review).
                        Match_Context :=
                          (Start => Ext_P (N.Bind_Pat).Start,
                           Stop => Ext_E (N.Bind_Expr,
                                          Arena.Node (N.Bind_Expr).Span).Stop);
                        Have_Context := True;
                        declare
                           Fv_Ref : constant Core.Real_Expr_Id :=
                             VarE (FV, Span);
                           Matched : constant Core.Real_Expr_Id :=
                             Match_One (X, N.Bind_Pat, Rest, Fv_Ref);
                           Bound : constant Core.Real_Expr_Id :=
                             Let1 (FV, Fail_E, Matched, Span);
                        begin
                           K := Lam (X, Bound, Span);
                        end;
                        Match_Context := Saved;
                        Have_Context := Saved_Have;
                     end;
                  end if;
                  return App2 (Global (Env.Bind_V, Span),
                               Ds_Expr (N.Bind_Expr), K, Span);
               end;
            when Let_S =>
               declare
                  Binds : Core.Bind_Vectors.Vector;
                  Forces : Core.Var_Id_Vectors.Vector;
                  Rest : constant Core.Real_Expr_Id :=
                    Ds_Do (Stmts, From + 1, Span);
               begin
                  Ds_Group (N.Let_Binds, Binds, Forces);
                  if Binds.Is_Empty then
                     return Rest;
                  end if;
                  declare
                     Forced : constant Core.Real_Expr_Id :=
                       Force_All (Forces, Rest, Span);
                  begin
                     return M.Add (Core.Expr_Node'
                       (Kind => Core.Let_C, Span => Span, Is_Rec => True,
                        Binds => Binds, Let_Body => Forced));
                  end;
               end;
         end case;
      end Ds_Do;

      --  Report 3.11 comprehension translation.
      function Ds_Comp
        (Quals : Syntax.Stmt_Id_Vectors.Vector; From : Natural;
         Head : Real_Expr_Id;
         Span : Diagnostics.Source_Span) return Core.Real_Expr_Id
      is
      begin
         if From > Quals.Last_Index then
            return Cons (Ds_Expr (Head), Nil (Span), Span);
         end if;
         declare
            N : constant Stmt_Node := Arena.Node (Quals (From));
         begin
            case N.Kind is
               when Syntax.Expr_S =>
                  --  Boolean guard.
                  declare
                     G : constant Core.Real_Expr_Id := Ds_Expr (N.Expr);
                     Rest : constant Core.Real_Expr_Id :=
                       Ds_Comp (Quals, From + 1, Head, Span);
                  begin
                     return Bool_Case (G, Rest, Nil (Span), Span);
                  end;
               when Bind_S =>
                  declare
                     Rest : constant Core.Real_Expr_Id :=
                       Ds_Comp (Quals, From + 1, Head, Span);
                     PN : constant Pat_Node :=
                       Arena.Node (N.Bind_Pat);
                     PR : constant Resolution :=
                       Res.Pat_Res (Positive (N.Bind_Pat));
                     F : Core.Real_Expr_Id;
                  begin
                     if PN.Kind = Var_P and then PR.Kind = Var_Res then
                        F := Lam (PR.Var, Rest, Span);
                     else
                        declare
                           X : constant Core.Real_Var_Id :=
                             Fresh ("$c", Span);
                        begin
                           F := Lam
                             (X,
                              Match_One (X, N.Bind_Pat, Rest,
                                         Nil (Span)),
                              Span);
                        end;
                     end if;
                     return App2 (Global (Env.Concat_Map_V, Span), F,
                                  Ds_Expr (N.Bind_Expr), Span);
                  end;
               when Let_S =>
                  declare
                     Binds : Core.Bind_Vectors.Vector;
                     Forces : Core.Var_Id_Vectors.Vector;
                     Rest : constant Core.Real_Expr_Id :=
                       Ds_Comp (Quals, From + 1, Head, Span);
                  begin
                     Ds_Group (N.Let_Binds, Binds, Forces);
                     if Binds.Is_Empty then
                        return Rest;
                     end if;
                     declare
                        Forced : constant Core.Real_Expr_Id :=
                          Force_All (Forces, Rest, Span);
                     begin
                        return M.Add (Core.Expr_Node'
                          (Kind => Core.Let_C, Span => Span,
                           Is_Rec => True, Binds => Binds,
                           Let_Body => Forced));
                     end;
                  end;
            end case;
         end;
      end Ds_Comp;

      ------------------------------------------------------------------
      --  Expressions
      ------------------------------------------------------------------

      function Ds_Expr (E : Real_Expr_Id) return Core.Real_Expr_Id is
         N : constant Expr_Node := Arena.Node (E);
         Span : constant Diagnostics.Source_Span := N.Span;
      begin
         case N.Kind is
            when Var_E | Left_Section_E | Right_Section_E =>
               --  Sections use their own resolution slot for the op.
               declare
                  R : constant Resolution :=
                    Res.Expr_Res (Positive (E));
                  Op_E : Core.Real_Expr_Id;
               begin
                  case R.Kind is
                     when Var_Res =>
                        --  GHC locates a left section `(e op)` at the
                        --  section's start, named "an operator section"
                        --  (M149 review); a right section at its operator.
                        Op_E := Located_Ref
                          (R.Var, Op_Span (N, Span),
                           (if N.Kind = Left_Section_E
                            then "an operator section" else ""));
                     when Data_Res =>
                        Op_E := ConE (R.Con, Span);
                     when Unresolved =>
                        return Error_Call ("unresolved name", Span);
                  end case;
                  case N.Kind is
                     when Var_E =>
                        return Op_E;
                     when Left_Section_E =>
                        --  (e op) = \x -> e op x
                        declare
                           X : constant Core.Real_Var_Id :=
                             Fresh ("$x", Span);
                        begin
                           return Lam
                             (X,
                              App2 (Op_E, Ds_Expr (N.Sec_Expr),
                                    VarE (X, Span), Span),
                              Span);
                        end;
                     when others =>
                        --  (op e) = let y = e in \x -> x op y
                        declare
                           X : constant Core.Real_Var_Id :=
                             Fresh ("$x", Span);
                           Y : constant Core.Real_Var_Id :=
                             Fresh ("$y", Span);
                        begin
                           return Let1
                             (Y, Ds_Expr (N.Sec_Expr),
                              Lam (X,
                                   App2 (Op_E, VarE (X, Span),
                                         VarE (Y, Span), Span),
                                   Span),
                              Span);
                        end;
                  end case;
               end;

            when Con_E =>
               declare
                  R : constant Resolution :=
                    Res.Expr_Res (Positive (E));
               begin
                  if R.Kind = Data_Res then
                     return ConE (R.Con, Span);
                  end if;
                  return Error_Call ("unresolved constructor", Span);
               end;

            when Lit_Int_E =>
               return App1
                 (Global (Env.From_Integer_V, Span),
                  M.Add (Core.Expr_Node'
                    (Kind => Core.Lit_C, Span => Span,
                     Lit => (Core.L_Int, N.Text))), Span);
            when Lit_Float_E =>
               return App1
                 (Global (Env.From_Rational_V, Span),
                  M.Add (Core.Expr_Node'
                    (Kind => Core.Lit_C, Span => Span,
                     Lit => (Core.L_Float, N.Text))), Span);
            when Lit_Char_E =>
               return M.Add (Core.Expr_Node'
                 (Kind => Core.Lit_C, Span => Span,
                  Lit => (Kind => Core.L_Char, Code => N.Char_Value)));
            when Lit_String_E =>
               --  OverloadedStrings (unconditional): the literal is
               --  IsString a => a, like numeric literals. Literal
               --  PATTERNS stay [Char] (Lit_Test below).
               return App1
                 (Global (Env.From_String_V, Span),
                  M.Add (Core.Expr_Node'
                    (Kind => Core.Lit_C, Span => Span,
                     Lit => (Core.L_String, N.Text))), Span);

            when App_E =>
               --  Ada leaves the order of actuals unspecified (RM
               --  6.4(10)) and both mint fresh variables: desugar left
               --  to right in named constants, or the Core numbering
               --  depends on the optimisation level.
               declare
                  F : constant Core.Real_Expr_Id := Ds_Expr (N.Fun);
                  A : constant Core.Real_Expr_Id := Ds_Expr (N.Arg);
               begin
                  return App1 (F, A, Span);
               end;

            when Op_Chain_E =>
               return Error_Call ("unresolved operator chain", Span);

            when Neg_E =>
               return App1 (Global (Env.Negate_V, Span),
                            Ds_Expr (N.Negated), Span);

            when Lambda_E =>
               --  \p1 p2 -> e: fresh binders + matching; a plain var
               --  pattern becomes the binder directly.
               declare
                  L_Span : constant Diagnostics.Source_Span :=
                    Ext_E (E, Span);
                  --  \case and \cases are a lambda over a case on the
                  --  parser's binders: GHC names and spans them whole.
                  Is_LC : constant Boolean :=
                    LC_Kind_Of (N) /= "" and then Note_LC (N, L_Span);
                  pragma Unreferenced (Is_LC);
                  Body_E : Core.Real_Expr_Id := Ds_Expr (N.L_Body);
                  Saved : constant Diagnostics.Source_Span := Match_Context;
                  Saved_Have : constant Boolean := Have_Context;
               begin
                  Match_Context := L_Span;
                  Have_Context := True;
                  for I in reverse 1 .. N.L_Pats.Last_Index loop
                     declare
                        P : constant Real_Pat_Id := N.L_Pats (I);
                        PN : constant Pat_Node := Arena.Node (P);
                        PR : constant Resolution :=
                          Res.Pat_Res (Positive (P));
                     begin
                        if PN.Kind = Var_P and then PR.Kind = Var_Res
                        then
                           Body_E := Lam (PR.Var, Body_E, Span);
                        else
                           declare
                              X : constant Core.Real_Var_Id :=
                                Fresh ("$l", Span);
                              --  One failure per pattern, holding the
                              --  argument that failed (M149).
                              Fail_E : constant Core.Real_Expr_Id :=
                                Fail_Match ("lambda", L_Span, VarE (X, Span),
                                            "lambda pattern match failed",
                                            Handled => Handled_Of_One (P),
                                            Schema => Pat_Schema (P));
                           begin
                              Body_E := Lam
                                (X,
                                 Match_One (X, P, Body_E, Fail_E),
                                 Span);
                           end;
                        end if;
                     end;
                  end loop;
                  Match_Context := Saved;
                  Have_Context := Saved_Have;
                  return Body_E;
               end;

            when Let_E =>
               declare
                  Binds : Core.Bind_Vectors.Vector;
                  Forces : Core.Var_Id_Vectors.Vector;
                  Body_E : constant Core.Real_Expr_Id :=
                    Ds_Expr (N.Let_Body);
               begin
                  Ds_Group (N.Binds, Binds, Forces);
                  if Binds.Is_Empty then
                     return Body_E;
                  end if;
                  declare
                     Forced : constant Core.Real_Expr_Id :=
                       Force_All (Forces, Body_E, Span);
                  begin
                     return M.Add (Core.Expr_Node'
                       (Kind => Core.Let_C, Span => Span, Is_Rec => True,
                        Binds => Binds, Let_Body => Forced));
                  end;
               end;

            when If_E =>
               declare
                  C : constant Core.Real_Expr_Id := Ds_Expr (N.Cond);
                  T : constant Core.Real_Expr_Id := Ds_Expr (N.Then_E);
                  E : constant Core.Real_Expr_Id := Ds_Expr (N.Else_E);
               begin
                  return Bool_Case (C, T, E, Span);
               end;

            when Case_E =>
               if N.Alts.Is_Empty then
                  --  EmptyCase (M148): force the scrutinee; if it ever
                  --  returns, the case has no alternative for it.
                  declare
                     Seq_C : constant Builtins.Var_Maps.Cursor :=
                       Env.Values.Find (Table.Intern ("seq"));
                     Scrut : constant Core.Real_Expr_Id :=
                       Ds_Expr (N.Scrutinee);
                     Unit_V : constant Core.Real_Expr_Id :=
                       ConE (Core.Real_DataCon_Id (Env.Unit_DC), Span);
                     Err : constant Core.Real_Expr_Id :=
                       Fail_Match (Case_Kind (E), Case_Span (E, Span), Unit_V,
                                   "empty case");
                  begin
                     return App2
                       (Global (Core.Var_Id
                          (Builtins.Var_Maps.Element (Seq_C)), Span),
                        Scrut, Err, Span);
                  end;
               end if;
               declare
                  S : constant Core.Real_Var_Id := Fresh ("$s", Span);
                  Fail_V : constant Core.Real_Var_Id :=
                    Fresh ("$fail", Span);
                  Result : Core.Real_Expr_Id :=
                    VarE (Fail_V, Span);
               begin
                  if Warn_Matches then
                     declare
                        Rows : Exhaustive.Row_Vectors.Vector;
                     begin
                        for I in 1 .. N.Alts.Last_Index loop
                           declare
                              A : constant Alt_Node :=
                                Arena.Node (N.Alts (I));
                              Ps : Syntax.Pat_Id_Vectors.Vector;
                           begin
                              Ps.Append (A.Pat);
                              Rows.Append
                                (Exhaustive.Row_Rec'
                                   (Pats => Ps,
                                    Total =>
                                      Rhs_Total (A.Alt_Rhs),
                                    Span => A.Span));
                           end;
                        end loop;
                        Exhaustive.Check_Match
                          (Arena, Res, Table, Bag, M, Env, Rows,
                           "case expression", Span);
                     end;
                  end if;
                  --  A lazy pattern in an alternative reports the whole
                  --  case (M149 review).
                  declare
                     Case_Ctx_Saved : constant Diagnostics.Source_Span :=
                       Match_Context;
                     Case_Ctx_Have : constant Boolean := Have_Context;
                  begin
                  Match_Context := Case_Span (E, Span);
                  Have_Context := True;
                  for I in reverse 1 .. N.Alts.Last_Index loop
                     declare
                        A : constant Alt_Node :=
                          Arena.Node (N.Alts (I));
                        FV : constant Core.Real_Var_Id :=
                          Fresh ("$fail", Span);
                        Body_E : constant Core.Real_Expr_Id :=
                          Ds_Rhs (A.Alt_Rhs, A.Where_Ds,
                                  VarE (FV, Span), A.Span);
                     begin
                        Result := Let1
                          (FV, Result,
                           Match_One (S, A.Pat, Body_E,
                                      VarE (FV, Span)),
                           A.Span);
                     end;
                  end loop;
                  Match_Context := Case_Ctx_Saved;
                  Have_Context := Case_Ctx_Have;
                  end;
                  --  One node-minting call per statement (M149 review:
                  --  the actuals' order is unspecified, and Core ids
                  --  then differ between release and validation).
                  declare
                     Fail_E : constant Core.Real_Expr_Id :=
                       (if Is_Multi_Way_If (N)
                        then Fail_Match
                          ("multi-way if", Ext_E (E, Span), VarE (S, Span),
                           "non-exhaustive guards in multi-way if",
                           Headline => "no guard is true",
                           Ghc_Text =>
                             (if Sites.Enabled (Ctx)
                              then Sites.Ghc_Span (Ctx, Ext_E (E, Span))
                                   & ": Non-exhaustive guards in "
                                   & "multi-way if" & ASCII.LF
                              else ""))
                        else Fail_Match
                          (Case_Kind (E), Case_Span (E, Span),
                           VarE (S, Span),
                           "non-exhaustive case",
                           Handled => Alts_Handled (N.Alts),
                           Schema => Alts_Schema (N.Alts)));
                     Inner : constant Core.Real_Expr_Id :=
                       Let1 (Fail_V, Fail_E, Result, Span);
                     Scrut_E : constant Core.Real_Expr_Id :=
                       Ds_Expr (N.Scrutinee);
                  begin
                     return Let1 (S, Scrut_E, Inner, Span);
                  end;
               end;

            when Do_E =>
               return Ds_Do (N.Stmts, 1, Span);

            when Tuple_E =>
               declare
                  Count : constant Natural := Natural (N.Items.Length);
                  Result : Core.Real_Expr_Id :=
                    ConE (Core.Real_DataCon_Id (Env.Tuple_DCs (Count)),
                          Span);
               begin
                  for E2 of N.Items loop
                     Result := App1 (Result, Ds_Expr (E2), Span);
                  end loop;
                  return Result;
               end;

            when List_E =>
               declare
                  Result : Core.Real_Expr_Id := Nil (Span);
               begin
                  for I in reverse 1 .. N.Items.Last_Index loop
                     Result := Cons (Ds_Expr (N.Items (I)), Result,
                                     Span);
                  end loop;
                  return Result;
               end;

            when Arith_Seq_E =>
               declare
                  Has_Then : constant Boolean := N.Seq_Then /= No_Expr;
                  Has_To   : constant Boolean := N.Seq_To /= No_Expr;
                  F : constant Core.Var_Id :=
                    (if Has_Then and Has_To then Env.Enum_From_Then_To_V
                     elsif Has_Then then Env.Enum_From_Then_V
                     elsif Has_To then Env.Enum_From_To_V
                     else Env.Enum_From_V);
                  Result : Core.Real_Expr_Id :=
                    App1 (Global (F, Span), Ds_Expr (N.Seq_From), Span);
               begin
                  if Has_Then then
                     Result := App1
                       (Result,
                        Ds_Expr (Real_Expr_Id (N.Seq_Then)), Span);
                  end if;
                  if Has_To then
                     Result := App1
                       (Result, Ds_Expr (Real_Expr_Id (N.Seq_To)),
                        Span);
                  end if;
                  return Result;
               end;

            when List_Comp_E =>
               return Ds_Comp (N.Comp_Quals, 1, N.Comp_Expr, Span);

            when Sig_E =>
               --  e :: T  ==  let $ann = e in $ann, with T as $ann's
               --  ordinary signature.
               declare
                  V : constant Core.Real_Var_Id :=
                    Fresh ("$ann", Span);
                  C : constant Kinds.Anno_Maps.Cursor :=
                    Annos.Find (Syntax.Type_Id (N.Sig_Type));
               begin
                  if Kinds.Anno_Maps.Has_Element (C) then
                     Sigs.Include (V, Kinds.Anno_Maps.Element (C));
                  end if;
                  return Let1 (V, Ds_Expr (N.Sig_Expr),
                               VarE (V, Span), Span);
               end;

            when Rec_Con_E =>
               declare
                  Base : constant Expr_Node := Arena.Node (N.Rec_Base);
                  BR : constant Resolution :=
                    Res.Expr_Res (Positive (N.Rec_Base));
                  pragma Unreferenced (Base);
               begin
                  if BR.Kind /= Data_Res then
                     return Error_Call
                       ("record construction needs a constructor",
                        Span);
                  end if;
                  declare
                     Info : constant Core.DataCon_Info :=
                       M.Info (BR.Con);
                     Result : Core.Real_Expr_Id := ConE (BR.Con, Span);
                  begin
                     --  Every argument position (`C {}` on a
                     --  positional constructor, Report 3.15.2).
                     for FI in 1 .. Info.Arity loop
                        declare
                           Named : constant Boolean :=
                             FI <= Info.Field_Names.Last_Index;
                           Unit_V : constant Core.Real_Expr_Id :=
                             ConE (Core.Real_DataCon_Id (Env.Unit_DC), Span);
                           --  GHC: "SPAN: Missing field in record
                           --  construction FIELD", no trailing newline.
                           Arg : Core.Real_Expr_Id :=
                             Fail_Match
                               ("", Ext_E (E, Span), Unit_V,
                                "missing field in record construction",
                                Ghc_Text =>
                                  (if not Sites.Enabled (Ctx) then ""
                                   elsif Named
                                   then Sites.Ghc_Span (Ctx, Ext_E (E, Span))
                                        & ": Missing field in record "
                                        & "construction "
                                        & Table.Text
                                            (Names.Real_Name_Id
                                               (Info.Field_Names.Element
                                                  (FI)))
                                        & ASCII.LF
                                   else Sites.Ghc_Span (Ctx, Ext_E (E, Span))
                                        & ": Missing field in record "
                                        & "construction" & ASCII.LF));
                        begin
                           for F of N.Rec_Fields loop
                              if Named
                                and then F.Field.Name
                                  = Info.Field_Names.Element (FI)
                              then
                                 Arg := Ds_Expr (F.Value);
                              end if;
                           end loop;
                           --  RecordWildCards (M148): a `..` field reads
                           --  its variable.
                           if Named
                             and then Res.Wild_Expr.Contains (Positive (E))
                           then
                              for W of Res.Wild_Expr.Element (Positive (E))
                              loop
                                 if W.Field = Info.Field_Names.Element (FI)
                                 then
                                    Arg := VarE (Core.Real_Var_Id (W.Var), Span);
                                 end if;
                              end loop;
                           end if;
                           Result := App1 (Result, Arg, Span);
                        end;
                     end loop;
                     return Result;
                  end;
               end;

            when Rec_Update_E =>
               --  r { f = e }: one alternative per constructor that
               --  has every updated field - by SELECTOR identity, as
               --  the renamer resolved them, so a same-named field of
               --  another module's type never joins the case (M75).
               declare
                  R_V : constant Core.Real_Var_Id := Fresh ("$r", Span);
                  Alts : Core.Alt_Id_Vectors.Vector;
                  Sels : constant Core.Var_Id_Vectors.Vector :=
                    (if Res.Field_Res.Contains (Positive (E))
                     then Res.Field_Res (Positive (E))
                     else Core.Var_Id_Vectors.Empty_Vector);

                  function Has_All_Fields
                    (Info : Core.DataCon_Info) return Boolean is
                  begin
                     for S of Sels loop
                        if not Info.Field_Sels.Contains (S) then
                           return False;
                        end if;
                     end loop;
                     return not Info.Field_Sels.Is_Empty;
                  end Has_All_Fields;
               begin
                  for DC in 1 .. M.Last_DataCon loop
                     declare
                        Info : constant Core.DataCon_Info :=
                          M.Info (Core.Real_DataCon_Id (DC));
                     begin
                        if Has_All_Fields (Info) then
                           declare
                              Binders : Core.Var_Id_Vectors.Vector;
                              Rebuild : Core.Real_Expr_Id :=
                                ConE (Core.Real_DataCon_Id (DC), Span);
                           begin
                              for FI in
                                1 .. Info.Field_Names.Last_Index
                              loop
                                 Binders.Append (Fresh ("$u", Span));
                              end loop;
                              for FI in
                                1 .. Info.Field_Names.Last_Index
                              loop
                                 declare
                                    Arg : Core.Real_Expr_Id :=
                                      VarE (Binders (FI), Span);
                                 begin
                                    for K in 1 .. Sels.Last_Index loop
                                       if Sels (K) =
                                          Info.Field_Sels.Element (FI)
                                       then
                                          Arg := Ds_Expr
                                            (N.Rec_Fields (K).Value);
                                       end if;
                                    end loop;
                                    Rebuild := App1 (Rebuild, Arg,
                                                     Span);
                                 end;
                              end loop;
                              Alts.Append (M.Add (Core.Alt_Node'
                                (Kind => Core.Con_Alt, Span => Span,
                                 Alt_Body => Rebuild,
                                 A_Con => Core.Real_DataCon_Id (DC),
                                 Binders => Binders)));
                           end;
                        end if;
                     end;
                  end loop;
                  Alts.Append (M.Add (Core.Alt_Node'
                    (Kind => Core.Default_Alt, Span => Span,
                     Alt_Body =>
                       Fail_Match ("record update", Ext_E (E, Span),
                                   VarE (R_V, Span),
                                   "record update failed"))));
                  return Let1
                    (R_V, Ds_Expr (N.Rec_Base),
                     M.Add (Core.Expr_Node'
                       (Kind => Core.Case_C, Span => Span,
                        Scrutinee => VarE (R_V, Span), Alts => Alts)),
                     Span);
               end;
         end case;
      end Ds_Expr;

      ------------------------------------------------------------------
      --  Binding groups
      ------------------------------------------------------------------

      --  One function unit (1+ equations) becomes \a1..an -> matches.
      function Ds_Fun_Unit
        (U : Binding_Unit) return Core.Real_Expr_Id
      is
         Span : constant Diagnostics.Source_Span := U.Span;
         --  GHC's span for the function's failure: the first equation's
         --  start to the last one's end (M149).
         F_Span : constant Diagnostics.Source_Span :=
           (Start => Ext_D (U.Equations.First_Element).Start,
            Stop => Ext_D (U.Equations.Last_Element).Stop);
         Args : Core.Var_Id_Vectors.Vector;
         Fun_Ctx_Saved : constant Diagnostics.Source_Span := Match_Context;
         Fun_Ctx_Have : constant Boolean := Have_Context;
         Fail_V : constant Core.Real_Var_Id := Fresh ("$fail", Span);
         Result : Core.Real_Expr_Id;
      begin
         if Warn_Matches and then U.Arity > 0 then
            declare
               Rows : Exhaustive.Row_Vectors.Vector;
            begin
               for EI in 1 .. U.Equations.Last_Index loop
                  declare
                     N : constant Decl_Node :=
                       Arena.Node (U.Equations (EI));
                  begin
                     Rows.Append
                       (Exhaustive.Row_Rec'
                          (Pats => N.Fun_Pats,
                           Total => Rhs_Total (N.Fun_Rhs),
                           Span => N.Span));
                  end;
               end loop;
               Exhaustive.Check_Match
                 (Arena, Res, Table, Bag, M, Env, Rows,
                  "function '"
                  & Table.Text (Names.Real_Name_Id (U.Name)) & "'",
                  Span);
            end;
         end if;

         --  If the single equation has all-variable patterns, use them
         --  directly as lambda binders (the common case reads well).
         if Natural (U.Equations.Length) = 1 then
            declare
               N : constant Decl_Node :=
                 Arena.Node (U.Equations.Element (1));
               All_Vars : Boolean := True;
            begin
               for P of N.Fun_Pats loop
                  if Arena.Node (P).Kind /= Var_P then
                     All_Vars := False;
                  end if;
               end loop;
               if All_Vars then
                  declare
                     --  All-variable equation whose guards all fail:
                     --  GHC reports it as the function's failure.
                     Arg_Vars : Core.Var_Id_Vectors.Vector;
                     Body_E : Core.Real_Expr_Id;
                  begin
                     for P of N.Fun_Pats loop
                        Arg_Vars.Append
                          (Core.Var_Id (Res.Pat_Res (Positive (P)).Var));
                     end loop;
                     Body_E :=
                       Ds_Rhs (N.Fun_Rhs, N.Fun_Where,
                               Fail_Match
                                 ("function " & Table.Text (U.Name), F_Span,
                                  Args_Value (Arg_Vars, Span),
                                  "non-exhaustive guards",
                                  --  the arguments matched; a guard failed
                                  Headline => "no guard is true"),
                               Span);
                     for I in reverse 1 .. N.Fun_Pats.Last_Index loop
                        declare
                           PR : constant Resolution :=
                             Res.Pat_Res
                               (Positive (N.Fun_Pats.Element (I)));
                        begin
                           Body_E := Lam (PR.Var, Body_E, Span);
                        end;
                     end loop;
                     return Body_E;
                  end;
               end if;
            end;
         end if;

         for I in 1 .. U.Arity loop
            Args.Append (Fresh ("$a", Span));
         end loop;

         --  A lazy pattern in an equation reports the whole function
         --  (M149 review).
         Match_Context := F_Span;
         Have_Context := True;
         Result := VarE (Fail_V, Span);
         for EI in reverse 1 .. U.Equations.Last_Index loop
            declare
               N : constant Decl_Node :=
                 Arena.Node (U.Equations (EI));
               FV : constant Core.Real_Var_Id := Fresh ("$k", Span);
               Pairs : Pair_Vectors.Vector;
               Body_E : constant Core.Real_Expr_Id :=
                 Ds_Rhs (N.Fun_Rhs, N.Fun_Where, VarE (FV, Span),
                         N.Span);
            begin
               for I in 1 .. N.Fun_Pats.Last_Index loop
                  Pairs.Append
                    (Pair'(Scrut => Args (I),
                           Pat => Syntax.Pat_Id (N.Fun_Pats.Element (I))));
               end loop;
               Result := Let1
                 (FV, Result,
                  Match_Seq (Pairs, Body_E, VarE (FV, Span)),
                  N.Span);
            end;
         end loop;
         Match_Context := Fun_Ctx_Saved;
         Have_Context := Fun_Ctx_Have;

         Result := Let1
           (Fail_V,
            Fail_Match ("function " & Table.Text (U.Name), F_Span,
                        Args_Value (Args, Span),
                        "non-exhaustive patterns in function",
                        Handled => Unit_Handled (U),
                        Schema => Unit_Schema (U)),
            Result, Span);

         for I in reverse 1 .. Natural (Args.Length) loop
            Result := Lam (Args (I), Result, Span);
         end loop;
         return Result;
      end Ds_Fun_Unit;

      procedure Ds_Group
        (Decls  : Syntax.Decl_Id_Vectors.Vector;
         Into   : in out Core.Bind_Vectors.Vector;
         Forces : in out Core.Var_Id_Vectors.Vector)
      is
         Units : constant Unit_Vectors.Vector :=
           Rename.Group (Arena, Decls, Bag);
      begin
         Group_Depth := Group_Depth + 1;
         for U of Units loop
            --  The enclosing top-level binding of every site inside
            --  (M149).
            if Group_Depth = 1 then
               Current_Top := To_Unbounded_String
                 (if U.Kind = Fun_Unit then Table.Text (U.Name)
                  elsif Sites.Enabled (Ctx)
                  then Pat_Text (Arena.Node (U.Equations.Element (1)).Span)
                  else "");
            end if;
            case U.Kind is
               when Fun_Unit =>
                  declare
                     V : constant Core.Var_Id :=
                       Res.Decl_Var (Positive (U.Equations.Element (1)));
                  begin
                     if V /= Core.No_Var then
                        Into.Append
                          (Core.Bind_Pair'
                             (Binder => Core.Real_Var_Id (V),
                              Rhs => Ds_Fun_Unit (U)));
                     end if;
                  end;
               when Pat_Unit =>
                  declare
                     D : constant Real_Decl_Id := U.Equations.Element (1);
                     N : constant Decl_Node := Arena.Node (D);
                     Span : constant Diagnostics.Source_Span := N.Span;
                     PN : constant Pat_Node := Arena.Node (N.Pat);
                     PR : constant Resolution :=
                       Res.Pat_Res (Positive (N.Pat));
                     --  `!p = e` (M150): a strict binding. BN/BR are
                     --  the pattern under the bang (PN/PR otherwise).
                     Strict : constant Boolean := PN.Kind = Bang_P;
                     BN : constant Pat_Node :=
                       (if Strict then Arena.Node (PN.Bang_Pat) else PN);
                     BR : constant Resolution :=
                       (if Strict then Res.Pat_Res (Positive (PN.Bang_Pat))
                        else PR);
                     Unit_V : constant Core.Real_Expr_Id :=
                       ConE (Core.Real_DataCon_Id (Env.Unit_DC), Span);
                     --  Guards that all fail (M149 review): GHC calls a
                     --  variable binding a function, a pattern binding
                     --  a pattern binding.
                     Guard_Fail : constant Core.Real_Expr_Id :=
                       (if PN.Kind = Var_P
                        then Fail_Match
                               ("function " & Table.Text (PN.Var), Ext_D (D),
                                Unit_V, "non-exhaustive guards")
                        else Fail_Match
                               ("", Ext_D (D), Unit_V, "non-exhaustive guards",
                                Ghc_Text =>
                                  (if Sites.Enabled (Ctx)
                                   then Sites.Ghc_Span (Ctx, Ext_D (D))
                                        & ": Non-exhaustive guards in pattern"
                                        & " binding" & ASCII.LF
                                   else "")));
                     RHS_E : constant Core.Real_Expr_Id :=
                       Ds_Rhs (N.Pat_Rhs, N.Pat_Where, Guard_Fail, Span);
                  begin
                     if BN.Kind = Var_P and then BR.Kind = Var_Res then
                        --  x = e directly; `!x = e` also forces x.
                        M.Vars (BR.Var).From_Pattern_Binding := True;
                        Into.Append
                          (Core.Bind_Pair'(Binder => BR.Var,
                                           Rhs => RHS_E));
                        if Strict then
                           Forces.Append (Core.Var_Id (BR.Var));
                        end if;
                     else
                        --  Selector translation (Report 4.4.3.2).
                        declare
                           PB : constant Core.Real_Var_Id :=
                             Fresh ("$pb", Span);
                           Vars : Core.Var_Id_Vectors.Vector;
                        begin
                           M.Vars (PB).From_Pattern_Binding := True;
                           Into.Append
                             (Core.Bind_Pair'(Binder => PB,
                                              Rhs => RHS_E));
                           Bound_Vars (N.Pat, Vars);
                           for V of Vars loop
                              M.Vars (V).From_Pattern_Binding := True;
                           end loop;
                           declare
                              --  A lazy pattern inside reports the
                              --  binding (M149 review).
                              Saved : constant Diagnostics.Source_Span :=
                                Match_Context;
                              Saved_Have : constant Boolean := Have_Context;
                           begin
                              Match_Context := Ext_D (D);
                              Have_Context := True;
                              for V of Vars loop
                                 declare
                                    --  One node-minting call per
                                    --  statement (actuals' order is
                                    --  unspecified).
                                    PB_Ref : constant Core.Real_Expr_Id :=
                                      VarE (PB, Span);
                                    --  GHC: the binding's span, the
                                    --  pattern's text (M149).
                                    Fail : constant Core.Real_Expr_Id :=
                                      Fail_Match
                                        (Pat_Text (Ext_P (Unbanged (N.Pat))),
                                         Ext_D (D), PB_Ref,
                                         "irrefutable pattern failed",
                                         Handled => Handled_Of_One (N.Pat),
                                         Schema => Pat_Schema (N.Pat));
                                    V_Ref : constant Core.Real_Expr_Id :=
                                      VarE (V, Span);
                                    Sel : constant Core.Real_Expr_Id :=
                                      Match_One (PB, N.Pat, V_Ref, Fail);
                                 begin
                                    Into.Append
                                      (Core.Bind_Pair'
                                         (Binder => V, Rhs => Sel));
                                 end;
                              end loop;
                              if Strict then
                                 --  `!p = e`: $bm = case $pb of !p -> ()
                                 --  forces e and matches p when the
                                 --  body forces $bm (GHC's translation).
                                 declare
                                    BM : constant Core.Real_Var_Id :=
                                      Fresh ("$bm", Span);
                                    PB_Ref : constant Core.Real_Expr_Id :=
                                      VarE (PB, Span);
                                    Fail : constant Core.Real_Expr_Id :=
                                      Fail_Match
                                        (Pat_Text (Ext_P (Unbanged (N.Pat))),
                                         Ext_D (D), PB_Ref,
                                         "irrefutable pattern failed",
                                         Handled => Handled_Of_One (N.Pat),
                                         Schema => Pat_Schema (N.Pat));
                                    Unit_R : constant Core.Real_Expr_Id :=
                                      ConE (Core.Real_DataCon_Id
                                              (Env.Unit_DC), Span);
                                    Check : constant Core.Real_Expr_Id :=
                                      Match_One (PB, N.Pat, Unit_R, Fail);
                                 begin
                                    Into.Append
                                      (Core.Bind_Pair'
                                         (Binder => BM, Rhs => Check));
                                    Forces.Append (Core.Var_Id (BM));
                                 end;
                              end if;
                              Match_Context := Saved;
                              Have_Context := Saved_Have;
                           end;
                        end;
                     end if;
                  end;
            end case;
         end loop;
         --  GHC's order for forcing a group's strict bindings (M150
         --  review): a binding after the strict ones it depends on,
         --  independent ones in reverse source order - what its
         --  dependency analysis yields (`let !a = ..; !b = .. a ..`
         --  forces a then b in either source order; three independent
         --  ones force the last first). Dependencies go through the
         --  group's other bindings too.
         if Natural (Forces.Length) > 1 then
            declare
               N : constant Natural := Natural (Forces.Length);

               --  E mentions V, directly or through a binding of Into.
               function Mentions
                 (E : Core.Real_Expr_Id; V : Core.Var_Id; Depth : Natural)
                  return Boolean
               is
                  Node : constant Core.Expr_Node := M.Node (E);
               begin
                  if Depth > 200 then
                     return False;
                  end if;
                  case Node.Kind is
                     when Core.Var_C =>
                        if Core.Var_Id (Node.V) = V then
                           return True;
                        end if;
                        for B of Into loop
                           if Core.Var_Id (B.Binder) = Core.Var_Id (Node.V)
                             and then Core.Var_Id (B.Binder) /= V
                             and then not Forces.Contains
                               (Core.Var_Id (B.Binder))
                           then
                              return Mentions (B.Rhs, V, Depth + 1);
                           end if;
                        end loop;
                        return False;
                     when Core.App_C =>
                        return Mentions (Node.Fun, V, Depth + 1)
                          or else Mentions (Node.Arg, V, Depth + 1);
                     when Core.Lam_C =>
                        return Mentions (Node.Lam_Body, V, Depth + 1);
                     when Core.Let_C =>
                        for B of Node.Binds loop
                           if Mentions (B.Rhs, V, Depth + 1) then
                              return True;
                           end if;
                        end loop;
                        return Mentions (Node.Let_Body, V, Depth + 1);
                     when Core.Case_C =>
                        if Mentions (Node.Scrutinee, V, Depth + 1) then
                           return True;
                        end if;
                        for A of Node.Alts loop
                           if Mentions (M.Node (A).Alt_Body, V, Depth + 1)
                           then
                              return True;
                           end if;
                        end loop;
                        return False;
                     when others =>
                        return False;
                  end case;
               end Mentions;

               function Rhs_Of (V : Core.Var_Id) return Core.Real_Expr_Id is
               begin
                  for B of Into loop
                     if Core.Var_Id (B.Binder) = V then
                        return B.Rhs;
                     end if;
                  end loop;
                  return Core.Real_Expr_Id'First;
               end Rhs_Of;

               Placed : array (1 .. N) of Boolean := [others => False];
               Sorted : Core.Var_Id_Vectors.Vector;
            begin
               for Round in 1 .. N loop
                  pragma Warnings (Off, Round);
                  declare
                     Pick : Natural := 0;
                  begin
                     for I in reverse 1 .. N loop
                        if not Placed (I) then
                           declare
                              Ready : Boolean := True;
                              R : constant Core.Real_Expr_Id :=
                                Rhs_Of (Forces (I));
                           begin
                              for J in 1 .. N loop
                                 if J /= I and then not Placed (J)
                                   and then Mentions (R, Forces (J), 0)
                                 then
                                    Ready := False;
                                 end if;
                              end loop;
                              if Ready then
                                 Pick := I;
                                 exit;
                              end if;
                           end;
                        end if;
                     end loop;
                     if Pick = 0 then
                        --  a cycle: the latest unplaced one
                        for I in reverse 1 .. N loop
                           if not Placed (I) then
                              Pick := I;
                              exit;
                           end if;
                        end loop;
                     end if;
                     Placed (Pick) := True;
                     Sorted.Append (Forces (Pick));
                  end;
               end loop;
               Forces := Sorted;
            end;
         end if;
         Group_Depth := Group_Depth - 1;
      end Ds_Group;

      --  A group whose bindings cannot be strict: the module's top
      --  level (the renamer rejects a bang there) and instance and
      --  class bodies.
      procedure Ds_Group
        (Decls : Syntax.Decl_Id_Vectors.Vector;
         Into  : in out Core.Bind_Vectors.Vector)
      is
         Ignored : Core.Var_Id_Vectors.Vector;
      begin
         Ds_Group (Decls, Into, Ignored);
      end Ds_Group;

      ------------------------------------------------------------------
      --  Module level
      ------------------------------------------------------------------

      procedure Ds_Method_Bodies
        (Decls : Syntax.Decl_Id_Vectors.Vector;
         Into  : in out Core.Bind_Vectors.Vector)
      is
         Value_Decls : Syntax.Decl_Id_Vectors.Vector;
      begin
         for D of Decls loop
            if Arena.Node (D).Kind in Fun_D | Pat_D then
               Value_Decls.Append (D);
            end if;
         end loop;
         Ds_Group (Value_Decls, Into);
      end Ds_Method_Bodies;

      ------------------------------------------------------------------
      --  Foreign imports: derive the marshalling spec from the
      --  binder's scheme; codegen turns each spec into a C wrapper.
      ------------------------------------------------------------------

      procedure Ds_Foreign (D : Real_Decl_Id; N : Decl_Node) is
         V : constant Core.Var_Id := Res.Decl_Var (Positive (D));

         --  The C symbol must be a plain C identifier - and not a C
         --  keyword, or the generated prototype/entry function would
         --  not compile (exporting Haskell's `double` is the classic
         --  trip-wire).
         --  Structural equality of Core types, for the wrapper-shape
         --  check ft -> IO (FunPtr ft).
         function Type_Eq (A, B : Core.Type_Id) return Boolean is
            use type Core.Type_Id;
            use type Core.Type_Kind;
         begin
            if A = B then
               return True;
            end if;
            if A = Core.No_Type or else B = Core.No_Type then
               return False;
            end if;
            declare
               NA : constant Core.Type_Node :=
                 M.Node (Core.Real_Type_Id (A));
               NB : constant Core.Type_Node :=
                 M.Node (Core.Real_Type_Id (B));
            begin
               if NA.Kind /= NB.Kind then
                  return False;
               end if;
               case NA.Kind is
                  when Core.TVar_T =>
                     return Core."=" (NA.Tv, NB.Tv);
                  when Core.TCon_T =>
                     return Core."=" (NA.Con, NB.Con);
                  when Core.TApp_T =>
                     return Type_Eq (Core.Type_Id (NA.T_Fun),
                                     Core.Type_Id (NB.T_Fun))
                       and then Type_Eq (Core.Type_Id (NA.T_Arg),
                                         Core.Type_Id (NB.T_Arg));
                  when Core.TFun_T =>
                     return Type_Eq (Core.Type_Id (NA.From),
                                     Core.Type_Id (NB.From))
                       and then Type_Eq (Core.Type_Id (NA.To),
                                         Core.Type_Id (NB.To));
                  when Core.TMeta_T =>
                     return False;
               end case;
            end;
         end Type_Eq;

         function Valid_C_Name (S : String) return Boolean is
         begin
            if S'Length = 0
              or else S (S'First) not in 'A' .. 'Z' | 'a' .. 'z' | '_'
            then
               return False;
            end if;
            for C of S loop
               if C not in 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_'
               then
                  return False;
               end if;
            end loop;
            return S not in
              "auto" | "break" | "case" | "char" | "const"
              | "continue" | "default" | "do" | "double" | "else"
              | "enum" | "extern" | "float" | "for" | "goto" | "if"
              | "inline" | "int" | "long" | "register" | "restrict"
              | "return" | "short" | "signed" | "sizeof" | "static"
              | "struct" | "switch" | "typedef" | "union"
              | "unsigned" | "void" | "volatile" | "while";
         end Valid_C_Name;

         procedure Err (Msg : String) is
         begin
            Bag.Add (Diagnostics.Error, Diagnostics.Rename_Unsupported,
                     N.Span,
                     "foreign "
                     & (if N.F_Export then "export" else "import")
                     & " '"
                     & Table.Text (Names.Real_Name_Id (N.F_Name))
                     & "': " & Msg);
         end Err;

         --  The marshallable universe: Int, Double, Char, Bool,
         --  (), String, Text, Ptr a, and the fixed-width C types.
         --  Anything else (bare tyvars included) fails; tyvars are
         --  thereby allowed only under Ptr.
         function Classify
           (T : Core.Type_Id; K : out Core.Marshal_Kind)
            return Boolean
         is
            use type Core.Type_Id;
            use type Core.TyCon_Id;
            use type Core.Type_Kind;
         begin
            K := Core.M_Unit;
            if T = Core.No_Type then
               return False;
            end if;
            declare
               TN : constant Core.Type_Node :=
                 M.Node (Core.Real_Type_Id (T));
            begin
               case TN.Kind is
                  when Core.TCon_T =>
                     if Core.TyCon_Id (TN.Con) = Env.Int_TC then
                        K := Core.M_Int;
                     elsif Core.TyCon_Id (TN.Con) = Env.Double_TC then
                        K := Core.M_Double;
                     elsif Core.TyCon_Id (TN.Con) = Env.Char_TC then
                        K := Core.M_Char;
                     elsif Core.TyCon_Id (TN.Con) = Env.Bool_TC then
                        K := Core.M_Bool;
                     elsif Core.TyCon_Id (TN.Con) = Env.Unit_TC then
                        K := Core.M_Unit;
                     elsif Core.TyCon_Id (TN.Con) = Env.Text_TC then
                        K := Core.M_Text;
                     elsif Core.TyCon_Id (TN.Con) = Env.Word_TC then
                        --  Word crosses as uint64_t, as Word64 (M150).
                        K := Core.M_U64;
                     else
                        for CK in Builtins.C_Fix_Kind loop
                           if Core.TyCon_Id (TN.Con)
                                = Env.CFix_TCs (CK)
                           then
                              K := Core.Marshal_Kind'Val
                                (Core.Marshal_Kind'Pos (Core.M_I8)
                                 + Builtins.C_Fix_Kind'Pos (CK));
                              return True;
                           end if;
                        end loop;
                        return False;
                     end if;
                     return True;
                  when Core.TApp_T =>
                     declare
                        FN : constant Core.Type_Node :=
                          M.Node (TN.T_Fun);
                     begin
                        if FN.Kind /= Core.TCon_T then
                           return False;
                        end if;
                        if Core.TyCon_Id (FN.Con) = Env.Ptr_TC
                          or else Core.TyCon_Id (FN.Con)
                                    = Env.FunPtr_TC
                        then
                           K := Core.M_Ptr;
                           return True;
                        end if;
                        if Core.TyCon_Id (FN.Con) = Env.List_TC then
                           declare
                              AN : constant Core.Type_Node :=
                                M.Node (TN.T_Arg);
                           begin
                              if AN.Kind = Core.TCon_T
                                and then Core.TyCon_Id (AN.Con)
                                           = Env.Char_TC
                              then
                                 K := Core.M_String;
                                 return True;
                              end if;
                           end;
                        end if;
                        return False;
                     end;
                  when others =>
                     return False;
               end case;
            end;
         end Classify;

      begin
         if Core."=" (V, Core.No_Var) then
            return;   --  rename already failed
         end if;
         declare
            use Kinds.Sig_Maps;
            C : constant Kinds.Sig_Maps.Cursor :=
              Sigs.Find (Core.Real_Var_Id (V));
         begin
            if not Has_Element (C) then
               return;   --  kind error already reported
            end if;
            declare
               use type Core.Type_Kind;
               Sch : constant Core.Scheme :=
                 M.Node (Core.Real_Scheme_Id (Element (C)));
               F : Core.Foreign_Import;
               T : Core.Type_Id := Sch.S_Body;
            begin
               --  "wrapper" imports: Haskell closure -> C function
               --  pointer, shape ft -> IO (FunPtr ft).
               if not N.F_Export
                 and then Table.Text (Names.Real_Name_Id (N.F_CName))
                            = "dynamic"
               then
                  Err ("dynamic imports are not supported");
                  return;
               end if;
               if not N.F_Export
                 and then Table.Text (Names.Real_Name_Id (N.F_CName))
                            = "wrapper"
               then
                  if not Sch.Context.Is_Empty then
                     Err ("a foreign declaration may not have a "
                          & "class context");
                     return;
                  end if;
                  declare
                     Bad_Shape : constant String :=
                       "a wrapper import must have type "
                       & "ft -> IO (FunPtr ft)";
                     TN : constant Core.Type_Node :=
                       M.Node (Core.Real_Type_Id (T));
                  begin
                     if TN.Kind /= Core.TFun_T then
                        Err (Bad_Shape);
                        return;
                     end if;
                     declare
                        FT : constant Core.Type_Id :=
                          Core.Type_Id (TN.From);
                        RN : constant Core.Type_Node :=
                          M.Node (TN.To);
                     begin
                        --  Result: IO (FunPtr ft).
                        if RN.Kind /= Core.TApp_T
                          or else M.Node (RN.T_Fun).Kind
                                    /= Core.TCon_T
                          or else Core."/="
                            (Core.TyCon_Id
                               (M.Node (RN.T_Fun).Con), Env.IO_TC)
                          or else M.Node (RN.T_Arg).Kind
                                    /= Core.TApp_T
                          or else M.Node
                                    (M.Node (RN.T_Arg).T_Fun).Kind
                                    /= Core.TCon_T
                          or else Core."/="
                            (Core.TyCon_Id
                               (M.Node
                                  (M.Node (RN.T_Arg).T_Fun).Con),
                             Env.FunPtr_TC)
                          or else not Type_Eq
                            (FT,
                             Core.Type_Id
                               (M.Node (RN.T_Arg).T_Arg))
                        then
                           Err (Bad_Shape);
                           return;
                        end if;
                        --  Derive the callback's own C signature
                        --  from ft.
                        F.Binder := Core.Real_Var_Id (V);
                        F.C_Name := N.F_CName;
                        F.Span := N.Span;
                        F.Is_Wrapper := True;
                        F.Res := Core.M_Ptr;
                        F.Res_IO := True;
                        declare
                           CT : Core.Type_Id := FT;
                        begin
                           loop
                              declare
                                 CN : constant Core.Type_Node :=
                                   M.Node (Core.Real_Type_Id (CT));
                              begin
                                 exit when CN.Kind /= Core.TFun_T;
                                 declare
                                    K : Core.Marshal_Kind;
                                 begin
                                    if not Classify
                                        (Core.Type_Id (CN.From), K)
                                      or else Core."="
                                        (K, Core.M_Unit)
                                    then
                                       Err ("callback argument type "
                                            & "is not marshallable "
                                            & "across the FFI");
                                       return;
                                    end if;
                                    F.CB_Args.Append (K);
                                 end;
                                 CT := Core.Type_Id (CN.To);
                              end;
                           end loop;
                           declare
                              CN : constant Core.Type_Node :=
                                M.Node (Core.Real_Type_Id (CT));
                           begin
                              if CN.Kind = Core.TApp_T
                                and then M.Node (CN.T_Fun).Kind
                                           = Core.TCon_T
                                and then Core."="
                                  (Core.TyCon_Id
                                     (M.Node (CN.T_Fun).Con),
                                   Env.IO_TC)
                              then
                                 F.CB_Res_IO := True;
                                 CT := Core.Type_Id (CN.T_Arg);
                              end if;
                           end;
                           declare
                              K : Core.Marshal_Kind;
                           begin
                              if not Classify (CT, K) then
                                 Err ("callback result type is not "
                                      & "marshallable across the "
                                      & "FFI");
                                 return;
                              end if;
                              F.CB_Res := K;
                           end;
                        end;
                        M.Foreigns.Append (F);
                        return;
                     end;
                  end;
               end if;

               if not Valid_C_Name
                        (Table.Text (Names.Real_Name_Id (N.F_CName)))
               then
                  Err ("'"
                       & Table.Text (Names.Real_Name_Id (N.F_CName))
                       & "' is not a usable C identifier (name the "
                       & "C symbol explicitly: foreign "
                       & (if N.F_Export then "export" else "import")
                       & " ccall ""c_name"" ...)");
                  return;
               end if;
               if not Sch.Context.Is_Empty then
                  Err ("a foreign declaration may not have a class "
                       & "context");
                  return;
               end if;
               F.Binder := Core.Real_Var_Id (V);
               F.C_Name := N.F_CName;
               F.Span := N.Span;

               --  Arguments along the function spine.
               loop
                  declare
                     TN : constant Core.Type_Node :=
                       M.Node (Core.Real_Type_Id (T));
                  begin
                     exit when TN.Kind /= Core.TFun_T;
                     declare
                        K : Core.Marshal_Kind;
                     begin
                        if not Classify (Core.Type_Id (TN.From), K)
                          or else Core."=" (K, Core.M_Unit)
                        then
                           Err ("argument type is not marshallable "
                                & "across the FFI");
                           return;
                        end if;
                        F.Args.Append (K);
                     end;
                     T := Core.Type_Id (TN.To);
                  end;
               end loop;

               --  Result, possibly under IO.
               declare
                  TN : constant Core.Type_Node :=
                    M.Node (Core.Real_Type_Id (T));
               begin
                  if TN.Kind = Core.TApp_T then
                     declare
                        FN : constant Core.Type_Node :=
                          M.Node (TN.T_Fun);
                     begin
                        if FN.Kind = Core.TCon_T
                          and then Core."="
                            (Core.TyCon_Id (FN.Con), Env.IO_TC)
                        then
                           F.Res_IO := True;
                           T := Core.Type_Id (TN.T_Arg);
                        end if;
                     end;
                  end if;
               end;
               declare
                  K : Core.Marshal_Kind;
               begin
                  if not Classify (T, K) then
                     Err ("result type is not marshallable across "
                          & "the FFI");
                     return;
                  end if;
                  F.Res := K;
               end;
               if N.F_Export then
                  M.Foreign_Exports.Append (F);
               else
                  M.Foreigns.Append (F);
               end if;
            end;
         end;
      end Ds_Foreign;

   begin
      for D of Arena.Top_Decls loop
         declare
            N : constant Decl_Node := Arena.Node (D);
         begin
            case N.Kind is
               when Fun_D | Pat_D =>
                  --  Handled through grouping below.
                  null;
               when Class_D =>
                  declare
                     Cl : constant Core.Class_Id :=
                       Res.Decl_Class (Positive (D));
                     Binds : Core.Bind_Vectors.Vector;
                  begin
                     if Core."/=" (Cl, Core.No_Class) then
                        Ds_Method_Bodies (N.C_Decls, Binds);
                        M.Classes (Core.Real_Class_Id (Cl))
                          .Default_Binds := Binds;
                        --  Mark defaults on the methods, so the
                        --  missing-implementation warning knows a
                        --  source-class default fills the slot
                        --  (wired classes set this in Def_Method).
                        for B of Binds loop
                           for Mth of M.Classes
                             (Core.Real_Class_Id (Cl)).Methods
                           loop
                              if Names."="
                                (Mth.Name, M.Info (B.Binder).Name)
                              then
                                 Mth.Has_Default := True;
                              end if;
                           end loop;
                        end loop;
                     end if;
                  end;
               when Instance_D =>
                  declare
                     Binds : Core.Bind_Vectors.Vector;
                  begin
                     Ds_Method_Bodies (N.I_Decls, Binds);
                     --  Attach to the Instance_Info the renamer minted
                     --  for THIS declaration - by identity: spans are
                     --  per-file offsets, and matching them overwrote a
                     --  Prelude instance's methods with another
                     --  module's (M142).
                     declare
                        I : constant Core.Instance_Id :=
                          Res.Decl_Inst.Element (Positive (D));
                     begin
                        if Core."/=" (I, 0) then
                           M.Instances (Core.Real_Instance_Id (I)).Method_Binds := Binds;
                        end if;
                     end;
                  end;
               when Foreign_D =>
                  Ds_Foreign (D, N);
               when others =>
                  null;
            end case;
         end;
      end loop;

      --  Top-level value bindings: one Top_Bind group per unit.
      declare
         Binds : Core.Bind_Vectors.Vector;
      begin
         Ds_Group (Arena.Top_Decls, Binds);
         for B of Binds loop
            declare
               G : Core.Top_Bind;
            begin
               G.Is_Rec := True;
               G.Binds.Append (B);
               M.Top_Binds.Append (G);
            end;
         end loop;
      end;

      --  Predicate-refinement bodies (stage 2): each pending pair
      --  from kind checking becomes an ordinary top-level binding
      --  `$pred = <predicate>`. Appended after every user group, so
      --  any function the predicate calls is already generalized
      --  when the typechecker reaches it.
      for P of Preds loop
         declare
            G : Core.Top_Bind;
         begin
            G.Is_Rec := False;
            G.Binds.Append
              (Core.Bind_Pair'
                 (Binder => P.Binder,
                  Rhs => Ds_Expr (Syntax.Real_Expr_Id (P.Expr))));
            M.Top_Binds.Append (G);
         end;
      end loop;

      --  Field selector bodies (Report 3.15.1): for every record
      --  field F, `F = \r -> case r of { K .. bF .. -> bF; ... }`
      --  with one alternative per constructor carrying the field.
      --  Kinds minted the selector variables and schemes; only the
      --  bodies are owed. Selectors already bound (a previous run
      --  over this shared module) are skipped.
      declare
         Done : Var_Sets.Set;
      begin
         for G of M.Top_Binds loop
            for B of G.Binds loop
               Done.Include (B.Binder);
            end loop;
         end loop;
         for DC in 1 .. M.Last_DataCon loop
            declare
               Info : constant Core.DataCon_Info :=
                 M.Info (Core.Real_DataCon_Id (DC));
            begin
               for FI in 1 .. Info.Field_Sels.Last_Index loop
                  declare
                     Span : constant Diagnostics.Source_Span :=
                       (Start => 1, Stop => 1);
                  begin
                     if not Done.Contains (Info.Field_Sels (FI)) then
                        declare
                           Sel : constant Core.Real_Var_Id :=
                             Info.Field_Sels (FI);
                           R_V : constant Core.Real_Var_Id :=
                             Fresh ("$r", Span);
                           Alts : Core.Alt_Id_Vectors.Vector;
                           G : Core.Top_Bind;
                        begin
                           --  One alternative per constructor that
                           --  carries this SELECTOR - its own type's
                           --  constructors, never a same-named field
                           --  of another module's type (M75).
                           for DC2 in 1 .. M.Last_DataCon loop
                              declare
                                 I2 : constant Core.DataCon_Info :=
                                   M.Info
                                     (Core.Real_DataCon_Id (DC2));
                              begin
                                 for FJ in
                                   1 .. I2.Field_Sels.Last_Index
                                 loop
                                    if I2.Field_Sels (FJ) = Sel then
                                       declare
                                          Bs : Core.Var_Id_Vectors
                                                 .Vector;
                                       begin
                                          for K in
                                            1 .. I2.Field_Names
                                                   .Last_Index
                                          loop
                                             Bs.Append
                                               (Fresh ("$f", Span));
                                          end loop;
                                          Alts.Append (M.Add
                                            (Core.Alt_Node'
                                             (Kind => Core.Con_Alt,
                                              Span => Span,
                                              A_Con =>
                                                Core.Real_DataCon_Id
                                                  (DC2),
                                              Binders => Bs,
                                              Alt_Body =>
                                                VarE (Bs (FJ),
                                                      Span))));
                                       end;
                                    end if;
                                 end loop;
                              end;
                           end loop;
                           Alts.Append (M.Add (Core.Alt_Node'
                             (Kind => Core.Default_Alt, Span => Span,
                              Alt_Body => Error_Call
                                ("No match in record selector "
                                 & Table.Text
                                     (Names.Real_Name_Id
                                        (Info.Field_Names.Element (FI))),
                                 Span))));
                           G.Is_Rec := False;
                           G.Binds.Append (Core.Bind_Pair'
                             (Binder => Sel,
                              Rhs => Lam (R_V,
                                M.Add (Core.Expr_Node'
                                  (Kind => Core.Case_C, Span => Span,
                                   Scrutinee => VarE (R_V, Span),
                                   Alts => Alts)), Span)));
                           M.Top_Binds.Append (G);
                           Done.Include (Sel);
                        end;
                     end if;
                  end;
               end loop;
            end;
         end loop;
      end;
   end Desugar_Module;

end AHC.Desugar;
