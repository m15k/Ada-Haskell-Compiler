with AHC.Diagnostics;

package body AHC.Builtins is

   use AHC.Core;

   procedure Install
     (M     : in out Core.Core_Module;
      Table : in out Names.Name_Table;
      Env   : in out Global_Env)
   is
      Star_K : constant Real_Kind_Id := M.Star;
      No_Span : constant Diagnostics.Source_Span := (Start => 1, Stop => 1);

      function K_Fun (From, To : Real_Kind_Id) return Real_Kind_Id
      is (M.Add (Kind_Node'(Kind => KFun_K, KFrom => From, KTo => To)));

      Star1 : constant Real_Kind_Id := K_Fun (Star_K, Star_K);
      Star2 : constant Real_Kind_Id := K_Fun (Star_K, Star1);

      ------------------------------------------------------------------
      --  Entity helpers
      ------------------------------------------------------------------

      function Def_TyCon
        (Name : String; Arity : Natural; Kind : Real_Kind_Id)
         return Real_TyCon_Id
      is
         Id : constant Real_TyCon_Id :=
           M.Mint_TyCon ((Name => Table.Intern (Name), Arity => Arity,
                          TC_Kind => Kind, Is_Builtin => True,
                          others => <>));
      begin
         Env.TyCons.Include (M.Info (Id).Name, Id);
         return Id;
      end Def_TyCon;

      function Def_DataCon
        (Name : String; TC : Real_TyCon_Id; Tag : Positive;
         Arity : Natural) return Real_DataCon_Id
      is
         Id : constant Real_DataCon_Id :=
           M.Mint_DataCon ((Name => Table.Intern (Name), TyCon => TC,
                            Tag => Tag, Arity => Arity, others => <>));
      begin
         Env.DataCons.Include (M.Info (Id).Name, Id);
         return Id;
      end Def_DataCon;

      ------------------------------------------------------------------
      --  Type-building helpers
      ------------------------------------------------------------------

      function TC (Id : TyCon_Id) return Real_Type_Id
      is (M.Add (Type_Node'(Kind => TCon_T, Con => Id,
                            Refine => No_Refinement)));

      function TV (Tv : Real_TyVar_Id) return Real_Type_Id
      is (M.Add (Type_Node'(Kind => TVar_T, Tv => Tv)));

      function AP (F, A : Real_Type_Id) return Real_Type_Id
      is (M.Add (Type_Node'(Kind => TApp_T, T_Fun => F, T_Arg => A)));

      function FN (A, B : Real_Type_Id) return Real_Type_Id
      is (M.Add (Type_Node'(Kind => TFun_T, From => A, To => B)));

      function FN (A, B, C : Real_Type_Id) return Real_Type_Id
      is (FN (A, FN (B, C)));

      function LST (T : Real_Type_Id) return Real_Type_Id
      is (AP (TC (Env.List_TC), T));

      function IO_T (T : Real_Type_Id) return Real_Type_Id
      is (AP (TC (Env.IO_TC), T));

      function New_Tv (Name : String) return Real_TyVar_Id
      is (M.Mint_TyVar ((Name => Table.Intern (Name),
                         Tv_Kind => Star_K)));

      ------------------------------------------------------------------
      --  Scheme and global helpers
      ------------------------------------------------------------------

      function Mono (T : Real_Type_Id) return Real_Scheme_Id
      is (M.Add (Scheme'(Tvs => TyVar_Id_Vectors.Empty_Vector,
                         Context => Constraint_Vectors.Empty_Vector,
                         S_Body => Type_Id (T))));

      function Poly1
        (Tv : Real_TyVar_Id; T : Real_Type_Id;
         Ctx : Constraint_Vectors.Vector := Constraint_Vectors.Empty_Vector)
         return Real_Scheme_Id
      is
         Tvs : TyVar_Id_Vectors.Vector;
      begin
         Tvs.Append (Tv);
         return M.Add (Scheme'(Tvs => Tvs, Context => Ctx,
                               S_Body => Type_Id (T)));
      end Poly1;

      function Poly2
        (Tv1, Tv2 : Real_TyVar_Id; T : Real_Type_Id;
         Ctx : Constraint_Vectors.Vector := Constraint_Vectors.Empty_Vector)
         return Real_Scheme_Id
      is
         Tvs : TyVar_Id_Vectors.Vector;
      begin
         Tvs.Append (Tv1);
         Tvs.Append (Tv2);
         return M.Add (Scheme'(Tvs => Tvs, Context => Ctx,
                               S_Body => Type_Id (T)));
      end Poly2;

      function Ctx1 (Cl : Real_Class_Id; Arg : Real_Type_Id)
        return Constraint_Vectors.Vector
      is
         C : Constraint_Vectors.Vector;
      begin
         C.Append (Constraint'(Class => Cl, Arg => Arg, Span => No_Span));
         return C;
      end Ctx1;

      function Def_Global
        (Name : String; Sch : Real_Scheme_Id) return Real_Var_Id
      is
         Id : constant Real_Var_Id :=
           M.Mint_Var ((Name => Table.Intern (Name), Span => No_Span,
                        Is_Global => True, Var_Scheme => Sch,
                        others => <>));
      begin
         Env.Values.Include (M.Info (Id).Name, Id);
         return Id;
      end Def_Global;

      ------------------------------------------------------------------
      --  Class helpers
      ------------------------------------------------------------------

      function Def_Class
        (Name : String; Var_Kind : Real_Kind_Id;
         Supers : Class_Id_Vectors.Vector := Class_Id_Vectors.Empty_Vector)
         return Real_Class_Id
      is
         Dict_TC : constant Real_TyCon_Id :=
           Def_TyCon ("Dict$" & Name, 1, K_Fun (Var_Kind, Star_K));
         Id : Real_Class_Id;
      begin
         Id := M.Mint_Class
           ((Name => Table.Intern (Name), Var_Kind => Kind_Id (Var_Kind),
             Supers => Supers, Dict_TyCon => TyCon_Id (Dict_TC),
             others => <>));
         --  Dict con arity is fixed when methods are complete; minted
         --  here with 0 and patched by Finish_Class.
         M.Classes (Id).Dict_Con := DataCon_Id
           (Def_DataCon ("MkDict$" & Name, Dict_TC, 1, 0));
         Env.Classes.Include (M.Info (Id).Name, Id);
         return Id;
      end Def_Class;

      --  Add a method: define the selector global with the constrained
      --  scheme and record it on the class.
      function Def_Method
        (Cl : Real_Class_Id; Name : String; Sch : Real_Scheme_Id;
         Has_Default : Boolean := False) return Real_Var_Id
      is
         Sel : constant Real_Var_Id := Def_Global (Name, Sch);
      begin
         M.Classes (Cl).Methods.Append
           (Method_Info'
              (Name => M.Info (Sel).Name,
               Method_Scheme => Scheme_Id (Sch),
               Selector => Var_Id (Sel), Has_Default => Has_Default));
         return Sel;
      end Def_Method;

      procedure Finish_Class (Cl : Real_Class_Id) is
         Arity : constant Natural :=
           Natural (M.Classes (Cl).Supers.Length)
           + Natural (M.Classes (Cl).Methods.Length);
      begin
         M.DataCons (Real_DataCon_Id (M.Classes (Cl).Dict_Con)).Arity :=
           Arity;
         for I in 1 .. M.Classes (Cl).Supers.Last_Index loop
            declare
               Img : constant String := I'Image;
               Sel : constant Real_Var_Id :=
                 M.Mint_Var
                   ((Name => Table.Intern
                       ("sup$" & Table.Text (M.Info (Cl).Name)
                        & "$" & Img (2 .. Img'Last)),
                     Span => No_Span, Is_Global => True,
                     others => <>));
            begin
               M.Classes (Cl).Super_Sels.Append (Sel);
            end;
         end loop;
      end Finish_Class;

      --  Signature-only instance: an opaque dictionary global.
      procedure Def_Instance
        (Cl : Real_Class_Id; Head : Real_TyCon_Id;
         Context : Constraint_Vectors.Vector :=
           Constraint_Vectors.Empty_Vector;
         Head_Vars : TyVar_Id_Vectors.Vector :=
           TyVar_Id_Vectors.Empty_Vector)
      is
         Dict_Name : constant String :=
           "$d" & Table.Text (M.Info (Cl).Name)
           & Table.Text (M.Info (Head).Name);
         Dict : constant Real_Var_Id :=
           Def_Global (Dict_Name, Mono (TC (Head)));
         --  The dict global's real type is Dict$C (T ...); Phase 2
         --  never inspects it, so a placeholder scheme suffices until
         --  Phase 4 provides bodies.
         Ignore : Real_Instance_Id;
      begin
         Ignore := M.Mint_Instance
           ((Of_Class => Class_Id (Cl), Head => TyCon_Id (Head),
             Head_Vars => Head_Vars, Context => Context,
             Dict_Global => Var_Id (Dict),
             Method_Binds => Bind_Vectors.Empty_Vector,
             Param_Vars => Var_Id_Vectors.Empty_Vector,
             Span => No_Span));
         pragma Unreferenced (Ignore);
      end Def_Instance;

   begin
      ------------------------------------------------------------------
      --  Types
      ------------------------------------------------------------------

      Env.Int_TC      := TyCon_Id (Def_TyCon ("Int", 0, Star_K));
      Env.Integer_TC  := TyCon_Id (Def_TyCon ("Integer", 0, Star_K));
      Env.Float_TC    := TyCon_Id (Def_TyCon ("Float", 0, Star_K));
      Env.Double_TC   := TyCon_Id (Def_TyCon ("Double", 0, Star_K));
      Env.Char_TC     := TyCon_Id (Def_TyCon ("Char", 0, Star_K));
      Env.Rational_TC := TyCon_Id (Def_TyCon ("Rational", 0, Star_K));
      Env.Bool_TC     := TyCon_Id (Def_TyCon ("Bool", 0, Star_K));
      Env.Unit_TC     := TyCon_Id (Def_TyCon ("()", 0, Star_K));
      Env.List_TC     := TyCon_Id (Def_TyCon ("[]", 1, Star1));
      Env.IO_TC       := TyCon_Id (Def_TyCon ("IO", 1, Star1));
      Env.Ordering_TC := TyCon_Id (Def_TyCon ("Ordering", 0, Star_K));
      Env.Maybe_TC    := TyCon_Id (Def_TyCon ("Maybe", 1, Star1));
      Env.Arrow_TC    := TyCon_Id (Def_TyCon ("(->)", 2, Star2));
      --  Ptr/FunPtr are phantom in their argument: the runtime value
      --  is a raw C pointer (AHC_PTR); the parameter only types the
      --  pointee (or the pointed-to function's Haskell type).
      Env.Ptr_TC      := TyCon_Id (Def_TyCon ("Ptr", 1, Star1));
      Env.FunPtr_TC   := TyCon_Id (Def_TyCon ("FunPtr", 1, Star1));

      --  Fixed-width C types: distinct tycons whose runtime nodes
      --  are plain AHC_INT - only the FFI boundary knows the width.
      Env.CFix_TCs (C_I8)  := TyCon_Id (Def_TyCon ("Int8", 0, Star_K));
      Env.CFix_TCs (C_I16) := TyCon_Id (Def_TyCon ("Int16", 0, Star_K));
      Env.CFix_TCs (C_I32) := TyCon_Id (Def_TyCon ("Int32", 0, Star_K));
      Env.CFix_TCs (C_I64) := TyCon_Id (Def_TyCon ("Int64", 0, Star_K));
      Env.CFix_TCs (C_U8)  := TyCon_Id (Def_TyCon ("Word8", 0, Star_K));
      Env.CFix_TCs (C_U16) := TyCon_Id (Def_TyCon ("Word16", 0, Star_K));
      Env.CFix_TCs (C_U32) := TyCon_Id (Def_TyCon ("Word32", 0, Star_K));
      Env.CFix_TCs (C_U64) := TyCon_Id (Def_TyCon ("Word64", 0, Star_K));

      Env.False_DC := DataCon_Id
        (Def_DataCon ("False", Real_TyCon_Id (Env.Bool_TC), 1, 0));
      Env.True_DC := DataCon_Id
        (Def_DataCon ("True", Real_TyCon_Id (Env.Bool_TC), 2, 0));
      Env.Unit_DC := DataCon_Id
        (Def_DataCon ("()", Real_TyCon_Id (Env.Unit_TC), 1, 0));
      Env.Nil_DC := DataCon_Id
        (Def_DataCon ("[]", Real_TyCon_Id (Env.List_TC), 1, 0));
      Env.Cons_DC := DataCon_Id
        (Def_DataCon (":", Real_TyCon_Id (Env.List_TC), 2, 2));
      Env.Nothing_DC := DataCon_Id
        (Def_DataCon ("Nothing", Real_TyCon_Id (Env.Maybe_TC), 1, 0));
      Env.Just_DC := DataCon_Id
        (Def_DataCon ("Just", Real_TyCon_Id (Env.Maybe_TC), 2, 1));

      declare
         Ignore : Real_DataCon_Id;
         Ord_TC : constant Real_TyCon_Id :=
           Real_TyCon_Id (Env.Ordering_TC);
      begin
         Ignore := Def_DataCon ("LT", Ord_TC, 1, 0);
         Ignore := Def_DataCon ("EQ", Ord_TC, 2, 0);
         Ignore := Def_DataCon ("GT", Ord_TC, 3, 0);
         pragma Unreferenced (Ignore);
      end;

      for N in 2 .. Max_Tuple loop
         declare
            Text : String (1 .. N + 1) := [others => ','];
            Kind : Real_Kind_Id := Star_K;
            TC_Id : Real_TyCon_Id;
            Ignore : Real_DataCon_Id;
         begin
            Text (1) := '(';
            Text (Text'Last) := ')';
            for I in 1 .. N loop
               Kind := K_Fun (Star_K, Kind);
            end loop;
            TC_Id := Def_TyCon (Text, N, Kind);
            Env.Tuple_TCs (N) := TyCon_Id (TC_Id);
            Ignore := Def_DataCon (Text, TC_Id, 1, N);
            Env.Tuple_DCs (N) := DataCon_Id (Ignore);
         end;
      end loop;

      --  String = [Char]
      Env.Synonyms.Include
        (Table.Intern ("String"),
         (Arity => 0, Core_Rhs => Type_Id (LST (TC (Env.Char_TC))),
          others => <>));

      --  Foreign.C.Types-style names as synonyms of the fixed-width
      --  types (the widths of the v1 targets: LP64).
      declare
         procedure C_Syn (Name : String; K : C_Fix_Kind) is
         begin
            Env.Synonyms.Include
              (Table.Intern (Name),
               (Arity => 0,
                Core_Rhs => Type_Id (TC (Env.CFix_TCs (K))),
                others => <>));
         end C_Syn;
      begin
         C_Syn ("CChar", C_I8);
         C_Syn ("CInt", C_I32);
         C_Syn ("CUInt", C_U32);
         C_Syn ("CLong", C_I64);
         C_Syn ("CULong", C_U64);
         C_Syn ("CSize", C_U64);
      end;

      --  Constructor schemes for the wired-in data constructors.
      declare
         procedure Set_Con_Scheme
           (DC : Core.DataCon_Id; Sch : Real_Scheme_Id) is
         begin
            M.DataCons (Real_DataCon_Id (DC)).Con_Scheme :=
              Scheme_Id (Sch);
         end Set_Con_Scheme;

         Bool_T : constant Real_Type_Id := TC (Env.Bool_TC);
      begin
         Set_Con_Scheme (Env.True_DC, Mono (Bool_T));
         Set_Con_Scheme (Env.False_DC, Mono (Bool_T));
         Set_Con_Scheme (Env.Unit_DC, Mono (TC (Env.Unit_TC)));
         declare
            A : constant Real_TyVar_Id := New_Tv ("a");
         begin
            Set_Con_Scheme (Env.Nil_DC, Poly1 (A, LST (TV (A))));
         end;
         declare
            A : constant Real_TyVar_Id := New_Tv ("a");
         begin
            Set_Con_Scheme
              (Env.Cons_DC,
               Poly1 (A, FN (TV (A), LST (TV (A)), LST (TV (A)))));
         end;
         declare
            A : constant Real_TyVar_Id := New_Tv ("a");
            Maybe_A : constant Real_Type_Id :=
              AP (TC (Env.Maybe_TC), TV (A));
         begin
            Set_Con_Scheme (Env.Nothing_DC, Poly1 (A, Maybe_A));
         end;
         declare
            A : constant Real_TyVar_Id := New_Tv ("a");
         begin
            Set_Con_Scheme
              (Env.Just_DC,
               Poly1 (A, FN (TV (A), AP (TC (Env.Maybe_TC), TV (A)))));
         end;
         --  Ordering constructors (ids follow Env.Ordering_TC's Cons).
         for DC of M.TyCons (Real_TyCon_Id (Env.Ordering_TC)).Cons loop
            Set_Con_Scheme (Core.DataCon_Id (DC),
                            Mono (TC (Env.Ordering_TC)));
         end loop;
         --  Tuple constructors: forall a1..an. a1 -> .. -> (a1,..,an).
         for N in 2 .. Max_Tuple loop
            declare
               Tvs : TyVar_Id_Vectors.Vector;
               Args : array (1 .. N) of Real_Type_Id;
               Result : Real_Type_Id := TC (Env.Tuple_TCs (N));
               Fn_T : Real_Type_Id;
            begin
               for I in 1 .. N loop
                  declare
                     T_Var : constant Real_TyVar_Id := New_Tv ("a");
                  begin
                     Tvs.Append (T_Var);
                     Args (I) := TV (T_Var);
                  end;
               end loop;
               for I in 1 .. N loop
                  Result := AP (Result, Args (I));
               end loop;
               Fn_T := Result;
               for I in reverse 1 .. N loop
                  Fn_T := FN (Args (I), Fn_T);
               end loop;
               Set_Con_Scheme
                 (Env.Tuple_DCs (N),
                  M.Add (Scheme'(Tvs => Tvs,
                                 Context =>
                                   Constraint_Vectors.Empty_Vector,
                                 S_Body => Type_Id (Fn_T))));
            end;
         end loop;
      end;

      ------------------------------------------------------------------
      --  Classes (Report chapter 9 signatures, abridged where defaults
      --  make methods optional)
      ------------------------------------------------------------------

      declare
         Bool_T : constant Real_Type_Id := TC (Env.Bool_TC);
         Int_T  : constant Real_Type_Id := TC (Env.Int_TC);
         Integer_T : constant Real_Type_Id := TC (Env.Integer_TC);
         Rational_T : constant Real_Type_Id := TC (Env.Rational_TC);
         Ordering_T : constant Real_Type_Id := TC (Env.Ordering_TC);
         Ignore : Real_Var_Id;

         function Sup1 (Cl : Core.Class_Id) return Class_Id_Vectors.Vector
         is
            V : Class_Id_Vectors.Vector;
         begin
            V.Append (Real_Class_Id (Cl));
            return V;
         end Sup1;

         function Sup2 (A, B : Core.Class_Id)
           return Class_Id_Vectors.Vector
         is
            V : Class_Id_Vectors.Vector;
         begin
            V.Append (Real_Class_Id (A));
            V.Append (Real_Class_Id (B));
            return V;
         end Sup2;
      begin
         --  Eq
         declare
            Cl : constant Real_Class_Id := Def_Class ("Eq", Star_K);
            A  : constant Real_TyVar_Id := New_Tv ("a");
            Cmp : constant Real_Type_Id :=
              FN (TV (A), TV (A), Bool_T);
         begin
            Env.Eq_Cl := Class_Id (Cl);
            Ignore := Def_Method
              (Cl, "==", Poly1 (A, Cmp, Ctx1 (Cl, TV (A))), True);
            Ignore := Def_Method
              (Cl, "/=", Poly1 (A, Cmp, Ctx1 (Cl, TV (A))), True);
            Finish_Class (Cl);
         end;

         --  Ord (Eq)
         declare
            Cl : constant Real_Class_Id :=
              Def_Class ("Ord", Star_K, Sup1 (Env.Eq_Cl));
            A  : constant Real_TyVar_Id := New_Tv ("a");
            Cmp2B : constant Real_Type_Id := FN (TV (A), TV (A), Bool_T);
            Cmp2A : constant Real_Type_Id :=
              FN (TV (A), TV (A), TV (A));
         begin
            Env.Ord_Cl := Class_Id (Cl);
            Ignore := Def_Method
              (Cl, "compare",
               Poly1 (A, FN (TV (A), TV (A), Ordering_T),
                      Ctx1 (Cl, TV (A))), True);
            for Op in 1 .. 4 loop
               Ignore := Def_Method
                 (Cl,
                  (case Op is
                     when 1 => "<", when 2 => "<=",
                     when 3 => ">", when others => ">="),
                  Poly1 (A, Cmp2B, Ctx1 (Cl, TV (A))), True);
            end loop;
            Ignore := Def_Method
              (Cl, "max", Poly1 (A, Cmp2A, Ctx1 (Cl, TV (A))), True);
            Ignore := Def_Method
              (Cl, "min", Poly1 (A, Cmp2A, Ctx1 (Cl, TV (A))), True);
            Finish_Class (Cl);
         end;

         --  Show
         declare
            Cl : constant Real_Class_Id := Def_Class ("Show", Star_K);
            A  : constant Real_TyVar_Id := New_Tv ("a");
            String_T : constant Real_Type_Id := LST (TC (Env.Char_TC));
         begin
            Env.Show_Cl := Class_Id (Cl);
            Ignore := Def_Method
              (Cl, "show",
               Poly1 (A, FN (TV (A), String_T), Ctx1 (Cl, TV (A))),
               True);
            Ignore := Def_Method
              (Cl, "showsPrec",
               Poly1 (A, FN (Int_T, TV (A),
                             FN (String_T, String_T)),
                      Ctx1 (Cl, TV (A))), True);
            Ignore := Def_Method
              (Cl, "showList",
               Poly1 (A, FN (LST (TV (A)),
                             FN (String_T, String_T)),
                      Ctx1 (Cl, TV (A))), True);
            Finish_Class (Cl);
         end;

         --  Functor (over f :: * -> *)
         declare
            Cl : constant Real_Class_Id := Def_Class ("Functor", Star1);
            F  : constant Real_TyVar_Id :=
              M.Mint_TyVar ((Name => Table.Intern ("f"),
                             Tv_Kind => Kind_Id (Star1)));
            A  : constant Real_TyVar_Id := New_Tv ("a");
            B  : constant Real_TyVar_Id := New_Tv ("b");
            Tvs : TyVar_Id_Vectors.Vector;
            Sch : Real_Scheme_Id;
         begin
            Env.Functor_Cl := Class_Id (Cl);
            Tvs.Append (F);
            Tvs.Append (A);
            Tvs.Append (B);
            Sch := M.Add
              (Scheme'(Tvs => Tvs,
                       Context => Ctx1 (Cl, TV (F)),
                       S_Body => Type_Id
                         (FN (FN (TV (A), TV (B)),
                              AP (TV (F), TV (A)),
                              AP (TV (F), TV (B))))));
            Ignore := Def_Method (Cl, "fmap", Sch, False);
            Finish_Class (Cl);
         end;

         --  Monad (over m :: * -> *)
         declare
            Cl : constant Real_Class_Id := Def_Class ("Monad", Star1);
            Mv : constant Real_TyVar_Id :=
              M.Mint_TyVar ((Name => Table.Intern ("m"),
                             Tv_Kind => Kind_Id (Star1)));
            A  : constant Real_TyVar_Id := New_Tv ("a");
            B  : constant Real_TyVar_Id := New_Tv ("b");

            function Sch3 (T : Real_Type_Id) return Real_Scheme_Id is
               Tvs : TyVar_Id_Vectors.Vector;
            begin
               Tvs.Append (Mv);
               Tvs.Append (A);
               Tvs.Append (B);
               return M.Add (Scheme'(Tvs => Tvs,
                                     Context => Ctx1 (Cl, TV (Mv)),
                                     S_Body => Type_Id (T)));
            end Sch3;
         begin
            Env.Monad_Cl := Class_Id (Cl);
            Env.Bind_V := Var_Id (Def_Method
              (Cl, ">>=",
               Sch3 (FN (AP (TV (Mv), TV (A)),
                         FN (TV (A), AP (TV (Mv), TV (B))),
                         AP (TV (Mv), TV (B)))), False));
            Env.Then_V := Var_Id (Def_Method
              (Cl, ">>",
               Sch3 (FN (AP (TV (Mv), TV (A)),
                         AP (TV (Mv), TV (B)),
                         AP (TV (Mv), TV (B)))), True));
            Env.Return_V := Var_Id (Def_Method
              (Cl, "return",
               Sch3 (FN (TV (A), AP (TV (Mv), TV (A)))), False));
            Env.Fail_V := Var_Id (Def_Method
              (Cl, "fail",
               Sch3 (FN (LST (TC (Env.Char_TC)),
                         AP (TV (Mv), TV (A)))), True));
            Finish_Class (Cl);
         end;

         --  Num (Eq, Show)
         declare
            Cl : constant Real_Class_Id :=
              Def_Class ("Num", Star_K, Sup2 (Env.Eq_Cl, Env.Show_Cl));
            A  : constant Real_TyVar_Id := New_Tv ("a");
            Bin : constant Real_Type_Id := FN (TV (A), TV (A), TV (A));
            Un  : constant Real_Type_Id := FN (TV (A), TV (A));
         begin
            Env.Num_Cl := Class_Id (Cl);
            for Op in 1 .. 3 loop
               Ignore := Def_Method
                 (Cl,
                  (case Op is
                     when 1 => "+", when 2 => "-", when others => "*"),
                  Poly1 (A, Bin, Ctx1 (Cl, TV (A))), Op = 2);
            end loop;
            Env.Negate_V := Var_Id (Def_Method
              (Cl, "negate", Poly1 (A, Un, Ctx1 (Cl, TV (A))), True));
            Ignore := Def_Method
              (Cl, "abs", Poly1 (A, Un, Ctx1 (Cl, TV (A))), False);
            Ignore := Def_Method
              (Cl, "signum", Poly1 (A, Un, Ctx1 (Cl, TV (A))), False);
            Env.From_Integer_V := Var_Id (Def_Method
              (Cl, "fromInteger",
               Poly1 (A, FN (Integer_T, TV (A)), Ctx1 (Cl, TV (A))),
               False));
            Finish_Class (Cl);
         end;

         --  Real (Num, Ord)
         declare
            Cl : constant Real_Class_Id :=
              Def_Class ("Real", Star_K, Sup2 (Env.Num_Cl, Env.Ord_Cl));
            A  : constant Real_TyVar_Id := New_Tv ("a");
         begin
            Env.Real_Cl := Class_Id (Cl);
            Ignore := Def_Method
              (Cl, "toRational",
               Poly1 (A, FN (TV (A), Rational_T), Ctx1 (Cl, TV (A))),
               False);
            Finish_Class (Cl);
         end;

         --  Fractional (Num)
         declare
            Cl : constant Real_Class_Id :=
              Def_Class ("Fractional", Star_K, Sup1 (Env.Num_Cl));
            A  : constant Real_TyVar_Id := New_Tv ("a");
         begin
            Env.Fractional_Cl := Class_Id (Cl);
            Ignore := Def_Method
              (Cl, "/", Poly1 (A, FN (TV (A), TV (A), TV (A)),
                               Ctx1 (Cl, TV (A))), False);
            Ignore := Def_Method
              (Cl, "recip", Poly1 (A, FN (TV (A), TV (A)),
                                   Ctx1 (Cl, TV (A))), True);
            Env.From_Rational_V := Var_Id (Def_Method
              (Cl, "fromRational",
               Poly1 (A, FN (Rational_T, TV (A)), Ctx1 (Cl, TV (A))),
               False));
            Finish_Class (Cl);
         end;

         --  Integral (Num, Ord) - the Report routes Ord through the
         --  Real superclass; AHC skips Real in the chain but keeps
         --  Ord so (^)'s exponent test and friends typecheck.
         declare
            Cl : constant Real_Class_Id :=
              Def_Class ("Integral", Star_K,
                         Sup2 (Env.Num_Cl, Env.Ord_Cl));
            A   : constant Real_TyVar_Id := New_Tv ("a");
            Bin : constant Real_Type_Id := FN (TV (A), TV (A), TV (A));
         begin
            Env.Integral_Cl := Class_Id (Cl);
            for Op in 1 .. 4 loop
               Ignore := Def_Method
                 (Cl,
                  (case Op is
                     when 1 => "quot", when 2 => "rem",
                     when 3 => "div", when others => "mod"),
                  Poly1 (A, Bin, Ctx1 (Cl, TV (A))), False);
            end loop;
            Ignore := Def_Method
              (Cl, "toInteger",
               Poly1 (A, FN (TV (A), Integer_T), Ctx1 (Cl, TV (A))),
               False);
            Finish_Class (Cl);
         end;

         --  Floating (Fractional)
         declare
            Cl : constant Real_Class_Id :=
              Def_Class ("Floating", Star_K,
                         Sup1 (Env.Fractional_Cl));
            A   : constant Real_TyVar_Id := New_Tv ("a");
            Un  : constant Real_Type_Id := FN (TV (A), TV (A));
            Bin : constant Real_Type_Id := FN (TV (A), TV (A), TV (A));
         begin
            Env.Floating_Cl := Class_Id (Cl);
            Ignore := Def_Method
              (Cl, "pi", Poly1 (A, TV (A), Ctx1 (Cl, TV (A))), False);
            for Op in 1 .. 3 loop
               Ignore := Def_Method
                 (Cl,
                  (case Op is
                     when 1 => "exp", when 2 => "log",
                     when others => "sqrt"),
                  Poly1 (A, Un, Ctx1 (Cl, TV (A))), False);
            end loop;
            Ignore := Def_Method
              (Cl, "**", Poly1 (A, Bin, Ctx1 (Cl, TV (A))), False);
            Ignore := Def_Method
              (Cl, "logBase",
               Poly1 (A, Bin, Ctx1 (Cl, TV (A))), False);
            for Op in 1 .. 9 loop
               Ignore := Def_Method
                 (Cl,
                  (case Op is
                     when 1 => "sin",  when 2 => "cos",
                     when 3 => "tan",  when 4 => "asin",
                     when 5 => "acos", when 6 => "atan",
                     when 7 => "sinh", when 8 => "cosh",
                     when others => "tanh"),
                  Poly1 (A, Un, Ctx1 (Cl, TV (A))), False);
            end loop;
            Finish_Class (Cl);
         end;

         --  RealFrac (Fractional) - results land at Integer (the
         --  Report's Integral-b polymorphic results default there
         --  anyway, so oracle outputs agree).
         declare
            Cl : constant Real_Class_Id :=
              Def_Class ("RealFrac", Star_K,
                         Sup1 (Env.Fractional_Cl));
            A  : constant Real_TyVar_Id := New_Tv ("a");
            AI : constant Real_Type_Id := FN (TV (A), Integer_T);
         begin
            Env.RealFrac_Cl := Class_Id (Cl);
            for Op in 1 .. 4 loop
               Ignore := Def_Method
                 (Cl,
                  (case Op is
                     when 1 => "truncate", when 2 => "round",
                     when 3 => "ceiling", when others => "floor"),
                  Poly1 (A, AI, Ctx1 (Cl, TV (A))), False);
            end loop;
            Ignore := Def_Method
              (Cl, "properFraction",
               Poly1 (A, FN (TV (A),
                             AP (AP (TC (Env.Tuple_TCs (2)),
                                     Integer_T), TV (A))),
                      Ctx1 (Cl, TV (A))), False);
            Finish_Class (Cl);
         end;

         --  RealFloat (RealFrac, Floating): the useful IEEE subset.
         declare
            Cl : constant Real_Class_Id :=
              Def_Class ("RealFloat", Star_K,
                         Sup2 (Env.RealFrac_Cl, Env.Floating_Cl));
            A  : constant Real_TyVar_Id := New_Tv ("a");
            AB : constant Real_Type_Id :=
              FN (TV (A), TC (Env.Bool_TC));
         begin
            Env.RealFloat_Cl := Class_Id (Cl);
            for Op in 1 .. 3 loop
               Ignore := Def_Method
                 (Cl,
                  (case Op is
                     when 1 => "isNaN", when 2 => "isInfinite",
                     when others => "isNegativeZero"),
                  Poly1 (A, AB, Ctx1 (Cl, TV (A))), False);
            end loop;
            Ignore := Def_Method
              (Cl, "atan2",
               Poly1 (A, FN (TV (A), TV (A), TV (A)),
                      Ctx1 (Cl, TV (A))), False);
            Finish_Class (Cl);
         end;

         --  Enum
         declare
            Cl : constant Real_Class_Id := Def_Class ("Enum", Star_K);
            A  : constant Real_TyVar_Id := New_Tv ("a");
            LA : constant Real_Type_Id := LST (TV (A));
         begin
            Env.Enum_Cl := Class_Id (Cl);
            Ignore := Def_Method
              (Cl, "succ", Poly1 (A, FN (TV (A), TV (A)),
                                  Ctx1 (Cl, TV (A))), True);
            Ignore := Def_Method
              (Cl, "pred", Poly1 (A, FN (TV (A), TV (A)),
                                  Ctx1 (Cl, TV (A))), True);
            Ignore := Def_Method
              (Cl, "toEnum", Poly1 (A, FN (Int_T, TV (A)),
                                    Ctx1 (Cl, TV (A))), False);
            Ignore := Def_Method
              (Cl, "fromEnum", Poly1 (A, FN (TV (A), Int_T),
                                      Ctx1 (Cl, TV (A))), False);
            Env.Enum_From_V := Var_Id (Def_Method
              (Cl, "enumFrom", Poly1 (A, FN (TV (A), LA),
                                      Ctx1 (Cl, TV (A))), True));
            Env.Enum_From_Then_V := Var_Id (Def_Method
              (Cl, "enumFromThen",
               Poly1 (A, FN (TV (A), TV (A), LA), Ctx1 (Cl, TV (A))),
               True));
            Env.Enum_From_To_V := Var_Id (Def_Method
              (Cl, "enumFromTo",
               Poly1 (A, FN (TV (A), TV (A), LA), Ctx1 (Cl, TV (A))),
               True));
            Env.Enum_From_Then_To_V := Var_Id (Def_Method
              (Cl, "enumFromThenTo",
               Poly1 (A, FN (TV (A), FN (TV (A), TV (A), LA)),
                      Ctx1 (Cl, TV (A))),
               True));
            Finish_Class (Cl);
         end;

         --  Bounded
         declare
            Cl : constant Real_Class_Id := Def_Class ("Bounded", Star_K);
            A  : constant Real_TyVar_Id := New_Tv ("a");
         begin
            Env.Bounded_Cl := Class_Id (Cl);
            Ignore := Def_Method
              (Cl, "minBound", Poly1 (A, TV (A), Ctx1 (Cl, TV (A))),
               False);
            Ignore := Def_Method
              (Cl, "maxBound", Poly1 (A, TV (A), Ctx1 (Cl, TV (A))),
               False);
            Finish_Class (Cl);
         end;

         pragma Unreferenced (Ignore);
      end;

      ------------------------------------------------------------------
      --  Instances (signature-only, opaque dictionaries)
      ------------------------------------------------------------------

      declare
         function Cl (Id : Core.Class_Id) return Real_Class_Id
         is (Real_Class_Id (Id));
         function TCn (Id : Core.TyCon_Id) return Real_TyCon_Id
         is (Real_TyCon_Id (Id));

         Ground : constant array (1 .. 5) of Core.TyCon_Id :=
           [Env.Int_TC, Env.Integer_TC, Env.Char_TC, Env.Bool_TC,
            Env.Unit_TC];
         Numeric : constant array (1 .. 4) of Core.TyCon_Id :=
           [Env.Int_TC, Env.Integer_TC, Env.Float_TC, Env.Double_TC];

         --  C a => C (T a): one fresh head tyvar carrying the context.
         procedure Def_Ctx1_Instance
           (Class : Core.Class_Id; Head : Core.TyCon_Id)
         is
            A : constant Real_TyVar_Id := New_Tv ("a");
            Vars : TyVar_Id_Vectors.Vector;
         begin
            Vars.Append (A);
            Def_Instance (Cl (Class), TCn (Head),
                          Ctx1 (Cl (Class), TV (A)), Vars);
         end Def_Ctx1_Instance;
      begin
         for T of Ground loop
            Def_Instance (Cl (Env.Eq_Cl), TCn (T));
            Def_Instance (Cl (Env.Ord_Cl), TCn (T));
            Def_Instance (Cl (Env.Show_Cl), TCn (T));
            Def_Instance (Cl (Env.Enum_Cl), TCn (T));
            Def_Instance (Cl (Env.Bounded_Cl), TCn (T));
         end loop;
         Def_Instance (Cl (Env.Eq_Cl), TCn (Env.Float_TC));
         Def_Instance (Cl (Env.Ord_Cl), TCn (Env.Float_TC));
         Def_Instance (Cl (Env.Show_Cl), TCn (Env.Float_TC));
         Def_Instance (Cl (Env.Eq_Cl), TCn (Env.Double_TC));
         Def_Instance (Cl (Env.Ord_Cl), TCn (Env.Double_TC));
         Def_Instance (Cl (Env.Show_Cl), TCn (Env.Double_TC));
         Def_Instance (Cl (Env.Show_Cl), TCn (Env.Ordering_TC));
         Def_Instance (Cl (Env.Eq_Cl), TCn (Env.Ordering_TC));

         --  Eq/Ord (Ptr a) / (FunPtr a): address comparison, so no
         --  context on a.
         for TC_I in 1 .. 2 loop
            declare
               T : constant Core.TyCon_Id :=
                 (if TC_I = 1 then Env.Ptr_TC else Env.FunPtr_TC);
               A1 : constant Real_TyVar_Id := New_Tv ("a");
               A2 : constant Real_TyVar_Id := New_Tv ("a");
               V1, V2 : TyVar_Id_Vectors.Vector;
            begin
               V1.Append (A1);
               V2.Append (A2);
               Def_Instance (Cl (Env.Eq_Cl), TCn (T),
                             Head_Vars => V1);
               Def_Instance (Cl (Env.Ord_Cl), TCn (T),
                             Head_Vars => V2);
            end;
         end loop;

         for T of Numeric loop
            Def_Instance (Cl (Env.Num_Cl), TCn (T));
            Def_Instance (Cl (Env.Real_Cl), TCn (T));
         end loop;
         Def_Instance (Cl (Env.Fractional_Cl), TCn (Env.Float_TC));
         Def_Instance (Cl (Env.Fractional_Cl), TCn (Env.Double_TC));
         Def_Instance (Cl (Env.Enum_Cl), TCn (Env.Float_TC));
         Def_Instance (Cl (Env.Enum_Cl), TCn (Env.Double_TC));
         Def_Instance (Cl (Env.Integral_Cl), TCn (Env.Int_TC));
         Def_Instance (Cl (Env.Integral_Cl), TCn (Env.Integer_TC));

         --  Fixed-width C types share Int's runtime representation,
         --  so their dictionaries reuse Int's prims wholesale
         --  (arithmetic is exact/promoting, not wrapping - only the
         --  FFI boundary enforces the width).
         for K in C_Fix_Kind loop
            Def_Instance (Cl (Env.Eq_Cl), TCn (Env.CFix_TCs (K)));
            Def_Instance (Cl (Env.Ord_Cl), TCn (Env.CFix_TCs (K)));
            Def_Instance (Cl (Env.Show_Cl), TCn (Env.CFix_TCs (K)));
            Def_Instance (Cl (Env.Num_Cl), TCn (Env.CFix_TCs (K)));
            Def_Instance (Cl (Env.Integral_Cl),
                          TCn (Env.CFix_TCs (K)));
         end loop;
         Def_Instance (Cl (Env.Floating_Cl), TCn (Env.Float_TC));
         Def_Instance (Cl (Env.Floating_Cl), TCn (Env.Double_TC));
         Def_Instance (Cl (Env.RealFrac_Cl), TCn (Env.Float_TC));
         Def_Instance (Cl (Env.RealFrac_Cl), TCn (Env.Double_TC));
         Def_Instance (Cl (Env.RealFloat_Cl), TCn (Env.Float_TC));
         Def_Instance (Cl (Env.RealFloat_Cl), TCn (Env.Double_TC));

         --  Eq a => Eq [a], etc.
         Def_Ctx1_Instance (Env.Eq_Cl, Env.List_TC);
         Def_Ctx1_Instance (Env.Ord_Cl, Env.List_TC);
         Def_Ctx1_Instance (Env.Show_Cl, Env.List_TC);

         --  Pair instances with two-constraint contexts.
         declare
            procedure Def_Pair_Instance (Class : Core.Class_Id) is
               A : constant Real_TyVar_Id := New_Tv ("a");
               B : constant Real_TyVar_Id := New_Tv ("b");
               C : Constraint_Vectors.Vector;
               Vars : TyVar_Id_Vectors.Vector;
            begin
               C.Append (Constraint'(Class => Cl (Class), Arg => TV (A),
                                     Span => No_Span));
               C.Append (Constraint'(Class => Cl (Class), Arg => TV (B),
                                     Span => No_Span));
               Vars.Append (A);
               Vars.Append (B);
               Def_Instance (Cl (Class), TCn (Env.Tuple_TCs (2)),
                             C, Vars);
            end Def_Pair_Instance;
         begin
            Def_Pair_Instance (Env.Eq_Cl);
            Def_Pair_Instance (Env.Ord_Cl);
            --  Show for pairs is defined in prelude/Prelude.hs.
         end;

         Def_Instance (Cl (Env.Functor_Cl), TCn (Env.List_TC));
         Def_Instance (Cl (Env.Monad_Cl), TCn (Env.List_TC));
         Def_Instance (Cl (Env.Functor_Cl), TCn (Env.IO_TC));
         Def_Instance (Cl (Env.Monad_Cl), TCn (Env.IO_TC));
         Def_Instance (Cl (Env.Functor_Cl), TCn (Env.Maybe_TC));
         Def_Instance (Cl (Env.Monad_Cl), TCn (Env.Maybe_TC));
         Def_Ctx1_Instance (Env.Eq_Cl, Env.Maybe_TC);
         Def_Ctx1_Instance (Env.Ord_Cl, Env.Maybe_TC);
         --  Show for Maybe is defined in prelude/Prelude.hs.
      end;

      ------------------------------------------------------------------
      --  Plain globals
      ------------------------------------------------------------------

      declare
         Bool_T : constant Real_Type_Id := TC (Env.Bool_TC);
         String_T : constant Real_Type_Id := LST (TC (Env.Char_TC));
         Unit_T : constant Real_Type_Id := TC (Env.Unit_TC);
         Ignore : Real_Var_Id;
      begin
         declare
            A : constant Real_TyVar_Id := New_Tv ("a");
            B : constant Real_TyVar_Id := New_Tv ("b");
         begin
            Env.Map_V := Var_Id (Def_Global
              ("map", Poly2 (A, B,
                             FN (FN (TV (A), TV (B)),
                                 LST (TV (A)), LST (TV (B))))));
            Env.Concat_Map_V := Var_Id (Def_Global
              ("concatMap",
               Poly2 (A, B, FN (FN (TV (A), LST (TV (B))),
                                LST (TV (A)), LST (TV (B))))));
            Ignore := Def_Global
              ("seq", Poly2 (A, B, FN (TV (A), TV (B), TV (B))));
            Ignore := Def_Global
              ("$!", Poly2 (A, B, FN (FN (TV (A), TV (B)),
                                      TV (A), TV (B))));
            Ignore := Def_Global
              ("foldr", Poly2 (A, B,
                               FN (FN (TV (A), FN (TV (B), TV (B))),
                                   TV (B), FN (LST (TV (A)), TV (B)))));
            Ignore := Def_Global
              ("const", Poly2 (A, B, FN (TV (A), TV (B), TV (A))));
            Ignore := Def_Global
              ("fst", Poly2 (A, B,
                             FN (AP (AP (TC (Env.Tuple_TCs (2)), TV (A)),
                                     TV (B)), TV (A))));
            Ignore := Def_Global
              ("snd", Poly2 (A, B,
                             FN (AP (AP (TC (Env.Tuple_TCs (2)), TV (A)),
                                     TV (B)), TV (B))));
         end;

         declare
            A : constant Real_TyVar_Id := New_Tv ("a");
         begin
            Env.Filter_V := Var_Id (Def_Global
              ("filter", Poly1 (A, FN (FN (TV (A), Bool_T),
                                       LST (TV (A)), LST (TV (A))))));
            Env.Append_V := Var_Id (Def_Global
              ("++", Poly1 (A, FN (LST (TV (A)), LST (TV (A)),
                                   LST (TV (A))))));
            Ignore := Def_Global
              ("concat", Poly1 (A, FN (LST (LST (TV (A))),
                                       LST (TV (A)))));
            Env.Error_V := Var_Id (Def_Global
              ("error", Poly1 (A, FN (String_T, TV (A)))));
            Ignore := Def_Global ("undefined", Poly1 (A, TV (A)));
            Ignore := Def_Global
              ("id", Poly1 (A, FN (TV (A), TV (A))));
            Ignore := Def_Global
              ("print",
               Poly1 (A, FN (TV (A), IO_T (Unit_T)),
                      Ctx1 (Real_Class_Id (Env.Show_Cl), TV (A))));
            Ignore := Def_Global
              ("subtract",
               Poly1 (A, FN (TV (A), TV (A), TV (A)),
                      Ctx1 (Real_Class_Id (Env.Num_Cl), TV (A))));
            --  quot/rem/div/mod are real Integral methods now.
            Ignore := Def_Global
              ("length", Poly1 (A, FN (LST (TV (A)), TC (Env.Int_TC))));
         end;

         declare
            A : constant Real_TyVar_Id := New_Tv ("a");
            B : constant Real_TyVar_Id := New_Tv ("b");
            C : constant Real_TyVar_Id := New_Tv ("c");
            Tvs : TyVar_Id_Vectors.Vector;
         begin
            Tvs.Append (A);
            Tvs.Append (B);
            Tvs.Append (C);
            Ignore := Def_Global
              (".", M.Add (Scheme'
                 (Tvs => Tvs,
                  Context => Constraint_Vectors.Empty_Vector,
                  S_Body => Type_Id
                    (FN (FN (TV (B), TV (C)), FN (TV (A), TV (B)),
                         FN (TV (A), TV (C)))))));
            declare
               Tvs2 : TyVar_Id_Vectors.Vector;
               Tvs3 : TyVar_Id_Vectors.Vector;
            begin
               Tvs2.Append (A);
               Tvs2.Append (B);
               Ignore := Def_Global
                 ("$", M.Add (Scheme'
                    (Tvs => Tvs2,
                     Context => Constraint_Vectors.Empty_Vector,
                     S_Body => Type_Id
                       (FN (FN (TV (A), TV (B)), TV (A), TV (B))))));
               Tvs3.Append (A);
               Tvs3.Append (B);
               Tvs3.Append (C);
               Ignore := Def_Global
                 ("flip", M.Add (Scheme'
                    (Tvs => Tvs3,
                     Context => Constraint_Vectors.Empty_Vector,
                     S_Body => Type_Id
                       (FN (FN (TV (A), TV (B), TV (C)),
                            FN (TV (B), TV (A), TV (C)))))));
            end;
         end;

         Env.Otherwise_V := Var_Id (Def_Global
           ("otherwise", Mono (Bool_T)));
         Ignore := Def_Global ("not", Mono (FN (Bool_T, Bool_T)));
         Ignore := Def_Global
           ("&&", Mono (FN (Bool_T, Bool_T, Bool_T)));
         Ignore := Def_Global
           ("||", Mono (FN (Bool_T, Bool_T, Bool_T)));
         Ignore := Def_Global
           ("putStr", Mono (FN (String_T, IO_T (Unit_T))));
         Ignore := Def_Global
           ("putStrLn", Mono (FN (String_T, IO_T (Unit_T))));

         --  The whole numeric vocabulary is class methods now
         --  (atan2 lives in RealFloat); fromIntegral is Prelude
         --  source (fromInteger . toInteger).
         declare
            String_T2 : constant Real_Type_Id :=
              LST (TC (Env.Char_TC));
         begin
            Ignore := Def_Global
              ("ord", Mono (FN (TC (Env.Char_TC), TC (Env.Int_TC))));
            Ignore := Def_Global
              ("chr", Mono (FN (TC (Env.Int_TC), TC (Env.Char_TC))));
            Ignore := Def_Global
              ("getLine", Mono (IO_T (String_T2)));
            Ignore := Def_Global
              ("isEOF", Mono (IO_T (TC (Env.Bool_TC))));
            Ignore := Def_Global
              ("getContents", Mono (IO_T (String_T2)));
            Ignore := Def_Global
              ("readFile",
               Mono (FN (String_T2, IO_T (String_T2))));
            Ignore := Def_Global
              ("primHOpen",
               Mono (FN (String_T2, TC (Env.Int_TC),
                         IO_T (TC (Env.Int_TC)))));
            Ignore := Def_Global
              ("primHClose",
               Mono (FN (TC (Env.Int_TC), IO_T (TC (Env.Unit_TC)))));
            Ignore := Def_Global
              ("primHPutStr",
               Mono (FN (TC (Env.Int_TC), String_T2,
                         IO_T (TC (Env.Unit_TC)))));
            Ignore := Def_Global
              ("primHGetLine",
               Mono (FN (TC (Env.Int_TC), IO_T (String_T2))));
            Ignore := Def_Global
              ("primHGetChar",
               Mono (FN (TC (Env.Int_TC), IO_T (TC (Env.Char_TC)))));
            Ignore := Def_Global
              ("primHGetContents",
               Mono (FN (TC (Env.Int_TC), IO_T (String_T2))));
            Ignore := Def_Global
              ("primHIsEOF",
               Mono (FN (TC (Env.Int_TC), IO_T (TC (Env.Bool_TC)))));
            Ignore := Def_Global
              ("primHFlush",
               Mono (FN (TC (Env.Int_TC), IO_T (TC (Env.Unit_TC)))));
            Ignore := Def_Global
              ("getArgs", Mono (IO_T (LST (String_T2))));
            Ignore := Def_Global
              ("getProgName", Mono (IO_T (String_T2)));
            declare
               A2 : constant Real_TyVar_Id := New_Tv ("a");
               I_T : constant Real_Type_Id := TC (Env.Int_TC);
               III : constant Real_Type_Id := FN (I_T, I_T, I_T);
               II  : constant Real_Type_Id := FN (I_T, I_T);
            begin
               Ignore := Def_Global
                 ("exitWithCode",
                  Poly1 (A2, FN (TC (Env.Int_TC),
                                 IO_T (TV (A2)))));
               Ignore := Def_Global ("primAndI", Mono (III));
               Ignore := Def_Global ("primOrI", Mono (III));
               Ignore := Def_Global ("primXorI", Mono (III));
               Ignore := Def_Global ("primShiftLI", Mono (III));
               Ignore := Def_Global ("primShiftRI", Mono (III));
               Ignore := Def_Global ("primComplementI", Mono (II));
               Ignore := Def_Global ("primPopCountI", Mono (II));
            end;
            declare
               A3 : constant Real_TyVar_Id := New_Tv ("a");
               A4 : constant Real_TyVar_Id := New_Tv ("a");
               A5 : constant Real_TyVar_Id := New_Tv ("a");
            begin
               Ignore := Def_Global
                 ("nullPtr", Poly1 (A3, AP (TC (Env.Ptr_TC), TV (A3))));
               Ignore := Def_Global
                 ("nullFunPtr",
                  Poly1 (A4, AP (TC (Env.FunPtr_TC), TV (A4))));
               Ignore := Def_Global
                 ("freeHaskellFunPtr",
                  Poly1 (A5, FN (AP (TC (Env.FunPtr_TC), TV (A5)),
                                 IO_T (TC (Env.Unit_TC)))));
            end;
            Ignore := Def_Global
              ("peekCString",
               Mono (FN (AP (TC (Env.Ptr_TC), TC (Env.Char_TC)),
                         IO_T (String_T2))));

            --  Foreign.Marshal surface: raw memory, byte offsets.
            declare
               function Fix_Nm (K : C_Fix_Kind) return String
               is (case K is
                     when C_I8 => "Int8",   when C_I16 => "Int16",
                     when C_I32 => "Int32", when C_I64 => "Int64",
                     when C_U8 => "Word8",  when C_U16 => "Word16",
                     when C_U32 => "Word32",
                     when C_U64 => "Word64");

               I_T : constant Real_Type_Id := TC (Env.Int_TC);
               U_T : constant Real_Type_Id := TC (Env.Unit_TC);
               D_T : constant Real_Type_Id := TC (Env.Double_TC);

               function Ptr_Of (V : Real_TyVar_Id)
                  return Real_Type_Id
               is (AP (TC (Env.Ptr_TC), TV (V)));
            begin
               declare
                  A : constant Real_TyVar_Id := New_Tv ("a");
               begin
                  Ignore := Def_Global
                    ("mallocBytes",
                     Poly1 (A, FN (I_T, IO_T (Ptr_Of (A)))));
               end;
               declare
                  A : constant Real_TyVar_Id := New_Tv ("a");
               begin
                  Ignore := Def_Global
                    ("free",
                     Poly1 (A, FN (Ptr_Of (A), IO_T (U_T))));
               end;
               declare
                  A : constant Real_TyVar_Id := New_Tv ("a");
                  B : constant Real_TyVar_Id := New_Tv ("b");
               begin
                  Ignore := Def_Global
                    ("plusPtr",
                     Poly2 (A, B,
                            FN (Ptr_Of (A), I_T, Ptr_Of (B))));
               end;
               declare
                  A : constant Real_TyVar_Id := New_Tv ("a");
                  B : constant Real_TyVar_Id := New_Tv ("b");
               begin
                  Ignore := Def_Global
                    ("castPtr",
                     Poly2 (A, B, FN (Ptr_Of (A), Ptr_Of (B))));
               end;
               for K in C_Fix_Kind loop
                  declare
                     A : constant Real_TyVar_Id := New_Tv ("a");
                     B : constant Real_TyVar_Id := New_Tv ("a");
                     T : constant Real_Type_Id :=
                       TC (Env.CFix_TCs (K));
                  begin
                     Ignore := Def_Global
                       ("peek" & Fix_Nm (K),
                        Poly1 (A, FN (Ptr_Of (A), I_T, IO_T (T))));
                     Ignore := Def_Global
                       ("poke" & Fix_Nm (K),
                        Poly1 (B, FN (Ptr_Of (B), I_T,
                                      FN (T, IO_T (U_T)))));
                  end;
               end loop;
               declare
                  A : constant Real_TyVar_Id := New_Tv ("a");
                  B : constant Real_TyVar_Id := New_Tv ("a");
               begin
                  Ignore := Def_Global
                    ("peekDouble",
                     Poly1 (A, FN (Ptr_Of (A), I_T, IO_T (D_T))));
                  Ignore := Def_Global
                    ("pokeDouble",
                     Poly1 (B, FN (Ptr_Of (B), I_T,
                                   FN (D_T, IO_T (U_T)))));
               end;
               declare
                  A : constant Real_TyVar_Id := New_Tv ("a");
                  B : constant Real_TyVar_Id := New_Tv ("b");
                  C2 : constant Real_TyVar_Id := New_Tv ("a");
                  D2 : constant Real_TyVar_Id := New_Tv ("b");
               begin
                  Ignore := Def_Global
                    ("peekPtr",
                     Poly2 (A, B, FN (Ptr_Of (A), I_T,
                                      IO_T (Ptr_Of (B)))));
                  Ignore := Def_Global
                    ("pokePtr",
                     Poly2 (C2, D2,
                            FN (Ptr_Of (C2), I_T,
                                FN (Ptr_Of (D2), IO_T (U_T)))));
               end;
               Ignore := Def_Global
                 ("newCString",
                  Mono (FN (String_T2,
                            IO_T (AP (TC (Env.Ptr_TC),
                                      TC (Env.Char_TC))))));
               Ignore := Def_Global
                 ("peekCStringLen",
                  Mono (FN (AP (TC (Env.Ptr_TC), TC (Env.Char_TC)),
                            I_T, IO_T (String_T2))));
            end;
         end;
         pragma Unreferenced (Ignore);
      end;
   end Install;

end AHC.Builtins;
