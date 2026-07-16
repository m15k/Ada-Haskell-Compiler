with AHC.Diagnostics;

package body AHC.Refine is

   use AHC.Core;

   procedure Insert_Checks
     (Table          : in out Names.Name_Table;
      M              : in out Core.Core_Module;
      Sigs           : Kinds.Sig_Maps.Map;
      Prims          : in out Prelude_Core.Prim_Maps.Map;
      Checks_Enabled : Boolean := True)
   is
      Check_Prim : Var_Id := No_Var;   --  minted on first use
      Pred_Prim  : Var_Id := No_Var;
      Mod_Prim   : Var_Id := No_Var;
      FRange_Prim : Var_Id := No_Var;

      function Mint_Prim
        (Name, Symbol : String; Cache : in out Var_Id)
         return Real_Var_Id is
      begin
         if Cache = No_Var then
            Cache := Var_Id
              (M.Mint_Var ((Name => Table.Intern (Name),
                            Is_Global => True, others => <>)));
            Prims.Include
              (Real_Var_Id (Cache),
               Names.Name_Id (Table.Intern (Symbol)));
         end if;
         return Real_Var_Id (Cache);
      end Mint_Prim;

      function Prim return Real_Var_Id
      is (Mint_Prim ("$checkRange", "ahc_prim_check_range",
                     Check_Prim));

      function PPrim return Real_Var_Id
      is (Mint_Prim ("$checkPred", "ahc_prim_check_pred",
                     Pred_Prim));

      function MPrim return Real_Var_Id
      is (Mint_Prim ("$wrapMod", "ahc_prim_wrap_mod", Mod_Prim));

      function FPrim return Real_Var_Id
      is (Mint_Prim ("$checkRangeD", "ahc_prim_check_range_d",
                     FRange_Prim));

      --  Whether refinement R rewrites this compilation. Range and
      --  predicate checks are contracts (skipped when checks are
      --  disabled); modular wrapping is arithmetic semantics and is
      --  always applied.
      function Active (R : Refinement_Id) return Boolean
      is (R /= No_Refinement
          and then (Checks_Enabled
                    or else M.Info (Real_Refinement_Id (R)).Kind =
                              Mod_R));

      function Refinement_Of (T : Real_Type_Id) return Refinement_Id is
         N : constant Type_Node := M.Node (T);
      begin
         if N.Kind = TCon_T then
            return N.Refine;
         end if;
         return No_Refinement;
      end Refinement_Of;

      function Decimal (V : Long_Long_Integer) return String is
         S : constant String := V'Image;
      begin
         return (if S (S'First) = ' ' then S (S'First + 1 .. S'Last)
                 else S);
      end Decimal;

      --  Range_R: check LO HI E.  Pred_R: checkPred $pred E.
      function Check_E
        (R    : Real_Refinement_Id;
         E    : Real_Expr_Id;
         Span : Diagnostics.Source_Span) return Real_Expr_Id
      is
         Info : constant Refinement_Info := M.Info (R);

         function Lit (V : Long_Long_Integer) return Real_Expr_Id
         is (M.Add (Expr_Node'
              (Kind => Lit_C, Span => Span,
               Lit => (Kind => L_Int,
                       Text => Names.Name_Id
                                 (Table.Intern (Decimal (V)))))));

         Acc : Real_Expr_Id;
      begin
         case Info.Kind is
            when Range_R =>
               Acc := M.Add (Expr_Node'(Kind => Var_C, Span => Span,
                                        V => Prim));
               Acc := M.Add (Expr_Node'(Kind => App_C, Span => Span,
                                        Fun => Acc,
                                        Arg => Lit (Info.Lo)));
               Acc := M.Add (Expr_Node'(Kind => App_C, Span => Span,
                                        Fun => Acc,
                                        Arg => Lit (Info.Hi)));
            when Pred_R =>
               Acc := M.Add (Expr_Node'(Kind => Var_C, Span => Span,
                                        V => PPrim));
               Acc := M.Add (Expr_Node'(Kind => App_C, Span => Span,
                                        Fun => Acc,
                                        Arg => M.Add (Expr_Node'
                                          (Kind => Var_C, Span => Span,
                                           V => Info.Pred_Var))));
            when Mod_R =>
               Acc := M.Add (Expr_Node'(Kind => Var_C, Span => Span,
                                        V => MPrim));
               Acc := M.Add (Expr_Node'(Kind => App_C, Span => Span,
                                        Fun => Acc,
                                        Arg => Lit (Info.Modulus)));
            when FRange_R =>
               declare
                  function FLit
                    (Neg : Boolean; Text : Names.Name_Id)
                     return Real_Expr_Id
                  is
                     Image : constant String :=
                       (if Neg then "-" else "")
                       & Table.Text (Names.Real_Name_Id (Text));
                  begin
                     return M.Add (Expr_Node'
                       (Kind => Lit_C, Span => Span,
                        Lit => (Kind => L_Float,
                                Text => Names.Name_Id
                                          (Table.Intern (Image)))));
                  end FLit;
               begin
                  Acc := M.Add (Expr_Node'(Kind => Var_C, Span => Span,
                                           V => FPrim));
                  Acc := M.Add (Expr_Node'
                    (Kind => App_C, Span => Span, Fun => Acc,
                     Arg => FLit (Info.FLo_Neg, Info.FLo_Text)));
                  Acc := M.Add (Expr_Node'
                    (Kind => App_C, Span => Span, Fun => Acc,
                     Arg => FLit (Info.FHi_Neg, Info.FHi_Text)));
               end;
         end case;
         return M.Add (Expr_Node'(Kind => App_C, Span => Span,
                                  Fun => Acc, Arg => E));
      end Check_E;

      --  Build the checked wrapper around Old_Rhs for binder V.
      function Wrap
        (V       : Real_Var_Id;
         Old_Rhs : Real_Expr_Id;
         Sch     : Scheme;
         Args    : Type_Id_Vectors.Vector;
         Result  : Real_Type_Id) return Real_Expr_Id
      is
         Span : constant Diagnostics.Source_Span := M.Info (V).Span;

         function Fresh (Name : String) return Real_Var_Id
         is (M.Mint_Var ((Name => Table.Intern (Name), Span => Span,
                          others => <>)));

         Unchecked : constant Real_Var_Id := Fresh ("$rv");
         Dicts     : Var_Id_Vectors.Vector;
         Params    : Var_Id_Vectors.Vector;
         Core_E    : Real_Expr_Id :=
           M.Add (Expr_Node'(Kind => Var_C, Span => Span,
                             V => Unchecked));
         Binds     : Bind_Vectors.Vector;
      begin
         for I in 1 .. Sch.Context.Last_Index loop
            Dicts.Append (Fresh ("$rq"));
         end loop;
         for I in 1 .. Args.Last_Index loop
            Params.Append (Fresh ("$rx"));
         end loop;

         for D of Dicts loop
            Core_E := M.Add
              (Expr_Node'(Kind => App_C, Span => Span, Fun => Core_E,
                          Arg => M.Add (Expr_Node'
                            (Kind => Var_C, Span => Span, V => D))));
         end loop;
         for I in 1 .. Args.Last_Index loop
            declare
               A : Real_Expr_Id :=
                 M.Add (Expr_Node'(Kind => Var_C, Span => Span,
                                   V => Params (I)));
               R : constant Refinement_Id := Refinement_Of (Args (I));
            begin
               if Active (R) then
                  A := Check_E (Real_Refinement_Id (R), A, Span);
               end if;
               Core_E := M.Add
                 (Expr_Node'(Kind => App_C, Span => Span,
                             Fun => Core_E, Arg => A));
            end;
         end loop;
         declare
            R : constant Refinement_Id := Refinement_Of (Result);
         begin
            if Active (R) then
               Core_E := Check_E (Real_Refinement_Id (R), Core_E, Span);
            end if;
         end;

         for I in reverse 1 .. Params.Last_Index loop
            Core_E := M.Add
              (Expr_Node'(Kind => Lam_C, Span => Span,
                          Binder => Params (I), Lam_Body => Core_E));
         end loop;
         for I in reverse 1 .. Dicts.Last_Index loop
            Core_E := M.Add
              (Expr_Node'(Kind => Lam_C, Span => Span,
                          Binder => Dicts (I), Lam_Body => Core_E));
         end loop;

         Binds.Append (Bind_Pair'(Binder => Unchecked, Rhs => Old_Rhs));
         return M.Add
           (Expr_Node'(Kind => Let_C, Span => Span, Is_Rec => False,
                       Binds => Binds, Let_Body => Core_E));
      end Wrap;

      --  Replace V's bind wherever it lives (the typechecker's wrap
      --  idiom: top-level groups, then every Let expression).
      procedure Rewrite_Bind
        (V       : Real_Var_Id;
         Sch     : Scheme;
         Args    : Type_Id_Vectors.Vector;
         Result  : Real_Type_Id)
      is
         procedure Wrap_In (Binds : in out Bind_Vectors.Vector) is
         begin
            for BI in 1 .. Binds.Last_Index loop
               if Binds (BI).Binder = V then
                  Binds.Replace_Element
                    (BI, Bind_Pair'
                       (Binder => V,
                        Rhs => Wrap (V, Binds (BI).Rhs, Sch,
                                     Args, Result)));
               end if;
            end loop;
         end Wrap_In;
      begin
         for GI in 1 .. M.Top_Binds.Last_Index loop
            declare
               G : Top_Bind := M.Top_Binds (GI);
            begin
               Wrap_In (G.Binds);
               M.Top_Binds.Replace_Element (GI, G);
            end;
         end loop;
         for EI in 1 .. Natural (M.Last_Expr) loop
            declare
               N : constant Expr_Node := M.Node (Real_Expr_Id (EI));
            begin
               if N.Kind = Let_C then
                  declare
                     Binds : Bind_Vectors.Vector := N.Binds;
                  begin
                     Wrap_In (Binds);
                     M.Exprs.Replace_Element
                       (Real_Expr_Id (EI),
                        Expr_Node'(Kind => Let_C, Span => N.Span,
                                   Is_Rec => N.Is_Rec,
                                   Binds => Binds,
                                   Let_Body => N.Let_Body));
                  end;
               end if;
            end;
         end loop;
      end Rewrite_Bind;

   begin
      for C in Sigs.Iterate loop
         declare
            V      : constant Real_Var_Id := Kinds.Sig_Maps.Key (C);
            Sch_Id : constant Scheme_Id := Kinds.Sig_Maps.Element (C);
         begin
            if Sch_Id /= No_Scheme then
               declare
                  Sch     : constant Scheme :=
                    M.Node (Real_Scheme_Id (Sch_Id));
                  Args    : Type_Id_Vectors.Vector;
                  Result  : Real_Type_Id := Sch.S_Body;
                  Refined : Boolean;
               begin
                  while M.Node (Result).Kind = TFun_T loop
                     Args.Append (M.Node (Result).From);
                     Result := M.Node (Result).To;
                  end loop;
                  Refined :=
                    Active (Refinement_Of (Result))
                    or else (for some A of Args =>
                               Active (Refinement_Of (A)));
                  if Refined then
                     Rewrite_Bind (V, Sch, Args, Result);
                  end if;
               end;
            end if;
         end;
      end loop;

      --  Constructor-site checks: every occurrence of a data
      --  constructor whose fields carry refinements is eta-wrapped so
      --  the check (or modular normalization) rides each refined
      --  field's thunk - construction sites, partial applications,
      --  record syntax and record update all route through Con_C.
      --  Field reads are not re-checked: the invariant is established
      --  here. Only expressions existing before this sweep are
      --  rewritten; nodes minted by the rewrites are beyond Snapshot.
      declare
         Snapshot : constant Expr_Id := M.Last_Expr;

         --  Refined field positions of DC's Con_Scheme spine, empty
         --  if none are active.
         function Field_Refs
           (DC : Real_DataCon_Id) return Type_Id_Vectors.Vector
         is
            Empty : Type_Id_Vectors.Vector;
            Sch_Id : constant Scheme_Id := M.Info (DC).Con_Scheme;
            Fields : Type_Id_Vectors.Vector;
            Any : Boolean := False;
         begin
            if Sch_Id = No_Scheme then
               return Empty;
            end if;
            declare
               T : Real_Type_Id :=
                 M.Node (Real_Scheme_Id (Sch_Id)).S_Body;
            begin
               while M.Node (T).Kind = TFun_T loop
                  Fields.Append (M.Node (T).From);
                  Any := Any or else Active (Refinement_Of
                                               (M.Node (T).From));
                  T := M.Node (T).To;
               end loop;
            end;
            return (if Any then Fields else Empty);
         end Field_Refs;
      begin
         for EI in 1 .. Natural (Snapshot) loop
            declare
               N : constant Expr_Node := M.Node (Real_Expr_Id (EI));
            begin
               if N.Kind = Con_C then
                  declare
                     Fields : constant Type_Id_Vectors.Vector :=
                       Field_Refs (N.Con);
                     Span : constant Diagnostics.Source_Span := N.Span;
                     DC : constant Real_DataCon_Id := N.Con;
                  begin
                     if not Fields.Is_Empty then
                        declare
                           Params : Var_Id_Vectors.Vector;
                           Core_E : Real_Expr_Id;
                        begin
                           for I in 1 .. Fields.Last_Index loop
                              Params.Append
                                (M.Mint_Var
                                   ((Name => Table.Intern ("$rf"),
                                     Span => Span, others => <>)));
                           end loop;
                           Core_E := M.Add
                             (Expr_Node'(Kind => Con_C, Span => Span,
                                         Con => DC));
                           for I in 1 .. Fields.Last_Index loop
                              declare
                                 A : Real_Expr_Id :=
                                   M.Add (Expr_Node'
                                     (Kind => Var_C, Span => Span,
                                      V => Params (I)));
                                 R : constant Refinement_Id :=
                                   Refinement_Of (Fields (I));
                              begin
                                 if Active (R) then
                                    A := Check_E
                                      (Real_Refinement_Id (R), A,
                                       Span);
                                 end if;
                                 Core_E := M.Add
                                   (Expr_Node'
                                      (Kind => App_C, Span => Span,
                                       Fun => Core_E, Arg => A));
                              end;
                           end loop;
                           for I in reverse 1 .. Params.Last_Index loop
                              Core_E := M.Add
                                (Expr_Node'
                                   (Kind => Lam_C, Span => Span,
                                    Binder => Params (I),
                                    Lam_Body => Core_E));
                           end loop;
                           --  The wrapper's top lambda lands in the
                           --  original node, so every reference to
                           --  this occurrence sees the checked form.
                           M.Exprs.Replace_Element
                             (Real_Expr_Id (EI),
                              M.Node (Core_E));
                        end;
                     end if;
                  end;
               end if;
            end;
         end loop;
      end;
   end Insert_Checks;

end AHC.Refine;
