with Ada.Containers.Vectors;

with Ada.Containers.Hashed_Sets;

with AHC.Exhaustive;

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
      Warn_Matches : Boolean := False)
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

      function Fresh
        (Prefix : String; Span : Diagnostics.Source_Span)
         return Core.Real_Var_Id
      is (M.Mint_Var ((Name => Table.Intern (Prefix), Span => Span,
                       Is_Global => False, others => <>)));

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

      function Str_Lit
        (S : String; Span : Diagnostics.Source_Span)
         return Core.Real_Expr_Id
      is (M.Add (Core.Expr_Node'
           (Kind => Core.Lit_C, Span => Span,
            Lit => (Kind => Core.L_String,
                    Text => Names.Name_Id (Table.Intern (S))))));

      function Error_Call
        (Msg : String; Span : Diagnostics.Source_Span)
         return Core.Real_Expr_Id
      is (App1 (Global (Env.Error_V, Span), Str_Lit (Msg, Span), Span));

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

      procedure Ds_Group
        (Decls : Syntax.Decl_Id_Vectors.Vector;
         Into  : in out Core.Bind_Vectors.Vector);

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
            when Rec_P =>
               for F of N.Rec_Fields loop
                  Bound_Vars (F.Value, Into);
               end loop;
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
               Sel : constant Core.Real_Expr_Id := Match_One
                 (Scrut, Pat, VarE (V, Span),
                  Error_Call ("irrefutable pattern failed", Span));
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

         function Con_Match
           (DC : Core.Real_DataCon_Id;
            Sub_Pats : Syntax.Pat_Id_Vectors.Vector)
            return Core.Real_Expr_Id
         is
            Binders : Core.Var_Id_Vectors.Vector;
            Pairs   : Pair_Vectors.Vector;
            Alts    : Core.Alt_Id_Vectors.Vector;
         begin
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
                  --  Positional expansion: mentioned fields in place,
                  --  wildcards elsewhere.
                  declare
                     Info : constant Core.DataCon_Info :=
                       M.Info (R.Con);
                     Binders : Core.Var_Id_Vectors.Vector;
                     Pairs   : Pair_Vectors.Vector;
                     Alts    : Core.Alt_Id_Vectors.Vector;
                  begin
                     for FI in 1 .. Info.Field_Names.Last_Index loop
                        declare
                           B : Core.Real_Var_Id := Fresh ("$f", Span);
                           Matched : Boolean := False;
                        begin
                           for F of N.Rec_Fields loop
                              if F.Field.Name = Info.Field_Names (FI)
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
                                 begin
                                    Acc := Let1
                                      (Scrut,
                                       Ds_Expr (QN.Bind_Expr),
                                       Match_One
                                         (Scrut,
                                          QN.Bind_Pat,
                                          Acc,
                                          Fresh_Ref
                                            (VarE (GK, Span))),
                                       Span);
                                 end;
                              when Let_S =>
                                 declare
                                    Binds : Core.Bind_Vectors.Vector;
                                 begin
                                    Ds_Group (QN.Let_Binds, Binds);
                                    if not Binds.Is_Empty then
                                       Acc := M.Add
                                         (Core.Expr_Node'
                                            (Kind => Core.Let_C,
                                             Span => Span,
                                             Is_Rec => True,
                                             Binds => Binds,
                                             Let_Body => Acc));
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
            begin
               Ds_Group (Where_Ds, Binds);
               if not Binds.Is_Empty then
                  Result := M.Add (Core.Expr_Node'
                    (Kind => Core.Let_C, Span => Span, Is_Rec => True,
                     Binds => Binds, Let_Body => Result));
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
               begin
                  return App2
                    (Global (Core.Var_Id
                       (Builtins.Var_Maps.Element (Then_Sel)), Span),
                     Ds_Expr (N.Expr),
                     Ds_Do (Stmts, From + 1, Span), Span);
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
                        Fail_E : constant Core.Real_Expr_Id :=
                          App1 (Global (Env.Fail_V, Span),
                                Str_Lit ("pattern match failure in"
                                         & " do block", Span), Span);
                     begin
                        --  Match_One's contract: Fail must be a
                        --  VARIABLE reference to a join point, so
                        --  each failure position embeds a fresh Var
                        --  node (tree invariant). Passing the fail
                        --  CALL directly shared its `fail` node
                        --  between nested failure positions and the
                        --  evidence rewriter applied the dictionary
                        --  twice.
                        K := Lam (X,
                                  Let1 (FV, Fail_E,
                                        Match_One
                                          (X, N.Bind_Pat, Rest,
                                           VarE (FV, Span)),
                                        Span),
                                  Span);
                     end;
                  end if;
                  return App2 (Global (Env.Bind_V, Span),
                               Ds_Expr (N.Bind_Expr), K, Span);
               end;
            when Let_S =>
               declare
                  Binds : Core.Bind_Vectors.Vector;
                  Rest : constant Core.Real_Expr_Id :=
                    Ds_Do (Stmts, From + 1, Span);
               begin
                  Ds_Group (N.Let_Binds, Binds);
                  if Binds.Is_Empty then
                     return Rest;
                  end if;
                  return M.Add (Core.Expr_Node'
                    (Kind => Core.Let_C, Span => Span, Is_Rec => True,
                     Binds => Binds, Let_Body => Rest));
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
                  return Bool_Case
                    (Ds_Expr (N.Expr),
                     Ds_Comp (Quals, From + 1, Head, Span),
                     Nil (Span), Span);
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
                     Rest : constant Core.Real_Expr_Id :=
                       Ds_Comp (Quals, From + 1, Head, Span);
                  begin
                     Ds_Group (N.Let_Binds, Binds);
                     if Binds.Is_Empty then
                        return Rest;
                     end if;
                     return M.Add (Core.Expr_Node'
                       (Kind => Core.Let_C, Span => Span,
                        Is_Rec => True, Binds => Binds,
                        Let_Body => Rest));
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
                        Op_E := VarE (R.Var, Span);
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
               return M.Add (Core.Expr_Node'
                 (Kind => Core.Lit_C, Span => Span,
                  Lit => (Core.L_String, N.Text)));

            when App_E =>
               return App1 (Ds_Expr (N.Fun), Ds_Expr (N.Arg), Span);

            when Op_Chain_E =>
               return Error_Call ("unresolved operator chain", Span);

            when Neg_E =>
               return App1 (Global (Env.Negate_V, Span),
                            Ds_Expr (N.Negated), Span);

            when Lambda_E =>
               --  \p1 p2 -> e: fresh binders + matching; a plain var
               --  pattern becomes the binder directly.
               declare
                  Body_E : Core.Real_Expr_Id := Ds_Expr (N.L_Body);
                  Fail_E : constant Core.Real_Expr_Id :=
                    Error_Call ("lambda pattern match failed", Span);
               begin
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
                           begin
                              Body_E := Lam
                                (X,
                                 Match_One (X, P, Body_E, Fail_E),
                                 Span);
                           end;
                        end if;
                     end;
                  end loop;
                  return Body_E;
               end;

            when Let_E =>
               declare
                  Binds : Core.Bind_Vectors.Vector;
                  Body_E : constant Core.Real_Expr_Id :=
                    Ds_Expr (N.Let_Body);
               begin
                  Ds_Group (N.Binds, Binds);
                  if Binds.Is_Empty then
                     return Body_E;
                  end if;
                  return M.Add (Core.Expr_Node'
                    (Kind => Core.Let_C, Span => Span, Is_Rec => True,
                     Binds => Binds, Let_Body => Body_E));
               end;

            when If_E =>
               return Bool_Case (Ds_Expr (N.Cond), Ds_Expr (N.Then_E),
                                 Ds_Expr (N.Else_E), Span);

            when Case_E =>
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
                  return Let1
                    (S, Ds_Expr (N.Scrutinee),
                     Let1 (Fail_V,
                           Error_Call ("non-exhaustive case", Span),
                           Result, Span),
                     Span);
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
                     for FI in 1 .. Info.Field_Names.Last_Index loop
                        declare
                           Arg : Core.Real_Expr_Id :=
                             Error_Call
                               ("missing field in record construction",
                                Span);
                        begin
                           for F of N.Rec_Fields loop
                              if F.Field.Name = Info.Field_Names (FI)
                              then
                                 Arg := Ds_Expr (F.Value);
                              end if;
                           end loop;
                           Result := App1 (Result, Arg, Span);
                        end;
                     end loop;
                     return Result;
                  end;
               end;

            when Rec_Update_E =>
               --  r { f = e }: one alternative per constructor that
               --  has every updated field.
               declare
                  R_V : constant Core.Real_Var_Id := Fresh ("$r", Span);
                  Alts : Core.Alt_Id_Vectors.Vector;

                  function Has_All_Fields
                    (Info : Core.DataCon_Info) return Boolean is
                  begin
                     for F of N.Rec_Fields loop
                        declare
                           Found : Boolean := False;
                        begin
                           for FN of Info.Field_Names loop
                              if FN = F.Field.Name then
                                 Found := True;
                              end if;
                           end loop;
                           if not Found then
                              return False;
                           end if;
                        end;
                     end loop;
                     return not Info.Field_Names.Is_Empty;
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
                                    for F of N.Rec_Fields loop
                                       if F.Field.Name =
                                          Info.Field_Names (FI)
                                       then
                                          Arg := Ds_Expr (F.Value);
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
                       Error_Call ("record update failed", Span))));
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
         Args : Core.Var_Id_Vectors.Vector;
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
                 Arena.Node (U.Equations (1));
               All_Vars : Boolean := True;
            begin
               for P of N.Fun_Pats loop
                  if Arena.Node (P).Kind /= Var_P then
                     All_Vars := False;
                  end if;
               end loop;
               if All_Vars then
                  declare
                     Body_E : Core.Real_Expr_Id :=
                       Ds_Rhs (N.Fun_Rhs, N.Fun_Where,
                               Error_Call
                                 ("non-exhaustive guards", Span),
                               Span);
                  begin
                     for I in reverse 1 .. N.Fun_Pats.Last_Index loop
                        declare
                           PR : constant Resolution :=
                             Res.Pat_Res
                               (Positive (N.Fun_Pats (I)));
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
                           Pat => Syntax.Pat_Id (N.Fun_Pats (I))));
               end loop;
               Result := Let1
                 (FV, Result,
                  Match_Seq (Pairs, Body_E, VarE (FV, Span)),
                  N.Span);
            end;
         end loop;

         Result := Let1
           (Fail_V,
            Error_Call ("non-exhaustive patterns in function", Span),
            Result, Span);

         for I in reverse 1 .. Natural (Args.Length) loop
            Result := Lam (Args (I), Result, Span);
         end loop;
         return Result;
      end Ds_Fun_Unit;

      procedure Ds_Group
        (Decls : Syntax.Decl_Id_Vectors.Vector;
         Into  : in out Core.Bind_Vectors.Vector)
      is
         Units : constant Unit_Vectors.Vector :=
           Rename.Group (Arena, Decls, Bag);
      begin
         for U of Units loop
            case U.Kind is
               when Fun_Unit =>
                  declare
                     V : constant Core.Var_Id :=
                       Res.Decl_Var (Positive (U.Equations (1)));
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
                     D : constant Real_Decl_Id := U.Equations (1);
                     N : constant Decl_Node := Arena.Node (D);
                     Span : constant Diagnostics.Source_Span := N.Span;
                     PN : constant Pat_Node := Arena.Node (N.Pat);
                     PR : constant Resolution :=
                       Res.Pat_Res (Positive (N.Pat));
                     RHS_E : constant Core.Real_Expr_Id :=
                       Ds_Rhs (N.Pat_Rhs, N.Pat_Where,
                               Error_Call
                                 ("non-exhaustive guards", Span),
                               Span);
                  begin
                     if PN.Kind = Var_P and then PR.Kind = Var_Res then
                        --  x = e directly.
                        M.Vars (PR.Var).From_Pattern_Binding := True;
                        Into.Append
                          (Core.Bind_Pair'(Binder => PR.Var,
                                           Rhs => RHS_E));
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
                           for V of Vars loop
                              Into.Append
                                (Core.Bind_Pair'
                                   (Binder => V,
                                    Rhs => Match_One
                                      (PB, N.Pat, VarE (V, Span),
                                       Error_Call
                                         ("irrefutable pattern failed",
                                          Span))));
                           end loop;
                        end;
                     end if;
                  end;
            end case;
         end loop;
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

         procedure Err (Msg : String) is
         begin
            Bag.Add (Diagnostics.Error, Diagnostics.Rename_Unsupported,
                     N.Span,
                     "foreign import '"
                     & Table.Text (Names.Real_Name_Id (N.F_Name))
                     & "': " & Msg);
         end Err;

         --  The v1 marshallable universe: Int, Double, Char, Bool,
         --  (), String, Ptr a. Anything else (bare tyvars included)
         --  fails; tyvars are thereby allowed only under Ptr.
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
                     else
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
                        if Core.TyCon_Id (FN.Con) = Env.Ptr_TC then
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
               if not Sch.Context.Is_Empty then
                  Err ("a foreign import may not have a class "
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
               M.Foreigns.Append (F);
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
                     end if;
                  end;
               when Instance_D =>
                  declare
                     Binds : Core.Bind_Vectors.Vector;
                  begin
                     Ds_Method_Bodies (N.I_Decls, Binds);
                     --  Attach to the Instance_Info with this span.
                     for I in 1 .. M.Instances.Last_Index loop
                        if Diagnostics."="
                             (M.Instances (I).Span, N.Span)
                        then
                           M.Instances (I).Method_Binds := Binds;
                        end if;
                     end loop;
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
               for FI in 1 .. Info.Field_Names.Last_Index loop
                  declare
                     Sel_C : constant Builtins.Var_Maps.Cursor :=
                       Env.Values.Find (Info.Field_Names (FI));
                     Span : constant Diagnostics.Source_Span :=
                       (Start => 1, Stop => 1);
                  begin
                     if Builtins.Var_Maps.Has_Element (Sel_C)
                       and then not Done.Contains
                         (Builtins.Var_Maps.Element (Sel_C))
                     then
                        declare
                           Sel : constant Core.Real_Var_Id :=
                             Builtins.Var_Maps.Element (Sel_C);
                           R_V : constant Core.Real_Var_Id :=
                             Fresh ("$r", Span);
                           Alts : Core.Alt_Id_Vectors.Vector;
                           G : Core.Top_Bind;
                        begin
                           --  One alternative per constructor that
                           --  has this field (any TyCon; field names
                           --  are globally unique).
                           for DC2 in 1 .. M.Last_DataCon loop
                              declare
                                 I2 : constant Core.DataCon_Info :=
                                   M.Info
                                     (Core.Real_DataCon_Id (DC2));
                              begin
                                 for FJ in
                                   1 .. I2.Field_Names.Last_Index
                                 loop
                                    if I2.Field_Names (FJ) =
                                       Info.Field_Names (FI)
                                    then
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
                                ("no match in record selector "
                                 & Table.Text
                                     (Names.Real_Name_Id
                                        (Info.Field_Names (FI))),
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
