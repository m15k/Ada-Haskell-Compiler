with Ada.Containers.Vectors;

package body AHC.Elaborate is

   use AHC.Core;
   use type Names.Name_Id;

   --  An instance needs a dictionary binding iff it came from user
   --  source (its Method_Binds may still be empty if all methods
   --  default).
   function Needs_Dict (M : Core.Core_Module; I : Instance_Info)
     return Boolean
   is (not I.Method_Binds.Is_Empty
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
      Env   : in out Builtins.Global_Env)
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
         --  Post-kinds instance contexts constrain plain tyvars.
         return NA.Kind = TVar_T and then NB.Kind = TVar_T
           and then NA.Tv = NB.Tv;
      end Same_Head_Arg;

      --  Solve C to a dictionary expression using Givens and the
      --  instance table (head-shape matching only: the typechecker
      --  already established solvability).
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

         --  Head-directed instance lookup.
         declare
            Head : TyCon_Id := No_TyCon;
            T : Real_Type_Id := C.Arg;
         begin
            loop
               declare
                  N : constant Type_Node := M.Node (T);
               begin
                  case N.Kind is
                     when TCon_T =>
                        Head := TyCon_Id (N.Con);
                        exit;
                     when TApp_T =>
                        T := N.T_Fun;
                     when others =>
                        exit;
                  end case;
               end;
            end loop;

            if Head /= No_TyCon then
               for I of M.Info (C.Class).Instances loop
                  declare
                     Inst : constant Instance_Info := M.Info (I);
                  begin
                     if Inst.Head = Head then
                        declare
                           Result : Real_Expr_Id :=
                             M.Add (Expr_Node'
                               (Kind => Var_C, Span => Span,
                                V => Real_Var_Id
                                       (Inst.Dict_Global)));
                        begin
                           for IC of Inst.Context loop
                              Result := M.Add (Expr_Node'
                                (Kind => App_C, Span => Span,
                                 Fun => Result,
                                 Arg => Solve_Ev
                                   (IC, Givens, Span, Depth + 1)));
                           end loop;
                           return Result;
                        end;
                     end if;
                  end;
               end loop;
            end if;
         end;

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
            if Needs_Dict (M, Inst) then
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
                     Head_T : Real_Type_Id :=
                       M.Add (Type_Node'
                         (Kind => TCon_T,
                          Con => Real_TyCon_Id (Inst.Head),
                          Refine => No_Refinement));
                  begin
                     for HV of Inst.Head_Vars loop
                        Head_T := M.Add (Type_Node'
                          (Kind => TApp_T, T_Fun => Head_T,
                           T_Arg => M.Add (Type_Node'
                             (Kind => TVar_T, Tv => HV))));
                     end loop;
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
                                 (Cl_Info.Methods (I).Selector)),
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
                                   (M.Info (Ord_TC).Cons (Tag)),
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
                                      (Env.Ordering_TC)).Cons
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
                                                (Cl_Info.Super_Sels
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
