package body AHC.Derive_Functor is

   use AHC.Core;
   use type Names.Name_Id;

   procedure Synthesize
     (Table : in out Names.Name_Table;
      Bag   : in out Diagnostics.Diagnostic_Bag;
      M     : in out Core.Core_Module;
      Env   : Builtins.Global_Env)
   is
      Failed : Boolean;

      --  The Prelude global of this name (Env holds only builtins and
      --  the Prelude, so a lookup by name is that entity - M75).
      function G (Nm : String; Span : Diagnostics.Source_Span)
        return Real_Expr_Id
      is
         C : constant Builtins.Var_Maps.Cursor :=
           Env.Values.Find (Table.Intern (Nm));
      begin
         return M.Add (Expr_Node'
           (Kind => Var_C, Span => Span,
            V => Real_Var_Id (Builtins.Var_Maps.Element (C))));
      end G;

      function Fresh (Nm : String; Span : Diagnostics.Source_Span)
        return Real_Var_Id
      is (M.Mint_Var ((Name => Table.Intern (Nm), Span => Span,
                       others => <>)));

      function V (X : Real_Var_Id; Span : Diagnostics.Source_Span)
        return Real_Expr_Id
      is (M.Add (Expr_Node'(Kind => Var_C, Span => Span, V => X)));

      function Ap (F, A : Real_Expr_Id; Span : Diagnostics.Source_Span)
        return Real_Expr_Id
      is (M.Add (Expr_Node'(Kind => App_C, Span => Span, Fun => F, Arg => A)));

      function Lam (X : Real_Var_Id; B : Real_Expr_Id;
                    Span : Diagnostics.Source_Span) return Real_Expr_Id
      is (M.Add (Expr_Node'(Kind => Lam_C, Span => Span, Binder => X,
                            Lam_Body => B)));

      function Con (DC : Real_DataCon_Id; Span : Diagnostics.Source_Span)
        return Real_Expr_Id
      is (M.Add (Expr_Node'(Kind => Con_C, Span => Span, Con => DC)));

      function Occurs (Tv : Real_TyVar_Id; T : Real_Type_Id) return Boolean is
         N : constant Type_Node := M.Node (T);
      begin
         case N.Kind is
            when TVar_T => return N.Tv = Tv;
            when TApp_T => return Occurs (Tv, N.T_Fun)
                             or else Occurs (Tv, N.T_Arg);
            when TFun_T => return Occurs (Tv, N.From)
                             or else Occurs (Tv, N.To);
            when others => return False;
         end case;
      end Occurs;

      --  The tuple arity of T's spine, or 0.
      function Tuple_Arity (T : Real_Type_Id) return Natural is
         H : Real_Type_Id := T;
         K : Natural := 0;
      begin
         while M.Node (H).Kind = TApp_T loop
            K := K + 1;
            H := M.Node (H).T_Fun;
         end loop;
         if M.Node (H).Kind = TCon_T and then K in 2 .. Builtins.Max_Tuple
           and then TyCon_Id (M.Node (H).Con) = Env.Tuple_TCs (K)
         then
            return K;
         end if;
         return 0;
      end Tuple_Arity;

      --  The I-th argument of a tuple spine (1-based, left to right).
      function Tuple_Arg (T : Real_Type_Id; I, K : Positive)
        return Real_Type_Id
      is
         H : Real_Type_Id := T;
      begin
         for J in reverse I + 1 .. K loop
            H := M.Node (H).T_Fun;
         end loop;
         return M.Node (H).T_Arg;
      end Tuple_Arg;

      procedure Synthesize_One (II : Real_Instance_Id) is
         Inst : constant Instance_Info := M.Info (II);
         Span : constant Diagnostics.Source_Span := Inst.Span;
         TCI : constant TyCon_Info := M.Info (Real_TyCon_Id (Inst.Head));
         Kind : constant Stock_Derive_Kind := Inst.Stock_Derive;
         Cls_Name : constant String :=
           (case Kind is
              when Stock_Functor => "Functor",
              when Stock_Foldable => "Foldable",
              when others => "Traversable");
         A : Real_TyVar_Id;   --  the last type parameter
         F : constant Real_Var_Id := Fresh ("f$", Span);

         procedure Fail (Why : String) is
         begin
            if not Failed then
               Bag.Add (Diagnostics.Error, Diagnostics.Class_Gnd, Span,
                        "cannot derive '" & Cls_Name & "' for '"
                        & Table.Text (Names.Real_Name_Id (TCI.Name))
                        & "': " & Why);
            end if;
            Failed := True;
         end Fail;

         function Tuple_Case (T : Real_Type_Id; X : Real_Expr_Id)
           return Real_Expr_Id;

         --  fmap's image of X : T.
         function Map_T (T : Real_Type_Id; X : Real_Expr_Id)
           return Real_Expr_Id
         is
            N : constant Type_Node := M.Node (T);
         begin
            if not Occurs (A, T) then
               return X;
            elsif N.Kind = TVar_T then
               return Ap (V (F, Span), X, Span);
            elsif N.Kind = TFun_T then
               if Occurs (A, N.From) then
                  Fail ("the last type variable occurs in a "
                        & "contravariant position");
                  return X;
               end if;
               declare
                  Z : constant Real_Var_Id := Fresh ("z$", Span);
               begin
                  return Lam (Z, Map_T (N.To, Ap (X, V (Z, Span), Span)),
                              Span);
               end;
            elsif Tuple_Arity (T) > 0 then
               return Tuple_Case (T, X);
            elsif N.Kind = TApp_T then
               if Occurs (A, N.T_Fun) then
                  Fail ("the last type variable occurs in an argument "
                        & "other than the last");
                  return X;
               end if;
               declare
                  Y : constant Real_Var_Id := Fresh ("y$", Span);
                  Body_E : constant Real_Expr_Id :=
                    Map_T (N.T_Arg, V (Y, Span));
                  Fn : constant Real_Expr_Id := Lam (Y, Body_E, Span);
               begin
                  return Ap (Ap (G ("fmap", Span), Fn, Span), X, Span);
               end;
            end if;
            Fail ("unsupported field type");
            return X;
         end Map_T;

         --  case X of (y1..yk) -> (Map_T t1 y1, ..)
         function Tuple_Case (T : Real_Type_Id; X : Real_Expr_Id)
           return Real_Expr_Id
         is
            K : constant Natural := Tuple_Arity (T);
            DC : constant Real_DataCon_Id :=
              Real_DataCon_Id (Env.Tuple_DCs (K));
            Ys : Var_Id_Vectors.Vector;
            R : Real_Expr_Id := Con (DC, Span);
            Alts : Alt_Id_Vectors.Vector;
         begin
            for I in 1 .. K loop
               Ys.Append (Var_Id (Fresh ("t$", Span)));
            end loop;
            for I in 1 .. K loop
               declare
                  E : constant Real_Expr_Id :=
                    Map_T (Tuple_Arg (T, I, K),
                           V (Real_Var_Id (Ys.Element (I)), Span));
               begin
                  R := Ap (R, E, Span);
               end;
            end loop;
            Alts.Append (M.Add (Alt_Node'
              (Kind => Con_Alt, Span => Span, A_Con => DC,
               Binders => Ys, Alt_Body => R)));
            return M.Add (Expr_Node'
              (Kind => Case_C, Span => Span, Scrutinee => X, Alts => Alts));
         end Tuple_Case;

         --  foldr's step over X : T with accumulator Acc.
         function Fold_T (T : Real_Type_Id; X, Acc : Real_Expr_Id)
           return Real_Expr_Id
         is
            N : constant Type_Node := M.Node (T);
         begin
            if not Occurs (A, T) then
               return Acc;
            elsif N.Kind = TVar_T then
               return Ap (Ap (V (F, Span), X, Span), Acc, Span);
            elsif N.Kind = TFun_T then
               Fail ("a constructor contains a function type");
               return Acc;
            elsif Tuple_Arity (T) > 0 then
               declare
                  K : constant Natural := Tuple_Arity (T);
                  DC : constant Real_DataCon_Id :=
                    Real_DataCon_Id (Env.Tuple_DCs (K));
                  Ys : Var_Id_Vectors.Vector;
                  R : Real_Expr_Id := Acc;
                  Alts : Alt_Id_Vectors.Vector;
               begin
                  for I in 1 .. K loop
                     Ys.Append (Var_Id (Fresh ("t$", Span)));
                  end loop;
                  for I in reverse 1 .. K loop
                     R := Fold_T (Tuple_Arg (T, I, K),
                                  V (Real_Var_Id (Ys.Element (I)), Span), R);
                  end loop;
                  Alts.Append (M.Add (Alt_Node'
                    (Kind => Con_Alt, Span => Span, A_Con => DC,
                     Binders => Ys, Alt_Body => R)));
                  return M.Add (Expr_Node'
                    (Kind => Case_C, Span => Span, Scrutinee => X,
                     Alts => Alts));
               end;
            elsif N.Kind = TApp_T then
               if Occurs (A, N.T_Fun) then
                  Fail ("the last type variable occurs in an argument "
                        & "other than the last");
                  return Acc;
               end if;
               declare
                  Y : constant Real_Var_Id := Fresh ("y$", Span);
                  Ac : constant Real_Var_Id := Fresh ("acc$", Span);
                  Step_Body : constant Real_Expr_Id :=
                    Fold_T (N.T_Arg, V (Y, Span), V (Ac, Span));
                  Step : constant Real_Expr_Id :=
                    Lam (Y, Lam (Ac, Step_Body, Span), Span);
               begin
                  return Ap (Ap (Ap (G ("foldr", Span), Step, Span), Acc,
                                 Span), X, Span);
               end;
            end if;
            Fail ("unsupported field type");
            return Acc;
         end Fold_T;

         --  traverse's effect for X : T.
         function Trav_T (T : Real_Type_Id; X : Real_Expr_Id)
           return Real_Expr_Id
         is
            N : constant Type_Node := M.Node (T);
         begin
            if not Occurs (A, T) then
               return Ap (G ("pure", Span), X, Span);
            elsif N.Kind = TVar_T then
               return Ap (V (F, Span), X, Span);
            elsif N.Kind = TFun_T then
               Fail ("a constructor contains a function type");
               return X;
            elsif Tuple_Arity (T) > 0 then
               declare
                  K : constant Natural := Tuple_Arity (T);
                  DC : constant Real_DataCon_Id :=
                    Real_DataCon_Id (Env.Tuple_DCs (K));
                  Ys : Var_Id_Vectors.Vector;
                  Alts : Alt_Id_Vectors.Vector;
                  R : Real_Expr_Id :=
                    Ap (G ("pure", Span), Con (DC, Span), Span);
               begin
                  for I in 1 .. K loop
                     Ys.Append (Var_Id (Fresh ("t$", Span)));
                  end loop;
                  for I in 1 .. K loop
                     declare
                        E : constant Real_Expr_Id :=
                          Trav_T (Tuple_Arg (T, I, K),
                                  V (Real_Var_Id (Ys.Element (I)), Span));
                     begin
                        R := Ap (Ap (G ("<*>", Span), R, Span), E, Span);
                     end;
                  end loop;
                  Alts.Append (M.Add (Alt_Node'
                    (Kind => Con_Alt, Span => Span, A_Con => DC,
                     Binders => Ys, Alt_Body => R)));
                  return M.Add (Expr_Node'
                    (Kind => Case_C, Span => Span, Scrutinee => X,
                     Alts => Alts));
               end;
            elsif N.Kind = TApp_T then
               if Occurs (A, N.T_Fun) then
                  Fail ("the last type variable occurs in an argument "
                        & "other than the last");
                  return X;
               end if;
               declare
                  Y : constant Real_Var_Id := Fresh ("y$", Span);
                  Body_E : constant Real_Expr_Id :=
                    Trav_T (N.T_Arg, V (Y, Span));
                  Fn : constant Real_Expr_Id := Lam (Y, Body_E, Span);
               begin
                  return Ap (Ap (G ("traverse", Span), Fn, Span), X, Span);
               end;
            end if;
            Fail ("unsupported field type");
            return X;
         end Trav_T;

         Scrut : constant Real_Var_Id := Fresh ("v$", Span);
         Z : constant Real_Var_Id := Fresh ("z$", Span);   --  foldr's seed
         Alts : Alt_Id_Vectors.Vector;
         Method : Real_Expr_Id;
         Binds : Bind_Vectors.Vector;
      begin
         --  The last parameter, from the first constructor's scheme
         --  (whose quantifier order is the data declaration's).
         if TCI.Cons.Is_Empty then
            Fail ("the type has no constructors");
            return;
         end if;
         declare
            Sch0 : constant Scheme := M.Node
              (Real_Scheme_Id (M.Info (TCI.Cons (1)).Con_Scheme));
         begin
            if Sch0.Tvs.Is_Empty then
               Fail ("the type has no type parameter");
               return;
            end if;
            A := Real_TyVar_Id (Sch0.Tvs.Last_Element);
         end;

         for DCI of TCI.Cons loop
            declare
               DI : constant DataCon_Info := M.Info (DCI);
               Sch : constant Scheme :=
                 M.Node (Real_Scheme_Id (DI.Con_Scheme));
               Tys : Type_Id_Vectors.Vector;
               Xs : Var_Id_Vectors.Vector;
               T : Real_Type_Id := Real_Type_Id (Sch.S_Body);
               R : Real_Expr_Id;
            begin
               --  This constructor's quantifiers are its own ids: map
               --  the last one onto A by position.
               A := Real_TyVar_Id (Sch.Tvs.Last_Element);
               while M.Node (T).Kind = TFun_T loop
                  Tys.Append (M.Node (T).From);
                  T := M.Node (T).To;
               end loop;
               for I in 1 .. Tys.Last_Index loop
                  Xs.Append (Var_Id (Fresh ("x$", Span)));
               end loop;
               case Kind is
                  when Stock_Functor =>
                     R := Con (DCI, Span);
                     for I in 1 .. Tys.Last_Index loop
                        declare
                           E : constant Real_Expr_Id :=
                             Map_T (Tys.Element (I), V (Real_Var_Id (Xs.Element (I)), Span));
                        begin
                           R := Ap (R, E, Span);
                        end;
                     end loop;
                  when Stock_Foldable =>
                     R := V (Z, Span);
                     for I in reverse 1 .. Tys.Last_Index loop
                        R := Fold_T (Tys.Element (I), V (Real_Var_Id (Xs.Element (I)), Span),
                                     R);
                     end loop;
                  when others =>
                     R := Ap (G ("pure", Span), Con (DCI, Span), Span);
                     for I in 1 .. Tys.Last_Index loop
                        declare
                           E : constant Real_Expr_Id :=
                             Trav_T (Tys.Element (I), V (Real_Var_Id (Xs.Element (I)), Span));
                        begin
                           R := Ap (Ap (G ("<*>", Span), R, Span), E, Span);
                        end;
                     end loop;
               end case;
               Alts.Append (M.Add (Alt_Node'
                 (Kind => Con_Alt, Span => Span, A_Con => DCI,
                  Binders => Xs, Alt_Body => R)));
            end;
         end loop;

         if Failed then
            return;
         end if;
         Method := M.Add (Expr_Node'
           (Kind => Case_C, Span => Span, Scrutinee => V (Scrut, Span),
            Alts => Alts));
         --  fmap f v / traverse f v / foldr f z v
         Method := Lam (Scrut, Method, Span);
         if Kind = Stock_Foldable then
            Method := Lam (Z, Method, Span);
         end if;
         Method := Lam (F, Method, Span);
         Binds.Append (Bind_Pair'
           (Binder => Fresh ((case Kind is
                                when Stock_Functor => "fmap",
                                when Stock_Foldable => "foldr",
                                when others => "traverse"), Span),
            Rhs => Method));
         M.Instances (II).Method_Binds := Binds;
      end Synthesize_One;
   begin
      for II in 1 .. M.Last_Instance loop
         if M.Info (Real_Instance_Id (II)).Stock_Derive /= No_Stock_Derive
           and then M.Info (Real_Instance_Id (II)).Method_Binds.Is_Empty
         then
            Failed := False;
            Synthesize_One (Real_Instance_Id (II));
         end if;
      end loop;
   end Synthesize;

end AHC.Derive_Functor;
