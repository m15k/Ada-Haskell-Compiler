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
      pragma Unreferenced (Env);

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
               begin
                  --  One dictionary parameter per context constraint.
                  for C of Inst.Context loop
                     declare
                        D : constant Real_Var_Id :=
                          M.Mint_Var
                            ((Name => Table.Intern ("$d"),
                              Span => Span, others => <>));
                     begin
                        Params.Append (D);
                        Givens.Append (Given_Ev'(C => C, D => D));
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
                  for Mth of Cl_Info.Methods loop
                     declare
                        Impl : Expr_Id := No_Expr;
                     begin
                        for B of Inst.Method_Binds loop
                           if M.Info (B.Binder).Name = Mth.Name then
                              Impl := Expr_Id (B.Rhs);
                           end if;
                        end loop;
                        if Impl = No_Expr then
                           --  Fall back to the class default.
                           for B of M.Classes (Cl).Default_Binds loop
                              if M.Info (B.Binder).Name = Mth.Name
                              then
                                 Lift_Default (B);
                                 Impl := Expr_Id
                                   (M.Add (Expr_Node'
                                      (Kind => Var_C, Span => Span,
                                       V => B.Binder)));
                              end if;
                           end loop;
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
                     Dict : Real_Expr_Id :=
                       Mk_Dict (M, Cl, Supers, Methods, Span);
                     G : Top_Bind;
                  begin
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
