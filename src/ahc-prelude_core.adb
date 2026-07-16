with AHC.Diagnostics;

package body AHC.Prelude_Core is

   use AHC.Core;

   procedure Install_Bodies
     (Table : in out Names.Name_Table;
      M     : in out Core.Core_Module;
      Env   : in out Builtins.Global_Env;
      Prims : in out Prim_Maps.Map)
   is
      Span : constant Diagnostics.Source_Span := (Start => 1, Stop => 1);

      ------------------------------------------------------------------
      --  Core builders
      ------------------------------------------------------------------

      function V (Id : Var_Id) return Real_Expr_Id
      is (M.Add (Expr_Node'(Kind => Var_C, Span => Span,
                            V => Real_Var_Id (Id))));

      function Fresh (Name : String) return Real_Var_Id
      is (M.Mint_Var ((Name => Table.Intern (Name), Span => Span,
                       others => <>)));

      function Ap (F, A : Real_Expr_Id) return Real_Expr_Id
      is (M.Add (Expr_Node'(Kind => App_C, Span => Span,
                            Fun => F, Arg => A)));

      function Ap2 (F, A, B : Real_Expr_Id) return Real_Expr_Id
      is (Ap (Ap (F, A), B));

      function Lam (P : Real_Var_Id; B : Real_Expr_Id)
        return Real_Expr_Id
      is (M.Add (Expr_Node'(Kind => Lam_C, Span => Span,
                            Binder => P, Lam_Body => B)));

      function ConE (DC : DataCon_Id) return Real_Expr_Id
      is (M.Add (Expr_Node'(Kind => Con_C, Span => Span,
                            Con => Real_DataCon_Id (DC))));

      function Str (S : String) return Real_Expr_Id
      is (M.Add (Expr_Node'
           (Kind => Lit_C, Span => Span,
            Lit => (Kind => L_String,
                    Text => Names.Name_Id (Table.Intern (S))))));

      function Prim (Name, Symbol : String) return Real_Var_Id is
         P : constant Real_Var_Id :=
           M.Mint_Var ((Name => Table.Intern (Name), Span => Span,
                        Is_Global => True, others => <>));
      begin
         Prims.Include (P, Names.Name_Id (Table.Intern (Symbol)));
         return P;
      end Prim;

      function Lookup (Name : String) return Var_Id is
         C : constant Builtins.Var_Maps.Cursor :=
           Env.Values.Find (Table.Intern (Name));
      begin
         if Builtins.Var_Maps.Has_Element (C) then
            return Var_Id (Builtins.Var_Maps.Element (C));
         end if;
         return No_Var;
      end Lookup;

      procedure Bind (Binder : Var_Id; Rhs : Real_Expr_Id) is
         G : Top_Bind;
      begin
         if Binder = No_Var then
            return;
         end if;
         --  Skip if a body already exists (user shadowing).
         for TG of M.Top_Binds loop
            for B of TG.Binds loop
               if Var_Id (B.Binder) = Binder then
                  return;
               end if;
            end loop;
         end loop;
         G.Is_Rec := True;
         G.Binds.Append (Bind_Pair'(Binder => Real_Var_Id (Binder),
                                    Rhs => Rhs));
         M.Top_Binds.Append (G);
      end Bind;

      procedure Bind_Name (Name : String; Rhs : Real_Expr_Id) is
      begin
         Bind (Lookup (Name), Rhs);
      end Bind_Name;

      function Err (Msg : String) return Real_Expr_Id
      is (Ap (V (Env.Error_V), Str (Msg)));

      --  case Scrut of [] -> Nil_Body; (h:t) -> Cons_Body h t
      function List_Case
        (Scrut : Real_Expr_Id;
         Nil_Body : Real_Expr_Id;
         H, T : Real_Var_Id;
         Cons_Body : Real_Expr_Id) return Real_Expr_Id
      is
         Alts : Alt_Id_Vectors.Vector;
         Binders : Var_Id_Vectors.Vector;
      begin
         Alts.Append (M.Add (Alt_Node'
           (Kind => Con_Alt, Span => Span, Alt_Body => Nil_Body,
            A_Con => Real_DataCon_Id (Env.Nil_DC),
            Binders => Var_Id_Vectors.Empty_Vector)));
         Binders.Append (H);
         Binders.Append (T);
         Alts.Append (M.Add (Alt_Node'
           (Kind => Con_Alt, Span => Span, Alt_Body => Cons_Body,
            A_Con => Real_DataCon_Id (Env.Cons_DC),
            Binders => Binders)));
         return M.Add (Expr_Node'
           (Kind => Case_C, Span => Span, Scrutinee => Scrut,
            Alts => Alts));
      end List_Case;

      function Bool_Case
        (Scrut, Then_E, Else_E : Real_Expr_Id) return Real_Expr_Id
      is
         Alts : Alt_Id_Vectors.Vector;
      begin
         Alts.Append (M.Add (Alt_Node'
           (Kind => Con_Alt, Span => Span, Alt_Body => Then_E,
            A_Con => Real_DataCon_Id (Env.True_DC),
            Binders => Var_Id_Vectors.Empty_Vector)));
         Alts.Append (M.Add (Alt_Node'
           (Kind => Default_Alt, Span => Span, Alt_Body => Else_E)));
         return M.Add (Expr_Node'
           (Kind => Case_C, Span => Span, Scrutinee => Scrut,
            Alts => Alts));
      end Bool_Case;

      Nil  : constant Real_Expr_Id := ConE (Env.Nil_DC);

      function Cons (H, T : Real_Expr_Id) return Real_Expr_Id
      is (Ap2 (ConE (Env.Cons_DC), H, T));

      ------------------------------------------------------------------
      --  Primitives
      ------------------------------------------------------------------

      P_Add   : constant Real_Var_Id := Prim ("prim+", "ahc_prim_add_int");
      P_Sub   : constant Real_Var_Id := Prim ("prim-", "ahc_prim_sub_int");
      P_Mul   : constant Real_Var_Id := Prim ("prim*", "ahc_prim_mul_int");
      P_Div   : constant Real_Var_Id := Prim ("primdiv", "ahc_prim_div_int");
      P_Mod   : constant Real_Var_Id := Prim ("primmod", "ahc_prim_mod_int");
      P_Quot  : constant Real_Var_Id :=
        Prim ("primquot", "ahc_prim_quot_int");
      P_Rem   : constant Real_Var_Id := Prim ("primrem", "ahc_prim_rem_int");
      P_Neg   : constant Real_Var_Id := Prim ("primneg", "ahc_prim_neg_int");
      P_Abs   : constant Real_Var_Id := Prim ("primabs", "ahc_prim_abs_int");
      P_Sig   : constant Real_Var_Id :=
        Prim ("primsignum", "ahc_prim_signum_int");
      P_FromI : constant Real_Var_Id :=
        Prim ("primfromInteger", "ahc_prim_from_integer");
      P_AddD  : constant Real_Var_Id :=
        Prim ("primaddD", "ahc_prim_add_d");
      P_SubD  : constant Real_Var_Id :=
        Prim ("primsubD", "ahc_prim_sub_d");
      P_MulD  : constant Real_Var_Id :=
        Prim ("primmulD", "ahc_prim_mul_d");
      P_DivD  : constant Real_Var_Id :=
        Prim ("primdivD", "ahc_prim_div_d");
      P_NegD  : constant Real_Var_Id :=
        Prim ("primnegD", "ahc_prim_neg_d");
      P_AbsD  : constant Real_Var_Id :=
        Prim ("primabsD", "ahc_prim_abs_d");
      P_SigD  : constant Real_Var_Id :=
        Prim ("primsignumD", "ahc_prim_signum_d");
      P_FromID : constant Real_Var_Id :=
        Prim ("primfromIntegerD", "ahc_prim_from_integer_d");
      P_ShowD : constant Real_Var_Id :=
        Prim ("primshowD", "ahc_prim_show_d");
      P_EqP   : constant Real_Var_Id := Prim ("primeq", "ahc_prim_eq_poly");
      P_CmpP  : constant Real_Var_Id :=
        Prim ("primcompare", "ahc_prim_compare_poly");
      P_ShowI : constant Real_Var_Id :=
        Prim ("primshowInt", "ahc_prim_show_int");
      P_ShowC : constant Real_Var_Id :=
        Prim ("primshowChar", "ahc_prim_show_char");
      P_ShowB : constant Real_Var_Id :=
        Prim ("primshowBool", "ahc_prim_show_bool");
      P_EnumFT : constant Real_Var_Id :=
        Prim ("primenumFromTo", "ahc_prim_enum_from_to_int");
      P_EnumF : constant Real_Var_Id :=
        Prim ("primenumFrom", "ahc_prim_enum_from_int");
      P_PutStr : constant Real_Var_Id :=
        Prim ("primputStr", "ahc_prim_put_str");
      P_PutStrLn : constant Real_Var_Id :=
        Prim ("primputStrLn", "ahc_prim_put_str_ln");
      P_BindIO : constant Real_Var_Id :=
        Prim ("primbindIO", "ahc_prim_bind_io");
      P_ThenIO : constant Real_Var_Id :=
        Prim ("primthenIO", "ahc_prim_then_io");
      P_RetIO : constant Real_Var_Id :=
        Prim ("primreturnIO", "ahc_prim_return_io");
      P_Error : constant Real_Var_Id :=
        Prim ("primerror", "ahc_prim_error");

      ------------------------------------------------------------------
      --  Method-set builders for instance dictionaries
      ------------------------------------------------------------------

      Ordering_LT : Real_DataCon_Id := 1;
      Ordering_GT : Real_DataCon_Id := 1;

      --  compare x y == LT / GT etc. built over primcompare.
      function Cmp_Method (Want_Tag : Real_DataCon_Id; Negate : Boolean)
        return Real_Expr_Id
      is
         X : constant Real_Var_Id := Fresh ("x");
         Y : constant Real_Var_Id := Fresh ("y");
         Alts : Alt_Id_Vectors.Vector;
         T_E : constant Real_Expr_Id :=
           ConE ((if Negate then Env.False_DC
                             else Env.True_DC));
         F_E : constant Real_Expr_Id :=
           ConE ((if Negate then Env.True_DC
                             else Env.False_DC));
      begin
         Alts.Append (M.Add (Alt_Node'
           (Kind => Con_Alt, Span => Span, Alt_Body => T_E,
            A_Con => Want_Tag,
            Binders => Var_Id_Vectors.Empty_Vector)));
         Alts.Append (M.Add (Alt_Node'
           (Kind => Default_Alt, Span => Span, Alt_Body => F_E)));
         return Lam (X, Lam (Y, M.Add (Expr_Node'
           (Kind => Case_C, Span => Span,
            Scrutinee => Ap2 (V (P_CmpP), V (X),
                              V (Y)),
            Alts => Alts))));
      end Cmp_Method;

      function Max_Min (Is_Max : Boolean) return Real_Expr_Id is
         X : constant Real_Var_Id := Fresh ("x");
         Y : constant Real_Var_Id := Fresh ("y");
         Alts : Alt_Id_Vectors.Vector;
      begin
         Alts.Append (M.Add (Alt_Node'
           (Kind => Con_Alt, Span => Span,
            Alt_Body => V (Var_Id (if Is_Max then Y else X)),
            A_Con => Ordering_LT,
            Binders => Var_Id_Vectors.Empty_Vector)));
         Alts.Append (M.Add (Alt_Node'
           (Kind => Default_Alt, Span => Span,
            Alt_Body => V (Var_Id (if Is_Max then X else Y)))));
         return Lam (X, Lam (Y, M.Add (Expr_Node'
           (Kind => Case_C, Span => Span,
            Scrutinee => Ap2 (V (P_CmpP), V (X),
                              V (Y)),
            Alts => Alts))));
      end Max_Min;

      --  Build a dictionary for Inst with the given method list,
      --  supers solved against sibling instances (context params
      --  ignored: the generic prims need no element evidence).
      procedure Give_Dict
        (Inst_Idx : Real_Instance_Id;
         Methods  : Expr_Id_Vectors.Vector)
      is
         Inst : constant Instance_Info := M.Info (Inst_Idx);
         Cl : constant Real_Class_Id :=
           Real_Class_Id (Inst.Of_Class);
         Cl_Info : constant Class_Info := M.Info (Cl);
         Supers : Expr_Id_Vectors.Vector;
         Params : Var_Id_Vectors.Vector;
         Dict : Real_Expr_Id;
      begin
         for Super of Cl_Info.Supers loop
            declare
               Found : Var_Id := No_Var;
            begin
               for SI of M.Info (Super).Instances loop
                  if M.Info (SI).Head = Inst.Head then
                     Found := M.Info (SI).Dict_Global;
                  end if;
               end loop;
               if Found /= No_Var then
                  Supers.Append (V (Found));
               else
                  Supers.Append (Err ("missing superclass dictionary"));
               end if;
            end;
         end loop;
         Dict := Mk_Dict (M, Cl, Supers, Methods, Span);
         for CI in 1 .. Inst.Context.Last_Index loop
            Params.Append (Fresh ("$d"));
            pragma Unreferenced (CI);
         end loop;
         for PI in reverse 1 .. Params.Last_Index loop
            Dict := Lam (Params (PI), Dict);
         end loop;
         Bind (Inst.Dict_Global, Dict);
      end Give_Dict;

      function Errs (Cl : Real_Class_Id;
                     Fill : Expr_Id_Vectors.Vector :=
                       Expr_Id_Vectors.Empty_Vector)
        return Expr_Id_Vectors.Vector
      is
         Ms : Expr_Id_Vectors.Vector := Fill;
      begin
         for I in Natural (Fill.Length) + 1 ..
                  Natural (M.Info (Cl).Methods.Length)
         loop
            Ms.Append
              (Err ("method '"
                    & Table.Text (M.Info (Cl).Methods (I).Name)
                    & "' has no runtime yet"));
         end loop;
         return Ms;
      end Errs;

   begin
      --  Ordering constructor handles (tags 1 = LT, 3 = GT).
      declare
         Cons_Of : constant DataCon_Id_Vectors.Vector :=
           M.Info (Real_TyCon_Id (Env.Ordering_TC)).Cons;
      begin
         Ordering_LT := Cons_Of (1);
         Ordering_GT := Cons_Of (3);
      end;

      ------------------------------------------------------------------
      --  Value combinators
      ------------------------------------------------------------------

      --  map f xs = case xs of [] -> []; (h:t) -> f h : map f t
      declare
         F : constant Real_Var_Id := Fresh ("f");
         XS : constant Real_Var_Id := Fresh ("xs");
         H : constant Real_Var_Id := Fresh ("h");
         T : constant Real_Var_Id := Fresh ("t");
      begin
         Bind (Env.Map_V,
           Lam (F, Lam (XS, List_Case
             (V (XS), Nil, H, T,
              Cons (Ap (V (F), V (H)),
                    Ap2 (V (Env.Map_V), V (F),
                         V (T)))))));
      end;

      --  filter p xs
      declare
         P : constant Real_Var_Id := Fresh ("p");
         XS : constant Real_Var_Id := Fresh ("xs");
         H : constant Real_Var_Id := Fresh ("h");
         T : constant Real_Var_Id := Fresh ("t");
         Rest : constant Real_Expr_Id :=
           Ap2 (V ((Lookup ("filter"))), V (P),
                V (T));
      begin
         Bind_Name ("filter",
           Lam (P, Lam (XS, List_Case
             (V (XS), Nil, H, T,
              Bool_Case (Ap (V (P), V (H)),
                         Cons (V (H), Rest), Rest)))));
      end;

      --  foldr f z xs
      declare
         F : constant Real_Var_Id := Fresh ("f");
         Z : constant Real_Var_Id := Fresh ("z");
         XS : constant Real_Var_Id := Fresh ("xs");
         H : constant Real_Var_Id := Fresh ("h");
         T : constant Real_Var_Id := Fresh ("t");
      begin
         Bind_Name ("foldr",
           Lam (F, Lam (Z, Lam (XS, List_Case
             (V (XS), V (Z), H, T,
              Ap2 (V (F), V (H),
                   Ap (Ap2 (V ((Lookup ("foldr"))),
                            V (F), V (Z)),
                       V (T))))))));
      end;

      --  xs ++ ys
      declare
         XS : constant Real_Var_Id := Fresh ("xs");
         YS : constant Real_Var_Id := Fresh ("ys");
         H : constant Real_Var_Id := Fresh ("h");
         T : constant Real_Var_Id := Fresh ("t");
      begin
         Bind (Env.Append_V,
           Lam (XS, Lam (YS, List_Case
             (V (XS), V (YS), H, T,
              Cons (V (H),
                    Ap2 (V (Env.Append_V), V (T),
                         V (YS)))))));
      end;

      --  concat, concatMap, length
      declare
         XS : constant Real_Var_Id := Fresh ("xs");
         H : constant Real_Var_Id := Fresh ("h");
         T : constant Real_Var_Id := Fresh ("t");
      begin
         Bind_Name ("concat",
           Lam (XS, List_Case
             (V (XS), Nil, H, T,
              Ap2 (V (Env.Append_V), V (H),
                   Ap (V ((Lookup ("concat"))),
                       V (T))))));
      end;
      declare
         F : constant Real_Var_Id := Fresh ("f");
         XS : constant Real_Var_Id := Fresh ("xs");
      begin
         Bind (Env.Concat_Map_V,
           Lam (F, Lam (XS,
             Ap (V ((Lookup ("concat"))),
                 Ap2 (V (Env.Map_V), V (F),
                      V (XS))))));
      end;
      declare
         XS : constant Real_Var_Id := Fresh ("xs");
         H : constant Real_Var_Id := Fresh ("h");
         T : constant Real_Var_Id := Fresh ("t");
         Zero : constant Real_Expr_Id :=
           M.Add (Expr_Node'(Kind => Lit_C, Span => Span,
                             Lit => (Kind => L_Int,
                                     Text => Names.Name_Id
                                       (Table.Intern ("0")))));
         One : constant Real_Expr_Id :=
           M.Add (Expr_Node'(Kind => Lit_C, Span => Span,
                             Lit => (Kind => L_Int,
                                     Text => Names.Name_Id
                                       (Table.Intern ("1")))));
      begin
         Bind_Name ("length",
           Lam (XS, List_Case
             (V (XS), Zero, H, T,
              Ap2 (V (P_Add), One,
                   Ap (V ((Lookup ("length"))),
                       V (T))))));
      end;

      --  id, const, flip, (.), ($), fst, snd, not, (&&), (||),
      --  otherwise, subtract, undefined
      declare
         X : constant Real_Var_Id := Fresh ("x");
      begin
         Bind_Name ("id", Lam (X, V (X)));
      end;
      declare
         X : constant Real_Var_Id := Fresh ("x");
         Y : constant Real_Var_Id := Fresh ("y");
      begin
         Bind_Name ("const", Lam (X, Lam (Y, V (X))));
      end;
      declare
         F : constant Real_Var_Id := Fresh ("f");
         X : constant Real_Var_Id := Fresh ("x");
         Y : constant Real_Var_Id := Fresh ("y");
      begin
         Bind_Name ("flip",
           Lam (F, Lam (X, Lam (Y,
             Ap2 (V (F), V (Y), V (X))))));
      end;
      declare
         F : constant Real_Var_Id := Fresh ("f");
         G : constant Real_Var_Id := Fresh ("g");
         X : constant Real_Var_Id := Fresh ("x");
      begin
         Bind_Name (".",
           Lam (F, Lam (G, Lam (X,
             Ap (V (F),
                 Ap (V (Var_Id (G)), V (X)))))));
      end;
      declare
         F : constant Real_Var_Id := Fresh ("f");
         X : constant Real_Var_Id := Fresh ("x");
      begin
         Bind_Name ("$",
           Lam (F, Lam (X, Ap (V (F), V (X)))));
      end;
      declare
         P : constant Real_Var_Id := Fresh ("p");
         A : constant Real_Var_Id := Fresh ("a");
         B : constant Real_Var_Id := Fresh ("b");
         Binders : Var_Id_Vectors.Vector;
         Alts : Alt_Id_Vectors.Vector;
      begin
         Binders.Append (A);
         Binders.Append (B);
         Alts.Append (M.Add (Alt_Node'
           (Kind => Con_Alt, Span => Span,
            Alt_Body => V (Var_Id (A)),
            A_Con => Real_DataCon_Id (Env.Tuple_DCs (2)),
            Binders => Binders)));
         Bind_Name ("fst",
           Lam (P, M.Add (Expr_Node'
             (Kind => Case_C, Span => Span,
              Scrutinee => V (P), Alts => Alts))));
      end;
      declare
         P : constant Real_Var_Id := Fresh ("p");
         A : constant Real_Var_Id := Fresh ("a");
         B : constant Real_Var_Id := Fresh ("b");
         Binders : Var_Id_Vectors.Vector;
         Alts : Alt_Id_Vectors.Vector;
      begin
         Binders.Append (A);
         Binders.Append (B);
         Alts.Append (M.Add (Alt_Node'
           (Kind => Con_Alt, Span => Span,
            Alt_Body => V (Var_Id (B)),
            A_Con => Real_DataCon_Id (Env.Tuple_DCs (2)),
            Binders => Binders)));
         Bind_Name ("snd",
           Lam (P, M.Add (Expr_Node'
             (Kind => Case_C, Span => Span,
              Scrutinee => V (P), Alts => Alts))));
      end;
      declare
         X : constant Real_Var_Id := Fresh ("x");
      begin
         Bind_Name ("not",
           Lam (X, Bool_Case (V (X),
                              ConE (Env.False_DC),
                              ConE (Env.True_DC))));
      end;
      declare
         X : constant Real_Var_Id := Fresh ("x");
         Y : constant Real_Var_Id := Fresh ("y");
      begin
         Bind_Name ("&&",
           Lam (X, Lam (Y, Bool_Case (V (X),
                                      V (Y),
                                      ConE (Env.False_DC)))));
         null;
      end;
      declare
         X : constant Real_Var_Id := Fresh ("x");
         Y : constant Real_Var_Id := Fresh ("y");
      begin
         Bind_Name ("||",
           Lam (X, Lam (Y, Bool_Case (V (X),
                                      ConE (Env.True_DC),
                                      V (Y)))));
      end;
      Bind (Env.Otherwise_V, ConE (Env.True_DC));
      declare
         D : constant Real_Var_Id := Fresh ("$d");
         X : constant Real_Var_Id := Fresh ("x");
         Y : constant Real_Var_Id := Fresh ("y");
      begin
         --  subtract d x y = (-) d y x; '-' is Num's second method,
         --  but the prim works for the defaultable types directly.
         Bind_Name ("subtract",
           Lam (D, Lam (X, Lam (Y,
             Ap2 (V (P_Sub), V (Y),
                  V (X))))));
      end;
      Bind_Name ("undefined", Err ("Prelude.undefined"));
      Bind_Name ("error", V (P_Error));
      Bind_Name ("putStr", V (P_PutStr));
      Bind_Name ("putStrLn", V (P_PutStrLn));

      --  div/mod/quot/rem take a (ignored) Num dictionary.
      declare
         procedure Wrap2 (Name : String; P : Real_Var_Id) is
            D : constant Real_Var_Id := Fresh ("$d");
         begin
            Bind_Name (Name, Lam (D, V (P)));
         end Wrap2;
      begin
         Wrap2 ("div", P_Div);
         Wrap2 ("mod", P_Mod);
         Wrap2 ("quot", P_Quot);
         Wrap2 ("rem", P_Rem);
      end;

      --  print d x = putStrLn (show-selector d x)
      declare
         D : constant Real_Var_Id := Fresh ("$d");
         X : constant Real_Var_Id := Fresh ("x");
         Show_Sel : constant Var_Id :=
           M.Info (Real_Class_Id (Env.Show_Cl)).Methods (1).Selector;
      begin
         Bind_Name ("print",
           Lam (D, Lam (X,
             Ap (V (P_PutStrLn),
                 Ap2 (V (Show_Sel), V (D),
                      V (X))))));
      end;

      ------------------------------------------------------------------
      --  Instance dictionaries without bodies yet
      ------------------------------------------------------------------

      for II in 1 .. M.Last_Instance loop
         declare
            Inst : constant Instance_Info :=
              M.Info (Real_Instance_Id (II));
            Cl_Id : constant Class_Id := Inst.Of_Class;
         begin
            if Inst.Method_Binds.Is_Empty
              and then Inst.Dict_Global /= No_Var
            then
               declare
                  Cl : constant Real_Class_Id := Real_Class_Id (Cl_Id);
                  Ms : Expr_Id_Vectors.Vector;
               begin
                  if Cl_Id = Env.Eq_Cl then
                     declare
                        X : constant Real_Var_Id := Fresh ("x");
                        Y : constant Real_Var_Id := Fresh ("y");
                     begin
                        Ms.Append (V (P_EqP));
                        Ms.Append
                          (Lam (X, Lam (Y,
                             Bool_Case
                               (Ap2 (V (P_EqP),
                                     V (X), V (Y)),
                                ConE (Env.False_DC),
                                ConE (Env.True_DC)))));
                     end;
                     Give_Dict (Real_Instance_Id (II), Ms);
                  elsif Cl_Id = Env.Ord_Cl then
                     Ms.Append (V (P_CmpP));   --  compare
                     Ms.Append (Cmp_Method (Ordering_LT, False));  --  <
                     Ms.Append (Cmp_Method (Ordering_GT, True));   --  <=
                     Ms.Append (Cmp_Method (Ordering_GT, False));  --  >
                     Ms.Append (Cmp_Method (Ordering_LT, True));   --  >=
                     Ms.Append (Max_Min (True));
                     Ms.Append (Max_Min (False));
                     Give_Dict (Real_Instance_Id (II), Ms);
                  elsif Cl_Id = Env.Num_Cl
                    and then (Inst.Head = Env.Int_TC
                              or else Inst.Head =
                                        Env.Integer_TC)
                  then
                     Ms.Append (V (P_Add));
                     Ms.Append (V (P_Sub));
                     Ms.Append (V (P_Mul));
                     Ms.Append (V (P_Neg));
                     Ms.Append (V (P_Abs));
                     Ms.Append (V (P_Sig));
                     Ms.Append (V (P_FromI));
                     Give_Dict (Real_Instance_Id (II), Ms);
                  elsif Cl_Id = Env.Num_Cl
                    and then (Inst.Head = Env.Double_TC
                              or else Inst.Head = Env.Float_TC)
                  then
                     Ms.Append (V (P_AddD));
                     Ms.Append (V (P_SubD));
                     Ms.Append (V (P_MulD));
                     Ms.Append (V (P_NegD));
                     Ms.Append (V (P_AbsD));
                     Ms.Append (V (P_SigD));
                     Ms.Append (V (P_FromID));
                     Give_Dict (Real_Instance_Id (II), Ms);
                  elsif Cl_Id = Env.Fractional_Cl
                    and then (Inst.Head = Env.Double_TC
                              or else Inst.Head = Env.Float_TC)
                  then
                     --  Float literals are already double nodes at
                     --  run time (codegen emits the lexeme through
                     --  ahc_mk_double), so fromRational is identity.
                     declare
                        R : constant Real_Var_Id := Fresh ("r");
                        X : constant Real_Var_Id := Fresh ("x");
                        One : constant Real_Expr_Id :=
                          M.Add (Expr_Node'
                            (Kind => Lit_C, Span => Span,
                             Lit => (Kind => L_Float,
                                     Text => Names.Name_Id
                                       (Table.Intern ("1.0")))));
                     begin
                        Ms.Append (V (P_DivD));
                        Ms.Append
                          (Lam (X, Ap2 (V (P_DivD), One, V (X))));
                        Ms.Append (Lam (R, V (R)));
                     end;
                     Give_Dict (Real_Instance_Id (II), Ms);
                  elsif Cl_Id = Env.Show_Cl
                    and then Inst.Head = Env.List_TC
                  then
                     --  show xs = "[" ++ go xs ++ "]" with the element
                     --  show extracted from the context dictionary.
                     declare
                        Go : constant Real_Var_Id :=
                          M.Mint_Var
                            ((Name => Table.Intern ("$showListGo"),
                              Span => Span, Is_Global => True,
                              others => <>));
                        SE : constant Real_Var_Id := Fresh ("se");
                        XS : constant Real_Var_Id := Fresh ("xs");
                        H : constant Real_Var_Id := Fresh ("h");
                        T : constant Real_Var_Id := Fresh ("t");
                        H2 : constant Real_Var_Id := Fresh ("h2");
                        T2 : constant Real_Var_Id := Fresh ("t2");
                        Show_Sel : constant Var_Id :=
                          M.Info (Real_Class_Id (Env.Show_Cl))
                            .Methods (1).Selector;
                        D : constant Real_Var_Id := Fresh ("$d");
                        XS2 : constant Real_Var_Id := Fresh ("xs");
                        Cl2 : constant Real_Class_Id :=
                          Real_Class_Id (Cl_Id);
                        Supers2 : Expr_Id_Vectors.Vector;
                        Ms2 : Expr_Id_Vectors.Vector;
                        Dict : Real_Expr_Id;
                        Inner : Real_Expr_Id;
                     begin
                        Inner := List_Case
                          (V (T), Ap (V (SE), V (H)), H2, T2,
                           Ap2 (V (Env.Append_V),
                                Ap (V (SE), V (H)),
                                Ap2 (V (Env.Append_V), Str (","),
                                     Ap2 (V (Var_Id (Go)), V (SE),
                                          V (T)))));
                        Bind (Var_Id (Go),
                          Lam (SE, Lam (XS, List_Case
                            (V (XS), Str (""), H, T, Inner))));
                        Ms2.Append
                          (Lam (XS2,
                             Ap2 (V (Env.Append_V), Str ("["),
                                  Ap2 (V (Env.Append_V),
                                       Ap2 (V (Var_Id (Go)),
                                            Ap (V (Show_Sel),
                                                V (D)),
                                            V (XS2)),
                                       Str ("]")))));
                        Ms2.Append (Err ("showsPrec"));
                        Dict := Mk_Dict (M, Cl2, Supers2, Ms2, Span);
                        Bind (Inst.Dict_Global, Lam (D, Dict));
                     end;
                  elsif Cl_Id = Env.Show_Cl then
                     if Inst.Head = Env.Int_TC
                       or else Inst.Head = Env.Integer_TC
                     then
                        Ms.Append (V (P_ShowI));
                     elsif Inst.Head = Env.Char_TC then
                        Ms.Append (V (P_ShowC));
                     elsif Inst.Head = Env.Bool_TC then
                        Ms.Append (V (P_ShowB));
                     elsif Inst.Head = Env.Double_TC
                       or else Inst.Head = Env.Float_TC
                     then
                        Ms.Append (V (P_ShowD));
                     else
                        Ms.Append (Err ("show: no runtime for this"
                                        & " type yet"));
                     end if;
                     Give_Dict (Real_Instance_Id (II), Errs (Cl,
                                Fill => Ms));
                  elsif Cl_Id = Env.Enum_Cl
                    and then (Inst.Head = Env.Int_TC
                              or else Inst.Head =
                                        Env.Integer_TC)
                  then
                     declare
                        Fill : Expr_Id_Vectors.Vector;
                     begin
                        Fill.Append (Err ("succ"));
                        Fill.Append (Err ("pred"));
                        Fill.Append (Err ("toEnum"));
                        Fill.Append (Err ("fromEnum"));
                        Fill.Append (V (P_EnumF));
                        Fill.Append (Err ("enumFromThen"));
                        Fill.Append (V (P_EnumFT));
                        Fill.Append (Err ("enumFromThenTo"));
                        Give_Dict (Real_Instance_Id (II), Fill);
                     end;
                  elsif Cl_Id = Env.Monad_Cl
                    and then Inst.Head = Env.IO_TC
                  then
                     declare
                        S : constant Real_Var_Id := Fresh ("s");
                     begin
                        Ms.Append (V (P_BindIO));
                        Ms.Append (V (P_ThenIO));
                        Ms.Append (V (P_RetIO));
                        Ms.Append (Lam (S, Ap (V (P_Error),
                                               V (S))));
                        Give_Dict (Real_Instance_Id (II), Ms);
                     end;
                  elsif Cl_Id = Env.Monad_Cl
                    and then Inst.Head = Env.List_TC
                  then
                     declare
                        Mv : constant Real_Var_Id := Fresh ("m");
                        K : constant Real_Var_Id := Fresh ("k");
                        M2 : constant Real_Var_Id := Fresh ("m");
                        K2 : constant Real_Var_Id := Fresh ("k");
                        X : constant Real_Var_Id := Fresh ("x");
                        S : constant Real_Var_Id := Fresh ("s");
                     begin
                        Ms.Append
                          (Lam (Mv, Lam (K,
                             Ap2 (V (Env.Concat_Map_V),
                                  V (K), V (Mv)))));
                        Ms.Append
                          (Lam (M2, Lam (K2,
                             Ap2 (V (Env.Concat_Map_V),
                                  Lam (Fresh ("_"), V (K2)),
                                  V (M2)))));
                        Ms.Append (Lam (X, Cons (V (X),
                                                 Nil)));
                        Ms.Append (Lam (S, Nil));
                        Give_Dict (Real_Instance_Id (II), Ms);
                     end;
                  else
                     Give_Dict (Real_Instance_Id (II), Errs (Cl));
                  end if;
               end;
            end if;
         end;
      end loop;
   end Install_Bodies;

end AHC.Prelude_Core;
