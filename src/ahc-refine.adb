with AHC.Discharge;

package body AHC.Refine is

   use AHC.Core;

   procedure Insert_Checks
     (Table          : in out Names.Name_Table;
      M              : in out Core.Core_Module;
      Sigs           : Kinds.Sig_Maps.Map;
      Prims          : in out Prelude_Core.Prim_Maps.Map;
      Bag            : in out Diagnostics.Diagnostic_Bag;
      Checks_Enabled : Boolean := True;
      Contracts      : AHC.Contracts.Contract_Maps.Map :=
        AHC.Contracts.Contract_Maps.Empty_Map)
   is
      Check_Prim : Var_Id := No_Var;   --  minted on first use
      Pred_Prim  : Var_Id := No_Var;
      Mod_Prim   : Var_Id := No_Var;
      FRange_Prim : Var_Id := No_Var;
      Claim_Prim : Var_Id := No_Var;

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

      --  Function contracts (docs/contracts-design-note.md): each
      --  contracted binding f = RHS becomes
      --    f = \x1..xn -> claim (preF x1..xn) preMsg
      --                     (let r = RHS x1..xn
      --                      in claim (postF x1..xn r) postMsg r)
      --  Claims fire at demand time (forcing the result forces pre,
      --  then post); the result is let-shared so the value the
      --  postcondition inspects is the value the caller receives.
      --  Contracts wrap OUTSIDE the refinement wrappers above.
      --  Every embedded reference is a fresh Var node.
      if Checks_Enabled and then not Contracts.Is_Empty then
         declare
            function ClPrim return Real_Var_Id
            is (Mint_Prim ("$checkClaim", "ahc_prim_check_claim",
                           Claim_Prim));

            Span0 : constant Diagnostics.Source_Span :=
              (Start => 1, Stop => 1);

            function CV (V : Var_Id) return Real_Expr_Id
            is (M.Add (Expr_Node'(Kind => Var_C, Span => Span0,
                                  V => Real_Var_Id (V))));

            function CAp (F, A : Real_Expr_Id) return Real_Expr_Id
            is (M.Add (Expr_Node'(Kind => App_C, Span => Span0,
                                  Fun => F, Arg => A)));

            function CStr (S : String) return Real_Expr_Id
            is (M.Add (Expr_Node'
                  (Kind => Lit_C, Span => Span0,
                   Lit => (Kind => L_String,
                           Text => Names.Name_Id
                             (Table.Intern (S))))));

            function Claim
              (B : Real_Expr_Id; Msg : String; V : Real_Expr_Id)
               return Real_Expr_Id
            is (CAp (CAp (CAp (CV (Var_Id (ClPrim)), B),
                          CStr (Msg)), V));

            procedure Wrap_Contract
              (FV : Real_Var_Id;
               CB : AHC.Contracts.Contract_Binds)
            is
               Sig_C : constant Kinds.Sig_Maps.Cursor :=
                 Sigs.Find (FV);
               Fn_Text : constant String :=
                 Table.Text
                   (Names.Real_Name_Id (M.Info (FV).Name));

               function Build (Old : Real_Expr_Id)
                 return Real_Expr_Id
               is
                  --  Refine runs AFTER dictionary elaboration: a
                  --  constrained function's rhs is dict-lambda
                  --  wrapped, and so are the elaborated contract
                  --  globals - thread the same dictionary
                  --  parameters through all three.
                  Sch : constant Scheme :=
                    M.Node (Real_Scheme_Id
                      (Kinds.Sig_Maps.Element (Sig_C)));
                  Arity : Natural := 0;
                  Ds, Xs : Var_Id_Vectors.Vector;
                  R_V : constant Real_Var_Id :=
                    M.Mint_Var ((Name => Table.Intern ("$r"),
                                 Span => Span0, others => <>));
                  Applied : Real_Expr_Id;
                  Inner : Real_Expr_Id;

                  function Applied_To_Ctx
                    (F : Real_Expr_Id) return Real_Expr_Id
                  is
                     Acc : Real_Expr_Id := F;
                  begin
                     for D of Ds loop
                        Acc := CAp (Acc, CV (D));
                     end loop;
                     for X of Xs loop
                        Acc := CAp (Acc, CV (X));
                     end loop;
                     return Acc;
                  end Applied_To_Ctx;
               begin
                  declare
                     T : Real_Type_Id :=
                       Real_Type_Id (Sch.S_Body);
                  begin
                     while M.Node (T).Kind = TFun_T loop
                        Arity := Arity + 1;
                        T := M.Node (T).To;
                     end loop;
                  end;
                  for I in 1 .. Sch.Context.Last_Index loop
                     Ds.Append (Var_Id
                       (M.Mint_Var
                          ((Name => Table.Intern ("$cd"),
                            Span => Span0, others => <>))));
                  end loop;
                  for I in 1 .. Arity loop
                     Xs.Append (Var_Id
                       (M.Mint_Var
                          ((Name => Table.Intern ("$c"),
                            Span => Span0, others => <>))));
                  end loop;

                  Applied := Applied_To_Ctx (Old);

                  if CB.Post_V /= No_Var then
                     declare
                        Post_Call : constant Real_Expr_Id :=
                          CAp (Applied_To_Ctx (CV (CB.Post_V)),
                               CV (Var_Id (R_V)));
                        Binds : Bind_Vectors.Vector;
                     begin
                        Binds.Append
                          (Bind_Pair'(Binder => R_V,
                                      Rhs => Applied));
                        Inner := M.Add (Expr_Node'
                          (Kind => Let_C, Span => Span0,
                           Is_Rec => False, Binds => Binds,
                           Let_Body =>
                             Claim (Post_Call,
                                    "postcondition of '"
                                    & Fn_Text & "' violated",
                                    CV (Var_Id (R_V)))));
                     end;
                  else
                     Inner := Applied;
                  end if;

                  if CB.Pre_V /= No_Var then
                     Inner :=
                       Claim (Applied_To_Ctx (CV (CB.Pre_V)),
                              "precondition of '"
                              & Fn_Text & "' violated",
                              Inner);
                  end if;

                  for I in reverse 1 .. Xs.Last_Index loop
                     Inner := M.Add (Expr_Node'
                       (Kind => Lam_C, Span => Span0,
                        Binder => Real_Var_Id (Xs.Element (I)),
                        Lam_Body => Inner));
                  end loop;
                  for I in reverse 1 .. Ds.Last_Index loop
                     Inner := M.Add (Expr_Node'
                       (Kind => Lam_C, Span => Span0,
                        Binder => Real_Var_Id (Ds.Element (I)),
                        Lam_Body => Inner));
                  end loop;
                  return Inner;
               end Build;
            begin
               if not Kinds.Sig_Maps.Has_Element (Sig_C) then
                  return;
               end if;
               for GI in 1 .. M.Top_Binds.Last_Index loop
                  declare
                     G : Top_Bind := M.Top_Binds (GI);
                     Changed : Boolean := False;
                  begin
                     for BI in 1 .. G.Binds.Last_Index loop
                        if G.Binds (BI).Binder = FV then
                           G.Binds.Replace_Element
                             (BI, Bind_Pair'
                                (Binder => FV,
                                 Rhs => Build
                                   (G.Binds (BI).Rhs)));
                           Changed := True;
                        end if;
                     end loop;
                     if Changed then
                        M.Top_Binds.Replace_Element (GI, G);
                     end if;
                  end;
               end loop;
            end Wrap_Contract;

            Cur : AHC.Contracts.Contract_Maps.Cursor :=
              Contracts.First;
         begin
            while AHC.Contracts.Contract_Maps.Has_Element (Cur) loop
               declare
                  use type AHC.Discharge.Verdict;
                  CB : AHC.Contracts.Contract_Binds :=
                    AHC.Contracts.Contract_Maps.Element (Cur);

                  --  Compile-time discharge: a claim proved True on
                  --  every call is dropped; one proved False can
                  --  never hold and earns a warning (the runtime
                  --  check stays, so the program still fails with
                  --  the standard message when demanded).
                  procedure Consider
                    (V : in out Core.Var_Id; What : String)
                  is
                  begin
                     if V = Core.No_Var then
                        return;
                     end if;
                     case AHC.Discharge.Try_Claim
                            (Table, M, Prims, Core.Real_Var_Id (V))
                     is
                        when AHC.Discharge.Proved_True =>
                           V := Core.No_Var;
                        when AHC.Discharge.Proved_False =>
                           Bag.Add
                             (Diagnostics.Warning,
                              Diagnostics.Match_Warning,
                              M.Info (Core.Real_Var_Id (V)).Span,
                              What & " can never hold");
                        when AHC.Discharge.Unknown =>
                           null;
                     end case;
                  end Consider;
               begin
                  Consider (CB.Pre_V, "this precondition");
                  Consider (CB.Post_V, "this postcondition");
                  if CB.Pre_V /= No_Var
                    or else CB.Post_V /= No_Var
                  then
                     Wrap_Contract
                       (AHC.Contracts.Contract_Maps.Key (Cur), CB);
                  end if;
               end;
               AHC.Contracts.Contract_Maps.Next (Cur);
            end loop;
         end;
      end if;

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
