with AHC.Diagnostics;

package body AHC.Prelude_Core is

   use AHC.Core;

   procedure Install_Bodies
     (Table : in out Names.Name_Table;
      M     : in out Core.Core_Module;
      Env   : in out Builtins.Global_Env;
      Prims : in out Prim_Maps.Map;
      Base  : Builtins.Var_Maps.Map := Builtins.Var_Maps.Empty_Map)
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
         N : constant Names.Real_Name_Id := Table.Intern (Name);
         B : constant Builtins.Var_Maps.Cursor := Base.Find (N);
         C : constant Builtins.Var_Maps.Cursor :=
           Env.Values.Find (N);
      begin
         --  The Base snapshot first: the wired var, not whatever
         --  module most recently claimed the bare name.
         if Builtins.Var_Maps.Has_Element (B) then
            return Var_Id (Builtins.Var_Maps.Element (B));
         end if;
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
      P_ShowStr : constant Real_Var_Id :=
        Prim ("primshowString", "ahc_prim_show_string");
      P_ShowsL : constant Real_Var_Id :=
        Prim ("primshowsList", "ahc_prim_shows_list");
      P_SPI : constant Real_Var_Id :=
        Prim ("primshowsPrecI", "ahc_prim_showsprec_int");
      P_SPD : constant Real_Var_Id :=
        Prim ("primshowsPrecD", "ahc_prim_showsprec_d");
      P_GtI : constant Real_Var_Id :=
        Prim ("primgtI", "ahc_prim_gt_int");
      --  Floating/RealFrac method implementations at Double.
      P_ExpD : constant Real_Var_Id :=
        Prim ("primexpD", "ahc_prim_exp_d");
      P_LogD : constant Real_Var_Id :=
        Prim ("primlogD", "ahc_prim_log_d");
      P_SqrtD : constant Real_Var_Id :=
        Prim ("primsqrtD", "ahc_prim_sqrt_d");
      P_PowD : constant Real_Var_Id :=
        Prim ("primpowD", "ahc_prim_pow_d");
      P_LogBaseD : constant Real_Var_Id :=
        Prim ("primlogBaseD", "ahc_prim_logbase_d");
      P_SinD : constant Real_Var_Id :=
        Prim ("primsinD", "ahc_prim_sin_d");
      P_CosD : constant Real_Var_Id :=
        Prim ("primcosD", "ahc_prim_cos_d");
      P_TanD : constant Real_Var_Id :=
        Prim ("primtanD", "ahc_prim_tan_d");
      P_AsinD : constant Real_Var_Id :=
        Prim ("primasinD", "ahc_prim_asin_d");
      P_AcosD : constant Real_Var_Id :=
        Prim ("primacosD", "ahc_prim_acos_d");
      P_AtanD : constant Real_Var_Id :=
        Prim ("primatanD", "ahc_prim_atan_d");
      P_SinhD : constant Real_Var_Id :=
        Prim ("primsinhD", "ahc_prim_sinh_d");
      P_CoshD : constant Real_Var_Id :=
        Prim ("primcoshD", "ahc_prim_cosh_d");
      P_TanhD : constant Real_Var_Id :=
        Prim ("primtanhD", "ahc_prim_tanh_d");
      P_FloorD : constant Real_Var_Id :=
        Prim ("primfloorD", "ahc_prim_floor_d");
      P_CeilD : constant Real_Var_Id :=
        Prim ("primceilingD", "ahc_prim_ceiling_d");
      P_RoundD : constant Real_Var_Id :=
        Prim ("primroundD", "ahc_prim_round_d");
      P_TruncD : constant Real_Var_Id :=
        Prim ("primtruncateD", "ahc_prim_truncate_d");
      P_IsNanD : constant Real_Var_Id :=
        Prim ("primisNaND", "ahc_prim_isnan_d");
      P_IsInfD : constant Real_Var_Id :=
        Prim ("primisInfiniteD", "ahc_prim_isinf_d");
      P_IsNegZD : constant Real_Var_Id :=
        Prim ("primisNegativeZeroD", "ahc_prim_isnegzero_d");
      P_Atan2D : constant Real_Var_Id :=
        Prim ("primatan2D", "ahc_prim_atan2_d");

      P_EnumFTh : constant Real_Var_Id :=
        Prim ("primenumFromThen", "ahc_prim_enum_from_then");
      P_EnumFTT : constant Real_Var_Id :=
        Prim ("primenumFromThenTo", "ahc_prim_enum_from_then_to");
      P_Succ : constant Real_Var_Id :=
        Prim ("primsucc", "ahc_prim_succ_int");
      P_Pred : constant Real_Var_Id :=
        Prim ("primpred", "ahc_prim_pred_int");
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
      P_Seq : constant Real_Var_Id :=
        Prim ("primseq", "ahc_prim_seq");
      P_FromRatD : constant Real_Var_Id :=
        Prim ("primfromRationalD", "ahc_prim_from_rational_d");

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

      --  Derived Enum/Bounded/Ix/Read for ENUMERATIONS (all-nullary
      --  constructors): everything is constructor-tag arithmetic.
      --  Every builder mints fresh nodes per use (tree invariant).

      function All_Nullary (TC : Real_TyCon_Id) return Boolean is
      begin
         for DC of M.Info (TC).Cons loop
            if M.Info (Real_DataCon_Id (DC)).Arity /= 0 then
               return False;
            end if;
         end loop;
         return not M.Info (TC).Cons.Is_Empty;
      end All_Nullary;

      function IntE (K : Integer) return Real_Expr_Id is
         Img : constant String := K'Image;
         T : constant String :=
           (if Img (Img'First) = ' '
            then Img (Img'First + 1 .. Img'Last) else Img);
      begin
         return M.Add (Expr_Node'
           (Kind => Lit_C, Span => Span,
            Lit => (Kind => L_Int,
                    Text => Names.Name_Id (Table.Intern (T)))));
      end IntE;

      --  case X of C1 -> tag-1 exprs ... (one alt per constructor,
      --  bodies supplied per tag by F).
      function Tag_Case
        (TC : Real_TyCon_Id; X : Real_Var_Id;
         F : access function (Tag : Positive) return Real_Expr_Id)
         return Real_Expr_Id
      is
         Alts : Alt_Id_Vectors.Vector;
      begin
         for I in 1 .. M.Info (TC).Cons.Last_Index loop
            Alts.Append (M.Add (Alt_Node'
              (Kind => Con_Alt, Span => Span,
               A_Con => Real_DataCon_Id (M.Info (TC).Cons (I)),
               Binders => Var_Id_Vectors.Empty_Vector,
               Alt_Body => F (I))));
         end loop;
         return M.Add (Expr_Node'
           (Kind => Case_C, Span => Span,
            Scrutinee => V (Var_Id (X)), Alts => Alts));
      end Tag_Case;

      --  fromEnum body over variable X: constructor -> tag-1.
      function From_E
        (TC : Real_TyCon_Id; X : Real_Var_Id) return Real_Expr_Id
      is
         function F (Tag : Positive) return Real_Expr_Id
         is (IntE (Tag - 1));
      begin
         return Tag_Case (TC, X, F'Access);
      end From_E;

      --  toEnum as a fresh lambda: eq-chain over tags.
      function To_E_Lam (TC : Real_TyCon_Id) return Real_Expr_Id is
         I : constant Real_Var_Id := Fresh ("i");
         N : constant Positive := M.Info (TC).Cons.Last_Index;
         Body_E : Real_Expr_Id := Err ("toEnum: bad argument");
      begin
         for K in reverse 1 .. N loop
            Body_E := Bool_Case
              (Ap2 (V (P_EqP), V (Var_Id (I)), IntE (K - 1)),
               ConE (M.Info (TC).Cons (K)), Body_E);
         end loop;
         return Lam (I, Body_E);
      end To_E_Lam;

      --  map toEnum Over  (fresh trees per call).
      function Map_To_E
        (TC : Real_TyCon_Id; Over : Real_Expr_Id) return Real_Expr_Id
      is (Ap2 (V (Lookup ("map")), To_E_Lam (TC), Over));

      procedure Derive_Enum (II : Real_Instance_Id) is
         TC : constant Real_TyCon_Id :=
           Real_TyCon_Id (M.Info (II).Head);
         N : constant Positive := M.Info (TC).Cons.Last_Index;
         Ms : Expr_Id_Vectors.Vector;

         function Succ_F (Tag : Positive) return Real_Expr_Id
         is (if Tag < N then ConE (M.Info (TC).Cons (Tag + 1))
             else Err ("succ: bad argument"));
         function Pred_F (Tag : Positive) return Real_Expr_Id
         is (if Tag > 1 then ConE (M.Info (TC).Cons (Tag - 1))
             else Err ("pred: bad argument"));
      begin
         declare
            X : constant Real_Var_Id := Fresh ("x");
         begin
            Ms.Append (Lam (X, Tag_Case (TC, X, Succ_F'Access)));
         end;
         declare
            X : constant Real_Var_Id := Fresh ("x");
         begin
            Ms.Append (Lam (X, Tag_Case (TC, X, Pred_F'Access)));
         end;
         Ms.Append (To_E_Lam (TC));
         declare
            X : constant Real_Var_Id := Fresh ("x");
         begin
            Ms.Append (Lam (X, From_E (TC, X)));
         end;
         declare
            A : constant Real_Var_Id := Fresh ("a");
         begin
            Ms.Append (Lam (A, Map_To_E (TC,
              Ap2 (V (P_EnumFT), From_E (TC, A), IntE (N - 1)))));
         end;
         declare
            A : constant Real_Var_Id := Fresh ("a");
            B : constant Real_Var_Id := Fresh ("b");
            Bound : constant Real_Expr_Id :=
              Bool_Case (Ap2 (V (P_GtI), From_E (TC, A),
                              From_E (TC, B)),
                         IntE (0), IntE (N - 1));
         begin
            Ms.Append (Lam (A, Lam (B, Map_To_E (TC,
              Ap (Ap2 (V (P_EnumFTT), From_E (TC, A),
                       From_E (TC, B)), Bound)))));
         end;
         declare
            A : constant Real_Var_Id := Fresh ("a");
            B : constant Real_Var_Id := Fresh ("b");
         begin
            Ms.Append (Lam (A, Lam (B, Map_To_E (TC,
              Ap2 (V (P_EnumFT), From_E (TC, A),
                   From_E (TC, B))))));
         end;
         declare
            A : constant Real_Var_Id := Fresh ("a");
            B : constant Real_Var_Id := Fresh ("b");
            C : constant Real_Var_Id := Fresh ("c");
         begin
            Ms.Append (Lam (A, Lam (B, Lam (C, Map_To_E (TC,
              Ap (Ap2 (V (P_EnumFTT), From_E (TC, A),
                       From_E (TC, B)), From_E (TC, C)))))));
         end;
         Give_Dict (II, Ms);
      end Derive_Enum;

      procedure Derive_Bounded (II : Real_Instance_Id) is
         TC : constant Real_TyCon_Id :=
           Real_TyCon_Id (M.Info (II).Head);
         Ms : Expr_Id_Vectors.Vector;
      begin
         Ms.Append (ConE (M.Info (TC).Cons (1)));
         Ms.Append
           (ConE (M.Info (TC).Cons (M.Info (TC).Cons.Last_Index)));
         Give_Dict (II, Ms);
      end Derive_Bounded;

      --  case P of (a, b) -> Body (a, b)  (pair scrutinee).
      function Pair_Case
        (P : Real_Var_Id; A, B : Real_Var_Id;
         Body_E : Real_Expr_Id) return Real_Expr_Id
      is
         Alts : Alt_Id_Vectors.Vector;
         Bs : Var_Id_Vectors.Vector;
      begin
         Bs.Append (Var_Id (A));
         Bs.Append (Var_Id (B));
         Alts.Append (M.Add (Alt_Node'
           (Kind => Con_Alt, Span => Span,
            A_Con => Real_DataCon_Id (Env.Tuple_DCs (2)),
            Binders => Bs, Alt_Body => Body_E)));
         return M.Add (Expr_Node'
           (Kind => Case_C, Span => Span,
            Scrutinee => V (Var_Id (P)), Alts => Alts));
      end Pair_Case;

      procedure Derive_Ix (II : Real_Instance_Id) is
         TC : constant Real_TyCon_Id :=
           Real_TyCon_Id (M.Info (II).Head);
         Ms : Expr_Id_Vectors.Vector;
      begin
         declare
            P : constant Real_Var_Id := Fresh ("p");
            A : constant Real_Var_Id := Fresh ("a");
            B : constant Real_Var_Id := Fresh ("b");
         begin
            Ms.Append (Lam (P, Pair_Case (P, A, B, Map_To_E (TC,
              Ap2 (V (P_EnumFT), From_E (TC, A),
                   From_E (TC, B))))));
         end;
         declare
            P : constant Real_Var_Id := Fresh ("p");
            A : constant Real_Var_Id := Fresh ("a");
            B : constant Real_Var_Id := Fresh ("b");
            I : constant Real_Var_Id := Fresh ("i");
         begin
            Ms.Append (Lam (P, Lam (I, Pair_Case (P, A, B,
              Ap2 (V (P_Sub), From_E (TC, I),
                   From_E (TC, A))))));
         end;
         declare
            P : constant Real_Var_Id := Fresh ("p");
            A : constant Real_Var_Id := Fresh ("a");
            B : constant Real_Var_Id := Fresh ("b");
            I : constant Real_Var_Id := Fresh ("i");
         begin
            Ms.Append (Lam (P, Lam (I, Pair_Case (P, A, B,
              Bool_Case
                (Ap2 (V (P_GtI), From_E (TC, A), From_E (TC, I)),
                 ConE (Env.False_DC),
                 Bool_Case
                   (Ap2 (V (P_GtI), From_E (TC, I),
                         From_E (TC, B)),
                    ConE (Env.False_DC),
                    ConE (Env.True_DC)))))));
         end;
         declare
            P : constant Real_Var_Id := Fresh ("p");
            A : constant Real_Var_Id := Fresh ("a");
            B : constant Real_Var_Id := Fresh ("b");
         begin
            Ms.Append (Lam (P, Pair_Case (P, A, B,
              Bool_Case
                (Ap2 (V (P_GtI), From_E (TC, A), From_E (TC, B)),
                 IntE (0),
                 Ap2 (V (P_Add),
                      Ap2 (V (P_Sub), From_E (TC, B),
                           From_E (TC, A)),
                      IntE (1))))));
         end;
         Give_Dict (II, Ms);
      end Derive_Ix;

      procedure Derive_Read (II : Real_Instance_Id) is
         TC : constant Real_TyCon_Id :=
           Real_TyCon_Id (M.Info (II).Head);
         Ms : Expr_Id_Vectors.Vector;
         Tbl : Real_Expr_Id := Nil;
      begin
         for I in reverse 1 .. M.Info (TC).Cons.Last_Index loop
            declare
               DC : constant Real_DataCon_Id :=
                 Real_DataCon_Id (M.Info (TC).Cons (I));
            begin
               Tbl := Cons
                 (Ap2 (ConE (Env.Tuple_DCs (2)),
                       Str (Table.Text (M.Info (DC).Name)),
                       ConE (DataCon_Id (DC))),
                  Tbl);
            end;
         end loop;
         Ms.Append (Ap (V (Lookup ("readsEnum_")), Tbl));
         Give_Dict (II, Ms);
      end Derive_Read;

      --  Report 11.4 Show method shapes. Each helper embeds the given
      --  show-function expression once (callers rebuild it per use to
      --  keep Core a tree).
      --  showsPrec via show: \_ x s -> show x ++ s
      function F_SP (Show_Fn : Real_Expr_Id) return Real_Expr_Id is
         D : constant Real_Var_Id := Fresh ("d");
         X : constant Real_Var_Id := Fresh ("x");
         S : constant Real_Var_Id := Fresh ("s");
      begin
         return Lam (D, Lam (X, Lam (S,
           Ap2 (V (Env.Append_V), Ap (Show_Fn, V (Var_Id (X))),
                V (Var_Id (S))))));
      end F_SP;

      --  showsPrec via a precedence-aware prim: \d x s -> p d x ++ s
      function F_SP_Prim (P : Real_Var_Id) return Real_Expr_Id is
         D : constant Real_Var_Id := Fresh ("d");
         X : constant Real_Var_Id := Fresh ("x");
         S : constant Real_Var_Id := Fresh ("s");
      begin
         return Lam (D, Lam (X, Lam (S,
           Ap2 (V (Env.Append_V),
                Ap2 (V (P), V (Var_Id (D)), V (Var_Id (X))),
                V (Var_Id (S))))));
      end F_SP_Prim;

      --  showList: \xs s -> primshowsList show xs ++ s
      function F_SL (Show_Fn : Real_Expr_Id) return Real_Expr_Id is
         XS : constant Real_Var_Id := Fresh ("xs");
         S  : constant Real_Var_Id := Fresh ("s");
      begin
         return Lam (XS, Lam (S,
           Ap2 (V (Env.Append_V),
                Ap2 (V (P_ShowsL), Show_Fn, V (Var_Id (XS))),
                V (Var_Id (S)))));
      end F_SL;

      function Has_DataCons (TC : Real_TyCon_Id) return Boolean
      is (not M.Info (TC).Cons.Is_Empty);

      --  deriving Show (Report 11.5). Builds showsPrec directly:
      --
      --    \d x s -> case x of
      --      K0        -> "K0" ++ s
      --      K a b     -> if d > 10 then "(" ++ B ++ ")" ++ s
      --                             else B ++ s
      --        where B = "K " ++ showsPrec 11 a "" ++ " " ++ ...
      --      R {f = v} -> "R {f = " ++ show v ++ ", ..." (records)
      --
      --  Field dictionaries resolve statically: type variables map to
      --  the derived instance's context parameters, constructors to
      --  their instance dictionaries (applied recursively for list /
      --  Maybe / tuple arguments).
      procedure Derive_Show (II : Real_Instance_Id) is
         Inst : constant Instance_Info := M.Info (II);

         --  Leaf-node copy (Var/Lit): every embedding of the d / s
         --  parameters needs a fresh node - Core must stay a tree.
         function Fresh_Copy
           (E : Real_Expr_Id) return Real_Expr_Id
         is (M.Add (M.Node (E)));
         Cl : constant Real_Class_Id := Real_Class_Id (Inst.Of_Class);
         SP_Sel : constant Var_Id := M.Info (Cl).Methods (2).Selector;
         Params : Var_Id_Vectors.Vector;

         --  Tvs is the constructor scheme's quantifier list, whose
         --  order matches the data declaration's type variables (and
         --  therefore the derived instance's context parameters); the
         --  ids themselves differ, so map positionally.
         function Dict_For
           (T : Real_Type_Id; Tvs : TyVar_Id_Vectors.Vector)
            return Expr_Id
         is
            N : constant Type_Node := M.Node (T);
         begin
            case N.Kind is
               when TVar_T =>
                  for I in 1 .. Tvs.Last_Index loop
                     if Tvs (I) = N.Tv
                       and then I <= Params.Last_Index
                     then
                        return Expr_Id (V (Var_Id (Params (I))));
                     end if;
                  end loop;
                  return No_Expr;
               when TCon_T =>
                  for SI of M.Info (Cl).Instances loop
                     if M.Info (SI).Head = TyCon_Id (N.Con)
                       and then M.Info (SI).Dict_Global /= No_Var
                     then
                        return Expr_Id (V (M.Info (SI).Dict_Global));
                     end if;
                  end loop;
                  return No_Expr;
               when TApp_T =>
                  --  Head instance dictionary applied to the
                  --  arguments' dictionaries.
                  declare
                     Head : Real_Type_Id := T;
                     Args : Type_Id_Vectors.Vector;
                  begin
                     while M.Node (Head).Kind = TApp_T loop
                        Args.Prepend (M.Node (Head).T_Arg);
                        Head := M.Node (Head).T_Fun;
                     end loop;
                     if M.Node (Head).Kind /= TCon_T then
                        return No_Expr;
                     end if;
                     for SI of M.Info (Cl).Instances loop
                        if M.Info (SI).Head =
                             TyCon_Id (M.Node (Head).Con)
                          and then M.Info (SI).Dict_Global /= No_Var
                        then
                           declare
                              Acc : Expr_Id :=
                                Expr_Id (V (M.Info (SI).Dict_Global));
                           begin
                              for A of Args loop
                                 declare
                                    DA : constant Expr_Id :=
                                      Dict_For (A, Tvs);
                                 begin
                                    if DA = No_Expr then
                                       return No_Expr;
                                    end if;
                                    Acc := Expr_Id
                                      (Ap (Real_Expr_Id (Acc),
                                           Real_Expr_Id (DA)));
                                 end;
                              end loop;
                              return Acc;
                           end;
                        end if;
                     end loop;
                     return No_Expr;
                  end;
               when others =>
                  return No_Expr;
            end case;
         end Dict_For;

         --  showsPrec 11 <field> "" as a string expression, or show
         --  at precedence 0 for record fields.
         function Field_S
           (FT : Real_Type_Id; B : Real_Var_Id; Prec : Natural;
            Tvs : TyVar_Id_Vectors.Vector)
            return Real_Expr_Id
         is
            D : constant Expr_Id := Dict_For (FT, Tvs);
            P_Lit : constant Real_Expr_Id :=
              M.Add (Expr_Node'
                (Kind => Lit_C, Span => Span,
                 Lit => (Kind => L_Int,
                         Text => Names.Name_Id
                           (Table.Intern
                              (Natural'Image (Prec)
                                 (2 .. Natural'Image (Prec)'Last))))));
         begin
            if D = No_Expr then
               return Err ("deriving Show: unsupported field type");
            end if;
            return Ap2 (Ap2 (V (SP_Sel),
                             Real_Expr_Id (D), P_Lit),
                        V (Var_Id (B)), Str (""));
         end Field_S;

         --  The case over constructors; D_E/S_E are embedded once.
         function Build_Case
           (X : Real_Var_Id; D_E, S_E : Real_Expr_Id)
            return Real_Expr_Id
         is
            Alts : Alt_Id_Vectors.Vector;
         begin
            for DCI of M.Info (Real_TyCon_Id (Inst.Head)).Cons loop
               declare
                  DC : constant Real_DataCon_Id :=
                    Real_DataCon_Id (DCI);
                  DInfo : constant DataCon_Info := M.Info (DC);
                  CName : constant String :=
                    Table.Text (Names.Real_Name_Id (DInfo.Name));
                  Sch : constant Scheme :=
                    M.Node (Real_Scheme_Id (DInfo.Con_Scheme));
                  FTypes : Type_Id_Vectors.Vector;
                  Bs : Var_Id_Vectors.Vector;

                  function Inner return Real_Expr_Id is
                     Acc : Real_Expr_Id;
                  begin
                     if CName'Length > 0
                       and then CName (CName'First) = ':'
                       and then FTypes.Last_Index = 2
                     then
                        --  Infix constructor: l :* r, fields at
                        --  precedence 10 (GHC's derived layout for
                        --  an undeclared-fixity operator con).
                        Acc := Ap2 (V (Env.Append_V),
                          Field_S (FTypes (1), Bs (1), 10, Sch.Tvs),
                          Ap2 (V (Env.Append_V),
                            Str (" " & CName & " "),
                            Field_S (FTypes (2), Bs (2), 10,
                                     Sch.Tvs)));
                        return Acc;
                     end if;
                     if DInfo.Field_Names.Is_Empty then
                        Acc := Str (CName & " ");
                        for I in 1 .. FTypes.Last_Index loop
                           declare
                              FS : constant Real_Expr_Id :=
                                Field_S (FTypes (I), Bs (I), 11,
                                         Sch.Tvs);
                           begin
                              Acc := Ap2 (V (Env.Append_V), Acc,
                                (if I < FTypes.Last_Index
                                 then Ap2 (V (Env.Append_V), FS,
                                           Str (" "))
                                 else FS));
                           end;
                        end loop;
                     else
                        Acc := Str (CName & " {");
                        for I in 1 .. FTypes.Last_Index loop
                           declare
                              Lbl : constant String :=
                                Table.Text (Names.Real_Name_Id
                                  (DInfo.Field_Names (I)))
                                & " = ";
                              FS : constant Real_Expr_Id :=
                                Field_S (FTypes (I), Bs (I), 0,
                                         Sch.Tvs);
                           begin
                              Acc := Ap2 (V (Env.Append_V), Acc,
                                Ap2 (V (Env.Append_V), Str (Lbl),
                                  (if I < FTypes.Last_Index
                                   then Ap2 (V (Env.Append_V), FS,
                                             Str (", "))
                                   else FS)));
                           end;
                        end loop;
                        Acc := Ap2 (V (Env.Append_V), Acc, Str ("}"));
                     end if;
                     return Acc;
                  end Inner;

                  Body_E : Real_Expr_Id;
               begin
                  declare
                     T : Real_Type_Id := Real_Type_Id (Sch.S_Body);
                  begin
                     while M.Node (T).Kind = TFun_T loop
                        FTypes.Append (M.Node (T).From);
                        Bs.Append (Fresh ("b"));
                        T := M.Node (T).To;
                     end loop;
                  end;
                  if FTypes.Is_Empty then
                     Body_E := Ap2 (V (Env.Append_V), Str (CName),
                                    Fresh_Copy (S_E));
                  else
                     Body_E := Bool_Case
                       (Ap2 (V (P_GtI), Fresh_Copy (D_E),
                             M.Add (Expr_Node'
                               (Kind => Lit_C, Span => Span,
                                Lit => (Kind => L_Int,
                                        Text => Names.Name_Id
                                          (Table.Intern
                                             ((if CName'Length > 0
                                               and then CName
                                                 (CName'First) = ':'
                                               and then
                                                 FTypes.Last_Index
                                                   = 2
                                               then "9"
                                               else "10"))))))),
                        Ap2 (V (Env.Append_V), Str ("("),
                          Ap2 (V (Env.Append_V), Inner,
                            Ap2 (V (Env.Append_V), Str (")"),
                                 Fresh_Copy (S_E)))),
                        Ap2 (V (Env.Append_V), Inner,
                             Fresh_Copy (S_E)));
                  end if;
                  Alts.Append (M.Add (Alt_Node'
                    (Kind => Con_Alt, Span => Span, A_Con => DC,
                     Binders => Bs, Alt_Body => Body_E)));
               end;
            end loop;
            return M.Add (Expr_Node'
              (Kind => Case_C, Span => Span,
               Scrutinee => V (Var_Id (X)), Alts => Alts));
         end Build_Case;

         Ms : Expr_Id_Vectors.Vector;
         Dict : Real_Expr_Id;
      begin
         for CI in 1 .. Inst.Context.Last_Index loop
            Params.Append (Fresh ("$d"));
         end loop;
         declare
            X1 : constant Real_Var_Id := Fresh ("x");
            X2 : constant Real_Var_Id := Fresh ("x");
            D1 : constant Real_Var_Id := Fresh ("d");
            S1 : constant Real_Var_Id := Fresh ("s");

            function Show_X return Real_Expr_Id is
               XI : constant Real_Var_Id := Fresh ("x");
            begin
               return Lam (XI, Build_Case
                 (XI,
                  M.Add (Expr_Node'
                    (Kind => Lit_C, Span => Span,
                     Lit => (Kind => L_Int,
                             Text => Names.Name_Id
                               (Table.Intern ("0"))))),
                  Str ("")));
            end Show_X;
            pragma Unreferenced (X2);
         begin
            Ms.Append (Show_X);
            Ms.Append (Lam (D1, Lam (X1, Lam (S1,
              Build_Case (X1, V (Var_Id (D1)), V (Var_Id (S1)))))));
            Ms.Append (F_SL (Show_X));
         end;
         Dict := Mk_Dict (M, Cl, Expr_Id_Vectors.Empty_Vector, Ms,
                          Span);
         for PI in reverse 1 .. Params.Last_Index loop
            Dict := Lam (Params (PI), Dict);
         end loop;
         Bind (Inst.Dict_Global, Dict);
      end Derive_Show;

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
      Bind_Name ("seq", V (P_Seq));
      declare
         F : constant Real_Var_Id := Fresh ("f");
         X : constant Real_Var_Id := Fresh ("x");
      begin
         --  f $! x forces x before the call (Report 6.2).
         Bind_Name ("$!",
           Lam (F, Lam (X,
             Ap2 (V (P_Seq), V (X), Ap (V (F), V (X))))));
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

      --  Floating/RealFrac moved into instance dictionaries; only
      --  atan2 stays a bound global.
      declare
         procedure BP (Name, Symbol : String) is
         begin
            Bind_Name (Name, V (Prim ("prim" & Name, Symbol)));
         end BP;
      begin
         BP ("ord", "ahc_prim_ord");
         BP ("chr", "ahc_prim_chr");
         BP ("getLine", "ahc_prim_getline");
         BP ("isEOF", "ahc_prim_iseof");
         BP ("getContents", "ahc_prim_getcontents");
         BP ("readFile", "ahc_prim_readfile");
         BP ("primHOpen", "ahc_prim_h_open");
         BP ("primHClose", "ahc_prim_h_close");
         BP ("primHPutStr", "ahc_prim_h_put_str");
         BP ("primHGetLine", "ahc_prim_h_get_line");
         BP ("primHGetChar", "ahc_prim_h_get_char");
         BP ("primHGetContents", "ahc_prim_h_get_contents");
         BP ("primHIsEOF", "ahc_prim_h_is_eof");
         BP ("primHFlush", "ahc_prim_h_flush");
         BP ("primScope", "ahc_prim_scope");
         BP ("primSpawn", "ahc_prim_spawn");
         BP ("primAwait", "ahc_prim_await");
         BP ("primChanNew", "ahc_prim_chan_new");
         BP ("primChanSend", "ahc_prim_chan_send");
         BP ("primChanRecv", "ahc_prim_chan_recv");
         BP ("primYield", "ahc_prim_task_yield");
         BP ("primProtNew", "ahc_prim_prot_new");
         BP ("primProtRead", "ahc_prim_prot_read");
         BP ("primProtUpdate", "ahc_prim_prot_update");
         BP ("primProtEntry", "ahc_prim_prot_entry");
         BP ("primPar", "ahc_prim_par");
         BP ("primPseq", "ahc_prim_pseq");
         BP ("getArgs", "ahc_prim_getargs");
         BP ("getProgName", "ahc_prim_getprogname");
         BP ("exitWithCode", "ahc_prim_exit_with");
         BP ("primAndI", "ahc_prim_band");
         BP ("primOrI", "ahc_prim_bor");
         BP ("primXorI", "ahc_prim_bxor");
         BP ("primShiftLI", "ahc_prim_bshl");
         BP ("primShiftRI", "ahc_prim_bshr");
         BP ("primComplementI", "ahc_prim_bcompl");
         BP ("primPopCountI", "ahc_prim_popcount");
         BP ("nullPtr", "ahc_prim_null_ptr");
         BP ("peekCString", "ahc_prim_peek_cstring");
         BP ("nullFunPtr", "ahc_prim_null_ptr");
         BP ("freeHaskellFunPtr", "ahc_prim_free_funptr");
         BP ("mallocBytes", "ahc_prim_malloc_bytes");
         BP ("free", "ahc_prim_free_ptr");
         BP ("plusPtr", "ahc_prim_plus_ptr");
         BP ("castPtr", "ahc_prim_cast_ptr");
         BP ("peekInt8", "ahc_prim_peek_i8");
         BP ("peekInt16", "ahc_prim_peek_i16");
         BP ("peekInt32", "ahc_prim_peek_i32");
         BP ("peekInt64", "ahc_prim_peek_i64");
         BP ("peekWord8", "ahc_prim_peek_u8");
         BP ("peekWord16", "ahc_prim_peek_u16");
         BP ("peekWord32", "ahc_prim_peek_u32");
         BP ("peekWord64", "ahc_prim_peek_u64");
         BP ("peekDouble", "ahc_prim_peek_d");
         BP ("peekPtr", "ahc_prim_peek_p");
         BP ("pokeInt8", "ahc_prim_poke_i8");
         BP ("pokeInt16", "ahc_prim_poke_i16");
         BP ("pokeInt32", "ahc_prim_poke_i32");
         BP ("pokeInt64", "ahc_prim_poke_i64");
         BP ("pokeWord8", "ahc_prim_poke_u8");
         BP ("pokeWord16", "ahc_prim_poke_u16");
         BP ("pokeWord32", "ahc_prim_poke_u32");
         BP ("pokeWord64", "ahc_prim_poke_u64");
         BP ("pokeDouble", "ahc_prim_poke_d");
         BP ("pokePtr", "ahc_prim_poke_p");
         BP ("newCString", "ahc_prim_new_cstring");
         BP ("peekCStringLen", "ahc_prim_peek_cstring_len");
      end;

      --  quot/rem/div/mod are Integral methods now; their prims are
      --  installed through the instance dictionaries below.

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

            --  Fixed-width C types share Int's runtime nodes, so
            --  their Num/Integral/Show dictionaries reuse Int's.
            function Is_Fix (T : TyCon_Id) return Boolean
            is (for some K in Builtins.C_Fix_Kind =>
                  Env.CFix_TCs (K) = T);
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
                              or else Inst.Head = Env.Integer_TC
                              or else Is_Fix (Inst.Head))
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
                  elsif Cl_Id = Env.Integral_Cl
                    and then (Inst.Head = Env.Int_TC
                              or else Inst.Head = Env.Integer_TC
                              or else Is_Fix (Inst.Head))
                  then
                     --  Canonical bignum representation: Int and
                     --  Integer share nodes, so both instances bind
                     --  the same promoting prims, and toInteger is
                     --  the identity.
                     declare
                        X : constant Real_Var_Id := Fresh ("x");
                     begin
                        Ms.Append (V (P_Quot));
                        Ms.Append (V (P_Rem));
                        Ms.Append (V (P_Div));
                        Ms.Append (V (P_Mod));
                        Ms.Append (Lam (X, V (X)));
                     end;
                     Give_Dict (Real_Instance_Id (II), Ms);
                  elsif Cl_Id = Env.Floating_Cl
                    and then (Inst.Head = Env.Double_TC
                              or else Inst.Head = Env.Float_TC)
                  then
                     Ms.Append (M.Add (Expr_Node'
                       (Kind => Lit_C, Span => Span,
                        Lit => (Kind => L_Float,
                                Text => Names.Name_Id
                                  (Table.Intern
                                     ("3.141592653589793"))))));
                     Ms.Append (V (P_ExpD));
                     Ms.Append (V (P_LogD));
                     Ms.Append (V (P_SqrtD));
                     Ms.Append (V (P_PowD));
                     Ms.Append (V (P_LogBaseD));
                     Ms.Append (V (P_SinD));
                     Ms.Append (V (P_CosD));
                     Ms.Append (V (P_TanD));
                     Ms.Append (V (P_AsinD));
                     Ms.Append (V (P_AcosD));
                     Ms.Append (V (P_AtanD));
                     Ms.Append (V (P_SinhD));
                     Ms.Append (V (P_CoshD));
                     Ms.Append (V (P_TanhD));
                     Give_Dict (Real_Instance_Id (II), Ms);
                  elsif Cl_Id = Env.RealFrac_Cl
                    and then (Inst.Head = Env.Double_TC
                              or else Inst.Head = Env.Float_TC)
                  then
                     Ms.Append (V (P_TruncD));
                     Ms.Append (V (P_RoundD));
                     Ms.Append (V (P_CeilD));
                     Ms.Append (V (P_FloorD));
                     Ms.Append (V (Lookup ("dblPF_")));
                     Give_Dict (Real_Instance_Id (II), Ms);
                  elsif Cl_Id = Env.RealFloat_Cl
                    and then (Inst.Head = Env.Double_TC
                              or else Inst.Head = Env.Float_TC)
                  then
                     Ms.Append (V (P_IsNanD));
                     Ms.Append (V (P_IsInfD));
                     Ms.Append (V (P_IsNegZD));
                     Ms.Append (V (P_Atan2D));
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
                        --  Exact rational pair (or a legacy double
                        --  node) -> one correctly rounded Double.
                        Ms.Append (V (P_FromRatD));
                        pragma Unreferenced (R);
                     end;
                     Give_Dict (Real_Instance_Id (II), Ms);
                  elsif Cl_Id = Env.Show_Cl
                    and then Inst.Head = Env.List_TC
                  then
                     --  Show a => Show [a] (Report 11.4): show
                     --  dispatches to the ELEMENT dictionary's
                     --  showList, so strings render as string
                     --  literals via Show Char's showList.
                     declare
                        SL_Sel : constant Var_Id :=
                          M.Info (Real_Class_Id (Env.Show_Cl))
                            .Methods (3).Selector;
                        D : constant Real_Var_Id := Fresh ("$d");

                        --  \xs -> showList-sel d xs ""
                        function Show_XS return Real_Expr_Id is
                           XS : constant Real_Var_Id := Fresh ("xs");
                        begin
                           return Lam (XS,
                             Ap2 (Ap (V (SL_Sel), V (Var_Id (D))),
                                  V (Var_Id (XS)), Str ("")));
                        end Show_XS;

                        Supers2 : Expr_Id_Vectors.Vector;
                        Ms2 : Expr_Id_Vectors.Vector;
                        Dict : Real_Expr_Id;
                     begin
                        Ms2.Append (Show_XS);
                        Ms2.Append (F_SP (Show_XS));
                        Ms2.Append (F_SL (Show_XS));
                        Dict := Mk_Dict (M, Real_Class_Id (Cl_Id),
                                         Supers2, Ms2, Span);
                        Bind (Inst.Dict_Global, Lam (D, Dict));
                     end;
                  elsif Cl_Id = Env.Show_Cl then
                     if Inst.Head = Env.Int_TC
                       or else Inst.Head = Env.Integer_TC
                       or else Is_Fix (Inst.Head)
                     then
                        Ms.Append (V (P_ShowI));
                        Ms.Append (F_SP_Prim (P_SPI));
                        Ms.Append (F_SL (V (P_ShowI)));
                     elsif Inst.Head = Env.Char_TC then
                        --  showList at Char is string-literal
                        --  rendering (Report 11.4).
                        declare
                           XS : constant Real_Var_Id := Fresh ("xs");
                           St : constant Real_Var_Id := Fresh ("s");
                        begin
                           Ms.Append (V (P_ShowC));
                           Ms.Append (F_SP (V (P_ShowC)));
                           Ms.Append (Lam (XS, Lam (St,
                             Ap2 (V (Env.Append_V),
                                  Ap (V (P_ShowStr), V (Var_Id (XS))),
                                  V (Var_Id (St))))));
                        end;
                     elsif Inst.Head = Env.Bool_TC then
                        Ms.Append (V (P_ShowB));
                        Ms.Append (F_SP (V (P_ShowB)));
                        Ms.Append (F_SL (V (P_ShowB)));
                     elsif Inst.Head = Env.Double_TC
                       or else Inst.Head = Env.Float_TC
                     then
                        Ms.Append (V (P_ShowD));
                        Ms.Append (F_SP_Prim (P_SPD));
                        Ms.Append (F_SL (V (P_ShowD)));
                     elsif Inst.Head = Env.Unit_TC then
                        declare
                           function Show_U return Real_Expr_Id is
                              U : constant Real_Var_Id := Fresh ("u");
                           begin
                              return Lam (U, Str ("()"));
                           end Show_U;
                        begin
                           Ms.Append (Show_U);
                           Ms.Append (F_SP (Show_U));
                           Ms.Append (F_SL (Show_U));
                        end;
                     elsif Inst.Head = Env.Ordering_TC then
                        declare
                           --  case o of LT -> "LT"; EQ -> "EQ";
                           --  _ -> "GT"
                           function Show_O return Real_Expr_Id is
                              O : constant Real_Var_Id := Fresh ("o");
                              Alts : Alt_Id_Vectors.Vector;
                           begin
                              Alts.Append (M.Add (Alt_Node'
                                (Kind => Con_Alt, Span => Span,
                                 A_Con => Ordering_LT,
                                 Binders =>
                                   Var_Id_Vectors.Empty_Vector,
                                 Alt_Body => Str ("LT"))));
                              Alts.Append (M.Add (Alt_Node'
                                (Kind => Con_Alt, Span => Span,
                                 A_Con => Ordering_LT + 1,
                                 Binders =>
                                   Var_Id_Vectors.Empty_Vector,
                                 Alt_Body => Str ("EQ"))));
                              Alts.Append (M.Add (Alt_Node'
                                (Kind => Default_Alt, Span => Span,
                                 Alt_Body => Str ("GT"))));
                              return Lam (O, M.Add (Expr_Node'
                                (Kind => Case_C, Span => Span,
                                 Scrutinee => V (Var_Id (O)),
                                 Alts => Alts)));
                           end Show_O;
                        begin
                           Ms.Append (Show_O);
                           Ms.Append (F_SP (Show_O));
                           Ms.Append (F_SL (Show_O));
                        end;
                     elsif Has_DataCons (Real_TyCon_Id (Inst.Head))
                     then
                        --  deriving Show (Report 11.5): per-
                        --  constructor showsPrec with fields at
                        --  precedence 11, record syntax for labelled
                        --  constructors.
                        Derive_Show (Real_Instance_Id (II));
                     else
                        Ms.Append (Err ("show: no runtime for this"
                                        & " type yet"));
                     end if;
                     if Ms.Is_Empty then
                        null;   --  Derive_Show bound the dictionary
                     else
                        Give_Dict (Real_Instance_Id (II), Errs (Cl,
                                   Fill => Ms));
                     end if;
                  elsif Cl_Id = Env.Enum_Cl
                    and then Inst.Head = Env.Char_TC
                  then
                     --  Char rides ord/chr over the Int instance;
                     --  bodies are Prelude source (charSucc_ etc.).
                     Ms.Append (V (Lookup ("charSucc_")));
                     Ms.Append (V (Lookup ("charPred_")));
                     Ms.Append (V (Lookup ("chr")));
                     Ms.Append (V (Lookup ("ord")));
                     Ms.Append (V (Lookup ("charEF_")));
                     Ms.Append (V (Lookup ("charEFTh_")));
                     Ms.Append (V (Lookup ("charEFT_")));
                     Ms.Append (V (Lookup ("charEFThT_")));
                     Give_Dict (Real_Instance_Id (II), Ms);
                  elsif Cl_Id = Env.Enum_Cl
                    and then (Inst.Head = Env.Double_TC
                              or else Inst.Head = Env.Float_TC)
                  then
                     --  Report 6.3.4 numeric enumeration (half-step
                     --  rule); bodies are Prelude source (dbl*_).
                     Ms.Append (V (Lookup ("dblSucc_")));
                     Ms.Append (V (Lookup ("dblPred_")));
                     Ms.Append (V (Lookup ("dblToE_")));
                     Ms.Append (V (Lookup ("dblFromE_")));
                     Ms.Append (V (Lookup ("dblEF_")));
                     Ms.Append (V (Lookup ("dblEFTh_")));
                     Ms.Append (V (Lookup ("dblEFT_")));
                     Ms.Append (V (Lookup ("dblEFThT_")));
                     Give_Dict (Real_Instance_Id (II), Ms);
                  elsif Cl_Id = Env.Enum_Cl
                    and then (Inst.Head = Env.Int_TC
                              or else Inst.Head =
                                        Env.Integer_TC)
                  then
                     declare
                        Fill : Expr_Id_Vectors.Vector;
                     begin
                        Fill.Append (V (P_Succ));
                        Fill.Append (V (P_Pred));
                        declare
                           N : constant Real_Var_Id := Fresh ("n");
                        begin
                           Fill.Append (Lam (N, V (Var_Id (N))));
                           --  toEnum at Int is the identity ...
                        end;
                        declare
                           N : constant Real_Var_Id := Fresh ("n");
                        begin
                           Fill.Append (Lam (N, V (Var_Id (N))));
                           --  ... and so is fromEnum.
                        end;
                        Fill.Append (V (P_EnumF));
                        Fill.Append (V (P_EnumFTh));
                        Fill.Append (V (P_EnumFT));
                        Fill.Append (V (P_EnumFTT));
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
                    and then Inst.Head = Env.Maybe_TC
                  then
                     --  Nothing >>= _ = Nothing; Just x >>= k = k x.
                     declare
                        function Maybe_Case
                          (Scrut : Real_Expr_Id;
                           On_Nothing : Real_Expr_Id;
                           X : Real_Var_Id;
                           On_Just : Real_Expr_Id)
                           return Real_Expr_Id
                        is
                           Alts : Alt_Id_Vectors.Vector;
                           Bs : Var_Id_Vectors.Vector;
                        begin
                           Alts.Append (M.Add (Alt_Node'
                             (Kind => Con_Alt, Span => Span,
                              A_Con => Real_DataCon_Id
                                         (Env.Nothing_DC),
                              Binders =>
                                Var_Id_Vectors.Empty_Vector,
                              Alt_Body => On_Nothing)));
                           Bs.Append (X);
                           Alts.Append (M.Add (Alt_Node'
                             (Kind => Con_Alt, Span => Span,
                              A_Con => Real_DataCon_Id (Env.Just_DC),
                              Binders => Bs,
                              Alt_Body => On_Just)));
                           return M.Add (Expr_Node'
                             (Kind => Case_C, Span => Span,
                              Scrutinee => Scrut, Alts => Alts));
                        end Maybe_Case;

                        Mv : constant Real_Var_Id := Fresh ("m");
                        K  : constant Real_Var_Id := Fresh ("k");
                        X  : constant Real_Var_Id := Fresh ("x");
                        M2 : constant Real_Var_Id := Fresh ("m");
                        K2 : constant Real_Var_Id := Fresh ("k");
                        X2 : constant Real_Var_Id := Fresh ("x");
                        S  : constant Real_Var_Id := Fresh ("s");
                     begin
                        Ms.Append (Lam (Mv, Lam (K,
                          Maybe_Case (V (Var_Id (Mv)),
                            ConE (Env.Nothing_DC), X,
                            Ap (V (Var_Id (K)), V (Var_Id (X)))))));
                        Ms.Append (Lam (M2, Lam (K2,
                          Maybe_Case (V (Var_Id (M2)),
                            ConE (Env.Nothing_DC), X2,
                            V (Var_Id (K2))))));
                        Ms.Append (ConE (Env.Just_DC));
                        Ms.Append (Lam (S, ConE (Env.Nothing_DC)));
                        Give_Dict (Real_Instance_Id (II), Ms);
                     end;
                  elsif Cl_Id = Env.Functor_Cl
                    and then Inst.Head = Env.List_TC
                  then
                     declare
                        D : constant Real_Var_Id := Fresh ("$d");
                        Map_V : constant Var_Id := Lookup ("map");
                     begin
                        --  fmap = map (map's own dict-free scheme).
                        Ms.Append (V (Map_V));
                        pragma Unreferenced (D);
                        Give_Dict (Real_Instance_Id (II), Ms);
                     end;
                  elsif Cl_Id = Env.Functor_Cl
                    and then Inst.Head = Env.Maybe_TC
                  then
                     declare
                        F : constant Real_Var_Id := Fresh ("f");
                        Mv : constant Real_Var_Id := Fresh ("m");
                        X : constant Real_Var_Id := Fresh ("x");
                        Alts : Alt_Id_Vectors.Vector;
                        Bs : Var_Id_Vectors.Vector;
                     begin
                        Alts.Append (M.Add (Alt_Node'
                          (Kind => Con_Alt, Span => Span,
                           A_Con => Real_DataCon_Id (Env.Nothing_DC),
                           Binders => Var_Id_Vectors.Empty_Vector,
                           Alt_Body => ConE (Env.Nothing_DC))));
                        Bs.Append (X);
                        Alts.Append (M.Add (Alt_Node'
                          (Kind => Con_Alt, Span => Span,
                           A_Con => Real_DataCon_Id (Env.Just_DC),
                           Binders => Bs,
                           Alt_Body =>
                             Ap (ConE (Env.Just_DC),
                                 Ap (V (Var_Id (F)),
                                     V (Var_Id (X)))))));
                        Ms.Append (Lam (F, Lam (Mv,
                          M.Add (Expr_Node'
                            (Kind => Case_C, Span => Span,
                             Scrutinee => V (Var_Id (Mv)),
                             Alts => Alts)))));
                        Give_Dict (Real_Instance_Id (II), Ms);
                     end;
                  elsif Cl_Id = Env.Functor_Cl
                    and then Inst.Head = Env.IO_TC
                  then
                     --  fmap f io = io >>= (return . f)
                     declare
                        F : constant Real_Var_Id := Fresh ("f");
                        Io : constant Real_Var_Id := Fresh ("io");
                        X : constant Real_Var_Id := Fresh ("x");
                     begin
                        Ms.Append (Lam (F, Lam (Io,
                          Ap2 (V (P_BindIO), V (Var_Id (Io)),
                               Lam (X,
                                 Ap (V (P_RetIO),
                                     Ap (V (Var_Id (F)),
                                         V (Var_Id (X)))))))));
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
                  elsif Cl_Id = Env.Enum_Cl
                    and then Has_DataCons (Real_TyCon_Id (Inst.Head))
                    and then All_Nullary (Real_TyCon_Id (Inst.Head))
                  then
                     --  deriving Enum for enumerations (also covers
                     --  the wired Bool/Ordering/() instances).
                     Derive_Enum (Real_Instance_Id (II));
                  elsif Cl_Id = Env.Bounded_Cl
                    and then Has_DataCons (Real_TyCon_Id (Inst.Head))
                    and then All_Nullary (Real_TyCon_Id (Inst.Head))
                  then
                     Derive_Bounded (Real_Instance_Id (II));
                  elsif Table.Text (M.Info (Cl).Name) = "Ix"
                    and then Has_DataCons (Real_TyCon_Id (Inst.Head))
                    and then All_Nullary (Real_TyCon_Id (Inst.Head))
                  then
                     Derive_Ix (Real_Instance_Id (II));
                  elsif Table.Text (M.Info (Cl).Name) = "Read"
                    and then Has_DataCons (Real_TyCon_Id (Inst.Head))
                    and then All_Nullary (Real_TyCon_Id (Inst.Head))
                  then
                     Derive_Read (Real_Instance_Id (II));
                  else
                     Give_Dict (Real_Instance_Id (II), Errs (Cl));
                  end if;
               end;
            end if;
         end;
      end loop;
   end Install_Bodies;

end AHC.Prelude_Core;
