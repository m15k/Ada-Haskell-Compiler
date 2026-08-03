with Ada.Containers.Hashed_Maps;
with Ada.Containers.Vectors;

with AHC.Core.Printer;

package body AHC.Typechecker is

   use AHC.Core;
   use type Ada.Containers.Count_Type;
   use type Names.Name_Id;

   Max_Context_Depth : constant := 63;

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
      Sigs  : Kinds.Sig_Maps.Map;
      Group_Origins : Diagnostics.Origin_Vectors.Vector :=
        Diagnostics.Origin_Vectors.Empty_Vector;
      Inst_Origins : Diagnostics.Origin_Vectors.Vector :=
        Diagnostics.Origin_Vectors.Empty_Vector)
   is
      ------------------------------------------------------------------
      --  Inference state
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

      --  Wanted constraints with evidence shapes (M16): every scheme
      --  instantiation appends wanteds; solving records HOW each was
      --  discharged; evidence expressions are built at the end and
      --  applied at the recorded occurrence sites.
      package Nat_Vectors is new Ada.Containers.Vectors
        (Positive, Positive);

      type Sol_Kind is (Unsolved, By_Given, By_Param, By_Instance,
                        By_Error);

      type Wanted_Rec is record
         C     : Constraint;
         Site  : Expr_Id := No_Expr;    --  occurrence to rewrite
         Owner : Var_Id := No_Var;      --  binder whose rhs holds At
         Sol   : Sol_Kind := Unsolved;
         GEv   : Expr_Id := No_Expr;    --  By_Given evidence expr
         Dict  : Var_Id := No_Var;      --  By_Param dictionary param
         Inst  : Instance_Id := 0;      --  By_Instance
         Subs  : Nat_Vectors.Vector;    --  wanted indices for Inst ctx
      end record;

      package Wanted_Vectors is new Ada.Containers.Vectors
        (Positive, Wanted_Rec);

      W_List : Wanted_Vectors.Vector;
      Current_Owner : Var_Id := No_Var;
      Probing : Boolean := False;

      --  Dictionary-lambda wraps to apply at the end: binder -> params.
      type Wrap_Rec is record
         Binder : Real_Var_Id;
         Params : Var_Id_Vectors.Vector;
      end record;

      package Wrap_Vectors is new Ada.Containers.Vectors
        (Positive, Wrap_Rec);

      Wraps : Wrap_Vectors.Vector;

      function Fresh_Meta return Real_Type_Id is
      begin
         Cells.Append (Meta_Cell'(Bound => False, To => No_Type,
                                  Level => Level));
         return M.Add (Type_Node'(Kind => TMeta_T,
                                  Meta => Real_Meta_Id (
                                    Cells.Last_Index)));
      end Fresh_Meta;

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

      --  The observable acyclicity witness.
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
               Bag.Add (Diagnostics.Error,
                        Diagnostics.Type_Occurs_Check, Span,
                        "cannot construct the infinite type: "
                        & Type_Str (ZA) & " ~ " & Type_Str (ZB));
               return;
            end if;
            Bind_Meta (NA.Meta, ZB);
            return;
         end if;
         if NB.Kind = TMeta_T then
            if Occurs (NB.Meta, ZA) then
               Bag.Add (Diagnostics.Error,
                        Diagnostics.Type_Occurs_Check, Span,
                        "cannot construct the infinite type: "
                        & Type_Str (ZB) & " ~ " & Type_Str (ZA));
               return;
            end if;
            Bind_Meta (NB.Meta, ZA);
            return;
         end if;

         --  The wired Rational placeholder behaves as a nullary
         --  synonym the moment a library defines `type Rational`
         --  (Data.Ratio's `Ratio Integer`): expand it here so the
         --  wired fromRational scheme meets the source type. The
         --  cached Core rhs is filled by AHC.Kinds when the
         --  defining module's kind pass runs; before that the
         --  placeholder stays opaque, exactly as wired.
         if NA.Kind = TCon_T
           and then NA.Con = Env.Rational_TC
           and then (NB.Kind /= TCon_T
                     or else NB.Con /= Env.Rational_TC)
         then
            declare
               C : constant Builtins.Syn_Maps.Cursor :=
                 Env.Synonyms.Find (Table.Intern ("Rational"));
            begin
               if Builtins.Syn_Maps.Has_Element (C)
                 and then Builtins.Syn_Maps.Element (C).Core_Rhs
                          /= Core.No_Type
               then
                  Unify (Real_Type_Id
                    (Builtins.Syn_Maps.Element (C).Core_Rhs),
                    ZB, Span);
                  return;
               end if;
            end;
         end if;
         if NB.Kind = TCon_T
           and then NB.Con = Env.Rational_TC
           and then (NA.Kind /= TCon_T
                     or else NA.Con /= Env.Rational_TC)
         then
            declare
               C : constant Builtins.Syn_Maps.Cursor :=
                 Env.Synonyms.Find (Table.Intern ("Rational"));
            begin
               if Builtins.Syn_Maps.Has_Element (C)
                 and then Builtins.Syn_Maps.Element (C).Core_Rhs
                          /= Core.No_Type
               then
                  Unify (ZA, Real_Type_Id
                    (Builtins.Syn_Maps.Element (C).Core_Rhs), Span);
                  return;
               end if;
            end;
         end if;

         case NA.Kind is
            when TCon_T =>
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
               null;
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
                  C : constant TyVar_Type_Maps.Cursor :=
                    Map.Find (N.Tv);
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
      --  wanted constraints recorded against the occurrence site.
      function Instantiate
        (S : Real_Scheme_Id; Span : Diagnostics.Source_Span;
         Site : Expr_Id := No_Expr) return Real_Type_Id
      is
         Sch : constant Scheme := M.Node (S);
         Map : TyVar_Type_Maps.Map;
      begin
         for Tv of Sch.Tvs loop
            Map.Include (Tv, Fresh_Meta);
         end loop;
         for C of Sch.Context loop
            W_List.Append
              (Wanted_Rec'
                 (C => Constraint'(Class => C.Class,
                                   Arg => Subst_TyVars (C.Arg, Map),
                                   Span => Span),
                  Site => Site, Owner => Current_Owner,
                  others => <>));
         end loop;
         return Subst_TyVars (Real_Type_Id (Sch.S_Body), Map);
      end Instantiate;

      ------------------------------------------------------------------
      --  Literal types
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
      --  Givens and evidence-shaped context reduction
      ------------------------------------------------------------------

      type Given_Rec is record
         C  : Constraint;
         Ev : Real_Expr_Id;    --  dictionary expression
      end record;

      package Given_Vectors is new Ada.Containers.Vectors
        (Positive, Given_Rec);

      Givens : Given_Vectors.Vector;

      function Same_Tv_Arg (A, B : Real_Type_Id) return Boolean is
         NA : constant Type_Node := M.Node (Repr (A));
         NB : constant Type_Node := M.Node (Repr (B));
      begin
         return NA.Kind = TVar_T and then NB.Kind = TVar_T
           and then NA.Tv = NB.Tv;
      end Same_Tv_Arg;

      --  Assume C with evidence Ev, plus superclasses via their
      --  selector globals.
      procedure Assume (C : Constraint; Ev : Real_Expr_Id) is
         Info : constant Class_Info := M.Info (C.Class);
      begin
         Givens.Append (Given_Rec'(C => C, Ev => Ev));
         for I in 1 .. Info.Supers.Last_Index loop
            declare
               Sel : constant Var_Id :=
                 (if I <= Info.Super_Sels.Last_Index
                  then Var_Id (Info.Super_Sels (I)) else No_Var);
               Sup_Ev : Real_Expr_Id := Ev;
            begin
               if Sel /= No_Var then
                  Sup_Ev := M.Add (Expr_Node'
                    (Kind => App_C, Span => C.Span,
                     Fun => M.Add (Expr_Node'
                       (Kind => Var_C, Span => C.Span,
                        V => Real_Var_Id (Sel))),
                     Arg => Ev));
               end if;
               Assume (Constraint'(Class => Info.Supers (I),
                                   Arg => C.Arg, Span => C.Span),
                       Sup_Ev);
            end;
         end loop;
      end Assume;

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

      --  Reduce wanted I to HNF, recording its evidence shape.
      --  Unsolved entries have tyvar/meta heads (residuals).
      procedure Solve (I : Positive; Depth : Natural) is
         W : Wanted_Rec := W_List (I);
      begin
         if W.Sol /= Unsolved then
            return;
         end if;

         if Depth > Max_Context_Depth then
            if not Probing then
               Bag.Add (Diagnostics.Error,
                        Diagnostics.Class_Context_Depth, W.C.Span,
                        "context reduction stack overflow");
            end if;
            W.Sol := By_Error;
            W_List.Replace_Element (I, W);
            return;
         end if;

         for G of Givens loop
            if G.C.Class = W.C.Class
              and then Same_Tv_Arg (G.C.Arg, W.C.Arg)
            then
               W.Sol := By_Given;
               W.GEv := Expr_Id (G.Ev);
               W_List.Replace_Element (I, W);
               return;
            end if;
         end loop;

         declare
            Head : TyCon_Id;
            Args : Type_Id_Vectors.Vector;
         begin
            Head_Of (W.C.Arg, Head, Args);
            if Head = No_TyCon then
               return;   --  residual
            end if;

            for Inst_Id of M.Info (W.C.Class).Instances loop
               declare
                  Inst : constant Instance_Info := M.Info (Inst_Id);
               begin
                  if Inst.Head = Head then
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
                           W_List.Append
                             (Wanted_Rec'
                                (C => Constraint'
                                   (Class => IC.Class,
                                    Arg => Subst_TyVars (IC.Arg, Map),
                                    Span => W.C.Span),
                                 Site => No_Expr, Owner => W.Owner,
                                 others => <>));
                           W.Subs.Append (W_List.Last_Index);
                           Solve (W_List.Last_Index, Depth + 1);
                        end loop;
                        W.Sol := By_Instance;
                        W.Inst := Instance_Id (Inst_Id);
                        W_List.Replace_Element (I, W);
                        return;
                     end;
                  end if;
               end;
            end loop;

            if not Probing then
               Bag.Add (Diagnostics.Error,
                        Diagnostics.Class_No_Instance, W.C.Span,
                        "no instance for '"
                        & Table.Text (M.Info (W.C.Class).Name) & " "
                        & Type_Str (W.C.Arg) & "'");
            end if;
            W.Sol := By_Error;
            W_List.Replace_Element (I, W);
         end;
      end Solve;

      --  Report 4.3.4 defaulting over the unsolved residuals.
      procedure Try_Default is
      begin
         for I in 1 .. W_List.Last_Index loop
            if W_List (I).Sol = Unsolved then
               declare
                  Z : constant Real_Type_Id :=
                    Repr (W_List (I).C.Arg);
                  N : constant Type_Node := M.Node (Z);
               begin
                  if N.Kind = TMeta_T then
                     --  Collect the classes constraining this meta.
                     declare
                        Numeric : Boolean := False;
                        Solved : Boolean := False;
                     begin
                        for J in I .. W_List.Last_Index loop
                           if W_List (J).Sol = Unsolved then
                              declare
                                 ZJ : constant Real_Type_Id :=
                                   Repr (W_List (J).C.Arg);
                                 NJ : constant Type_Node :=
                                   M.Node (ZJ);
                              begin
                                 if NJ.Kind = TMeta_T
                                   and then NJ.Meta = N.Meta
                                   and then
                                     (Class_Id (W_List (J).C.Class) =
                                        Env.Num_Cl
                                      or else
                                      Class_Id (W_List (J).C.Class) =
                                        Env.Fractional_Cl
                                      or else
                                      Class_Id (W_List (J).C.Class) =
                                        Env.Real_Cl
                                      or else
                                      Class_Id (W_List (J).C.Class) =
                                        Env.Integral_Cl
                                      or else
                                      Class_Id (W_List (J).C.Class) =
                                        Env.Floating_Cl
                                      or else
                                      Class_Id (W_List (J).C.Class) =
                                        Env.RealFrac_Cl
                                      or else
                                      Class_Id (W_List (J).C.Class) =
                                        Env.RealFloat_Cl)
                                 then
                                    Numeric := True;
                                 end if;
                              end;
                           end if;
                        end loop;

                        if Numeric then
                           for Cand in 1 .. 2 loop
                              if not Solved then
                                 declare
                                    T : constant Real_Type_Id :=
                                      TCon (if Cand = 1
                                            then Env.Integer_TC
                                            else Env.Double_TC);
                                    Ok : Boolean := True;
                                    Mark : constant Natural :=
                                      W_List.Last_Index;
                                 begin
                                    --  Quiet probe on every class of
                                    --  this meta.
                                    Probing := True;
                                    for J in 1 .. Mark loop
                                       if W_List (J).Sol = Unsolved
                                       then
                                          declare
                                             ZJ : constant
                                               Real_Type_Id :=
                                                 Repr (W_List (J)
                                                         .C.Arg);
                                             NJ : constant Type_Node
                                               := M.Node (ZJ);
                                          begin
                                             if NJ.Kind = TMeta_T
                                               and then NJ.Meta =
                                                          N.Meta
                                             then
                                                declare
                                                   CJ : constant
                                                     Constraint :=
                                                       W_List (J).C;
                                                begin
                                                   W_List.Append
                                                     (Wanted_Rec'
                                                        (C =>
                                                           Constraint'
                                                           (Class =>
                                                              CJ.Class,
                                                            Arg => T,
                                                            Span =>
                                                              CJ.Span),
                                                         others =>
                                                           <>));
                                                end;
                                                Solve
                                                  (W_List.Last_Index,
                                                   0);
                                                if W_List
                                                  (W_List.Last_Index)
                                                  .Sol in
                                                    By_Error | Unsolved
                                                then
                                                   Ok := False;
                                                end if;
                                             end if;
                                          end;
                                       end if;
                                    end loop;
                                    Probing := False;
                                    while W_List.Last_Index > Mark loop
                                       W_List.Delete_Last;
                                    end loop;
                                    if Ok then
                                       Bind_Meta (N.Meta, T);
                                       Solved := True;
                                       --  Re-solve for evidence.
                                       for J in 1 .. Mark loop
                                          if W_List (J).Sol = Unsolved
                                          then
                                             Solve (J, 0);
                                          end if;
                                       end loop;
                                    end if;
                                 end;
                              end if;
                           end loop;
                           if not Solved then
                              Bag.Add (Diagnostics.Error,
                                       Diagnostics.Type_Ambiguous,
                                       W_List (I).C.Span,
                                       "ambiguous type variable in"
                                       & " constraints");
                           end if;
                        else
                           Bag.Add
                             (Diagnostics.Error,
                              Diagnostics.Type_Ambiguous,
                              W_List (I).C.Span,
                              "ambiguous type variable in constraint '"
                              & Table.Text
                                  (M.Info (W_List (I).C.Class).Name)
                              & " " & Type_Str (W_List (I).C.Arg)
                              & "'");
                        end if;
                     end;
                  end if;
               end;
            end if;
         end loop;
      end Try_Default;

      ------------------------------------------------------------------
      --  Inference over Core
      ------------------------------------------------------------------

      procedure Check_Group
        (Binds : in out Bind_Vectors.Vector);

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
                       (Real_Scheme_Id (V.Var_Scheme), Span,
                        Site => Expr_Id (E));
                  elsif V.Var_Type /= No_Type then
                     return Real_Type_Id (V.Var_Type);
                  else
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
               declare
                  Local : Bind_Vectors.Vector := N.Binds;
               begin
                  Check_Group (Local);
                  --  Write back (dictionary wraps may have changed
                  --  the binds); node surgery via Replace_Element.
                  M.Exprs.Replace_Element
                    (E, Expr_Node'(Kind => Let_C, Span => Span,
                                   Is_Rec => N.Is_Rec, Binds => Local,
                                   Let_Body => N.Let_Body));
                  return Infer (N.Let_Body);
               end;
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
                        Unify (Infer (M.Node (A).Alt_Body), R,
                               Alt.Span);
                     end;
                  end loop;
                  return R;
               end;
         end case;
      end Infer;

      ------------------------------------------------------------------
      --  Binding groups
      ------------------------------------------------------------------

      function Free_Metas_In_Env_Level (T : Real_Type_Id)
        return Boolean
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
         Order : in out TyVar_Id_Vectors.Vector)
      is
         Z : constant Real_Type_Id := Repr (T);
         N : constant Type_Node := M.Node (Z);
      begin
         case N.Kind is
            when TMeta_T =>
               if Cells (Positive (N.Meta)).Level > Level
                 and then not Into.Contains (N.Meta)
               then
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
               Collect_Gen_Metas (N.T_Fun, Into, Order);
               Collect_Gen_Metas (N.T_Arg, Into, Order);
            when TFun_T =>
               Collect_Gen_Metas (N.From, Into, Order);
               Collect_Gen_Metas (N.To, Into, Order);
            when others =>
               null;
         end case;
      end Collect_Gen_Metas;

      --  Rewrite occurrences of group binders inside Rhs to apply the
      --  owner's dictionary params (ties the recursive knot).
      procedure Apply_Rec_Params
        (Rhs : Real_Expr_Id;
         Group_Binders : Var_Id_Vectors.Vector;
         Params : Var_Id_Vectors.Vector)
      is
         N : constant Expr_Node := M.Node (Rhs);
      begin
         case N.Kind is
            when Var_C =>
               for GB of Group_Binders loop
                  if GB = N.V then
                     declare
                        Copy : constant Real_Expr_Id :=
                          M.Add (Expr_Node'(Kind => Var_C,
                                            Span => N.Span,
                                            V => N.V));
                        Chain : Real_Expr_Id := Copy;
                     begin
                        for P of Params loop
                           Chain := M.Add (Expr_Node'
                             (Kind => App_C, Span => N.Span,
                              Fun => Chain,
                              Arg => M.Add (Expr_Node'
                                (Kind => Var_C, Span => N.Span,
                                 V => P))));
                        end loop;
                        M.Exprs.Replace_Element (Rhs, M.Node (Chain));
                     end;
                     return;
                  end if;
               end loop;
            when App_C =>
               Apply_Rec_Params (N.Fun, Group_Binders, Params);
               Apply_Rec_Params (N.Arg, Group_Binders, Params);
            when Lam_C =>
               Apply_Rec_Params (N.Lam_Body, Group_Binders, Params);
            when Let_C =>
               for B of N.Binds loop
                  Apply_Rec_Params (B.Rhs, Group_Binders, Params);
               end loop;
               Apply_Rec_Params (N.Let_Body, Group_Binders, Params);
            when Case_C =>
               Apply_Rec_Params (N.Scrutinee, Group_Binders, Params);
               for A of N.Alts loop
                  Apply_Rec_Params (M.Node (A).Alt_Body,
                                    Group_Binders, Params);
               end loop;
            when others =>
               null;
         end case;
      end Apply_Rec_Params;

      procedure Check_Group
        (Binds : in out Bind_Vectors.Vector)
      is
         W_Mark : constant Natural := W_List.Last_Index;
         Givens_Mark : constant Natural := Givens.Last_Index;
         Restricted : Boolean := False;
         Saved_Owner : constant Var_Id := Current_Owner;
      begin
         Level := Level + 1;

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

         --  Check right-hand sides. Signatured bindings solve their
         --  wanteds inside their givens window and get dict wraps.
         for B of Binds loop
            declare
               Info : constant Var_Info := M.Info (B.Binder);
               Span : constant Diagnostics.Source_Span := Info.Span;
            begin
               Current_Owner := Var_Id (B.Binder);
               if Info.Var_Scheme /= No_Scheme then
                  declare
                     Sch : constant Scheme :=
                       M.Node (Real_Scheme_Id (Info.Var_Scheme));
                     W_Mark2 : constant Natural := W_List.Last_Index;
                     Params : Var_Id_Vectors.Vector;
                  begin
                     for C of Sch.Context loop
                        declare
                           D : constant Real_Var_Id :=
                             M.Mint_Var
                               ((Name => Table.Intern ("$d"),
                                 Span => Span, others => <>));
                        begin
                           Params.Append (D);
                           Assume (C, M.Add (Expr_Node'
                             (Kind => Var_C, Span => Span, V => D)));
                        end;
                     end loop;
                     Unify (Infer (B.Rhs),
                            Real_Type_Id (Sch.S_Body), Span);
                     for I in W_Mark2 + 1 .. W_List.Last_Index loop
                        Solve (I, 0);
                     end loop;
                     while Givens.Last_Index > Givens_Mark loop
                        Givens.Delete_Last;
                     end loop;
                     if not Params.Is_Empty then
                        Wraps.Append
                          (Wrap_Rec'(Binder => B.Binder,
                                     Params => Params));
                     end if;
                  end;
               else
                  Unify (Infer (B.Rhs),
                         Real_Type_Id (Info.Var_Type), Span);
               end if;
            end;
         end loop;
         Current_Owner := Saved_Owner;

         Level := Level - 1;

         --  Solve the group's wanteds, then generalize with a shared
         --  quantifier set and context.
         for I in W_Mark + 1 .. W_List.Last_Index loop
            Solve (I, 0);
         end loop;

         declare
            Subst : Meta_Type_Maps.Map;
            Order : TyVar_Id_Vectors.Vector;
            Ctx : Constraint_Vectors.Vector;
            Group_Binders : Var_Id_Vectors.Vector;
         begin
            if not Restricted then
               for B of Binds loop
                  if M.Info (B.Binder).Var_Scheme = No_Scheme then
                     Collect_Gen_Metas
                       (Real_Type_Id (M.Info (B.Binder).Var_Type),
                        Subst, Order);
                  end if;
               end loop;
            end if;

            --  Shared context from residual wanteds over generalized
            --  metas (deduplicated).
            for I in W_Mark + 1 .. W_List.Last_Index loop
               if W_List (I).Sol = Unsolved then
                  declare
                     Z : constant Real_Type_Id :=
                       Repr (W_List (I).C.Arg);
                     NC : constant Type_Node := M.Node (Z);
                  begin
                     if NC.Kind = TMeta_T
                       and then Subst.Contains (NC.Meta)
                     then
                        declare
                           New_C : constant Constraint :=
                             (Class => W_List (I).C.Class,
                              Arg => Zonk_With (W_List (I).C.Arg,
                                                Subst),
                              Span => W_List (I).C.Span);
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
                     end if;
                  end;
               end if;
            end loop;

            --  Per-binder params; schemes; wanted -> By_Param.
            for B of Binds loop
               if M.Info (B.Binder).Var_Scheme = No_Scheme then
                  Group_Binders.Append (B.Binder);
               end if;
            end loop;

            for B of Binds loop
               if M.Info (B.Binder).Var_Scheme = No_Scheme then
                  declare
                     Zonked : constant Real_Type_Id :=
                       Zonk_With
                         (Real_Type_Id (M.Info (B.Binder).Var_Type),
                          Subst);
                     Sch : Scheme;
                     Params : Var_Id_Vectors.Vector;
                  begin
                     pragma Assert
                       (Restricted or else Meta_Free (Zonked)
                        or else Free_Metas_In_Env_Level (Zonked));
                     for CI in 1 .. Ctx.Last_Index loop
                        Params.Append
                          (M.Mint_Var
                             ((Name => Table.Intern ("$d"),
                               Span => M.Info (B.Binder).Span,
                               others => <>)));
                     end loop;
                     Sch.Tvs := Order;
                     Sch.Context := Ctx;
                     Sch.S_Body := Type_Id (Zonked);
                     M.Vars (B.Binder).Var_Scheme :=
                       Scheme_Id (M.Add (Sch));

                     if not Ctx.Is_Empty then
                        Wraps.Append
                          (Wrap_Rec'(Binder => B.Binder,
                                     Params => Params));
                        Apply_Rec_Params (B.Rhs, Group_Binders,
                                          Params);
                        --  Wanteds owned by this binder that joined
                        --  the context resolve to its params.
                        for I in W_Mark + 1 .. W_List.Last_Index loop
                           if W_List (I).Sol = Unsolved
                             and then W_List (I).Owner =
                                        Var_Id (B.Binder)
                           then
                              declare
                                 W : Wanted_Rec := W_List (I);
                              begin
                                 for CI in 1 .. Ctx.Last_Index loop
                                    if Ctx (CI).Class = W.C.Class
                                      and then Same_Tv_Arg
                                        (Ctx (CI).Arg,
                                         Zonk_With (W.C.Arg, Subst))
                                    then
                                       W.Sol := By_Param;
                                       W.Dict :=
                                         Var_Id (Params.Element (CI));
                                       W_List.Replace_Element (I, W);
                                    end if;
                                 end loop;
                              end;
                           end if;
                        end loop;
                     end if;
                  end;
               end if;
            end loop;
         end;

         --  Wanteds still unsolved after this group float to the
         --  enclosing binding: they are ITS responsibility, to be
         --  discharged by its signature givens or joined to its
         --  inferred context. Without this, a wanted arising inside
         --  an inner let (e.g. a match-compiler join point) keeps
         --  the inner binder as Owner and the enclosing group's
         --  By_Param marking never claims it.
         for I in W_Mark + 1 .. W_List.Last_Index loop
            if W_List (I).Sol = Unsolved then
               declare
                  W : Wanted_Rec := W_List (I);
               begin
                  W.Owner := Saved_Owner;
                  W_List.Replace_Element (I, W);
               end;
            end if;
         end loop;
      end Check_Group;

      ------------------------------------------------------------------
      --  Top level
      ------------------------------------------------------------------

      function Var_Hash (K : Real_Var_Id)
        return Ada.Containers.Hash_Type
      is (Ada.Containers.Hash_Type (K));

      package Var_Nat_Maps is new Ada.Containers.Hashed_Maps
        (Real_Var_Id, Positive,
         Hash => Var_Hash, Equivalent_Keys => "=");

      Binder_Group : Var_Nat_Maps.Map;

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

      Index_Counter : Natural := 0;
      Indices  : array (1 .. Group_Count) of Natural := [others => 0];
      Lowlinks : array (1 .. Group_Count) of Natural := [others => 0];
      On_Stack : array (1 .. Group_Count) of Boolean :=
        [others => False];
      Stack : Nat_Vectors.Vector;
      Adj : array (1 .. Group_Count) of Nat_Vectors.Vector;
      SCCs : Nat_Vectors.Vector;
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
               Lowlinks (V) :=
                 Natural'Min (Lowlinks (V), Lowlinks (W));
            elsif On_Stack (W) then
               Lowlinks (V) :=
                 Natural'Min (Lowlinks (V), Indices (W));
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

      --  Evidence expressions, built once every wanted is decided.
      function Build_Ev (I : Positive) return Real_Expr_Id is
         W : constant Wanted_Rec := W_List (I);
         Span : constant Diagnostics.Source_Span := W.C.Span;
      begin
         case W.Sol is
            when By_Given =>
               return Real_Expr_Id (W.GEv);
            when By_Param =>
               return M.Add (Expr_Node'
                 (Kind => Var_C, Span => Span,
                  V => Real_Var_Id (W.Dict)));
            when By_Instance =>
               declare
                  Result : Real_Expr_Id :=
                    M.Add (Expr_Node'
                      (Kind => Var_C, Span => Span,
                       V => Real_Var_Id
                         (M.Info (Real_Instance_Id (W.Inst))
                            .Dict_Global)));
               begin
                  for S of W.Subs loop
                     Result := M.Add (Expr_Node'
                       (Kind => App_C, Span => Span,
                        Fun => Result, Arg => Build_Ev (S)));
                  end loop;
                  return Result;
               end;
            when Unsolved | By_Error =>
               return M.Add (Expr_Node'
                 (Kind => Var_C, Span => Span,
                  V => M.Mint_Var
                    ((Name => Table.Intern ("$dMISSING"),
                      Span => Span, Is_Global => True,
                      others => <>))));
         end case;
      end Build_Ev;

   begin
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

      declare
         Pos : Natural := 0;
      begin
         for SI in 1 .. SCC_Sizes.Last_Index loop
            declare
               Merged : Bind_Vectors.Vector;
            begin
               if SCC_Sizes (SI) >= 1
                 and then SCCs (Pos + 1) <= Group_Origins.Last_Index
               then
                  Bag.Set_Origin (Group_Origins (SCCs (Pos + 1)));
               end if;
               for K in 1 .. SCC_Sizes (SI) loop
                  for B of M.Top_Binds (SCCs (Pos + K)).Binds loop
                     Merged.Append (B);
                  end loop;
               end loop;
               Pos := Pos + SCC_Sizes (SI);
               Check_Group (Merged);
            end;
         end loop;
      end;

      --  Instance method bodies against instance-substituted schemes,
      --  with the instance context as given evidence via Param_Vars.
      for II in 1 .. M.Last_Instance loop
         declare
            Inst : Instance_Info := M.Info (Real_Instance_Id (II));
         begin
            if Natural (II) <= Inst_Origins.Last_Index then
               Bag.Set_Origin (Inst_Origins (Natural (II)));
            end if;
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
                    Givens.Last_Index;
               begin
                  for HV of Inst.Head_Vars loop
                     Head_T := M.Add (Type_Node'
                       (Kind => TApp_T, T_Fun => Head_T,
                        T_Arg => M.Add (Type_Node'
                          (Kind => TVar_T, Tv => HV))));
                  end loop;
                  for C of Inst.Context loop
                     declare
                        D : constant Real_Var_Id :=
                          M.Mint_Var
                            ((Name => Table.Intern ("$d"),
                              Span => Inst.Span, others => <>));
                     begin
                        Inst.Param_Vars.Append (D);
                        Assume (C, M.Add (Expr_Node'
                          (Kind => Var_C, Span => Inst.Span,
                           V => D)));
                     end;
                  end loop;
                  M.Instances (Real_Instance_Id (II)).Param_Vars :=
                    Inst.Param_Vars;

                  for B of Inst.Method_Binds loop
                     declare
                        BName : constant Names.Name_Id :=
                          M.Info (B.Binder).Name;
                        Found : Boolean := False;
                     begin
                        Current_Owner := Var_Id (B.Binder);
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
                                   W_List.Last_Index;
                              begin
                                 if not Sch.Tvs.Is_Empty then
                                    Map.Include (Sch.Tvs (1),
                                                 Head_T);
                                 end if;
                                 M.Vars (B.Binder).Var_Type :=
                                   Type_Id (Subst_TyVars
                                     (Real_Type_Id (Sch.S_Body),
                                      Map));
                                 Unify
                                   (Infer (B.Rhs),
                                    Real_Type_Id
                                      (M.Info (B.Binder).Var_Type),
                                    M.Info (B.Binder).Span);
                                 for I in W_Mark + 1 ..
                                          W_List.Last_Index
                                 loop
                                    Solve (I, 0);
                                 end loop;
                              end;
                           end if;
                        end loop;
                        Current_Owner := No_Var;
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

                  while Givens.Last_Index > Givens_Mark loop
                     Givens.Delete_Last;
                  end loop;

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

      --  Class default-method bodies: class constraint given via a
      --  dictionary parameter; the default binding gets wrapped.
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
                             Givens.Last_Index;
                           W_Mark : constant Natural :=
                             W_List.Last_Index;
                           Params : Var_Id_Vectors.Vector;
                        begin
                           Current_Owner := Var_Id (B.Binder);
                           for C of Sch.Context loop
                              declare
                                 D : constant Real_Var_Id :=
                                   M.Mint_Var
                                     ((Name => Table.Intern ("$d"),
                                       Span =>
                                         M.Info (B.Binder).Span,
                                       others => <>));
                              begin
                                 Params.Append (D);
                                 Assume (C, M.Add (Expr_Node'
                                   (Kind => Var_C,
                                    Span => M.Info (B.Binder).Span,
                                    V => D)));
                              end;
                           end loop;
                           M.Vars (B.Binder).Var_Type := Sch.S_Body;
                           Unify (Infer (B.Rhs),
                                  Real_Type_Id (Sch.S_Body),
                                  M.Info (B.Binder).Span);
                           for I in W_Mark + 1 .. W_List.Last_Index
                           loop
                              Solve (I, 0);
                           end loop;
                           while Givens.Last_Index > Givens_Mark loop
                              Givens.Delete_Last;
                           end loop;
                           Current_Owner := No_Var;
                           if not Params.Is_Empty then
                              Wraps.Append
                                (Wrap_Rec'(Binder => B.Binder,
                                           Params => Params));
                           end if;
                        end;
                     end if;
                  end loop;
               end;
            end loop;
         end;
      end loop;

      --  Defaulting, then leftover residuals are errors.
      Try_Default;
      for I in 1 .. W_List.Last_Index loop
         if W_List (I).Sol = Unsolved then
            declare
               Z : constant Real_Type_Id := Repr (W_List (I).C.Arg);
               N : constant Type_Node := M.Node (Z);
            begin
               if N.Kind = TVar_T then
                  Bag.Add (Diagnostics.Error,
                           Diagnostics.Type_Signature_Too_General,
                           W_List (I).C.Span,
                           "could not deduce '"
                           & Table.Text
                               (M.Info (W_List (I).C.Class).Name)
                           & " " & Type_Str (W_List (I).C.Arg)
                           & "' required by the definition");
               end if;
            end;
         end if;
      end loop;

      --  Rewrite occurrence sites with their evidence.
      declare
         I : Positive := 1;
      begin
         while I <= W_List.Last_Index loop
            if W_List (I).Site /= No_Expr then
               declare
                  Site : constant Expr_Id := W_List (I).Site;
                  Original : constant Expr_Node :=
                    M.Node (Real_Expr_Id (Site));
                  Copy : constant Real_Expr_Id :=
                    M.Add (Original);
                  Chain : Real_Expr_Id := Copy;
                  J : Positive := I;
               begin
                  while J <= W_List.Last_Index
                    and then W_List (J).Site = Site
                  loop
                     Chain := M.Add (Expr_Node'
                       (Kind => App_C, Span => Original.Span,
                        Fun => Chain, Arg => Build_Ev (J)));
                     J := J + 1;
                  end loop;
                  M.Exprs.Replace_Element
                    (Real_Expr_Id (Site), M.Node (Chain));
                  I := J;
               end;
            else
               I := I + 1;
            end if;
         end loop;
      end;

      --  Apply dictionary-lambda wraps.
      for W of Wraps loop
         declare
            procedure Wrap_In (Binds : in out Bind_Vectors.Vector) is
            begin
               for BI in 1 .. Binds.Last_Index loop
                  if Binds (BI).Binder = W.Binder then
                     declare
                        Rhs : Real_Expr_Id := Binds (BI).Rhs;
                        Span : constant Diagnostics.Source_Span :=
                          M.Info (W.Binder).Span;
                     begin
                        for PI in reverse 1 .. W.Params.Last_Index loop
                           Rhs := M.Add (Expr_Node'
                             (Kind => Lam_C, Span => Span,
                              Binder => W.Params (PI),
                              Lam_Body => Rhs));
                        end loop;
                        Binds.Replace_Element
                          (BI, Bind_Pair'(Binder => W.Binder,
                                          Rhs => Rhs));
                     end;
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
                  N : constant Expr_Node :=
                    M.Node (Real_Expr_Id (EI));
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
            for CI in 1 .. M.Last_Class loop
               declare
                  Binds : Bind_Vectors.Vector :=
                    M.Classes (Real_Class_Id (CI)).Default_Binds;
               begin
                  Wrap_In (Binds);
                  M.Classes (Real_Class_Id (CI)).Default_Binds :=
                    Binds;
               end;
            end loop;
         end;
      end loop;

      --  Re-zonk top-level schemes so defaulting shows through.
      for G of M.Top_Binds loop
         for B of G.Binds loop
            declare
               SId : constant Scheme_Id :=
                 M.Info (B.Binder).Var_Scheme;
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

      --  Postcondition safety on error paths.
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
