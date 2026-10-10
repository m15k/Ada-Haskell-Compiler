with AHC.Inst_Match;

package body AHC.Derive_Functor is

   use AHC.Core;
   use type Names.Name_Id;
   use type Inst_Match.Match_Result;

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
         --  Each method's own binders (Core binders are unique, and a
         --  binder's type lives in the variable table): minted afresh
         --  before each method is built.
         F : Real_Var_Id;

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
         function Map_T (T : Real_Type_Id; X : Real_Expr_Id)
           return Real_Expr_Id;
         function Fold_T (T : Real_Type_Id; X, Acc : Real_Expr_Id)
           return Real_Expr_Id;
         function Trav_T (T : Real_Type_Id; X : Real_Expr_Id)
           return Real_Expr_Id;
         function FM_T (T : Real_Type_Id; X : Real_Expr_Id)
           return Real_Expr_Id;

         function Is_Param (T : Real_Type_Id) return Boolean is
           (M.Node (T).Kind = TVar_T and then M.Node (T).Tv = A);

         --  The function the recursive fmap/foldr/traverse/foldMap
         --  gets for a field `g T`: f itself when T is the parameter
         --  (M148 review: an eta-expanded \y -> f y wrapped f once
         --  more per level of a recursive type - quadratic).
         function Map_Fn (T : Real_Type_Id) return Real_Expr_Id is
         begin
            if Is_Param (T) then
               return V (F, Span);
            end if;
            declare
               Y : constant Real_Var_Id := Fresh ("y$", Span);
               B : constant Real_Expr_Id := Map_T (T, V (Y, Span));
            begin
               return Lam (Y, B, Span);
            end;
         end Map_Fn;

         function Fold_Fn (T : Real_Type_Id) return Real_Expr_Id is
         begin
            if Is_Param (T) then
               return V (F, Span);
            end if;
            declare
               Y : constant Real_Var_Id := Fresh ("y$", Span);
               Ac : constant Real_Var_Id := Fresh ("acc$", Span);
               B : constant Real_Expr_Id :=
                 Fold_T (T, V (Y, Span), V (Ac, Span));
               L : constant Real_Expr_Id := Lam (Ac, B, Span);
            begin
               return Lam (Y, L, Span);
            end;
         end Fold_Fn;

         function Trav_Fn (T : Real_Type_Id) return Real_Expr_Id is
         begin
            if Is_Param (T) then
               return V (F, Span);
            end if;
            declare
               Y : constant Real_Var_Id := Fresh ("y$", Span);
               B : constant Real_Expr_Id := Trav_T (T, V (Y, Span));
            begin
               return Lam (Y, B, Span);
            end;
         end Trav_Fn;

         function FM_Fn (T : Real_Type_Id) return Real_Expr_Id is
         begin
            if Is_Param (T) then
               return V (F, Span);
            end if;
            declare
               Y : constant Real_Var_Id := Fresh ("y$", Span);
               B : constant Real_Expr_Id := FM_T (T, V (Y, Span));
            begin
               return Lam (Y, B, Span);
            end;
         end FM_Fn;

         --  e1 `mappend` (e2 `mappend` .. en), or mempty for none:
         --  GHC's derived foldMap shape.
         function Mappends (Es : Expr_Id_Vectors.Vector) return Real_Expr_Id
         is
            R : Real_Expr_Id;
         begin
            if Es.Is_Empty then
               return G ("mempty", Span);
            end if;
            R := Real_Expr_Id (Es.Last_Element);
            for I in reverse 1 .. Es.Last_Index - 1 loop
               declare
                  Ma : constant Real_Expr_Id := G ("mappend", Span);
                  L : constant Real_Expr_Id :=
                    Ap (Ma, Real_Expr_Id (Es.Element (I)), Span);
               begin
                  R := Ap (L, R, Span);
               end;
            end loop;
            return R;
         end Mappends;

         --  foldMap's image of X : T (T mentions the parameter).
         function FM_T (T : Real_Type_Id; X : Real_Expr_Id)
           return Real_Expr_Id
         is
            N : constant Type_Node := M.Node (T);
         begin
            if N.Kind = TVar_T then
               return Ap (V (F, Span), X, Span);
            elsif Tuple_Arity (T) > 0 then
               declare
                  K : constant Natural := Tuple_Arity (T);
                  DC : constant Real_DataCon_Id :=
                    Real_DataCon_Id (Env.Tuple_DCs (K));
                  Ys : Var_Id_Vectors.Vector;
                  Es : Expr_Id_Vectors.Vector;
                  Alts : Alt_Id_Vectors.Vector;
               begin
                  for I in 1 .. K loop
                     Ys.Append (Var_Id (Fresh ("t$", Span)));
                  end loop;
                  for I in 1 .. K loop
                     if Occurs (A, Tuple_Arg (T, I, K)) then
                        Es.Append (Expr_Id (FM_T (Tuple_Arg (T, I, K),
                          V (Real_Var_Id (Ys.Element (I)), Span))));
                     end if;
                  end loop;
                  declare
                     R : constant Real_Expr_Id := Mappends (Es);
                  begin
                     Alts.Append (M.Add (Alt_Node'
                       (Kind => Con_Alt, Span => Span, A_Con => DC,
                        Binders => Ys, Alt_Body => R)));
                  end;
                  return M.Add (Expr_Node'
                    (Kind => Case_C, Span => Span, Scrutinee => X,
                     Alts => Alts));
               end;
            elsif N.Kind = TApp_T then
               declare
                  Fn : constant Real_Expr_Id := FM_Fn (N.T_Arg);
                  Fm : constant Real_Expr_Id := G ("foldMap", Span);
               begin
                  return Ap (Ap (Fm, Fn, Span), X, Span);
               end;
            end if;
            return G ("mempty", Span);   --  a function: Fold_T failed
         end FM_T;

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
                  Fn : constant Real_Expr_Id := Map_Fn (N.T_Arg);
                  Fm : constant Real_Expr_Id := G ("fmap", Span);
               begin
                  return Ap (Ap (Fm, Fn, Span), X, Span);
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
                  Step : constant Real_Expr_Id := Fold_Fn (N.T_Arg);
                  Fr : constant Real_Expr_Id := G ("foldr", Span);
               begin
                  return Ap (Ap (Ap (Fr, Step, Span), Acc, Span), X, Span);
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
                  Pu : constant Real_Expr_Id := G ("pure", Span);
                  R : Real_Expr_Id := Ap (Pu, Con (DC, Span), Span);
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
                  Fn : constant Real_Expr_Id := Trav_Fn (N.T_Arg);
                  Tr : constant Real_Expr_Id := G ("traverse", Span);
               begin
                  return Ap (Ap (Tr, Fn, Span), X, Span);
               end;
            end if;
            Fail ("unsupported field type");
            return X;
         end Trav_T;

         Scrut : Real_Var_Id;
         Z : Real_Var_Id;   --  foldr's seed
         Binds : Bind_Vectors.Vector;
         Ctx : Constraint_Vectors.Vector;
         Cls : constant Real_Class_Id := Real_Class_Id (Inst.Of_Class);

         procedure Fresh_Binders is
         begin
            F := Fresh ("f$", Span);
            Scrut := Fresh ("v$", Span);
            Z := Fresh ("z$", Span);
         end Fresh_Binders;

         --  \f$ [z$] v$ -> Body, bound under the method's name.
         procedure Bind_Method
           (Name : String; Body_E : Real_Expr_Id; With_Z : Boolean) is
            Meth : Real_Expr_Id := Lam (Scrut, Body_E, Span);
         begin
            if With_Z then
               Meth := Lam (Z, Meth, Span);
            end if;
            if Name /= "null" then   --  null takes the structure alone
               Meth := Lam (F, Meth, Span);
            end if;
            Binds.Append (Bind_Pair'(Binder => Fresh (Name, Span),
                                     Rhs => Meth));
         end Bind_Method;

         function Case_Of (As : Alt_Id_Vectors.Vector) return Real_Expr_Id is
           (M.Add (Expr_Node'
              (Kind => Case_C, Span => Span, Scrutinee => V (Scrut, Span),
               Alts => As)));

         function Same_Type (X, Y : Real_Type_Id) return Boolean is
            NX : constant Type_Node := M.Node (X);
            NY : constant Type_Node := M.Node (Y);
         begin
            if NX.Kind /= NY.Kind then
               return False;
            end if;
            case NX.Kind is
               when TVar_T => return NX.Tv = NY.Tv;
               when TCon_T => return NX.Con = NY.Con;
               when TApp_T => return Same_Type (NX.T_Fun, NY.T_Fun)
                                and then Same_Type (NX.T_Arg, NY.T_Arg);
               when TFun_T => return Same_Type (NX.From, NY.From)
                                and then Same_Type (NX.To, NY.To);
               when others => return X = Y;
            end case;
         end Same_Type;

         function Subst (T : Real_Type_Id; Vs : TyVar_Id_Vectors.Vector;
                         Ts : Type_Id_Vectors.Vector) return Real_Type_Id
         is (Inst_Match.Subst_Vars (M, T, Vs, Ts));

         --  GHC's inferred instance context (M148 review): every
         --  `C g` the method needs, reduced through the instances of
         --  g's head constructor; what is left has a type variable at
         --  its head (`Functor f`, `Functor (f b)`) and joins the
         --  context. A recursive use of the type itself needs nothing.
         procedure Reduce (C : Real_Class_Id; G_T : Real_Type_Id;
                           Depth : Natural) is
            H : Real_Type_Id := G_T;
         begin
            if Depth > 40 then
               return;
            end if;
            while M.Node (H).Kind = TApp_T loop
               H := M.Node (H).T_Fun;
            end loop;
            if M.Node (H).Kind = TVar_T then
               for Old of Ctx loop
                  if Old.Class = C and then Same_Type (Old.Arg, G_T) then
                     return;
                  end if;
               end loop;
               Ctx.Append (Constraint'(Class => C, Arg => G_T,
                                       Span => Span));
               return;
            elsif M.Node (H).Kind = TCon_T
              and then TyCon_Id (M.Node (H).Con) = Inst.Head
              and then C = Cls
            then
               return;   --  the type being derived, recursively
            end if;
            declare
               function Id (T : Real_Type_Id) return Real_Type_Id is (T);
               function Match is new Inst_Match.Match_Instance (Id);
               Cands : Instance_Id_Vectors.Vector;
               Chosen : Natural := 0;
            begin
               for J of M.Info (C).Instances loop
                  declare
                     JI : constant Instance_Info := M.Info (J);
                     Ign : Type_Id_Vectors.Vector;
                  begin
                     if J /= II
                       and then Match (M, Env, JI, G_T, Ign)
                                = Inst_Match.Matched
                     then
                        Cands.Append (J);
                     end if;
                  end;
               end loop;
               if Natural (Cands.Length) = 1 then
                  Chosen := Natural (Cands.First_Element);
               elsif Natural (Cands.Length) > 1 then
                  Chosen := Inst_Match.Pick (M, Env, Cands);
               end if;
               if Chosen = 0 then
                  return;   --  the typechecker reports the missing one
               end if;
               declare
                  JI : constant Instance_Info :=
                    M.Info (Real_Instance_Id (Chosen));
                  Args : Type_Id_Vectors.Vector;
                  Ign : constant Inst_Match.Match_Result :=
                    Match (M, Env, JI, G_T, Args);
                  pragma Unreferenced (Ign);
               begin
                  for IC of JI.Context loop
                     declare
                        Arg : constant Real_Type_Id :=
                          Subst (IC.Arg, JI.Head_Vars, Args);
                     begin
                        Reduce (IC.Class, Arg, Depth + 1);
                     end;
                  end loop;
               end;
            end;
         end Reduce;

         --  The `C g` wanted for each `g (.. a ..)` in a field type.
         procedure Want (T : Real_Type_Id) is
            N : constant Type_Node := M.Node (T);
         begin
            if not Occurs (A, T) or else N.Kind = TVar_T then
               return;
            elsif N.Kind = TFun_T then
               Want (N.To);
            elsif Tuple_Arity (T) > 0 then
               for I in 1 .. Tuple_Arity (T) loop
                  Want (Tuple_Arg (T, I, Tuple_Arity (T)));
               end loop;
            elsif N.Kind = TApp_T then
               Reduce (Cls, N.T_Fun, 0);
               Want (N.T_Arg);
            end if;
         end Want;
         type Method_Kind is (Fmap_M, Foldr_M, FoldMap_M, Null_M, Traverse_M);

         --  One method over every constructor, with fresh binders; Ok
         --  is False when null must keep the class default.
         procedure Build (Meth : Method_Kind; First : Boolean) is
            Alts : Alt_Id_Vectors.Vector;
            Ok : Boolean := True;
         begin
            Fresh_Binders;
            for DCI of TCI.Cons loop
               declare
                  DI : constant DataCon_Info := M.Info (DCI);
                  Sch : constant Scheme :=
                    M.Node (Real_Scheme_Id (DI.Con_Scheme));
                  Tys : Type_Id_Vectors.Vector;
                  Xs : Var_Id_Vectors.Vector;
                  T : Real_Type_Id := Real_Type_Id (Sch.S_Body);
                  R : Real_Expr_Id;
                  --  This constructor's own quantifiers onto the
                  --  instance's head variables, by position.
                  Own : TyVar_Id_Vectors.Vector;
                  Heads : Type_Id_Vectors.Vector;
               begin
                  --  This constructor's quantifiers are its own ids:
                  --  map the last one onto A by position.
                  A := Real_TyVar_Id (Sch.Tvs.Last_Element);
                  while M.Node (T).Kind = TFun_T loop
                     Tys.Append (M.Node (T).From);
                     T := M.Node (T).To;
                  end loop;
                  for I in 1 .. Tys.Last_Index loop
                     Xs.Append (Var_Id (Fresh ("x$", Span)));
                  end loop;
                  if First then
                     for I in 1 .. Sch.Tvs.Last_Index - 1 loop
                        if I <= Inst.Head_Vars.Last_Index then
                           Own.Append (Sch.Tvs.Element (I));
                           Heads.Append (Type_Id (M.Add (Type_Node'
                             (Kind => TVar_T,
                              Tv => Real_TyVar_Id
                                (Inst.Head_Vars.Element (I))))));
                        end if;
                     end loop;
                     for I in 1 .. Tys.Last_Index loop
                        Want (Subst (Tys.Element (I), Own, Heads));
                     end loop;
                  end if;
                  case Meth is
                     when Fmap_M =>
                        R := Con (DCI, Span);
                        for I in 1 .. Tys.Last_Index loop
                           declare
                              E : constant Real_Expr_Id :=
                                Map_T (Tys.Element (I),
                                       V (Real_Var_Id (Xs.Element (I)),
                                          Span));
                           begin
                              R := Ap (R, E, Span);
                           end;
                        end loop;
                     when Foldr_M =>
                        R := V (Z, Span);
                        for I in reverse 1 .. Tys.Last_Index loop
                           R := Fold_T (Tys.Element (I),
                                        V (Real_Var_Id (Xs.Element (I)),
                                           Span), R);
                        end loop;
                     when FoldMap_M =>
                        --  The fields mentioning the parameter,
                        --  mappend-ed right-nested: GHC derives
                        --  foldMap too, and a left-recursive type needs
                        --  it (M148 review).
                        declare
                           Es : Expr_Id_Vectors.Vector;
                        begin
                           for I in 1 .. Tys.Last_Index loop
                              if Occurs (A, Tys.Element (I)) then
                                 Es.Append (Expr_Id
                                   (FM_T (Tys.Element (I),
                                          V (Real_Var_Id (Xs.Element (I)),
                                             Span))));
                              end if;
                           end loop;
                           R := Mappends (Es);
                        end;
                     when Null_M =>
                        --  GHC's derived null: False with a bare
                        --  parameter field, else `null x` over the
                        --  `g a` fields joined by &&; any deeper shape
                        --  keeps the class default.
                        declare
                           Ns : Expr_Id_Vectors.Vector;
                           Direct : Boolean := False;
                        begin
                           for I in 1 .. Tys.Last_Index loop
                              declare
                                 FT : constant Real_Type_Id :=
                                   Tys.Element (I);
                                 FN : constant Type_Node := M.Node (FT);
                              begin
                                 if not Occurs (A, FT) then
                                    null;
                                 elsif Is_Param (FT) then
                                    Direct := True;
                                 elsif FN.Kind = TApp_T
                                   and then Is_Param (FN.T_Arg)
                                   and then Tuple_Arity (FT) = 0
                                 then
                                    declare
                                       Nu : constant Real_Expr_Id :=
                                         G ("null", Span);
                                       XE : constant Real_Expr_Id :=
                                         V (Real_Var_Id (Xs.Element (I)),
                                            Span);
                                    begin
                                       Ns.Append (Expr_Id (Ap (Nu, XE, Span)));
                                    end;
                                 else
                                    Ok := False;
                                 end if;
                              end;
                           end loop;
                           if Direct then
                              R := Con (Real_DataCon_Id (Env.False_DC), Span);
                           elsif Ns.Is_Empty then
                              R := Con (Real_DataCon_Id (Env.True_DC), Span);
                           else
                              R := Real_Expr_Id (Ns.Last_Element);
                              for I in reverse 1 .. Ns.Last_Index - 1 loop
                                 declare
                                    An : constant Real_Expr_Id :=
                                      G ("&&", Span);
                                    L : constant Real_Expr_Id :=
                                      Ap (An, Real_Expr_Id (Ns.Element (I)),
                                          Span);
                                 begin
                                    R := Ap (L, R, Span);
                                 end;
                              end loop;
                           end if;
                        end;
                     when Traverse_M =>
                        declare
                           Pu : constant Real_Expr_Id := G ("pure", Span);
                        begin
                           R := Ap (Pu, Con (DCI, Span), Span);
                        end;
                        for I in 1 .. Tys.Last_Index loop
                           declare
                              E : constant Real_Expr_Id :=
                                Trav_T (Tys.Element (I),
                                        V (Real_Var_Id (Xs.Element (I)),
                                           Span));
                              Ap_Op : constant Real_Expr_Id :=
                                G ("<*>", Span);
                           begin
                              R := Ap (Ap (Ap_Op, R, Span), E, Span);
                           end;
                        end loop;
                  end case;
                  Alts.Append (M.Add (Alt_Node'
                    (Kind => Con_Alt, Span => Span, A_Con => DCI,
                     Binders => Xs, Alt_Body => R)));
               end;
            end loop;
            if Ok and then not Failed then
               Bind_Method
                 ((case Meth is
                     when Fmap_M => "fmap",
                     when Foldr_M => "foldr",
                     when FoldMap_M => "foldMap",
                     when Null_M => "null",
                     when Traverse_M => "traverse"),
                  Case_Of (Alts), Meth = Foldr_M);
            end if;
         end Build;

         --  An empty type (M148 review): GHC's fmap and traverse force
         --  the (necessarily bottom) value, foldr returns the seed,
         --  foldMap is mempty and null is True.
         procedure Build_Empty (Meth : Method_Kind) is
         begin
            Fresh_Binders;
            declare
               Sq : constant Real_Expr_Id := G ("seq", Span);
               Un : constant Real_Expr_Id := G ("undefined", Span);
               Forced : constant Real_Expr_Id :=
                 Ap (Ap (Sq, V (Scrut, Span), Span), Un, Span);
            begin
               case Meth is
                  when Fmap_M =>
                     Bind_Method ("fmap", Forced, False);
                  when Foldr_M =>
                     Bind_Method ("foldr", V (Z, Span), True);
                  when FoldMap_M =>
                     Bind_Method ("foldMap", G ("mempty", Span), False);
                  when Null_M =>
                     Bind_Method
                       ("null", Con (Real_DataCon_Id (Env.True_DC), Span),
                        False);
                  when Traverse_M =>
                     declare
                        Pu : constant Real_Expr_Id := G ("pure", Span);
                     begin
                        Bind_Method ("traverse", Ap (Pu, Forced, Span),
                                     False);
                     end;
               end case;
            end;
         end Build_Empty;

         Methods : constant array (Positive range <>) of Method_Kind :=
           (case Kind is
              when Stock_Functor => [Fmap_M],
              when Stock_Foldable => [Foldr_M, FoldMap_M, Null_M],
              when others => [Traverse_M]);
      begin
         if TCI.Cons.Is_Empty then
            for Meth of Methods loop
               Build_Empty (Meth);
            end loop;
         else
            declare
               Sch0 : constant Scheme := M.Node
                 (Real_Scheme_Id (M.Info (TCI.Cons (1)).Con_Scheme));
            begin
               if Sch0.Tvs.Is_Empty then
                  Fail ("the type has no type parameter");
                  return;
               end if;
            end;
            for J in Methods'Range loop
               Build (Methods (J), First => J = Methods'First);
            end loop;
         end if;
         if Failed then
            return;
         end if;
         M.Instances (II).Method_Binds := Binds;
         M.Instances (II).Context := Ctx;
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
