with Ada.Containers.Hashed_Maps;
with Ada.Containers.Vectors;

with AHC.Core.Printer;

package body AHC.Typechecker is

   use AHC.Core;
   use type Ada.Containers.Count_Type;
   use type Names.Name_Id;

   Max_Context_Depth : constant := 63;

   ---------------------------------------------------------------------
   --  Fully_Typed
   ---------------------------------------------------------------------

   function Fully_Typed (M : Core.Core_Module) return Boolean is
   begin
      for G of M.Top_Binds loop
         for B of G.Binds loop
            if M.Info (B.Binder).Var_Scheme = No_Scheme then
               return False;
            end if;
         end loop;
      end loop;
      return True;
   end Fully_Typed;

   procedure Check_Module
     (Table : in out Names.Name_Table;
      Bag   : in out Diagnostics.Diagnostic_Bag;
      M     : in out Core.Core_Module;
      Env   : in out Builtins.Global_Env;
      Sigs  : Kinds.Sig_Maps.Map)
   is
      ------------------------------------------------------------------
      --  Inference state: union-find meta cells with levels
      ------------------------------------------------------------------

      type Meta_Cell is record
         Bound : Boolean := False;
         To    : Type_Id := No_Type;
         Level : Natural := 0;
      end record;

      package Cell_Vectors is new Ada.Containers.Vectors
        (Positive, Meta_Cell);

      Cells : Cell_Vectors.Vector;
      Level : Natural := 0;

      Wanted : Constraint_Vectors.Vector;

      function Fresh_Meta return Real_Type_Id is
      begin
         Cells.Append (Meta_Cell'(Bound => False, To => No_Type,
                                  Level => Level));
         return M.Add (Type_Node'(Kind => TMeta_T,
                                  Meta => Real_Meta_Id (
                                    Cells.Last_Index)));
      end Fresh_Meta;

      --  Follow bindings at the head.
      function Repr (T : Real_Type_Id) return Real_Type_Id is
         N : constant Type_Node := M.Node (T);
      begin
         if N.Kind = TMeta_T
           and then Cells (Positive (N.Meta)).Bound
         then
            return Repr
              (Real_Type_Id (Cells (Positive (N.Meta)).To));
         end if;
         return T;
      end Repr;

      function Occurs
        (Meta : Real_Meta_Id; T : Real_Type_Id) return Boolean
      is
         Z : constant Real_Type_Id := Repr (T);
         N : constant Type_Node := M.Node (Z);
      begin
         case N.Kind is
            when TMeta_T =>
               return N.Meta = Meta;
            when TApp_T =>
               return Occurs (Meta, N.T_Fun)
                 or else Occurs (Meta, N.T_Arg);
            when TFun_T =>
               return Occurs (Meta, N.From) or else Occurs (Meta, N.To);
            when others =>
               return False;
         end case;
      end Occurs;

      function Is_Unbound (Meta : Real_Meta_Id) return Boolean
      is (not Cells (Positive (Meta)).Bound);

      --  Lower the levels of metas inside T to at most L (level
      --  adjustment keeps generalization sound).
      procedure Adjust_Levels (T : Real_Type_Id; L : Natural) is
         Z : constant Real_Type_Id := Repr (T);
         N : constant Type_Node := M.Node (Z);
      begin
         case N.Kind is
            when TMeta_T =>
               if Cells (Positive (N.Meta)).Level > L then
                  Cells (Positive (N.Meta)).Level := L;
               end if;
            when TApp_T =>
               Adjust_Levels (N.T_Fun, L);
               Adjust_Levels (N.T_Arg, L);
            when TFun_T =>
               Adjust_Levels (N.From, L);
               Adjust_Levels (N.To, L);
            when others =>
               null;
         end case;
      end Adjust_Levels;

      --  The PRD occurs-check contract: the only operation that could
      --  build an infinite type refuses to.
      procedure Bind_Meta (Meta : Real_Meta_Id; T : Real_Type_Id)
        with Pre  => Is_Unbound (Meta) and then not Occurs (Meta, T),
             Post => not Is_Unbound (Meta)
      is
      begin
         Adjust_Levels (T, Cells (Positive (Meta)).Level);
         Cells (Positive (Meta)) :=
           (Bound => True, To => Type_Id (T),
            Level => Cells (Positive (Meta)).Level);
      end Bind_Meta;

      --  The observable acyclicity witness (Zonk terminates and the
      --  result is meta-free once generalization substitutes).
      function Meta_Free (T : Real_Type_Id) return Boolean is
         N : constant Type_Node := M.Node (T);
      begin
         case N.Kind is
            when TMeta_T =>
               return False;
            when TApp_T =>
               return Meta_Free (N.T_Fun) and then Meta_Free (N.T_Arg);
            when TFun_T =>
               return Meta_Free (N.From) and then Meta_Free (N.To);
            when others =>
               return True;
         end case;
      end Meta_Free;

      --  Rebuild T with all bound metas resolved; unbound metas are
      --  replaced via Subst (used by generalization) or left in place
      --  when Subst is empty.
      function Meta_Hash (K : Real_Meta_Id)
        return Ada.Containers.Hash_Type
      is (Ada.Containers.Hash_Type (K));

      package Meta_Type_Maps is new Ada.Containers.Hashed_Maps
        (Real_Meta_Id, Real_Type_Id,
         Hash => Meta_Hash, Equivalent_Keys => "=");

      function Zonk_With
        (T : Real_Type_Id; Subst : Meta_Type_Maps.Map)
         return Real_Type_Id
      is
         Z : constant Real_Type_Id := Repr (T);
         N : constant Type_Node := M.Node (Z);
      begin
         case N.Kind is
            when TMeta_T =>
               declare
                  C : constant Meta_Type_Maps.Cursor :=
                    Subst.Find (N.Meta);
               begin
                  if Meta_Type_Maps.Has_Element (C) then
                     return Meta_Type_Maps.Element (C);
                  end if;
                  return Z;
               end;
            when TApp_T =>
               return M.Add (Type_Node'
                 (Kind => TApp_T,
                  T_Fun => Zonk_With (N.T_Fun, Subst),
                  T_Arg => Zonk_With (N.T_Arg, Subst)));
            when TFun_T =>
               return M.Add (Type_Node'
                 (Kind => TFun_T,
                  From => Zonk_With (N.From, Subst),
                  To => Zonk_With (N.To, Subst)));
            when others =>
               return Z;
         end case;
      end Zonk_With;

      ------------------------------------------------------------------
      --  Unification
      ------------------------------------------------------------------

      function Type_Str (T : Real_Type_Id) return String is
         Sch : Scheme;
         Id : Real_Scheme_Id;
      begin
         Sch.S_Body := Type_Id (Zonk_With (T, Meta_Type_Maps.Empty_Map));
         Id := M.Add (Sch);
         return Core.Printer.Pretty_Scheme (M, Table, Id);
      end Type_Str;

      procedure Unify
        (A, B : Real_Type_Id; Span : Diagnostics.Source_Span)
      is
         ZA : constant Real_Type_Id := Repr (A);
         ZB : constant Real_Type_Id := Repr (B);
         NA : constant Type_Node := M.Node (ZA);
         NB : constant Type_Node := M.Node (ZB);

         procedure Mismatch is
         begin
            Bag.Add (Diagnostics.Error, Diagnostics.Type_Mismatch, Span,
                     "couldn't match type '" & Type_Str (ZA)
                     & "' with '" & Type_Str (ZB) & "'");
         end Mismatch;
      begin
         if ZA = ZB then
            return;
         end if;
         if NA.Kind = TMeta_T and then NB.Kind = TMeta_T
           and then NA.Meta = NB.Meta
         then
            return;
         end if;
         if NA.Kind = TMeta_T then
            if Occurs (NA.Meta, ZB) then
               Bag.Add (Diagnostics.Error, Diagnostics.Type_Occurs_Check,
                        Span,
                        "cannot construct the infinite type: "
                        & Type_Str (ZA) & " ~ " & Type_Str (ZB));
               return;
            end if;
            Bind_Meta (NA.Meta, ZB);
            return;
         end if;
         if NB.Kind = TMeta_T then
            if Occurs (NB.Meta, ZA) then
               Bag.Add (Diagnostics.Error, Diagnostics.Type_Occurs_Check,
                        Span,
                        "cannot construct the infinite type: "
                        & Type_Str (ZB) & " ~ " & Type_Str (ZA));
               return;
            end if;
            Bind_Meta (NB.Meta, ZA);
            return;
         end if;

         case NA.Kind is
            when TCon_T =>
               --  Design rule 2: erased-head comparison.
               if not Same_Con_Erased (NA, NB) then
                  Mismatch;
               end if;
            when TVar_T =>
               if NB.Kind /= TVar_T or else NA.Tv /= NB.Tv then
                  Mismatch;
               end if;
            when TApp_T =>
               if NB.Kind /= TApp_T then
                  Mismatch;
               else
                  Unify (NA.T_Fun, NB.T_Fun, Span);
                  Unify (NA.T_Arg, NB.T_Arg, Span);
               end if;
            when TFun_T =>
               if NB.Kind /= TFun_T then
                  Mismatch;
               else
                  Unify (NA.From, NB.From, Span);
                  Unify (NA.To, NB.To, Span);
               end if;
            when TMeta_T =>
               null;   --  unreachable
         end case;
      end Unify;

      ------------------------------------------------------------------
      --  Instantiation
      ------------------------------------------------------------------

      function TyVar_Hash (K : Real_TyVar_Id)
        return Ada.Containers.Hash_Type
      is (Ada.Containers.Hash_Type (K));

      package TyVar_Type_Maps is new Ada.Containers.Hashed_Maps
        (Real_TyVar_Id, Real_Type_Id,
         Hash => TyVar_Hash, Equivalent_Keys => "=");

      function Subst_TyVars
        (T : Real_Type_Id; Map : TyVar_Type_Maps.Map)
         return Real_Type_Id
      is
         N : constant Type_Node := M.Node (T);
      begin
         case N.Kind is
            when TVar_T =>
               declare
                  C : constant TyVar_Type_Maps.Cursor := Map.Find (N.Tv);
               begin
                  if TyVar_Type_Maps.Has_Element (C) then
                     return TyVar_Type_Maps.Element (C);
                  end if;
                  return T;
               end;
            when TApp_T =>
               return M.Add (Type_Node'
                 (Kind => TApp_T,
                  T_Fun => Subst_TyVars (N.T_Fun, Map),
                  T_Arg => Subst_TyVars (N.T_Arg, Map)));
            when TFun_T =>
               return M.Add (Type_Node'
                 (Kind => TFun_T,
                  From => Subst_TyVars (N.From, Map),
                  To => Subst_TyVars (N.To, Map)));
            when others =>
               return T;
         end case;
      end Subst_TyVars;

      --  Instantiate a scheme with fresh metas; its context becomes
      --  wanted constraints.
      function Instantiate
        (S : Real_Scheme_Id; Span : Diagnostics.Source_Span)
         return Real_Type_Id
      is
         Sch : constant Scheme := M.Node (S);
         Map : TyVar_Type_Maps.Map;
      begin
         for Tv of Sch.Tvs loop
            Map.Include (Tv, Fresh_Meta);
         end loop;
         for C of Sch.Context loop
            Wanted.Append
              (Constraint'(Class => C.Class,
                           Arg => Subst_TyVars (C.Arg, Map),
                           Span => Span));
         end loop;
         return Subst_TyVars (Real_Type_Id (Sch.S_Body), Map);
      end Instantiate;

      ------------------------------------------------------------------
      --  Built-in literal types
      ------------------------------------------------------------------

      function TCon (TC : Core.TyCon_Id) return Real_Type_Id
      is (M.Add (Type_Node'(Kind => TCon_T,
                            Con => Real_TyCon_Id (TC),
                            Refine => No_Refinement)));

      function Lit_Type (L : Literal) return Real_Type_Id
      is (case L.Kind is
            when L_Int    => TCon (Env.Integer_TC),
            when L_Float  => TCon (Env.Rational_TC),
            when L_Char   => TCon (Env.Char_TC),
            when L_String =>
              M.Add (Type_Node'
                (Kind => TApp_T,
                 T_Fun => TCon (Env.List_TC),
                 T_Arg => TCon (Env.Char_TC))));

      ------------------------------------------------------------------
      --  Context reduction (Report 4.5.3) and defaulting (4.3.4)
      ------------------------------------------------------------------

      --  Givens: constraints assumed from an enclosing signature,
      --  closed under superclasses.
      Givens : Constraint_Vectors.Vector;

      --  Both args zonked to rigid tyvars (post-generalization)?
      function Same_Tv_Arg (A, B : Real_Type_Id) return Boolean is
         NA : constant Type_Node := M.Node (Repr (A));
         NB : constant Type_Node := M.Node (Repr (B));
      begin
         return NA.Kind = TVar_T and then NB.Kind = TVar_T
           and then NA.Tv = NB.Tv;
      end Same_Tv_Arg;

      function Same_Constraint (A, B : Constraint) return Boolean is
         RA : constant Real_Type_Id := Repr (A.Arg);
         RB : constant Real_Type_Id := Repr (B.Arg);
      begin
         if A.Class /= B.Class then
            return False;
         end if;
         --  Given args are rigid tyvars; compare heads.
         declare
            NA : constant Type_Node := M.Node (RA);
            NB : constant Type_Node := M.Node (RB);
         begin
            return NA.Kind = TVar_T and then NB.Kind = TVar_T
              and then NA.Tv = NB.Tv;
         end;
      end Same_Constraint;

      --  Add C and all its superclass constraints to Givens.
      procedure Assume (C : Constraint) is
      begin
         Givens.Append (C);
         for Super of M.Info (C.Class).Supers loop
            Assume (Constraint'(Class => Super, Arg => C.Arg,
                                Span => C.Span));
         end loop;
      end Assume;

      --  Head TyCon of a zonked type, treating T1 -> T2 as (->) and
      --  following application spines. 0 if headed by a meta/tyvar.
      procedure Head_Of
        (T : Real_Type_Id;
         Head : out TyCon_Id;
         Args : out Type_Id_Vectors.Vector)
      is
         Z : constant Real_Type_Id := Repr (T);
         N : constant Type_Node := M.Node (Z);
      begin
         case N.Kind is
            when TCon_T =>
               Head := TyCon_Id (N.Con);
            when TApp_T =>
               Head_Of (N.T_Fun, Head, Args);
               Args.Append (N.T_Arg);
            when TFun_T =>
               Head := Env.Arrow_TC;
               Args.Append (N.From);
               Args.Append (N.To);
            when others =>
               Head := No_TyCon;
         end case;
      end Head_Of;

      --  Reduce one wanted to HNF. True if discharged or deferred as a
      --  tyvar-headed constraint (still wanted); False only on error.
      procedure Solve
        (C : Constraint; Depth : Natural;
         Residual : in out Constraint_Vectors.Vector;
         Quiet : Boolean := False;
         Failed : access Boolean := null)
      is
         procedure Report (Code : Diagnostics.Diag_Code; Msg : String)
         is
         begin
            if Quiet then
               if Failed /= null then
                  Failed.all := True;
               end if;
            else
               Bag.Add (Diagnostics.Error, Code, C.Span, Msg);
            end if;
         end Report;
         Head : TyCon_Id;
         Args : Type_Id_Vectors.Vector;
      begin
         if Depth > Max_Context_Depth then
            Report (Diagnostics.Class_Context_Depth,
                    "context reduction stack overflow");
            return;
         end if;

         --  Discharged by a given (or its superclasses)?
         for G of Givens loop
            if Same_Constraint (G, C) then
               return;
            end if;
         end loop;

         Head_Of (C.Arg, Head, Args);
         if Head = No_TyCon then
            --  Tyvar-headed: stays wanted (generalized or defaulted).
            Residual.Append (C);
            return;
         end if;

         --  Find the instance for (Class, Head).
         for I of M.Info (C.Class).Instances loop
            declare
               Inst : constant Instance_Info := M.Info (I);
            begin
               if Inst.Head = Head then
                  --  Map instance head vars to the wanted's args and
                  --  solve the instance context.
                  declare
                     Map : TyVar_Type_Maps.Map;
                  begin
                     for VI in 1 .. Inst.Head_Vars.Last_Index loop
                        if VI <= Args.Last_Index then
                           Map.Include (Inst.Head_Vars (VI),
                                        Args (VI));
                        end if;
                     end loop;
                     for IC of Inst.Context loop
                        Solve
                          (Constraint'
                             (Class => IC.Class,
                              Arg => Subst_TyVars (IC.Arg, Map),
                              Span => C.Span),
                           Depth + 1, Residual, Quiet, Failed);
                     end loop;
                  end;
                  return;
               end if;
            end;
         end loop;

         Report (Diagnostics.Class_No_Instance,
                 "no instance for '"
                 & Table.Text (M.Info (C.Class).Name) & " "
                 & Type_Str (C.Arg) & "'");
      end Solve;

      --  Report 4.3.4: default an ambiguous tyvar when all of its
      --  classes are standard and at least one is numeric; candidates
      --  are Integer then Double.
      procedure Try_Default (Residual : in out Constraint_Vectors.Vector)
      is
         Remaining : Constraint_Vectors.Vector;
      begin
         --  Group by head meta.
         while not Residual.Is_Empty loop
            declare
               First_C : constant Constraint := Residual.First_Element;
               FZ : constant Real_Type_Id := Repr (First_C.Arg);
               FN : constant Type_Node := M.Node (FZ);
               Group : Constraint_Vectors.Vector;
               Rest  : Constraint_Vectors.Vector;
               Numeric : Boolean := False;
            begin
               if FN.Kind /= TMeta_T then
                  Remaining.Append (First_C);
                  Residual.Delete_First;
               else
                  for C of Residual loop
                     declare
                        Z : constant Real_Type_Id := Repr (C.Arg);
                        N2 : constant Type_Node := M.Node (Z);
                     begin
                        if N2.Kind = TMeta_T
                          and then N2.Meta = FN.Meta
                        then
                           Group.Append (C);
                           if Class_Id (C.Class) = Env.Num_Cl
                             or else Class_Id (C.Class) =
                                       Env.Fractional_Cl
                             or else Class_Id (C.Class) = Env.Real_Cl
                           then
                              Numeric := True;
                           end if;
                        else
                           Rest.Append (C);
                        end if;
                     end;
                  end loop;
                  Residual := Rest;

                  if Numeric then
                     --  Try Integer, then Double.
                     declare
                        Solved : Boolean := False;
                     begin
                        for Cand in 1 .. 2 loop
                           if not Solved then
                              declare
                                 T : constant Real_Type_Id :=
                                   TCon (if Cand = 1 then Env.Integer_TC
                                         else Env.Double_TC);
                                 Ok : Boolean := True;
                              begin
                                 for C of Group loop
                                    declare
                                       Probe : Constraint_Vectors.Vector;
                                       Fail : aliased Boolean := False;
                                       Trial : Constraint := C;
                                    begin
                                       --  Probe quietly: does an
                                       --  instance exist?
                                       Trial.Arg := T;
                                       Solve (Trial, 0, Probe,
                                              Quiet => True,
                                              Failed => Fail'Access);
                                       if Fail or else not Probe.Is_Empty
                                       then
                                          Ok := False;
                                       end if;
                                    end;
                                 end loop;
                                 if Ok then
                                    Bind_Meta (FN.Meta, T);
                                    Solved := True;
                                 end if;
                              end;
                           end if;
                        end loop;
                        if not Solved then
                           Bag.Add (Diagnostics.Error,
                                    Diagnostics.Type_Ambiguous,
                                    First_C.Span,
                                    "ambiguous type variable in"
                                    & " constraints");
                        end if;
                     end;
                  else
                     Bag.Add (Diagnostics.Error,
                              Diagnostics.Type_Ambiguous, First_C.Span,
                              "ambiguous type variable in constraint '"
                              & Table.Text
                                  (M.Info (First_C.Class).Name)
                              & " " & Type_Str (First_C.Arg) & "'");
                  end if;
               end if;
            end;
         end loop;
         Residual := Remaining;
      end Try_Default;

      ------------------------------------------------------------------
      --  Inference over Core
      ------------------------------------------------------------------

      procedure Check_Group
        (Binds : Bind_Vectors.Vector; Top : Boolean);

      function Infer (E : Real_Expr_Id) return Real_Type_Id is
         N : constant Expr_Node := M.Node (E);
         Span : constant Diagnostics.Source_Span := N.Span;
      begin
         case N.Kind is
            when Var_C =>
               declare
                  V : constant Var_Info := M.Info (N.V);
               begin
                  if V.Var_Scheme /= No_Scheme then
                     return Instantiate
                       (Real_Scheme_Id (V.Var_Scheme), Span);
                  elsif V.Var_Type /= No_Type then
                     return Real_Type_Id (V.Var_Type);
                  else
                     --  A global whose type is unknown (opaque
                     --  dictionary or an errored binder): fresh meta.
                     declare
                        T : constant Real_Type_Id := Fresh_Meta;
                     begin
                        M.Vars (N.V).Var_Type := Type_Id (T);
                        return T;
                     end;
                  end if;
               end;
            when Lit_C =>
               return Lit_Type (N.Lit);
            when Con_C =>
               declare
                  Info : constant DataCon_Info := M.Info (N.Con);
               begin
                  if Info.Con_Scheme /= No_Scheme then
                     return Instantiate
                       (Real_Scheme_Id (Info.Con_Scheme), Span);
                  end if;
                  return Fresh_Meta;
               end;
            when App_C =>
               declare
                  TF : constant Real_Type_Id := Infer (N.Fun);
                  TA : constant Real_Type_Id := Infer (N.Arg);
                  R  : constant Real_Type_Id := Fresh_Meta;
               begin
                  Unify (TF,
                         M.Add (Type_Node'(Kind => TFun_T, From => TA,
                                           To => R)),
                         Span);
                  return R;
               end;
            when Lam_C =>
               declare
                  A : constant Real_Type_Id := Fresh_Meta;
               begin
                  M.Vars (N.Binder).Var_Type := Type_Id (A);
                  declare
                     B : constant Real_Type_Id := Infer (N.Lam_Body);
                  begin
                     return M.Add (Type_Node'(Kind => TFun_T,
                                              From => A, To => B));
                  end;
               end;
            when Let_C =>
               Check_Group (N.Binds, Top => False);
               return Infer (N.Let_Body);
            when Case_C =>
               declare
                  TS : constant Real_Type_Id := Infer (N.Scrutinee);
                  R  : constant Real_Type_Id := Fresh_Meta;
               begin
                  for A of N.Alts loop
                     declare
                        Alt : constant Alt_Node := M.Node (A);
                     begin
                        case Alt.Kind is
                           when Con_Alt =>
                              declare
                                 Info : constant DataCon_Info :=
                                   M.Info (Alt.A_Con);
                                 CT : Real_Type_Id;
                              begin
                                 if Info.Con_Scheme /= No_Scheme then
                                    CT := Instantiate
                                      (Real_Scheme_Id
                                         (Info.Con_Scheme),
                                       Alt.Span);
                                 else
                                    CT := Fresh_Meta;
                                 end if;
                                 --  CT = f1 -> .. -> fn -> T args.
                                 for B of Alt.Binders loop
                                    declare
                                       Z : constant Real_Type_Id :=
                                         Repr (CT);
                                       CN : constant Type_Node :=
                                         M.Node (Z);
                                    begin
                                       if CN.Kind = TFun_T then
                                          M.Vars (B).Var_Type :=
                                            Type_Id (CN.From);
                                          CT := CN.To;
                                       else
                                          M.Vars (B).Var_Type :=
                                            Type_Id (Fresh_Meta);
                                       end if;
                                    end;
                                 end loop;
                                 Unify (CT, TS, Alt.Span);
                              end;
                           when Lit_Alt =>
                              Unify (Lit_Type (Alt.A_Lit), TS,
                                     Alt.Span);
                           when Default_Alt =>
                              null;
                        end case;
                        Unify (Infer (Alt.Alt_Body), R, Alt.Span);
                     end;
                  end loop;
                  return R;
               end;
         end case;
      end Infer;

      ------------------------------------------------------------------
      --  Binding groups, generalization, MR
      ------------------------------------------------------------------

      function Free_Metas_In_Env_Level (T : Real_Type_Id) return Boolean
      is
         Z : constant Real_Type_Id := Repr (T);
         N : constant Type_Node := M.Node (Z);
      begin
         case N.Kind is
            when TMeta_T =>
               return Cells (Positive (N.Meta)).Level <= Level;
            when TApp_T =>
               return Free_Metas_In_Env_Level (N.T_Fun)
                 or else Free_Metas_In_Env_Level (N.T_Arg);
            when TFun_T =>
               return Free_Metas_In_Env_Level (N.From)
                 or else Free_Metas_In_Env_Level (N.To);
            when others =>
               return False;
         end case;
      end Free_Metas_In_Env_Level;

      procedure Collect_Gen_Metas
        (T : Real_Type_Id; Into : in out Meta_Type_Maps.Map;
         Order : in out TyVar_Id_Vectors.Vector;
         Names_Src : in out Natural)
      is
         Z : constant Real_Type_Id := Repr (T);
         N : constant Type_Node := M.Node (Z);
      begin
         case N.Kind is
            when TMeta_T =>
               if Cells (Positive (N.Meta)).Level > Level
                 and then not Into.Contains (N.Meta)
               then
                  Names_Src := Names_Src + 1;
                  declare
                     Tv : constant Real_TyVar_Id :=
                       M.Mint_TyVar
                         ((Name => Table.Intern ("t"),
                           Tv_Kind => Kind_Id (M.Star)));
                     TvT : constant Real_Type_Id :=
                       M.Add (Type_Node'(Kind => TVar_T, Tv => Tv));
                  begin
                     Into.Include (N.Meta, TvT);
                     Order.Append (Tv);
                  end;
               end if;
            when TApp_T =>
               Collect_Gen_Metas (N.T_Fun, Into, Order, Names_Src);
               Collect_Gen_Metas (N.T_Arg, Into, Order, Names_Src);
            when TFun_T =>
               Collect_Gen_Metas (N.From, Into, Order, Names_Src);
               Collect_Gen_Metas (N.To, Into, Order, Names_Src);
            when others =>
               null;
         end case;
      end Collect_Gen_Metas;

      procedure Check_Group
        (Binds : Bind_Vectors.Vector; Top : Boolean)
      is
         pragma Unreferenced (Top);
         Wanted_Mark : constant Natural := Natural (Wanted.Length);
         Givens_Mark : constant Natural := Natural (Givens.Length);
         Restricted : Boolean := False;
      begin
         Level := Level + 1;

         --  Binder setup.
         for B of Binds loop
            declare
               Sig_C : constant Kinds.Sig_Maps.Cursor :=
                 Sigs.Find (B.Binder);
            begin
               if Kinds.Sig_Maps.Has_Element (Sig_C) then
                  M.Vars (B.Binder).Var_Scheme :=
                    Kinds.Sig_Maps.Element (Sig_C);
               else
                  M.Vars (B.Binder).Var_Type := Type_Id (Fresh_Meta);
                  if M.Info (B.Binder).From_Pattern_Binding then
                     Restricted := True;
                  end if;
               end if;
            end;
         end loop;

         --  Check each right-hand side. A signatured binding solves
         --  its own wanteds inside its givens window.
         for B of Binds loop
            declare
               Info : constant Var_Info := M.Info (B.Binder);
               Span : constant Diagnostics.Source_Span := Info.Span;
            begin
               if Info.Var_Scheme /= No_Scheme then
                  declare
                     Sch : constant Scheme :=
                       M.Node (Real_Scheme_Id (Info.Var_Scheme));
                     W_Mark : constant Natural :=
                       Natural (Wanted.Length);
                  begin
                     for C of Sch.Context loop
                        Assume (C);
                     end loop;
                     Unify (Infer (B.Rhs),
                            Real_Type_Id (Sch.S_Body), Span);
                     declare
                        Res2 : Constraint_Vectors.Vector;
                     begin
                        while Natural (Wanted.Length) > W_Mark loop
                           declare
                              C : constant Constraint :=
                                Wanted.Last_Element;
                           begin
                              Wanted.Delete_Last;
                              Solve (C, 0, Res2);
                           end;
                        end loop;
                        for C of Res2 loop
                           Wanted.Append (C);
                        end loop;
                     end;
                     while Natural (Givens.Length) > Givens_Mark loop
                        Givens.Delete_Last;
                     end loop;
                  end;
               else
                  Unify (Infer (B.Rhs),
                         Real_Type_Id (Info.Var_Type), Span);
               end if;
            end;
         end loop;

         Level := Level - 1;

         --  Solve this group's wanteds to HNF, then generalize the
         --  whole group with one shared quantifier set (mutual
         --  recursion shares its type variables and context).
         declare
            Residual : Constraint_Vectors.Vector;
            Subst : Meta_Type_Maps.Map;
            Order : TyVar_Id_Vectors.Vector;
            Src : Natural := 0;
            Ctx : Constraint_Vectors.Vector;
         begin
            while Natural (Wanted.Length) > Wanted_Mark loop
               declare
                  C : constant Constraint := Wanted.Last_Element;
               begin
                  Wanted.Delete_Last;
                  Solve (C, 0, Residual);
               end;
            end loop;

            if not Restricted then
               for B of Binds loop
                  if M.Info (B.Binder).Var_Scheme = No_Scheme then
                     Collect_Gen_Metas
                       (Real_Type_Id (M.Info (B.Binder).Var_Type),
                        Subst, Order, Src);
                  end if;
               end loop;
            end if;

            --  Constraints on generalized metas form the shared
            --  context (deduplicated); the rest float up.
            declare
               Kept : Constraint_Vectors.Vector;
            begin
               for C of Residual loop
                  declare
                     Z : constant Real_Type_Id := Repr (C.Arg);
                     NC : constant Type_Node := M.Node (Z);
                  begin
                     if NC.Kind = TMeta_T
                       and then Subst.Contains (NC.Meta)
                     then
                        declare
                           New_C : constant Constraint :=
                             (Class => C.Class,
                              Arg => Zonk_With (C.Arg, Subst),
                              Span => C.Span);
                           Dup : Boolean := False;
                        begin
                           for Old of Ctx loop
                              if Old.Class = New_C.Class
                                and then Same_Tv_Arg
                                  (Old.Arg, New_C.Arg)
                              then
                                 Dup := True;
                              end if;
                           end loop;
                           if not Dup then
                              Ctx.Append (New_C);
                           end if;
                        end;
                     else
                        Kept.Append (C);
                     end if;
                  end;
               end loop;
               Residual := Kept;
            end;

            for B of Binds loop
               if M.Info (B.Binder).Var_Scheme = No_Scheme then
                  declare
                     Zonked : constant Real_Type_Id :=
                       Zonk_With
                         (Real_Type_Id (M.Info (B.Binder).Var_Type),
                          Subst);
                     Sch : Scheme;
                  begin
                     pragma Assert
                       (Restricted or else Meta_Free (Zonked)
                        or else Free_Metas_In_Env_Level (Zonked));
                     Sch.Tvs := Order;
                     Sch.Context := Ctx;
                     Sch.S_Body := Type_Id (Zonked);
                     M.Vars (B.Binder).Var_Scheme :=
                       Scheme_Id (M.Add (Sch));
                  end;
               end if;
            end loop;

            --  Whatever is left stays wanted for the enclosing group.
            for C of Residual loop
               Wanted.Append (C);
            end loop;
         end;
      end Check_Group;

      ------------------------------------------------------------------
      --  Top level: SCC over the top binds
      ------------------------------------------------------------------

      function Var_Hash (K : Real_Var_Id)
        return Ada.Containers.Hash_Type
      is (Ada.Containers.Hash_Type (K));

      package Var_Nat_Maps is new Ada.Containers.Hashed_Maps
        (Real_Var_Id, Positive,
         Hash => Var_Hash, Equivalent_Keys => "=");

      Binder_Group : Var_Nat_Maps.Map;   --  top binder -> group index

      package Nat_Vectors is new Ada.Containers.Vectors
        (Positive, Positive);

      procedure Free_Top_Vars
        (E : Real_Expr_Id; Into : in out Nat_Vectors.Vector)
      is
         N : constant Expr_Node := M.Node (E);
      begin
         case N.Kind is
            when Var_C =>
               declare
                  C : constant Var_Nat_Maps.Cursor :=
                    Binder_Group.Find (N.V);
               begin
                  if Var_Nat_Maps.Has_Element (C) then
                     Into.Append (Var_Nat_Maps.Element (C));
                  end if;
               end;
            when App_C =>
               Free_Top_Vars (N.Fun, Into);
               Free_Top_Vars (N.Arg, Into);
            when Lam_C =>
               Free_Top_Vars (N.Lam_Body, Into);
            when Let_C =>
               for B of N.Binds loop
                  Free_Top_Vars (B.Rhs, Into);
               end loop;
               Free_Top_Vars (N.Let_Body, Into);
            when Case_C =>
               Free_Top_Vars (N.Scrutinee, Into);
               for A of N.Alts loop
                  Free_Top_Vars (M.Node (A).Alt_Body, Into);
               end loop;
            when others =>
               null;
         end case;
      end Free_Top_Vars;

      Group_Count : constant Natural := Natural (M.Top_Binds.Length);

      --  Tarjan SCC state.
      Index_Counter : Natural := 0;
      Indices  : array (1 .. Group_Count) of Natural := [others => 0];
      Lowlinks : array (1 .. Group_Count) of Natural := [others => 0];
      On_Stack : array (1 .. Group_Count) of Boolean :=
        [others => False];
      Stack : Nat_Vectors.Vector;
      Adj : array (1 .. Group_Count) of Nat_Vectors.Vector;

      --  SCCs in reverse topological order (Tarjan emits callees
      --  before callers, which is exactly the check order we need).
      SCCs : Nat_Vectors.Vector;         --  flattened
      SCC_Sizes : Nat_Vectors.Vector;

      procedure Strong_Connect (V : Positive) is
      begin
         Index_Counter := Index_Counter + 1;
         Indices (V) := Index_Counter;
         Lowlinks (V) := Index_Counter;
         Stack.Append (V);
         On_Stack (V) := True;
         for W of Adj (V) loop
            if Indices (W) = 0 then
               Strong_Connect (W);
               Lowlinks (V) := Natural'Min (Lowlinks (V), Lowlinks (W));
            elsif On_Stack (W) then
               Lowlinks (V) := Natural'Min (Lowlinks (V), Indices (W));
            end if;
         end loop;
         if Lowlinks (V) = Indices (V) then
            declare
               Size : Natural := 0;
               W : Positive;
            begin
               loop
                  W := Stack.Last_Element;
                  Stack.Delete_Last;
                  On_Stack (W) := False;
                  SCCs.Append (W);
                  Size := Size + 1;
                  exit when W = V;
               end loop;
               SCC_Sizes.Append (Size);
            end;
         end if;
      end Strong_Connect;

   begin
      --  Build the call graph over top-level groups.
      for GI in 1 .. M.Top_Binds.Last_Index loop
         for B of M.Top_Binds (GI).Binds loop
            Binder_Group.Include (B.Binder, GI);
         end loop;
      end loop;
      for GI in 1 .. M.Top_Binds.Last_Index loop
         for B of M.Top_Binds (GI).Binds loop
            Free_Top_Vars (B.Rhs, Adj (GI));
         end loop;
      end loop;

      for GI in 1 .. Group_Count loop
         if Indices (GI) = 0 then
            Strong_Connect (GI);
         end if;
      end loop;

      --  Check each SCC as one binding group, in order.
      declare
         Pos : Natural := 0;
      begin
         for SI in 1 .. SCC_Sizes.Last_Index loop
            declare
               Merged : Bind_Vectors.Vector;
            begin
               for K in 1 .. SCC_Sizes (SI) loop
                  for B of M.Top_Binds (SCCs (Pos + K)).Binds loop
                     Merged.Append (B);
                  end loop;
               end loop;
               Pos := Pos + SCC_Sizes (SI);
               Check_Group (Merged, Top => True);
            end;
         end loop;
      end;

      --  Instance method bodies: each checked against the method's
      --  scheme with the class variable instantiated to the instance
      --  head and the instance context assumed.
      for II in 1 .. M.Last_Instance loop
         declare
            Inst : constant Instance_Info :=
              M.Info (Real_Instance_Id (II));
         begin
            if not Inst.Method_Binds.Is_Empty
              and then Inst.Of_Class /= No_Class
            then
               declare
                  Cl : constant Class_Info :=
                    M.Info (Real_Class_Id (Inst.Of_Class));
                  Head_T : Real_Type_Id :=
                    M.Add (Type_Node'
                      (Kind => TCon_T,
                       Con => Real_TyCon_Id (Inst.Head),
                       Refine => No_Refinement));
                  Givens_Mark : constant Natural :=
                    Natural (Givens.Length);
               begin
                  for HV of Inst.Head_Vars loop
                     Head_T := M.Add (Type_Node'
                       (Kind => TApp_T, T_Fun => Head_T,
                        T_Arg => M.Add (Type_Node'
                          (Kind => TVar_T, Tv => HV))));
                  end loop;
                  for C of Inst.Context loop
                     Assume (C);
                  end loop;

                  for B of Inst.Method_Binds loop
                     declare
                        BName : constant Names.Name_Id :=
                          M.Info (B.Binder).Name;
                        Found : Boolean := False;
                     begin
                        for Mth of Cl.Methods loop
                           if Mth.Name = BName
                             and then Mth.Method_Scheme /= No_Scheme
                           then
                              Found := True;
                              declare
                                 Sch : constant Scheme :=
                                   M.Node (Real_Scheme_Id
                                             (Mth.Method_Scheme));
                                 Map : TyVar_Type_Maps.Map;
                                 W_Mark : constant Natural :=
                                   Natural (Wanted.Length);
                              begin
                                 --  Class var (first scheme tyvar)
                                 --  becomes the instance head type.
                                 if not Sch.Tvs.Is_Empty then
                                    Map.Include (Sch.Tvs (1), Head_T);
                                 end if;
                                 --  Non-class constraints of the
                                 --  method's own context are given.
                                 for C of Sch.Context loop
                                    if C.Class /=
                                       Class_Id'(Inst.Of_Class)
                                    then
                                       Assume
                                         (Constraint'
                                            (Class => C.Class,
                                             Arg => Subst_TyVars
                                               (C.Arg, Map),
                                             Span => C.Span));
                                    end if;
                                 end loop;
                                 M.Vars (B.Binder).Var_Type :=
                                   Type_Id (Subst_TyVars
                                     (Real_Type_Id (Sch.S_Body), Map));
                                 Unify
                                   (Infer (B.Rhs),
                                    Real_Type_Id
                                      (M.Info (B.Binder).Var_Type),
                                    M.Info (B.Binder).Span);
                                 --  Solve this method's wanteds now.
                                 declare
                                    Res2 : Constraint_Vectors.Vector;
                                 begin
                                    while Natural (Wanted.Length) >
                                          W_Mark
                                    loop
                                       declare
                                          C2 : constant Constraint :=
                                            Wanted.Last_Element;
                                       begin
                                          Wanted.Delete_Last;
                                          Solve (C2, 0, Res2);
                                       end;
                                    end loop;
                                    for C2 of Res2 loop
                                       Wanted.Append (C2);
                                    end loop;
                                 end;
                              end;
                           end if;
                        end loop;
                        if not Found then
                           Bag.Add (Diagnostics.Error,
                                    Diagnostics.Class_Missing_Method,
                                    M.Info (B.Binder).Span,
                                    "'" & Table.Text (BName)
                                    & "' is not a method of the"
                                    & " class");
                        end if;
                     end;
                  end loop;

                  while Natural (Givens.Length) > Givens_Mark loop
                     Givens.Delete_Last;
                  end loop;

                  --  Methods lacking both an implementation and a
                  --  class default get a warning (Report 4.3.2).
                  for Mth of Cl.Methods loop
                     declare
                        Have : Boolean := Mth.Has_Default;
                     begin
                        for B of Inst.Method_Binds loop
                           if M.Info (B.Binder).Name = Mth.Name then
                              Have := True;
                           end if;
                        end loop;
                        if not Have then
                           Bag.Add (Diagnostics.Warning,
                                    Diagnostics.Class_Missing_Method,
                                    Inst.Span,
                                    "no explicit implementation for '"
                                    & Table.Text (Mth.Name) & "'");
                        end if;
                     end;
                  end loop;
               end;
            end if;
         end;
      end loop;

      --  Class default-method bodies: checked against the method
      --  scheme itself (class variable rigid, constraint given).
      for CI in 1 .. M.Last_Class loop
         declare
            Cl : constant Class_Info := M.Info (Real_Class_Id (CI));
         begin
            for B of Cl.Default_Binds loop
               declare
                  BName : constant Names.Name_Id :=
                    M.Info (B.Binder).Name;
               begin
                  for Mth of Cl.Methods loop
                     if Mth.Name = BName
                       and then Mth.Method_Scheme /= No_Scheme
                     then
                        declare
                           Sch : constant Scheme :=
                             M.Node (Real_Scheme_Id
                                       (Mth.Method_Scheme));
                           Givens_Mark : constant Natural :=
                             Natural (Givens.Length);
                        begin
                           for C of Sch.Context loop
                              Assume (C);
                           end loop;
                           M.Vars (B.Binder).Var_Type := Sch.S_Body;
                           Unify (Infer (B.Rhs),
                                  Real_Type_Id (Sch.S_Body),
                                  M.Info (B.Binder).Span);
                           while Natural (Givens.Length) > Givens_Mark
                           loop
                              Givens.Delete_Last;
                           end loop;
                        end;
                     end if;
                  end loop;
               end;
            end loop;
         end;
      end loop;

      --  Module-level residuals: defaulting, then ambiguity errors.
      declare
         Residual : Constraint_Vectors.Vector;
      begin
         for C of Wanted loop
            Residual.Append (C);
         end loop;
         Wanted.Clear;
         Try_Default (Residual);
         --  Anything still unsolved mentions a rigid signature
         --  variable: the signature promised more than the body keeps.
         for C of Residual loop
            Bag.Add (Diagnostics.Error,
                     Diagnostics.Type_Signature_Too_General, C.Span,
                     "could not deduce '"
                     & Table.Text (M.Info (C.Class).Name) & " "
                     & Type_Str (C.Arg)
                     & "' required by the definition");
         end loop;
      end;

      --  Re-zonk every top-level scheme so defaulting decisions made
      --  at module level show through restricted bindings.
      for G of M.Top_Binds loop
         for B of G.Binds loop
            declare
               SId : constant Scheme_Id := M.Info (B.Binder).Var_Scheme;
            begin
               if SId /= No_Scheme then
                  declare
                     Sch : Scheme := M.Node (Real_Scheme_Id (SId));
                  begin
                     Sch.S_Body := Type_Id
                       (Zonk_With (Real_Type_Id (Sch.S_Body),
                                   Meta_Type_Maps.Empty_Map));
                     for CI in 1 .. Sch.Context.Last_Index loop
                        declare
                           C : Constraint := Sch.Context (CI);
                        begin
                           C.Arg := Zonk_With
                             (C.Arg, Meta_Type_Maps.Empty_Map);
                           Sch.Context.Replace_Element (CI, C);
                        end;
                     end loop;
                     M.Vars (B.Binder).Var_Scheme :=
                       Scheme_Id (M.Add (Sch));
                  end;
               end if;
            end;
         end loop;
      end loop;

      --  Ensure the postcondition even on error paths: give every
      --  top binder some scheme.
      for G of M.Top_Binds loop
         for B of G.Binds loop
            if M.Info (B.Binder).Var_Scheme = No_Scheme then
               declare
                  Sch : Scheme;
               begin
                  Sch.S_Body :=
                    (if M.Info (B.Binder).Var_Type /= No_Type
                     then M.Info (B.Binder).Var_Type
                     else Type_Id (Fresh_Meta));
                  M.Vars (B.Binder).Var_Scheme :=
                    Scheme_Id (M.Add (Sch));
               end;
            end if;
         end loop;
      end loop;
   end Check_Module;

end AHC.Typechecker;
