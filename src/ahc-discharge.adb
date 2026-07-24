with Ada.Containers.Hashed_Maps;
with Ada.Containers.Vectors;

with AHC.Rename;

package body AHC.Discharge is

   use AHC.Core;
   use type AHC.Names.Name_Id;

   package Expr_Maps is new Ada.Containers.Hashed_Maps
     (Real_Var_Id, Real_Expr_Id,
      Hash => Rename.Var_Hash, Equivalent_Keys => "=");

   package Nat_Maps is new Ada.Containers.Hashed_Maps
     (Real_Var_Id, Positive,
      Hash => Rename.Var_Hash, Equivalent_Keys => "=");

   function Try_Claim
     (Table : Names.Name_Table;
      M     : Core.Core_Module;
      Prims : Prelude_Core.Prim_Maps.Map;
      Pred  : Core.Real_Var_Id) return Verdict
   is
      Fuel : Natural := 2000;

      --  Whole-module tables, built once per claim.
      Globals : Expr_Maps.Map;   --  top-level binder -> rhs
      Sels    : Nat_Maps.Map;    --  selector var -> dict field index

      ----------------------------------------------------------------
      --  Values (a local arena; the Core arena is never touched)
      ----------------------------------------------------------------

      type V_Kind is
        (V_Stuck, V_Int, V_Char, V_Bool, V_Ord3, V_Con, V_Clos,
         V_Prim);

      subtype Value_Id is Natural;
      No_Value : constant Value_Id := 0;

      package Val_Vectors is new Ada.Containers.Vectors
        (Positive, Value_Id);

      subtype Env_Id is Natural;
      Empty_Env : constant Env_Id := 0;

      type Value (Kind : V_Kind := V_Stuck) is record
         case Kind is
            when V_Stuck => null;
            when V_Int   => I : Long_Long_Integer := 0;
            when V_Char  => C : Natural := 0;
            when V_Bool  => B : Boolean := False;
            when V_Ord3  => O : Integer := 0;    --  -1 / 0 / +1
            when V_Con   =>
               Con  : Real_DataCon_Id := 1;
               Args : Val_Vectors.Vector;
            when V_Clos  =>
               Param  : Real_Var_Id := 1;
               C_Body : Real_Expr_Id := 1;
               C_Env  : Env_Id := Empty_Env;
            when V_Prim  =>
               Sym    : Names.Name_Id := Names.No_Name;
               P_Args : Val_Vectors.Vector;
         end case;
      end record;

      package Value_Vectors is new Ada.Containers.Vectors
        (Positive, Value);

      type Env_Cell is record
         Var    : Real_Var_Id := 1;
         Val    : Value_Id := No_Value;
         Parent : Env_Id := Empty_Env;
      end record;

      package Env_Vectors is new Ada.Containers.Vectors
        (Positive, Env_Cell);

      Vals : Value_Vectors.Vector;
      Envs : Env_Vectors.Vector;

      function Mk (V : Value) return Value_Id is
      begin
         Vals.Append (V);
         return Vals.Last_Index;
      end Mk;

      Stuck : constant Value_Id := 1;

      function Val (Id : Value_Id) return Value is (Vals (Id));

      function Bind (Var : Real_Var_Id; V : Value_Id; Parent : Env_Id)
        return Env_Id is
      begin
         Envs.Append
           (Env_Cell'(Var => Var, Val => V, Parent => Parent));
         return Envs.Last_Index;
      end Bind;

      function Find (Var : Real_Var_Id; En : Env_Id) return Value_Id
      is
         E : Env_Id := En;
      begin
         while E /= Empty_Env loop
            if Envs (E).Var = Var then
               return Envs (E).Val;
            end if;
            E := Envs (E).Parent;
         end loop;
         return No_Value;
      end Find;

      ----------------------------------------------------------------
      --  Primitive folding
      ----------------------------------------------------------------

      function Sym_Text (N : Names.Name_Id) return String
      is (Table.Text (Names.Real_Name_Id (N)));

      --  Arity of a foldable prim symbol; 0 = not foldable.
      function Prim_Arity (Sym : String) return Natural is
      begin
         if Sym in "ahc_prim_neg_int" | "ahc_prim_abs_int"
                  | "ahc_prim_signum_int" | "ahc_prim_pred_int"
                  | "ahc_prim_from_integer"
         then
            return 1;
         elsif Sym in "ahc_prim_add_int" | "ahc_prim_sub_int"
                     | "ahc_prim_mul_int" | "ahc_prim_div_int"
                     | "ahc_prim_mod_int" | "ahc_prim_quot_int"
                     | "ahc_prim_rem_int" | "ahc_prim_gt_int"
                     | "ahc_prim_eq_poly" | "ahc_prim_compare_poly"
                     | "ahc_prim_seq"
         then
            return 2;
         end if;
         return 0;
      end Prim_Arity;

      function Fold (Sym : String; A : Val_Vectors.Vector)
        return Value_Id
      is
         function Int_Of (Id : Value_Id) return Long_Long_Integer
         is (Val (Id).I);

         function Both_Int return Boolean
         is (Val (A (1)).Kind = V_Int
             and then Val (A (2)).Kind = V_Int);

         --  Report 6.4.2: div/mod are FLOORED.
         function Fdiv (X, Y : Long_Long_Integer)
           return Long_Long_Integer
         is
            Q : constant Long_Long_Integer := X / Y;
         begin
            return (if (X rem Y) /= 0 and then ((X < 0) /= (Y < 0))
                    then Q - 1 else Q);
         end Fdiv;
      begin
         if Sym = "ahc_prim_seq" then
            return (if Val (A (1)).Kind = V_Stuck then Stuck
                    else A (2));
         end if;
         if Sym = "ahc_prim_from_integer" then
            --  Identity on the canonical representation.
            return (if Val (A (1)).Kind = V_Int then A (1)
                    else Stuck);
         end if;
         if Sym = "ahc_prim_eq_poly" then
            declare
               X : constant Value := Val (A (1));
               Y : constant Value := Val (A (2));
            begin
               if X.Kind = V_Int and then Y.Kind = V_Int then
                  return Mk ((Kind => V_Bool, B => X.I = Y.I));
               elsif X.Kind = V_Char and then Y.Kind = V_Char then
                  return Mk ((Kind => V_Bool, B => X.C = Y.C));
               elsif X.Kind = V_Bool and then Y.Kind = V_Bool then
                  return Mk ((Kind => V_Bool, B => X.B = Y.B));
               elsif X.Kind = V_Ord3 and then Y.Kind = V_Ord3 then
                  return Mk ((Kind => V_Bool, B => X.O = Y.O));
               elsif X.Kind = V_Con and then Y.Kind = V_Con
                 and then X.Args.Is_Empty and then Y.Args.Is_Empty
               then
                  return Mk ((Kind => V_Bool, B => X.Con = Y.Con));
               end if;
               return Stuck;
            end;
         end if;
         if Sym = "ahc_prim_compare_poly" then
            declare
               X : constant Value := Val (A (1));
               Y : constant Value := Val (A (2));

               function Ord3 (Lt, Eq : Boolean) return Value_Id
               is (Mk ((Kind => V_Ord3,
                        O => (if Lt then -1 elsif Eq then 0
                              else 1))));
            begin
               if X.Kind = V_Int and then Y.Kind = V_Int then
                  return Ord3 (X.I < Y.I, X.I = Y.I);
               elsif X.Kind = V_Char and then Y.Kind = V_Char then
                  return Ord3 (X.C < Y.C, X.C = Y.C);
               end if;
               return Stuck;
            end;
         end if;
         --  Everything below is Int arithmetic/comparison.
         if Sym = "ahc_prim_gt_int" then
            return (if Both_Int
                    then Mk ((Kind => V_Bool,
                              B => Int_Of (A (1)) > Int_Of (A (2))))
                    else Stuck);
         end if;
         if Prim_Arity (Sym) = 1 then
            if Val (A (1)).Kind /= V_Int then
               return Stuck;
            end if;
            declare
               X : constant Long_Long_Integer := Int_Of (A (1));
               R : Long_Long_Integer;
            begin
               if Sym = "ahc_prim_neg_int" then
                  R := -X;
               elsif Sym = "ahc_prim_abs_int" then
                  R := abs X;
               elsif Sym = "ahc_prim_signum_int" then
                  R := (if X > 0 then 1 elsif X < 0 then -1 else 0);
               else                    --  pred
                  R := X - 1;
               end if;
               return Mk ((Kind => V_Int, I => R));
            end;
         end if;
         if not Both_Int then
            return Stuck;
         end if;
         declare
            X : constant Long_Long_Integer := Int_Of (A (1));
            Y : constant Long_Long_Integer := Int_Of (A (2));
            R : Long_Long_Integer;
         begin
            if Sym = "ahc_prim_add_int" then
               R := X + Y;
            elsif Sym = "ahc_prim_sub_int" then
               R := X - Y;
            elsif Sym = "ahc_prim_mul_int" then
               R := X * Y;
            elsif Y = 0 then            --  div/mod/quot/rem by zero
               return Stuck;
            elsif Sym = "ahc_prim_div_int" then
               R := Fdiv (X, Y);
            elsif Sym = "ahc_prim_mod_int" then
               R := X - Fdiv (X, Y) * Y;
            elsif Sym = "ahc_prim_quot_int" then
               R := X / Y;
            elsif Sym = "ahc_prim_rem_int" then
               R := X rem Y;
            else
               return Stuck;
            end if;
            return Mk ((Kind => V_Int, I => R));
         end;
      exception
         when Constraint_Error =>     --  overflow: runtime promotes
            return Stuck;
      end Fold;

      ----------------------------------------------------------------
      --  The evaluator: eager arguments, lazy branches
      ----------------------------------------------------------------

      function Con_Name (DC : Real_DataCon_Id) return String
      is (Table.Text (Names.Real_Name_Id (M.Info (DC).Name)));

      function Ev (E : Real_Expr_Id; En : Env_Id) return Value_Id;

      function Apply (F : Value_Id; Arg : Value_Id) return Value_Id
      is
         FV : constant Value := Val (F);
      begin
         case FV.Kind is
            when V_Clos =>
               return Ev (FV.C_Body, Bind (FV.Param, Arg, FV.C_Env));
            when V_Con =>
               declare
                  A : Val_Vectors.Vector := FV.Args;
               begin
                  A.Append (Arg);
                  return Mk ((Kind => V_Con, Con => FV.Con,
                              Args => A));
               end;
            when V_Prim =>
               declare
                  A : Val_Vectors.Vector := FV.P_Args;
                  S : constant String := Sym_Text (FV.Sym);
               begin
                  A.Append (Arg);
                  if Natural (A.Length) = Prim_Arity (S) then
                     return Fold (S, A);
                  end if;
                  return Mk ((Kind => V_Prim, Sym => FV.Sym,
                              P_Args => A));
               end;
            when others =>
               return Stuck;
         end case;
      end Apply;

      function Ev_Lit (L : Literal) return Value_Id is
      begin
         case L.Kind is
            when L_Int =>
               begin
                  return Mk
                    ((Kind => V_Int,
                      I => Long_Long_Integer'Value
                             (Table.Text
                                (Names.Real_Name_Id (L.Text)))));
               exception
                  when Constraint_Error =>   --  bignum literal
                     return Stuck;
               end;
            when L_Char =>
               return Mk ((Kind => V_Char, C => L.Code));
            when others =>
               return Stuck;
         end case;
      end Ev_Lit;

      function Lit_Matches (L : Literal; V : Value) return Boolean is
      begin
         case L.Kind is
            when L_Int =>
               begin
                  return V.Kind = V_Int
                    and then V.I = Long_Long_Integer'Value
                      (Table.Text (Names.Real_Name_Id (L.Text)));
               exception
                  when Constraint_Error =>
                     return False;
               end;
            when L_Char =>
               return V.Kind = V_Char and then V.C = L.Code;
            when others =>
               return False;
         end case;
      end Lit_Matches;

      --  Does alternative-constructor DC match scrutinee value V?
      function Con_Matches (DC : Real_DataCon_Id; V : Value)
        return Boolean is
      begin
         case V.Kind is
            when V_Con =>
               return DC = V.Con;
            when V_Bool =>
               return Con_Name (DC) = (if V.B then "True"
                                       else "False");
            when V_Ord3 =>
               return Con_Name (DC) = (if V.O < 0 then "LT"
                                       elsif V.O = 0 then "EQ"
                                       else "GT");
            when others =>
               return False;
         end case;
      end Con_Matches;

      function Ev (E : Real_Expr_Id; En : Env_Id) return Value_Id is
         N : constant Expr_Node := M.Node (E);
      begin
         if Fuel = 0 then
            return Stuck;
         end if;
         Fuel := Fuel - 1;
         case N.Kind is
            when Lit_C =>
               return Ev_Lit (N.Lit);
            when Con_C =>
               declare
                  Nm : constant String := Con_Name (N.Con);
               begin
                  if Nm = "True" then
                     return Mk ((Kind => V_Bool, B => True));
                  elsif Nm = "False" then
                     return Mk ((Kind => V_Bool, B => False));
                  elsif Nm = "LT" then
                     return Mk ((Kind => V_Ord3, O => -1));
                  elsif Nm = "EQ" then
                     return Mk ((Kind => V_Ord3, O => 0));
                  elsif Nm = "GT" then
                     return Mk ((Kind => V_Ord3, O => 1));
                  end if;
                  return Mk ((Kind => V_Con, Con => N.Con,
                              others => <>));
               end;
            when Lam_C =>
               return Mk ((Kind => V_Clos, Param => N.Binder,
                           C_Body => N.Lam_Body, C_Env => En));
            when Var_C =>
               declare
                  Hit : constant Value_Id := Find (N.V, En);
               begin
                  if Hit /= No_Value then
                     return Hit;
                  end if;
                  if Prims.Contains (N.V) then
                     declare
                        S : constant String :=
                          Sym_Text (Prims (N.V));
                     begin
                        if Prim_Arity (S) > 0 then
                           return Mk ((Kind => V_Prim,
                                       Sym => Prims (N.V),
                                       others => <>));
                        end if;
                        return Stuck;
                     end;
                  end if;
                  if Sels.Contains (N.V) then
                     --  A selector waits for its dictionary; model
                     --  it as a one-field projection closure via a
                     --  prim-like value is overkill - handle at the
                     --  App site instead (below).
                     return Stuck;
                  end if;
                  if Globals.Contains (N.V) then
                     return Ev (Globals (N.V), Empty_Env);
                  end if;
                  return Stuck;
               end;
            when App_C =>
               --  Selector applied to a known dictionary: project.
               declare
                  FN : constant Expr_Node := M.Node (N.Fun);
               begin
                  if FN.Kind = Var_C
                    and then Find (FN.V, En) = No_Value
                    and then Sels.Contains (FN.V)
                  then
                     declare
                        D : constant Value_Id := Ev (N.Arg, En);
                        DV : constant Value := Val (D);
                        Ix : constant Positive := Sels (FN.V);
                     begin
                        if DV.Kind = V_Con
                          and then Ix <= DV.Args.Last_Index
                        then
                           return DV.Args (Ix);
                        end if;
                        return Stuck;
                     end;
                  end if;
               end;
               declare
                  F : constant Value_Id := Ev (N.Fun, En);
                  A : constant Value_Id := Ev (N.Arg, En);
               begin
                  if Val (F).Kind = V_Stuck then
                     return Stuck;
                  end if;
                  return Apply (F, A);
               end;
            when Let_C =>
               if N.Is_Rec then
                  --  Two-pass letrec (dictionary globals are
                  --  letrec-shaped): bind every binder opaque,
                  --  evaluate the right-hand sides in that
                  --  environment, then PATCH the cells - closures
                  --  read cells at use time, so self-reference
                  --  resolves once patched.
                  declare
                     E2 : Env_Id := En;
                  begin
                     for B of N.Binds loop
                        E2 := Bind (B.Binder, Stuck, E2);
                     end loop;
                     declare
                        Cell : Env_Id :=
                          E2 - Natural (N.Binds.Length) + 1;
                     begin
                        for B of N.Binds loop
                           Envs (Cell).Val := Ev (B.Rhs, E2);
                           Cell := Cell + 1;
                        end loop;
                     end;
                     return Ev (N.Let_Body, E2);
                  end;
               end if;
               declare
                  E2 : Env_Id := En;
               begin
                  for B of N.Binds loop
                     E2 := Bind (B.Binder, Ev (B.Rhs, En), E2);
                  end loop;
                  return Ev (N.Let_Body, E2);
               end;
            when Case_C =>
               declare
                  SV : constant Value_Id := Ev (N.Scrutinee, En);
                  V  : constant Value := Val (SV);
               begin
                  if V.Kind = V_Stuck or else V.Kind = V_Clos
                    or else V.Kind = V_Prim
                  then
                     return Stuck;
                  end if;
                  for A of N.Alts loop
                     declare
                        Alt : constant Alt_Node := M.Node (A);
                     begin
                        case Alt.Kind is
                           when Default_Alt =>
                              return Ev (Alt.Alt_Body, En);
                           when Lit_Alt =>
                              if Lit_Matches (Alt.A_Lit, V) then
                                 return Ev (Alt.Alt_Body, En);
                              end if;
                           when Con_Alt =>
                              if Con_Matches (Alt.A_Con, V) then
                                 declare
                                    E2 : Env_Id := En;
                                 begin
                                    if V.Kind = V_Con then
                                       for BI in
                                         1 .. Alt.Binders.Last_Index
                                       loop
                                          exit when BI >
                                            V.Args.Last_Index;
                                          E2 := Bind
                                            (Alt.Binders (BI),
                                             V.Args (BI), E2);
                                       end loop;
                                    end if;
                                    return Ev (Alt.Alt_Body, E2);
                                 end;
                              end if;
                        end case;
                     end;
                  end loop;
                  return Stuck;
               end;
         end case;
      end Ev;

   begin
      --  Build the whole-module tables.
      for G of M.Top_Binds loop
         for B of G.Binds loop
            Globals.Include (B.Binder, B.Rhs);
         end loop;
      end loop;
      for CI in 1 .. M.Last_Class loop
         declare
            Info : constant Class_Info :=
              M.Info (Real_Class_Id (CI));
            Ix : Positive := 1;
         begin
            --  Dictionary layout: superclasses first, then methods.
            for SS of Info.Super_Sels loop
               Sels.Include (SS, Ix);
               Ix := Ix + 1;
            end loop;
            for Mth of Info.Methods loop
               if Mth.Selector /= No_Var then
                  Sels.Include (Real_Var_Id (Mth.Selector), Ix);
               end if;
               Ix := Ix + 1;
            end loop;
         end;
      end loop;

      Vals.Append (Value'(Kind => V_Stuck));   --  id 1 = Stuck

      if not Globals.Contains (Pred) then
         return Unknown;
      end if;

      --  Peel the leading lambdas (dict and value parameters) with
      --  opaque bindings, then evaluate the body.
      declare
         B  : Real_Expr_Id := Globals (Pred);
         En : Env_Id := Empty_Env;
      begin
         while M.Node (B).Kind = Lam_C loop
            En := Bind (M.Node (B).Binder, Stuck, En);
            B := M.Node (B).Lam_Body;
         end loop;
         declare
            R : constant Value := Val (Ev (B, En));
         begin
            if R.Kind = V_Bool then
               return (if R.B then Proved_True else Proved_False);
            end if;
            return Unknown;
         end;
      end;
   end Try_Claim;

end AHC.Discharge;
