with AHC.Inst_Match;
with Ada.Containers.Vectors;

package body AHC.Elaborate is

   use AHC.Core;
   use type Names.Name_Id;
   use type AHC.Inst_Match.Match_Result;

   --  An instance needs a dictionary binding iff it came from user
   --  source (its Method_Binds may still be empty if all methods
   --  default -- `instance MonadPlus Maybe` with no where-block).
   function Needs_Dict (M : Core.Core_Module; I : Instance_Info)
     return Boolean
   is ((I.From_Source or else I.Is_GND)
       and then I.Dict_Global in 1 .. M.Last_Var);

   function All_Dictionaries_Built (M : Core.Core_Module) return Boolean
   is
   begin
      for II in 1 .. M.Last_Instance loop
         declare
            I : constant Instance_Info :=
              M.Info (Real_Instance_Id (II));
            Found : Boolean := False;
         begin
            if Needs_Dict (M, I) then
               for G of M.Top_Binds loop
                  for B of G.Binds loop
                     if Var_Id (B.Binder) = I.Dict_Global then
                        Found := True;
                     end if;
                  end loop;
               end loop;
               if not Found then
                  return False;
               end if;
            end if;
         end;
      end loop;
      return True;
   end All_Dictionaries_Built;

   procedure Elaborate_Dictionaries
     (Table : in out Names.Name_Table;
      Bag   : in out Diagnostics.Diagnostic_Bag;
      M     : in out Core.Core_Module;
      Env   : in out Builtins.Global_Env;
      Inst_Origins : Diagnostics.Origin_Vectors.Vector :=
        Diagnostics.Origin_Vectors.Empty_Vector)
   is

      --  Given evidence: instance-context constraints and their
      --  lambda-parameter dictionary variables.
      type Given_Ev is record
         C : Constraint;
         D : Real_Var_Id;
      end record;

      package Given_Vectors is new Ada.Containers.Vectors
        (Positive, Given_Ev);

      --  Class defaults lifted to top-level bindings, memoized by
      --  their local binder.
      Lifted : Var_Id_Vectors.Vector;

      function Same_Head_Arg
        (M2 : Core.Core_Module; A, B : Real_Type_Id) return Boolean
      is
         NA : constant Type_Node := M2.Node (A);
         NB : constant Type_Node := M2.Node (B);
      begin
         --  Structural (M147 review): an inferred or GND context may
         --  constrain a constructed type (`C (Maybe a)`), not only a
         --  plain tyvar.
         if NA.Kind /= NB.Kind then
            return False;
         end if;
         case NA.Kind is
            when TVar_T => return NA.Tv = NB.Tv;
            when TMeta_T => return NA.Meta = NB.Meta;
            when TCon_T => return NA.Con = NB.Con;
            when TApp_T =>
               return Same_Head_Arg (M2, NA.T_Fun, NB.T_Fun)
                 and then Same_Head_Arg (M2, NA.T_Arg, NB.T_Arg);
            when TFun_T =>
               return Same_Head_Arg (M2, NA.From, NB.From)
                 and then Same_Head_Arg (M2, NA.To, NB.To);
         end case;
      end Same_Head_Arg;

      --  T with the instance head variables replaced (Subst maps
      --  Vars (I) to Args (I)); applications are rebuilt canonically.
      function Subst_Head
        (T : Real_Type_Id;
         Vars : TyVar_Id_Vectors.Vector;
         Args : Type_Id_Vectors.Vector) return Real_Type_Id
      is
         N : constant Type_Node := M.Node (T);
      begin
         case N.Kind is
            when TVar_T =>
               for I in 1 .. Vars.Last_Index loop
                  if Vars (I) = N.Tv and then I <= Args.Last_Index then
                     return Args (I);
                  end if;
               end loop;
               return T;
            when TApp_T =>
               return Builtins.Make_App
                 (M, Env, Subst_Head (N.T_Fun, Vars, Args),
                  Subst_Head (N.T_Arg, Vars, Args));
            when TFun_T =>
               return M.Add (Type_Node'
                 (Kind => TFun_T,
                  From => Subst_Head (N.From, Vars, Args),
                  To => Subst_Head (N.To, Vars, Args)));
            when others =>
               return T;
         end case;
      end Subst_Head;

      --  Does a dictionary for class From contain (through superclass
      --  selectors, transitively) one for class To?
      function Entails (From, To : Real_Class_Id; Depth : Natural)
        return Boolean
      is
      begin
         if From = To then
            return True;
         end if;
         if Depth > 63 then
            return False;
         end if;
         for S of M.Info (From).Supers loop
            if Entails (S, To, Depth + 1) then
               return True;
            end if;
         end loop;
         return False;
      end Entails;

      --  The superclass-selector path from a From dictionary Ev down
      --  to a To dictionary. Pre: Entails (From, To).
      function Super_Path
        (From, To : Real_Class_Id; Ev : Real_Expr_Id;
         Span : Diagnostics.Source_Span; Depth : Natural)
         return Real_Expr_Id
        with Pre => Entails (From, To, Depth)
      is
         Info : constant Class_Info := M.Info (From);
      begin
         if From = To then
            return Ev;
         end if;
         for I in 1 .. Info.Supers.Last_Index loop
            if Entails (Info.Supers (I), To, Depth + 1) then
               return Super_Path
                 (Info.Supers (I), To,
                  (if I <= Info.Super_Sels.Last_Index
                   then M.Add (Expr_Node'
                     (Kind => App_C, Span => Span,
                      Fun => M.Add (Expr_Node'
                        (Kind => Var_C, Span => Span,
                         V => Info.Super_Sels (I))),
                      Arg => Ev))
                   else Ev),
                  Span, Depth + 1);
            end if;
         end loop;
         raise Program_Error;   --  unreachable under the Pre
      end Super_Path;

      --  Solve C to a dictionary expression using Givens and the
      --  instance table (head-shape matching only: the typechecker
      --  already established solvability). Mirrors the typechecker's
      --  Solve: a given entails its superclasses (Assume), and an
      --  instance's context is instantiated at the constraint's head
      --  arguments before it is solved (M142 review: both were
      --  missing, so superclass dictionaries of instances with
      --  contexts came out $dMISSING at run time).
      --  Instance selection's view of a zonked type (M147): the wired
      --  Rational placeholder read as Data.Ratio's `Ratio Integer`, as
      --  the typechecker's Norm_TC does.
      function Norm_EL (T : Real_Type_Id) return Real_Type_Id is
         N : constant Type_Node := M.Node (T);
      begin
         if N.Kind = TCon_T and then TyCon_Id (N.Con) = Env.Rational_TC then
            declare
               SC : constant Builtins.Syn_Maps.Cursor :=
                 Env.Synonyms.Find (Table.Intern ("Rational"));
            begin
               if Builtins.Syn_Maps.Has_Element (SC)
                 and then Builtins.Syn_Maps.Element (SC).Core_Rhs /= No_Type
               then
                  return Real_Type_Id
                    (Builtins.Syn_Maps.Element (SC).Core_Rhs);
               end if;
            end;
         end if;
         return T;
      end Norm_EL;

      function Match_EL is new Inst_Match.Match_Instance (Norm_EL);

      function Solve_Ev
        (C : Constraint; Givens : Given_Vectors.Vector;
         Span : Diagnostics.Source_Span; Depth : Natural)
         return Real_Expr_Id
      is
      begin
         if Depth > 63 then
            return M.Add (Expr_Node'
              (Kind => Var_C, Span => Span,
               V => M.Mint_Var
                 ((Name => Table.Intern ("$dLOOP"), Span => Span,
                   Is_Global => True, others => <>))));
         end if;

         for G of Givens loop
            if G.C.Class = C.Class
              and then Same_Head_Arg (M, G.C.Arg, C.Arg)
            then
               return M.Add (Expr_Node'
                 (Kind => Var_C, Span => Span, V => G.D));
            end if;
         end loop;

         --  A given entails its superclasses: `Ord a` gives `Eq a`.
         for G of Givens loop
            if Same_Head_Arg (M, G.C.Arg, C.Arg)
              and then Entails (G.C.Class, C.Class, 0)
            then
               return Super_Path
                 (G.C.Class, C.Class,
                  M.Add (Expr_Node'
                    (Kind => Var_C, Span => Span, V => G.D)),
                  Span, 0);
            end if;
         end loop;

         --  Instance selection by one-way matching (M147), the same
         --  matcher the typechecker's Solve uses, so the two can never
         --  pick different instances.
         for I of M.Info (C.Class).Instances loop
            declare
               Inst : constant Instance_Info := M.Info (I);
               Args : Type_Id_Vectors.Vector;
            begin
               if Match_EL (M, Env, Inst, C.Arg, Args)
                 = Inst_Match.Matched
               then
                  declare
                     Result : Real_Expr_Id :=
                       M.Add (Expr_Node'
                         (Kind => Var_C, Span => Span,
                          V => Real_Var_Id (Inst.Dict_Global)));
                  begin
                     for IC of Inst.Context loop
                        declare
                           Sub : constant Real_Expr_Id :=
                             Solve_Ev
                               (Constraint'
                                  (Class => IC.Class,
                                   Arg => Subst_Head
                                     (IC.Arg, Inst.Head_Vars, Args),
                                   Span => IC.Span),
                                Givens, Span, Depth + 1);
                        begin
                           Result := M.Add (Expr_Node'
                             (Kind => App_C, Span => Span,
                              Fun => Result, Arg => Sub));
                        end;
                     end loop;
                     return Result;
                  end;
               end if;
            end;
         end loop;

         --  Unreachable when the typechecker accepted the module;
         --  reachable in error recovery.
         return M.Add (Expr_Node'
           (Kind => Var_C, Span => Span,
            V => M.Mint_Var
              ((Name => Table.Intern ("$dMISSING"), Span => Span,
                Is_Global => True, others => <>))));
      end Solve_Ev;

      --  Lift a class default binding to a top-level bind (once).
      procedure Lift_Default (B : Bind_Pair) is
      begin
         for V of Lifted loop
            if V = B.Binder then
               return;
            end if;
         end loop;
         Lifted.Append (B.Binder);
         declare
            G : Top_Bind;
         begin
            G.Is_Rec := True;
            G.Binds.Append (B);
            M.Top_Binds.Append (G);
         end;
      end Lift_Default;

   begin
      for II in 1 .. M.Last_Instance loop
         declare
            Inst : constant Instance_Info :=
              M.Info (Real_Instance_Id (II));
         begin
            if Natural (II) <= Inst_Origins.Last_Index then
               Bag.Set_Origin (Inst_Origins (Natural (II)));
            end if;
            if Needs_Dict (M, Inst) and then Inst.Is_GND then
               --  GeneralizedNewtypeDeriving (M147): with newtypes
               --  erased, the dictionary IS the representation's -
               --  \ctx... -> evidence for C GND_Target under the
               --  instance's context. No methods, no knot.
               declare
                  Span : constant Diagnostics.Source_Span := Inst.Span;
                  Givens : Given_Vectors.Vector;
                  Params : Var_Id_Vectors.Vector;
                  Dict : Real_Expr_Id;
                  G : Top_Bind;
               begin
                  for CI in 1 .. Inst.Context.Last_Index loop
                     declare
                        D : constant Real_Var_Id := M.Mint_Var
                          ((Name => Table.Intern ("$d"),
                            Span => Span, others => <>));
                     begin
                        Params.Append (D);
                        Givens.Append
                          (Given_Ev'(C => Inst.Context (CI), D => D));
                     end;
                  end loop;
                  --  A fresh record: the methods are the
                  --  representation's (selected out of its dictionary,
                  --  bound once), but the superclass slots are the
                  --  NEWTYPE's own instances - with a hand-written
                  --  `Eq Age`, (==) through an `Ord Age` dictionary
                  --  is Age's, as in GHC (M147 review: the slots were
                  --  the representation's).
                  declare
                     Cl : constant Real_Class_Id :=
                       Real_Class_Id (Inst.Of_Class);
                     Cl_Info : constant Class_Info := M.Info (Cl);
                     Rep_V : constant Real_Var_Id := M.Mint_Var
                       ((Name => Table.Intern ("$drep"), Span => Span,
                         others => <>));
                     Rep_D : constant Real_Expr_Id := Solve_Ev
                       (Constraint'(Class => Inst.Of_Class,
                                    Arg => Real_Type_Id (Inst.GND_Target),
                                    Span => Span),
                        Givens, Span, 0);
                     Head_T : constant Real_Type_Id :=
                       Inst_Match.Instance_Type (M, Env, Inst);
                     Supers : Expr_Id_Vectors.Vector;
                     Methods : Expr_Id_Vectors.Vector;
                     Binds : Bind_Vectors.Vector;
                  begin
                     for Super of Cl_Info.Supers loop
                        Supers.Append
                          (Solve_Ev
                             (Constraint'(Class => Super, Arg => Head_T,
                                          Span => Span),
                              Givens, Span, 0));
                     end loop;
                     for MI in 1 .. Cl_Info.Methods.Last_Index loop
                        declare
                           Sel : constant Real_Expr_Id := M.Add (Expr_Node'
                             (Kind => Var_C, Span => Span,
                              V => Real_Var_Id
                                     (Cl_Info.Methods.Element (MI).Selector)));
                           Rep : constant Real_Expr_Id := M.Add (Expr_Node'
                             (Kind => Var_C, Span => Span, V => Rep_V));
                        begin
                           Methods.Append (M.Add (Expr_Node'
                             (Kind => App_C, Span => Span,
                              Fun => Sel, Arg => Rep)));
                        end;
                     end loop;
                     Binds.Append (Bind_Pair'(Binder => Rep_V, Rhs => Rep_D));
                     Dict := M.Add (Expr_Node'
                       (Kind => Let_C, Span => Span, Is_Rec => False,
                        Binds => Binds,
                        Let_Body => Mk_Dict (M, Cl, Supers, Methods, Span)));
                  end;
                  for PI in reverse 1 .. Params.Last_Index loop
                     Dict := M.Add (Expr_Node'
                       (Kind => Lam_C, Span => Span,
                        Binder => Params (PI), Lam_Body => Dict));
                  end loop;
                  G.Is_Rec := False;
                  G.Binds.Append
                    (Bind_Pair'(Binder => Real_Var_Id (Inst.Dict_Global),
                                Rhs => Dict));
                  M.Top_Binds.Append (G);
               end;
            elsif Needs_Dict (M, Inst) then
               declare
                  Cl : constant Real_Class_Id :=
                    Real_Class_Id (Inst.Of_Class);
                  Cl_Info : constant Class_Info := M.Info (Cl);
                  Span : constant Diagnostics.Source_Span := Inst.Span;
                  Givens : Given_Vectors.Vector;
                  Supers : Expr_Id_Vectors.Vector;
                  Methods : Expr_Id_Vectors.Vector;
                  Params : Var_Id_Vectors.Vector;
                  Self_D : constant Real_Var_Id :=
                    M.Mint_Var ((Name => Table.Intern ("$dSelf"),
                                 Span => Inst.Span, others => <>));
               begin
                  --  One dictionary parameter per context constraint
                  --  (reusing the typechecker's params so method
                  --  bodies reference the same evidence variables).
                  for CI in 1 .. Inst.Context.Last_Index loop
                     declare
                        D : constant Real_Var_Id :=
                          (if CI <= Inst.Param_Vars.Last_Index
                           then Inst.Param_Vars (CI)
                           else M.Mint_Var
                             ((Name => Table.Intern ("$d"),
                               Span => Span, others => <>)));
                     begin
                        Params.Append (D);
                        Givens.Append
                          (Given_Ev'(C => Inst.Context (CI), D => D));
                     end;
                  end loop;

                  --  Superclass dictionaries at the instance head.
                  declare
                     Head_T : constant Real_Type_Id :=
                       Inst_Match.Instance_Type (M, Env, Inst);
                  begin
                     for Super of Cl_Info.Supers loop
                        Supers.Append
                          (Solve_Ev
                             (Constraint'(Class => Super,
                                          Arg => Head_T,
                                          Span => Span),
                              Givens, Span, 0));
                     end loop;
                  end;

                  --  Method implementations in class order.
                  for MI in 1 .. Cl_Info.Methods.Last_Index loop
                     declare
                        Mth : constant Method_Info :=
                          Cl_Info.Methods (MI);
                        Impl : Expr_Id := No_Expr;

                        --  Report default methods for the builtin
                        --  classes, built against this dictionary's
                        --  own knot ($dSelf) so sibling methods
                        --  resolve to THIS instance. No_Expr when the
                        --  (class, method) pair has no default.
                        function Builtin_Default return Expr_Id is
                           function V2 (Vr : Real_Var_Id)
                             return Real_Expr_Id
                           is (M.Add (Expr_Node'
                                (Kind => Var_C, Span => Span,
                                 V => Vr)));

                           function Ap2E (F, A : Real_Expr_Id)
                             return Real_Expr_Id
                           is (M.Add (Expr_Node'
                                (Kind => App_C, Span => Span,
                                 Fun => F, Arg => A)));

                           function Lam2E
                             (P : Real_Var_Id; B : Real_Expr_Id)
                             return Real_Expr_Id
                           is (M.Add (Expr_Node'
                                (Kind => Lam_C, Span => Span,
                                 Binder => P, Lam_Body => B)));

                           function Fresh2 (Nm : String)
                             return Real_Var_Id
                           is (M.Mint_Var
                                ((Name => Table.Intern (Nm),
                                  Span => Span, others => <>)));

                           --  Sibling method I of this dictionary.
                           function Sib (I : Positive)
                             return Real_Expr_Id
                           is (Ap2E (V2 (Real_Var_Id
                                 (Cl_Info.Methods.Element (I).Selector)),
                               V2 (Self_D)));

                           function Global_Named (Nm : String)
                             return Expr_Id
                           is
                              C : constant Builtins.Var_Maps.Cursor
                                := Env.Values.Find
                                     (Table.Intern (Nm));
                           begin
                              if Builtins.Var_Maps.Has_Element (C)
                              then
                                 return Expr_Id
                                   (V2 (Builtins.Var_Maps.Element
                                          (C)));
                              end if;
                              return No_Expr;
                           end Global_Named;

                           --  case E of True -> T; _ -> F
                           function Bool_Case2
                             (E, T, F : Real_Expr_Id)
                             return Real_Expr_Id
                           is
                              Alts : Alt_Id_Vectors.Vector;
                           begin
                              Alts.Append (M.Add (Alt_Node'
                                (Kind => Con_Alt, Span => Span,
                                 A_Con => Real_DataCon_Id
                                            (Env.True_DC),
                                 Binders =>
                                   Var_Id_Vectors.Empty_Vector,
                                 Alt_Body => T)));
                              Alts.Append (M.Add (Alt_Node'
                                (Kind => Default_Alt, Span => Span,
                                 Alt_Body => F)));
                              return M.Add (Expr_Node'
                                (Kind => Case_C, Span => Span,
                                 Scrutinee => E, Alts => Alts));
                           end Bool_Case2;

                           --  case (compare-of-self x y) of
                           --    TAG -> A; _ -> B
                           function Cmp_Case
                             (X, Y : Real_Var_Id;
                              Tag : Positive;
                              A, B : Real_Expr_Id)
                             return Real_Expr_Id
                           is
                              Ord_TC : constant Real_TyCon_Id :=
                                Real_TyCon_Id (Env.Ordering_TC);
                              Alts : Alt_Id_Vectors.Vector;
                           begin
                              Alts.Append (M.Add (Alt_Node'
                                (Kind => Con_Alt, Span => Span,
                                 A_Con => Real_DataCon_Id
                                   (M.Info (Ord_TC).Cons.Element (Tag)),
                                 Binders =>
                                   Var_Id_Vectors.Empty_Vector,
                                 Alt_Body => A)));
                              Alts.Append (M.Add (Alt_Node'
                                (Kind => Default_Alt, Span => Span,
                                 Alt_Body => B)));
                              return M.Add (Expr_Node'
                                (Kind => Case_C, Span => Span,
                                 Scrutinee =>
                                   Ap2E (Ap2E (Sib (1), V2 (X)),
                                         V2 (Y)),
                                 Alts => Alts));
                           end Cmp_Case;

                           function Ord_Con (Tag : Positive)
                             return Real_Expr_Id
                           is (M.Add (Expr_Node'
                                (Kind => Con_C, Span => Span,
                                 Con => Real_DataCon_Id
                                   (M.Info (Real_TyCon_Id
                                      (Env.Ordering_TC)).Cons.Element
                                        (Tag)))));

                           function Bool_Con (T : Boolean)
                             return Real_Expr_Id
                           is (M.Add (Expr_Node'
                                (Kind => Con_C, Span => Span,
                                 Con => Real_DataCon_Id
                                   (if T then Env.True_DC
                                    else Env.False_DC))));
                        begin
                           if Inst.Of_Class = Env.Show_Cl then
                              case MI is
                                 when 1 =>
                                    --  show x = showsPrec 0 x ""
                                    declare
                                       X : constant Real_Var_Id :=
                                         Fresh2 ("x");
                                    begin
                                       return Expr_Id (Lam2E (X,
                                         Ap2E (Ap2E (Ap2E (Sib (2),
                                           M.Add (Expr_Node'
                                             (Kind => Lit_C,
                                              Span => Span,
                                              Lit => (Kind => L_Int,
                                                Text => Names.Name_Id
                                                  (Table.Intern
                                                     ("0")))))),
                                           V2 (X)),
                                           M.Add (Expr_Node'
                                             (Kind => Lit_C,
                                              Span => Span,
                                              Lit =>
                                                (Kind => L_String,
                                                 Text =>
                                                   Names.No_Name))))));
                                    end;
                                 when 2 =>
                                    --  showsPrec _ x s = show x ++ s
                                    declare
                                       D : constant Real_Var_Id :=
                                         Fresh2 ("d");
                                       X : constant Real_Var_Id :=
                                         Fresh2 ("x");
                                       St : constant Real_Var_Id :=
                                         Fresh2 ("s");
                                    begin
                                       return Expr_Id (Lam2E (D,
                                         Lam2E (X, Lam2E (St,
                                           Ap2E (Ap2E
                                             (V2 (Real_Var_Id
                                                (Env.Append_V)),
                                              Ap2E (Sib (1),
                                                    V2 (X))),
                                            V2 (St))))));
                                    end;
                                 when 3 =>
                                    --  showList = showsList_ self
                                    declare
                                       G : constant Expr_Id :=
                                         Global_Named ("showsList_");
                                    begin
                                       if G = No_Expr then
                                          return No_Expr;
                                       end if;
                                       return Expr_Id
                                         (Ap2E (Real_Expr_Id (G),
                                                V2 (Self_D)));
                                    end;
                                 when others =>
                                    return No_Expr;
                              end case;
                           elsif Inst.Of_Class = Env.Eq_Cl then
                              declare
                                 NotF : constant Expr_Id :=
                                   Global_Named ("not");
                                 X : constant Real_Var_Id :=
                                   Fresh2 ("x");
                                 Y : constant Real_Var_Id :=
                                   Fresh2 ("y");
                                 Other : constant Positive :=
                                   (if MI = 1 then 2 else 1);
                              begin
                                 if NotF = No_Expr or else MI > 2
                                 then
                                    return No_Expr;
                                 end if;
                                 --  each of ==, /= is the negation
                                 --  of the other
                                 return Expr_Id (Lam2E (X,
                                   Lam2E (Y,
                                     Ap2E (Real_Expr_Id (NotF),
                                       Ap2E (Ap2E (Sib (Other),
                                         V2 (X)), V2 (Y))))));
                              end;
                           elsif Inst.Of_Class = Env.Ord_Cl then
                              declare
                                 X : constant Real_Var_Id :=
                                   Fresh2 ("x");
                                 Y : constant Real_Var_Id :=
                                   Fresh2 ("y");
                              begin
                                 case MI is
                                    when 1 =>
                                       --  compare x y =
                                       --    if x == y then EQ
                                       --    else if x <= y then LT
                                       --    else GT
                                       --  (== from the superclass
                                       --  Eq dictionary)
                                       declare
                                          Eq_Dict : constant
                                            Real_Expr_Id :=
                                              Ap2E (V2 (Real_Var_Id
                                                (Cl_Info.Super_Sels.Element
                                                   (1))),
                                               V2 (Self_D));
                                          Eq_M : constant
                                            Real_Expr_Id :=
                                              Ap2E (V2 (Real_Var_Id
                                                (M.Info
                                                  (Real_Class_Id
                                                    (Env.Eq_Cl))
                                                  .Methods (1)
                                                  .Selector)),
                                               Eq_Dict);
                                       begin
                                          return Expr_Id (Lam2E (X,
                                            Lam2E (Y,
                                             Bool_Case2
                                              (Ap2E (Ap2E (Eq_M,
                                                 V2 (X)), V2 (Y)),
                                               Ord_Con (2),
                                               Bool_Case2
                                                 (Ap2E (Ap2E
                                                    (Sib (3),
                                                     V2 (X)),
                                                  V2 (Y)),
                                                  Ord_Con (1),
                                                  Ord_Con (3))))));
                                       end;
                                    when 2 =>
                                       --  x < y: compare is LT
                                       return Expr_Id (Lam2E (X,
                                         Lam2E (Y, Cmp_Case (X, Y,
                                           1, Bool_Con (True),
                                           Bool_Con (False)))));
                                    when 3 =>
                                       --  x <= y: compare not GT
                                       return Expr_Id (Lam2E (X,
                                         Lam2E (Y, Cmp_Case (X, Y,
                                           3, Bool_Con (False),
                                           Bool_Con (True)))));
                                    when 4 =>
                                       --  x > y: compare is GT
                                       return Expr_Id (Lam2E (X,
                                         Lam2E (Y, Cmp_Case (X, Y,
                                           3, Bool_Con (True),
                                           Bool_Con (False)))));
                                    when 5 =>
                                       --  x >= y: compare not LT
                                       return Expr_Id (Lam2E (X,
                                         Lam2E (Y, Cmp_Case (X, Y,
                                           1, Bool_Con (False),
                                           Bool_Con (True)))));
                                    when 6 =>
                                       --  max
                                       return Expr_Id (Lam2E (X,
                                         Lam2E (Y, Cmp_Case (X, Y,
                                           1, V2 (Y), V2 (X)))));
                                    when 7 =>
                                       --  min
                                       return Expr_Id (Lam2E (X,
                                         Lam2E (Y, Cmp_Case (X, Y,
                                           3, V2 (Y), V2 (X)))));
                                    when others =>
                                       return No_Expr;
                                 end case;
                              end;
                           elsif Inst.Of_Class = Env.Monad_Cl then
                              case MI is
                                 when 2 =>
                                    --  m >> k = m >>= \_ -> k
                                    declare
                                       Mv : constant Real_Var_Id :=
                                         Fresh2 ("m");
                                       K : constant Real_Var_Id :=
                                         Fresh2 ("k");
                                       U : constant Real_Var_Id :=
                                         Fresh2 ("u");
                                    begin
                                       return Expr_Id (Lam2E (Mv,
                                         Lam2E (K,
                                           Ap2E (Ap2E (Sib (1),
                                             V2 (Mv)),
                                             Lam2E (U, V2 (K))))));
                                    end;
                                 when 3 =>
                                    --  return = pure, base's default:
                                    --  the whole-program frontend can
                                    --  solve Applicative at this
                                    --  instance's head right here.
                                    --  (Applicative is a Prelude
                                    --  SOURCE class: Env holds only
                                    --  builtin and Prelude entities,
                                    --  so a user class of that name
                                    --  can no longer stand in - a
                                    --  scan of every class by name
                                    --  let it, M75 review.)
                                    declare
                                       App_N : constant Names
                                         .Real_Name_Id :=
                                           Table.Intern ("Applicative");
                                       App_Cl : constant Class_Id :=
                                         (if Env.Classes.Contains (App_N)
                                          then Class_Id
                                            (Env.Classes.Element (App_N))
                                          else No_Class);
                                       PureF : constant Expr_Id :=
                                         Global_Named ("pure");
                                    begin
                                       if App_Cl = No_Class
                                         or else PureF = No_Expr
                                       then
                                          return No_Expr;
                                       end if;
                                       declare
                                          --  The full instance head (M147 review: a flexible
                                          --  `Monad (P Int)` was rebuilt as bare `P`).
                                          H : constant Real_Type_Id :=
                                            Inst_Match.Instance_Type (M, Env, Inst);
                                          --  Monad does NOT have
                                          --  Applicative as a
                                          --  superclass here, so the
                                          --  instance can genuinely be
                                          --  missing. Solve_Ev's
                                          --  contract is that the
                                          --  typechecker already
                                          --  proved solvability; it
                                          --  answers $dMISSING
                                          --  otherwise, which would
                                          --  only fail when the
                                          --  program runs. Say so at
                                          --  compile time instead.
                                          Has_App : Boolean := False;
                                       begin
                                          for I2 of M.Info (App_Cl)
                                                      .Instances
                                          loop
                                             declare
                                                AI : constant Instance_Info
                                                  := M.Info (I2);
                                                HT : constant Real_Type_Id
                                                  := Inst_Match
                                                       .Instance_Type
                                                         (M, Env, Inst);
                                                Ign : Type_Id_Vectors
                                                  .Vector;
                                             begin
                                                --  An Applicative
                                                --  instance covering
                                                --  this Monad's head
                                                --  (M147: by matching).
                                                if Match_EL
                                                     (M, Env, AI, HT, Ign)
                                                   = Inst_Match.Matched
                                                then
                                                   Has_App := True;
                                                end if;
                                             end;
                                          end loop;
                                          if not Has_App then
                                             Bag.Add
                                               (Diagnostics.Error,
                                                Diagnostics
                                                  .Class_No_Instance,
                                                Inst.Span,
                                                "no instance for"
                                                & " 'Applicative "
                                                & Table.Text
                                                    (Names.Real_Name_Id
                                                      (M.Info
                                                        (Real_TyCon_Id
                                                          (Inst.Head))
                                                        .Name))
                                                & "', required by the"
                                                & " default for"
                                                & " 'return'");
                                             return No_Expr;
                                          end if;
                                          return Expr_Id
                                            (Ap2E (Real_Expr_Id
                                                     (PureF),
                                               Solve_Ev
                                                 (Constraint'
                                                    (Class => App_Cl,
                                                     Arg => H,
                                                     Span => Span),
                                                  Givens, Span, 0)));
                                       end;
                                    end;
                                 when 4 =>
                                    --  fail = error (2010's shape)
                                    declare
                                       ErrF : constant Expr_Id :=
                                         Global_Named ("error");
                                       S2 : constant Real_Var_Id :=
                                         Fresh2 ("s");
                                    begin
                                       if ErrF = No_Expr then
                                          return No_Expr;
                                       end if;
                                       return Expr_Id (Lam2E (S2,
                                         Ap2E (Real_Expr_Id (ErrF),
                                               V2 (S2))));
                                    end;
                                 when others =>
                                    return No_Expr;
                              end case;
                           elsif (Inst.Of_Class = Env.Enum_Cl
                                  and then MI in 1 | 2 | 5 .. 8)
                             or else (Inst.Of_Class = Env.Fractional_Cl
                                      and then MI in 1 .. 2)
                           then
                              --  The Report's Enum and Fractional class
                              --  defaults (Prelude's enumSuccDefault_
                              --  ...), applied to this dictionary - a
                              --  user instance with only toEnum and
                              --  fromEnum was $mMISSING (M146 review).
                              declare
                                 F : constant Expr_Id :=
                                   Global_Named
                                     ((if Inst.Of_Class = Env.Fractional_Cl
                                       then (if MI = 1
                                             then "fracDivDefault_"
                                             else "fracRecipDefault_")
                                       else
                                         (case MI is
                                            when 1 => "enumSuccDefault_",
                                            when 2 => "enumPredDefault_",
                                            when 5 => "enumFromDefault_",
                                            when 6 =>
                                              "enumFromThenDefault_",
                                            when 7 =>
                                              "enumFromToDefault_",
                                            when others =>
                                              "enumFromThenToDefault_")));
                              begin
                                 if F = No_Expr then
                                    return No_Expr;
                                 end if;
                                 return Expr_Id
                                   (Ap2E (Real_Expr_Id (F), V2 (Self_D)));
                              end;
                           elsif Inst.Of_Class = Env.Floating_Cl
                             and then MI in 16 .. 18
                           then
                              --  asinh/acosh/atanh: GHC's class
                              --  defaults (Prelude's asinhDefault_
                              --  ...), applied to this dictionary.
                              declare
                                 F : constant Expr_Id :=
                                   Global_Named
                                     ((case MI is
                                         when 16 => "asinhDefault_",
                                         when 17 => "acoshDefault_",
                                         when others => "atanhDefault_"));
                              begin
                                 if F = No_Expr then
                                    return No_Expr;
                                 end if;
                                 return Expr_Id
                                   (Ap2E (Real_Expr_Id (F), V2 (Self_D)));
                              end;
                           end if;
                           return No_Expr;
                        end Builtin_Default;
                     begin
                        for B of Inst.Method_Binds loop
                           if M.Info (B.Binder).Name = Mth.Name then
                              Impl := Expr_Id (B.Rhs);
                           end if;
                        end loop;
                        if Impl = No_Expr then
                           --  Fall back to the class default, applied
                           --  to this very dictionary (letrec knot).
                           for B of M.Classes (Cl).Default_Binds loop
                              if M.Info (B.Binder).Name = Mth.Name
                              then
                                 Lift_Default (B);
                                 Impl := Expr_Id
                                   (M.Add (Expr_Node'
                                      (Kind => App_C, Span => Span,
                                       Fun => M.Add (Expr_Node'
                                         (Kind => Var_C,
                                          Span => Span,
                                          V => B.Binder)),
                                       Arg => M.Add (Expr_Node'
                                         (Kind => Var_C,
                                          Span => Span,
                                          V => Self_D)))));
                              end if;
                           end loop;
                        end if;
                        if Impl = No_Expr then
                           Impl := Builtin_Default;
                        end if;
                        if Impl = No_Expr then
                           Impl := Expr_Id
                             (M.Add (Expr_Node'
                                (Kind => Var_C, Span => Span,
                                 V => M.Mint_Var
                                   ((Name =>
                                       Table.Intern ("$mMISSING"),
                                     Span => Span,
                                     Is_Global => True,
                                     others => <>)))));
                        end if;
                        Methods.Append (Real_Expr_Id (Impl));
                     end;
                  end loop;

                  --  The PRD arity contract fires here if counts drift.
                  declare
                     Raw : constant Real_Expr_Id :=
                       Mk_Dict (M, Cl, Supers, Methods, Span);
                     Knot : Bind_Vectors.Vector;
                     Dict : Real_Expr_Id;
                     G : Top_Bind;
                  begin
                     Knot.Append (Bind_Pair'(Binder => Self_D,
                                             Rhs => Raw));
                     Dict := M.Add (Expr_Node'
                       (Kind => Let_C, Span => Span, Is_Rec => True,
                        Binds => Knot,
                        Let_Body => M.Add (Expr_Node'
                          (Kind => Var_C, Span => Span,
                           V => Self_D))));
                     for PI in reverse 1 .. Params.Last_Index loop
                        Dict := M.Add (Expr_Node'
                          (Kind => Lam_C, Span => Span,
                           Binder => Params (PI),
                           Lam_Body => Dict));
                     end loop;
                     G.Is_Rec := False;
                     G.Binds.Append
                       (Bind_Pair'
                          (Binder =>
                             Real_Var_Id (Inst.Dict_Global),
                           Rhs => Dict));
                     M.Top_Binds.Append (G);
                  end;
               end;
            end if;
         end;
      end loop;
   end Elaborate_Dictionaries;

end AHC.Elaborate;
