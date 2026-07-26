package body AHC.Kinds is

   use AHC.Syntax;
   use type Core.TyCon_Id;
   use type Core.Class_Id;
   use type Core.Kind_Id;
   use type Core.Type_Id;
   use type Core.Scheme_Id;
   use type Core.Kind_Kind;
   use type Core.Type_Kind;
   use type Core.Refinement_Id;
   use type Names.Name_Id;

   Max_Synonym_Depth : constant := 20;

   procedure Check_Module
     (Arena : Syntax.Module_Arena;
      Res   : Rename.Resolutions;
      Table : in out Names.Name_Table;
      Bag   : in out Diagnostics.Diagnostic_Bag;
      M     : in out Core.Core_Module;
      Env   : in out Builtins.Global_Env;
      Sigs  : in out Sig_Maps.Map;
      Annos : in out Anno_Maps.Map;
      Preds : in out Pred_Vectors.Vector)
   is
      Star_K : constant Core.Real_Kind_Id := M.Star;

      ------------------------------------------------------------------
      --  Kind metas (pass-local union-find cells)
      ------------------------------------------------------------------

      type KCell is record
         Bound : Boolean := False;
         To    : Core.Kind_Id := Core.No_Kind;
      end record;

      package KCell_Vectors is new Ada.Containers.Vectors
        (Positive, KCell);

      Cells : KCell_Vectors.Vector;

      function Fresh_KMeta return Core.Real_Kind_Id is
      begin
         Cells.Append (KCell'(others => <>));
         return M.Add (Core.Kind_Node'(Kind => Core.KMeta_K,
                                       KMeta => Cells.Last_Index));
      end Fresh_KMeta;

      --  Follow meta bindings at the head.
      function KZonk (K : Core.Real_Kind_Id) return Core.Real_Kind_Id is
         N : constant Core.Kind_Node := M.Node (K);
      begin
         if N.Kind = Core.KMeta_K and then Cells (N.KMeta).Bound then
            return KZonk (Core.Real_Kind_Id (Cells (N.KMeta).To));
         end if;
         return K;
      end KZonk;

      procedure KUnify
        (A, B : Core.Real_Kind_Id; Span : Diagnostics.Source_Span)
      is
         ZA : constant Core.Real_Kind_Id := KZonk (A);
         ZB : constant Core.Real_Kind_Id := KZonk (B);
         NA : constant Core.Kind_Node := M.Node (ZA);
         NB : constant Core.Kind_Node := M.Node (ZB);
      begin
         if ZA = ZB then
            return;
         end if;
         if NA.Kind = Core.KMeta_K then
            Cells (NA.KMeta) := (True, Core.Kind_Id (ZB));
         elsif NB.Kind = Core.KMeta_K then
            Cells (NB.KMeta) := (True, Core.Kind_Id (ZA));
         elsif NA.Kind = Core.Star_K and then NB.Kind = Core.Star_K then
            null;
         elsif NA.Kind = Core.KFun_K and then NB.Kind = Core.KFun_K then
            KUnify (NA.KFrom, NB.KFrom, Span);
            KUnify (NA.KTo, NB.KTo, Span);
         else
            Bag.Add (Diagnostics.Error, Diagnostics.Kind_Error, Span,
                     "kind mismatch");
         end if;
      end KUnify;

      --  Report 4.6: residual kind metas default to *.
      function Final_Kind (K : Core.Real_Kind_Id) return Core.Real_Kind_Id
      is
         Z : constant Core.Real_Kind_Id := KZonk (K);
         N : constant Core.Kind_Node := M.Node (Z);
      begin
         case N.Kind is
            when Core.Star_K =>
               return Z;
            when Core.KMeta_K =>
               return Star_K;
            when Core.KFun_K =>
               return M.Add
                 (Core.Kind_Node'(Kind => Core.KFun_K,
                                  KFrom => Final_Kind (N.KFrom),
                                  KTo => Final_Kind (N.KTo)));
         end case;
      end Final_Kind;

      ------------------------------------------------------------------
      --  Type-variable environments for conversion
      ------------------------------------------------------------------

      type Tv_Entry is record
         Ty      : Core.Type_Id := Core.No_Type;
         Tv_Kind : Core.Kind_Id := Core.No_Kind;
      end record;

      package Tv_Maps is new Ada.Containers.Hashed_Maps
        (Names.Name_Id, Tv_Entry, Builtins.Name_Hash, "=");

      --  Order of first occurrence (for scheme tyvar lists and
      --  instance Head_Vars).
      package TyVar_Vectors renames Core.TyVar_Id_Vectors;

      ------------------------------------------------------------------
      --  Surface -> Core type conversion with kind checking
      ------------------------------------------------------------------

      function Kind_Of_TyCon (TC : Core.Real_TyCon_Id)
        return Core.Real_Kind_Id
      is (Core.Real_Kind_Id (M.Info (TC).TC_Kind));

      --  Value of an integer literal lexeme (dec/hex/oct), signed.
      function Bound_Value
        (Text : Names.Name_Id; Neg : Boolean) return Long_Long_Integer
      is
         S     : constant String := Table.Text (Names.Real_Name_Id (Text));
         V     : Long_Long_Integer := 0;
         Base  : Long_Long_Integer := 10;
         First : Positive := S'First;
      begin
         if S'Length > 2 and then S (S'First) = '0'
           and then S (S'First + 1) in 'x' | 'X'
         then
            Base := 16;
            First := S'First + 2;
         elsif S'Length > 2 and then S (S'First) = '0'
           and then S (S'First + 1) in 'o' | 'O'
         then
            Base := 8;
            First := S'First + 2;
         end if;
         for I in First .. S'Last loop
            declare
               C : constant Character := S (I);
               D : constant Long_Long_Integer :=
                 (if C in '0' .. '9' then Character'Pos (C) - 48
                  elsif C in 'a' .. 'f' then Character'Pos (C) - 87
                  else Character'Pos (C) - 55);
            begin
               V := V * Base + D;
            end;
         end loop;
         return (if Neg then -V else V);
      end Bound_Value;

      --  A lexeme is a float if it has a point or exponent (hex/octal
      --  integer prefixes checked first: 0xE is an integer).
      function Is_Float_Lexeme (Text : Names.Name_Id) return Boolean is
         S : constant String := Table.Text (Names.Real_Name_Id (Text));
      begin
         if S'Length > 2 and then S (S'First) = '0'
           and then S (S'First + 1) in 'x' | 'X' | 'o' | 'O'
         then
            return False;
         end if;
         return (for some C of S => C in '.' | 'e' | 'E');
      end Is_Float_Lexeme;

      --  Numeric value of a bound lexeme for Double ranges.
      function F_Value
        (Text : Names.Name_Id; Neg : Boolean) return Long_Float
      is
         V : constant Long_Float :=
           (if Is_Float_Lexeme (Text)
            then Long_Float'Value
                   (Table.Text (Names.Real_Name_Id (Text)))
            else Long_Float (Bound_Value (Text, False)));
      begin
         return (if Neg then -V else V);
      end F_Value;

      procedure Convert
        (T          : Real_Type_Id;
         TvEnv      : in out Tv_Maps.Map;
         Order      : in out TyVar_Vectors.Vector;
         Implicit   : Boolean;
         Depth      : Natural;
         Result     : out Core.Type_Id;
         Kind       : out Core.Kind_Id);

      --  Substitute Args for Vars in a cached synonym rhs, copying
      --  the spine; untouched subtrees are shared (Core types are
      --  immutable, unlike Core expressions, so sharing is safe).
      function Subst_Syn
        (T    : Core.Type_Id;
         Vars : Core.TyVar_Id_Vectors.Vector;
         Args : Core.Type_Id_Vectors.Vector) return Core.Type_Id
      is
      begin
         if Core."=" (T, Core.No_Type) then
            return T;
         end if;
         declare
            N : constant Core.Type_Node := M.Node (T);
         begin
            case N.Kind is
               when Core.TVar_T =>
                  for I in 1 .. Vars.Last_Index loop
                     if Core."=" (Vars (I), N.Tv) then
                        return Args (I);
                     end if;
                  end loop;
                  return T;
               when Core.TMeta_T | Core.TCon_T =>
                  return T;
               when Core.TApp_T =>
                  return Core.Type_Id
                    (M.Add (Core.Type_Node'
                       (Kind => Core.TApp_T,
                        T_Fun => Core.Real_Type_Id
                          (Subst_Syn (Core.Type_Id (N.T_Fun),
                                      Vars, Args)),
                        T_Arg => Core.Real_Type_Id
                          (Subst_Syn (Core.Type_Id (N.T_Arg),
                                      Vars, Args)))));
               when Core.TFun_T =>
                  return Core.Type_Id
                    (M.Add (Core.Type_Node'
                       (Kind => Core.TFun_T,
                        From => Core.Real_Type_Id
                          (Subst_Syn (Core.Type_Id (N.From),
                                      Vars, Args)),
                        To => Core.Real_Type_Id
                          (Subst_Syn (Core.Type_Id (N.To),
                                      Vars, Args)))));
            end case;
         end;
      end Subst_Syn;

      --  Expand synonym Name applied to Args (already converted).
      procedure Expand_Synonym
        (Name  : Names.Name_Id;
         Args  : Core.Type_Id_Vectors.Vector;
         Kinds : Core.Kind_Id;   --  unused marker
         Span  : Diagnostics.Source_Span;
         Depth : Natural;
         Result : out Core.Type_Id;
         Out_Kind : out Core.Kind_Id)
      is
         pragma Unreferenced (Kinds);
         Syn : constant Builtins.Syn_Rec := Env.Synonyms (Name);
      begin
         Result := Core.No_Type;
         Out_Kind := Core.Kind_Id (Star_K);
         if Syn.Bad then
            --  Reported when the declaration was cached; stay silent.
            return;
         end if;
         if Depth > Max_Synonym_Depth then
            Bag.Add (Diagnostics.Error, Diagnostics.Kind_Error, Span,
                     "cyclic type synonym");
            return;
         end if;
         if Natural (Args.Length) /= Syn.Arity then
            Bag.Add (Diagnostics.Error, Diagnostics.Kind_Error, Span,
                     "type synonym '" & Table.Text (Name)
                     & "' needs" & Syn.Arity'Image & " arguments");
            return;
         end if;
         if Syn.Core_Rhs /= Core.No_Type then
            --  Cached Core form: the wired-in String, or any user
            --  synonym after its defining module's kind pass ran.
            --  Imported synonyms always take this path - their
            --  Syntax_Rhs points into another module's arena and
            --  must never be re-read here.
            if Syn.Core_Vars.Is_Empty then
               Result := Syn.Core_Rhs;
            else
               Result := Subst_Syn (Syn.Core_Rhs, Syn.Core_Vars, Args);
            end if;
            return;
         end if;
         declare
            Local : Tv_Maps.Map;
            Order2 : TyVar_Vectors.Vector;
            K : Core.Kind_Id;
         begin
            for I in 1 .. Syn.Vars.Last_Index loop
               Local.Include
                 (Syn.Vars (I).Name,
                  Tv_Entry'(Ty => Args (I),
                            Tv_Kind => Core.Kind_Id (Star_K)));
            end loop;
            Convert (Real_Type_Id (Syn.Syntax_Rhs), Local, Order2,
                     Implicit => False, Depth => Depth + 1,
                     Result => Result, Kind => K);
            Out_Kind := K;
         end;
      end Expand_Synonym;

      procedure Convert
        (T          : Real_Type_Id;
         TvEnv      : in out Tv_Maps.Map;
         Order      : in out TyVar_Vectors.Vector;
         Implicit   : Boolean;
         Depth      : Natural;
         Result     : out Core.Type_Id;
         Kind       : out Core.Kind_Id)
      is
         N : constant Type_Node := Arena.Node (T);

         procedure Convert_Star (S : Real_Type_Id;
                                 R : out Core.Type_Id) is
            K : Core.Kind_Id;
         begin
            Convert (S, TvEnv, Order, Implicit, Depth, R, K);
            if K /= Core.No_Kind then
               KUnify (Core.Real_Kind_Id (K), Star_K, N.Span);
            end if;
         end Convert_Star;
      begin
         Result := Core.No_Type;
         Kind := Core.Kind_Id (Star_K);

         case N.Kind is
            when Var_T =>
               declare
                  C : constant Tv_Maps.Cursor := TvEnv.Find (N.Var);
               begin
                  if Tv_Maps.Has_Element (C) then
                     Result := Tv_Maps.Element (C).Ty;
                     Kind := Tv_Maps.Element (C).Tv_Kind;
                  elsif Implicit then
                     declare
                        KM : constant Core.Real_Kind_Id := Fresh_KMeta;
                        Tv : constant Core.Real_TyVar_Id :=
                          M.Mint_TyVar ((Name => N.Var,
                                         Tv_Kind => Core.Kind_Id (KM)));
                     begin
                        Result := Core.Type_Id
                          (M.Add (Core.Type_Node'
                             (Kind => Core.TVar_T, Tv => Tv)));
                        Kind := Core.Kind_Id (KM);
                        TvEnv.Include
                          (N.Var, Tv_Entry'(Ty => Result,
                                            Tv_Kind => Kind));
                        Order.Append (Tv);
                     end;
                  else
                     Bag.Add (Diagnostics.Error, Diagnostics.Kind_Error,
                              N.Span,
                              "type variable '" & Table.Text (N.Var)
                              & "' not in scope");
                  end if;
               end;

            when Con_T =>
               if Env.Synonyms.Contains (N.Con.Name) then
                  Expand_Synonym
                    (N.Con.Name, Core.Type_Id_Vectors.Empty_Vector,
                     Core.No_Kind, N.Span, Depth, Result, Kind);
               else
                  declare
                     TC : constant Core.TyCon_Id :=
                       Res.Ty_Res (Positive (T));
                  begin
                     if TC = Core.No_TyCon then
                        return;   --  renamer already diagnosed
                     end if;
                     Result := Core.Type_Id
                       (M.Add (Core.Type_Node'
                          (Kind => Core.TCon_T,
                           Con => Core.Real_TyCon_Id (TC),
                           Refine => Core.No_Refinement)));
                     Kind := Core.Kind_Id
                       (Kind_Of_TyCon (Core.Real_TyCon_Id (TC)));
                  end;
               end if;

            when App_T =>
               --  Synonym applications need the whole spine.
               declare
                  Head : Real_Type_Id := T;
                  Rev_Args : Syntax.Type_Id_Vectors.Vector;
               begin
                  while Arena.Node (Head).Kind = App_T loop
                     Rev_Args.Append (Arena.Node (Head).Arg);
                     Head := Arena.Node (Head).Fun;
                  end loop;
                  if Arena.Node (Head).Kind = Con_T
                    and then Env.Synonyms.Contains
                               (Arena.Node (Head).Con.Name)
                  then
                     declare
                        Args : Core.Type_Id_Vectors.Vector;
                        R : Core.Type_Id;
                     begin
                        for I in reverse 1 .. Rev_Args.Last_Index loop
                           Convert_Star (Rev_Args (I), R);
                           if R = Core.No_Type then
                              return;
                           end if;
                           Args.Append (Core.Real_Type_Id (R));
                        end loop;
                        Expand_Synonym
                          (Arena.Node (Head).Con.Name, Args,
                           Core.No_Kind, N.Span, Depth, Result, Kind);
                        return;
                     end;
                  end if;
               end;

               declare
                  RF, RA : Core.Type_Id;
                  KF, KA : Core.Kind_Id;
                  KR : constant Core.Real_Kind_Id := Fresh_KMeta;
               begin
                  Convert (N.Fun, TvEnv, Order, Implicit, Depth, RF, KF);
                  Convert (N.Arg, TvEnv, Order, Implicit, Depth, RA, KA);
                  if RF = Core.No_Type or else RA = Core.No_Type then
                     return;
                  end if;
                  KUnify (Core.Real_Kind_Id (KF),
                          M.Add (Core.Kind_Node'
                            (Kind => Core.KFun_K,
                             KFrom => Core.Real_Kind_Id (KA),
                             KTo => KR)),
                          N.Span);
                  Result := Core.Type_Id
                    (M.Add (Core.Type_Node'
                       (Kind => Core.TApp_T,
                        T_Fun => Core.Real_Type_Id (RF),
                        T_Arg => Core.Real_Type_Id (RA))));
                  Kind := Core.Kind_Id (KR);
               end;

            when Fun_T =>
               declare
                  RF, RT : Core.Type_Id;
               begin
                  Convert_Star (N.From, RF);
                  Convert_Star (N.To, RT);
                  if RF = Core.No_Type or else RT = Core.No_Type then
                     return;
                  end if;
                  Result := Core.Type_Id
                    (M.Add (Core.Type_Node'
                       (Kind => Core.TFun_T,
                        From => Core.Real_Type_Id (RF),
                        To => Core.Real_Type_Id (RT))));
               end;

            when List_T =>
               declare
                  RE : Core.Type_Id;
                  List_Con : constant Core.Real_Type_Id :=
                    M.Add (Core.Type_Node'
                      (Kind => Core.TCon_T,
                       Con => Core.Real_TyCon_Id (Env.List_TC),
                       Refine => Core.No_Refinement));
               begin
                  Convert_Star (N.Elem, RE);
                  if RE = Core.No_Type then
                     return;
                  end if;
                  Result := Core.Type_Id
                    (M.Add (Core.Type_Node'
                       (Kind => Core.TApp_T, T_Fun => List_Con,
                        T_Arg => Core.Real_Type_Id (RE))));
               end;

            when Tuple_T =>
               declare
                  Count : constant Natural := Natural (N.Items.Length);
               begin
                  if Count not in 2 .. Builtins.Max_Tuple then
                     Bag.Add (Diagnostics.Error,
                              Diagnostics.Rename_Unsupported, N.Span,
                              "unsupported tuple size");
                     return;
                  end if;
                  declare
                     Acc : Core.Type_Id := Core.Type_Id
                       (M.Add (Core.Type_Node'
                          (Kind => Core.TCon_T,
                           Con => Core.Real_TyCon_Id
                                    (Env.Tuple_TCs (Count)),
                           Refine => Core.No_Refinement)));
                     RI : Core.Type_Id;
                  begin
                     for I of N.Items loop
                        Convert_Star (I, RI);
                        if RI = Core.No_Type then
                           return;
                        end if;
                        Acc := Core.Type_Id
                          (M.Add (Core.Type_Node'
                             (Kind => Core.TApp_T,
                              T_Fun => Core.Real_Type_Id (Acc),
                              T_Arg => Core.Real_Type_Id (RI))));
                     end loop;
                     Result := Acc;
                  end;
               end;

            when Qual_T =>
               Bag.Add (Diagnostics.Error, Diagnostics.Kind_Error,
                        N.Span, "unexpected context in type");

            when Refined_T =>
               declare
                  RB : Core.Type_Id;
                  KB : Core.Kind_Id;
               begin
                  Convert (N.R_Base, TvEnv, Order, Implicit, Depth,
                           RB, KB);
                  if RB = Core.No_Type then
                     return;
                  end if;
                  KUnify (Core.Real_Kind_Id (KB), Star_K, N.Span);
                  declare
                     BN : constant Core.Type_Node :=
                       M.Node (Core.Real_Type_Id (RB));
                  begin
                     if BN.Kind /= Core.TCon_T
                       or else (Core.TyCon_Id (BN.Con) /= Env.Int_TC
                                and then Core.TyCon_Id (BN.Con) /=
                                  Env.Integer_TC
                                and then Core.TyCon_Id (BN.Con) /=
                                  Env.Double_TC
                                and then Core.TyCon_Id (BN.Con) /=
                                  Env.Float_TC)
                     then
                        Bag.Add (Diagnostics.Error,
                                 Diagnostics.Kind_Error, N.Span,
                                 "range refinements are only supported"
                                 & " on Int, Integer, Double and"
                                 & " Float");
                        return;
                     end if;
                     if BN.Refine /= Core.No_Refinement then
                        Bag.Add (Diagnostics.Error,
                                 Diagnostics.Kind_Error, N.Span,
                                 "a type cannot carry two"
                                 & " refinements");
                        return;
                     end if;
                     if Core.TyCon_Id (BN.Con) = Env.Double_TC
                       or else Core.TyCon_Id (BN.Con) = Env.Float_TC
                     then
                        --  Double range: either lexeme form; the
                        --  original texts are kept for exact
                        --  reproduction in C and in printed types.
                        if F_Value (N.Lo_Text, N.Lo_Neg) >
                           F_Value (N.Hi_Text, N.Hi_Neg)
                        then
                           Bag.Add (Diagnostics.Error,
                                    Diagnostics.Kind_Error, N.Span,
                                    "empty refinement range");
                           return;
                        end if;
                        Result := Core.Type_Id
                          (M.Add (Core.Type_Node'
                             (Kind => Core.TCon_T, Con => BN.Con,
                              Refine => Core.Refinement_Id
                                (M.Add (Core.Refinement_Info'
                                   (Kind => Core.FRange_R,
                                    FLo_Neg => N.Lo_Neg,
                                    FHi_Neg => N.Hi_Neg,
                                    FLo_Text => N.Lo_Text,
                                    FHi_Text => N.Hi_Text))))));
                        return;
                     end if;
                     if Is_Float_Lexeme (N.Lo_Text)
                       or else Is_Float_Lexeme (N.Hi_Text)
                     then
                        Bag.Add (Diagnostics.Error,
                                 Diagnostics.Kind_Error, N.Span,
                                 "integer range bounds required for"
                                 & " an Int range");
                        return;
                     end if;
                     declare
                        Lo : constant Long_Long_Integer :=
                          Bound_Value (N.Lo_Text, N.Lo_Neg);
                        Hi : constant Long_Long_Integer :=
                          Bound_Value (N.Hi_Text, N.Hi_Neg);
                     begin
                        if Lo > Hi then
                           Bag.Add (Diagnostics.Error,
                                    Diagnostics.Kind_Error, N.Span,
                                    "empty refinement range");
                           return;
                        end if;
                        Result := Core.Type_Id
                          (M.Add (Core.Type_Node'
                             (Kind => Core.TCon_T, Con => BN.Con,
                              Refine => Core.Refinement_Id
                                (M.Add (Core.Refinement_Info'
                                   (Kind => Core.Range_R,
                                    Lo => Lo, Hi => Hi))))));
                     end;
                  end;
               end;

            when Pred_T =>
               declare
                  RB : Core.Type_Id;
                  KB : Core.Kind_Id;
               begin
                  Convert (N.P_Base, TvEnv, Order, Implicit, Depth,
                           RB, KB);
                  if RB = Core.No_Type then
                     return;
                  end if;
                  KUnify (Core.Real_Kind_Id (KB), Star_K, N.Span);
                  declare
                     BN : constant Core.Type_Node :=
                       M.Node (Core.Real_Type_Id (RB));
                  begin
                     if BN.Kind /= Core.TCon_T then
                        Bag.Add (Diagnostics.Error,
                                 Diagnostics.Kind_Error, N.Span,
                                 "predicate refinements need a"
                                 & " nullary base type");
                        return;
                     end if;
                     if BN.Refine /= Core.No_Refinement then
                        Bag.Add (Diagnostics.Error,
                                 Diagnostics.Kind_Error, N.Span,
                                 "a type cannot carry two"
                                 & " refinements");
                        return;
                     end if;
                     --  Hidden top-level predicate binder with the
                     --  signature BASE -> Bool; the desugarer supplies
                     --  its body from the pending list, and the
                     --  typechecker then treats it like any other
                     --  signatured binding.
                     declare
                        PV : constant Core.Real_Var_Id :=
                          M.Mint_Var
                            ((Name => Table.Intern ("$pred"),
                              Span => N.Span, Is_Global => True,
                              others => <>));
                        Bool_T : constant Core.Real_Type_Id :=
                          M.Add (Core.Type_Node'
                            (Kind => Core.TCon_T,
                             Con => Core.Real_TyCon_Id (Env.Bool_TC),
                             Refine => Core.No_Refinement));
                        Sch : Core.Scheme;
                     begin
                        Sch.S_Body := Core.Type_Id
                          (M.Add (Core.Type_Node'
                             (Kind => Core.TFun_T,
                              From => Core.Real_Type_Id (RB),
                              To => Bool_T)));
                        Sigs.Include
                          (PV, Core.Scheme_Id (M.Add (Sch)));
                        Preds.Append
                          (Pending_Pred'(Binder => PV,
                                         Expr => Syntax.Expr_Id
                                                   (N.P_Expr)));
                        Result := Core.Type_Id
                          (M.Add (Core.Type_Node'
                             (Kind => Core.TCon_T, Con => BN.Con,
                              Refine => Core.Refinement_Id
                                (M.Add (Core.Refinement_Info'
                                   (Kind => Core.Pred_R,
                                    Pred_Var => PV,
                                    P_Name => N.P_Name))))));
                     end;
                  end;
               end;

            when Mod_T =>
               declare
                  RB : Core.Type_Id;
                  KB : Core.Kind_Id;
               begin
                  Convert (N.M_Base, TvEnv, Order, Implicit, Depth,
                           RB, KB);
                  if RB = Core.No_Type then
                     return;
                  end if;
                  KUnify (Core.Real_Kind_Id (KB), Star_K, N.Span);
                  declare
                     BN : constant Core.Type_Node :=
                       M.Node (Core.Real_Type_Id (RB));
                  begin
                     if BN.Kind /= Core.TCon_T
                       or else (Core.TyCon_Id (BN.Con) /= Env.Int_TC
                                and then Core.TyCon_Id (BN.Con) /=
                                  Env.Integer_TC)
                     then
                        Bag.Add (Diagnostics.Error,
                                 Diagnostics.Kind_Error, N.Span,
                                 "modular types are only supported"
                                 & " on Int and Integer");
                        return;
                     end if;
                     if BN.Refine /= Core.No_Refinement then
                        Bag.Add (Diagnostics.Error,
                                 Diagnostics.Kind_Error, N.Span,
                                 "a type cannot carry two"
                                 & " refinements");
                        return;
                     end if;
                     declare
                        Modulus : constant Long_Long_Integer :=
                          Bound_Value (N.M_Text, False);
                     begin
                        if Modulus < 1 then
                           Bag.Add (Diagnostics.Error,
                                    Diagnostics.Kind_Error, N.Span,
                                    "modulus must be at least 1");
                           return;
                        end if;
                        Result := Core.Type_Id
                          (M.Add (Core.Type_Node'
                             (Kind => Core.TCon_T, Con => BN.Con,
                              Refine => Core.Refinement_Id
                                (M.Add (Core.Refinement_Info'
                                   (Kind => Core.Mod_R,
                                    Modulus => Modulus))))));
                     end;
                  end;
               end;
         end case;
      end Convert;

      --  Convert a context assertion into a constraint.
      procedure Convert_Assertion
        (T     : Real_Type_Id;
         TvEnv : in out Tv_Maps.Map;
         Order : in out TyVar_Vectors.Vector;
         Implicit : Boolean;
         Into  : in out Core.Constraint_Vectors.Vector)
      is
         N : constant Type_Node := Arena.Node (T);
      begin
         if N.Kind = App_T
           and then Arena.Node (N.Fun).Kind = Con_T
         then
            declare
               Cl : constant Core.Class_Id :=
                 Res.Class_Res (Positive (N.Fun));
               R : Core.Type_Id;
               K : Core.Kind_Id;
            begin
               if Cl = Core.No_Class then
                  return;   --  renamer already diagnosed
               end if;
               Convert (N.Arg, TvEnv, Order, Implicit, 0, R, K);
               if R = Core.No_Type then
                  return;
               end if;
               KUnify (Core.Real_Kind_Id (K),
                       Core.Real_Kind_Id
                         (M.Info (Core.Real_Class_Id (Cl)).Var_Kind),
                       N.Span);
               Into.Append
                 (Core.Constraint'
                    (Class => Core.Real_Class_Id (Cl),
                     Arg => Core.Real_Type_Id (R),
                     Span => N.Span));
            end;
         else
            Bag.Add (Diagnostics.Error, Diagnostics.Kind_Error,
                     Arena.Node (T).Span, "malformed class assertion");
         end if;
      end Convert_Assertion;

      --  Convert a possibly-qualified surface type into a Scheme,
      --  implicitly quantifying its free type variables.
      function Convert_Scheme
        (T : Real_Type_Id;
         Pre_Env : Tv_Maps.Map;
         Pre_Tvs : TyVar_Vectors.Vector;
         Pre_Ctx : Core.Constraint_Vectors.Vector)
         return Core.Scheme_Id
      is
         TvEnv : Tv_Maps.Map := Pre_Env;
         Order : TyVar_Vectors.Vector := Pre_Tvs;
         Ctx   : Core.Constraint_Vectors.Vector := Pre_Ctx;
         Body_T : Real_Type_Id := T;
         R : Core.Type_Id;
         K : Core.Kind_Id;
      begin
         if Arena.Node (T).Kind = Qual_T then
            declare
               --  Bind the node before iterating: 'for .. of' over the
               --  component of a function-result temporary iterates an
               --  already-finalized vector.
               TN : constant Type_Node := Arena.Node (T);
            begin
               for A of TN.Context loop
                  Convert_Assertion (A, TvEnv, Order, True, Ctx);
               end loop;
               Body_T := TN.Q_Body;
            end;
         end if;
         Convert (Body_T, TvEnv, Order, True, 0, R, K);
         if R = Core.No_Type then
            return Core.No_Scheme;
         end if;
         KUnify (Core.Real_Kind_Id (K), Star_K, Arena.Node (T).Span);
         return Core.Scheme_Id
           (M.Add (Core.Scheme'(Tvs => Order, Context => Ctx,
                                S_Body => R)));
      end Convert_Scheme;

      ------------------------------------------------------------------
      --  Per-declaration processing
      ------------------------------------------------------------------

      --  Data/newtype: mint canonical tyvars, kind the tycon, convert
      --  constructor fields, build Con_Schemes and field selectors.
      procedure Do_Data (N : Decl_Node) is
         TC : constant Core.Real_TyCon_Id :=
           Builtins.TyCon_Maps.Element (Env.TyCons.Find (N.D_Name));
         TvEnv : Tv_Maps.Map;
         Tvs   : TyVar_Vectors.Vector;
         Result_T : Core.Type_Id;
      begin
         --  Tyvars with fresh kind metas; tycon kind k1->..->kn->*.
         declare
            K : Core.Real_Kind_Id := Star_K;
            Metas : array (1 .. Natural (N.D_Vars.Length)) of
              Core.Real_Kind_Id;
         begin
            for I in Metas'Range loop
               Metas (I) := Fresh_KMeta;
            end loop;
            for I in reverse Metas'Range loop
               K := M.Add (Core.Kind_Node'(Kind => Core.KFun_K,
                                           KFrom => Metas (I),
                                           KTo => K));
            end loop;
            M.TyCons (TC).TC_Kind := Core.Kind_Id (K);
            for I in 1 .. N.D_Vars.Last_Index loop
               declare
                  Tv : constant Core.Real_TyVar_Id :=
                    M.Mint_TyVar
                      ((Name => N.D_Vars (I).Name,
                        Tv_Kind => Core.Kind_Id (Metas (I))));
                  TvT : constant Core.Real_Type_Id :=
                    M.Add (Core.Type_Node'(Kind => Core.TVar_T,
                                           Tv => Tv));
               begin
                  Tvs.Append (Tv);
                  TvEnv.Include
                    (N.D_Vars (I).Name,
                     Tv_Entry'(Ty => Core.Type_Id (TvT),
                               Tv_Kind => Core.Kind_Id (Metas (I))));
               end;
            end loop;
         end;

         --  Result type T a1 .. an.
         Result_T := Core.Type_Id
           (M.Add (Core.Type_Node'(Kind => Core.TCon_T, Con => TC,
                                   Refine => Core.No_Refinement)));
         for Tv of Tvs loop
            declare
               TvT : constant Core.Real_Type_Id :=
                 M.Add (Core.Type_Node'(Kind => Core.TVar_T, Tv => Tv));
            begin
               Result_T := Core.Type_Id
                 (M.Add (Core.Type_Node'
                    (Kind => Core.TApp_T,
                     T_Fun => Core.Real_Type_Id (Result_T),
                     T_Arg => TvT)));
            end;
         end loop;

         for CI of N.D_Cons loop
            declare
               CN : constant Con_Node := Arena.Node (CI);
               DC : constant Core.Real_DataCon_Id :=
                 Builtins.DataCon_Maps.Element
                   (Env.DataCons.Find (CN.Name.Name));
               Field_Types : Core.Type_Id_Vectors.Vector;

               procedure Add_Field (T : Real_Type_Id) is
                  Order : TyVar_Vectors.Vector;
                  R : Core.Type_Id;
                  K : Core.Kind_Id;
               begin
                  Convert (T, TvEnv, Order, False, 0, R, K);
                  if R /= Core.No_Type then
                     KUnify (Core.Real_Kind_Id (K), Star_K, CN.Span);
                     Field_Types.Append (Core.Real_Type_Id (R));
                  end if;
               end Add_Field;
            begin
               case CN.Shape is
                  when Prefix_Con | Infix_Con =>
                     for T of CN.Args loop
                        Add_Field (T);
                     end loop;
                  when Record_Con =>
                     for F of CN.Fields loop
                        for FQ of F.Names_List loop
                           pragma Unreferenced (FQ);
                           Add_Field (F.Field_Type);
                        end loop;
                     end loop;
               end case;

               --  Con scheme: forall tvs. f1 -> .. -> T tvs.
               declare
                  Fn_T : Core.Type_Id := Result_T;
               begin
                  for I in reverse 1 .. Field_Types.Last_Index loop
                     Fn_T := Core.Type_Id
                       (M.Add (Core.Type_Node'
                          (Kind => Core.TFun_T,
                           From => Field_Types (I),
                           To => Core.Real_Type_Id (Fn_T))));
                  end loop;
                  M.DataCons (DC).Con_Scheme := Core.Scheme_Id
                    (M.Add (Core.Scheme'
                       (Tvs => Tvs,
                        Context =>
                          Core.Constraint_Vectors.Empty_Vector,
                        S_Body => Fn_T)));
               end;

               --  Field selectors: forall tvs. T tvs -> field type.
               declare
                  FNames : constant Core.Name_Id_Vectors.Vector :=
                    M.Info (DC).Field_Names;
               begin
                  for I in 1 .. FNames.Last_Index loop
                     declare
                        Sel_C : constant Builtins.Var_Maps.Cursor :=
                          Env.Values.Find (FNames (I));
                     begin
                        if Builtins.Var_Maps.Has_Element (Sel_C)
                          and then M.Info (Builtins.Var_Maps.Element
                                             (Sel_C)).Var_Scheme
                                   = Core.No_Scheme
                        then
                           declare
                              Sel_T : constant Core.Real_Type_Id :=
                                M.Add (Core.Type_Node'
                                  (Kind => Core.TFun_T,
                                   From =>
                                     Core.Real_Type_Id (Result_T),
                                   To => Field_Types (I)));
                           begin
                              M.Vars (Builtins.Var_Maps.Element (Sel_C))
                                .Var_Scheme := Core.Scheme_Id
                                  (M.Add (Core.Scheme'
                                     (Tvs => Tvs,
                                      Context => Core.Constraint_Vectors
                                                   .Empty_Vector,
                                      S_Body =>
                                        Core.Type_Id (Sel_T))));
                           end;
                        end if;
                     end;
                  end loop;
               end;
            end;
         end loop;
      end Do_Data;

      procedure Do_Class (D : Real_Decl_Id; N : Decl_Node) is
         Cl_Id : constant Core.Class_Id :=
           Res.Decl_Class (Positive (D));
      begin
         if Cl_Id = Core.No_Class then
            return;
         end if;
         declare
            Cl : constant Core.Real_Class_Id :=
              Core.Real_Class_Id (Cl_Id);
            KM : constant Core.Real_Kind_Id := Fresh_KMeta;
            Tv : constant Core.Real_TyVar_Id :=
              M.Mint_TyVar ((Name => N.C_Var,
                             Tv_Kind => Core.Kind_Id (KM)));
            TvT : constant Core.Real_Type_Id :=
              M.Add (Core.Type_Node'(Kind => Core.TVar_T, Tv => Tv));
         begin
            M.Classes (Cl).Var_Kind := Core.Kind_Id (KM);
            if M.Classes (Cl).Dict_TyCon /= Core.No_TyCon then
               M.TyCons
                 (Core.Real_TyCon_Id (M.Classes (Cl).Dict_TyCon))
                 .TC_Kind := Core.Kind_Id
                   (M.Add (Core.Kind_Node'
                      (Kind => Core.KFun_K, KFrom => KM,
                       KTo => Star_K)));
            end if;

            for MI in 1 .. M.Classes (Cl).Methods.Last_Index loop
               declare
                  Sel : constant Core.Var_Id :=
                    M.Classes (Cl).Methods (MI).Selector;
                  Sig_C : constant Rename.Var_Sig_Maps.Cursor :=
                    Res.Var_Sig.Find (Core.Real_Var_Id (Sel));
               begin
                  if Rename.Var_Sig_Maps.Has_Element (Sig_C) then
                     declare
                        Pre_Env : Tv_Maps.Map;
                        Pre_Tvs : TyVar_Vectors.Vector;
                        Pre_Ctx : Core.Constraint_Vectors.Vector;
                        Sch : Core.Scheme_Id;
                     begin
                        Pre_Env.Include
                          (N.C_Var,
                           Tv_Entry'(Ty => Core.Type_Id (TvT),
                                     Tv_Kind => Core.Kind_Id (KM)));
                        Pre_Tvs.Append (Tv);
                        Pre_Ctx.Append
                          (Core.Constraint'
                             (Class => Cl,
                              Arg => Core.Real_Type_Id
                                       (Core.Type_Id (TvT)),
                              Span => N.Span));
                        Sch := Convert_Scheme
                          (Real_Type_Id
                             (Rename.Var_Sig_Maps.Element (Sig_C)),
                           Pre_Env, Pre_Tvs, Pre_Ctx);
                        M.Classes (Cl).Methods (MI).Method_Scheme := Sch;
                        if Sch /= Core.No_Scheme then
                           M.Vars (Core.Real_Var_Id (Sel)).Var_Scheme :=
                             Sch;
                        end if;
                     end;
                  end if;
               end;
            end loop;
         end;
      end Do_Class;

      procedure Do_Instance (D : Real_Decl_Id; N : Decl_Node) is
         Cl_Id : constant Core.Class_Id :=
           Res.Decl_Class (Positive (D));
      begin
         if Cl_Id = Core.No_Class then
            return;
         end if;
         declare
            TvEnv : Tv_Maps.Map;
            Order : TyVar_Vectors.Vector;
            Ctx   : Core.Constraint_Vectors.Vector;
            R : Core.Type_Id;
            K : Core.Kind_Id;
         begin
            Convert (N.I_Type, TvEnv, Order, True, 0, R, K);
            if R = Core.No_Type then
               return;
            end if;
            KUnify (Core.Real_Kind_Id (K),
                    Core.Real_Kind_Id
                      (M.Info (Core.Real_Class_Id (Cl_Id)).Var_Kind),
                    N.Span);
            for A of N.I_Context loop
               Convert_Assertion (A, TvEnv, Order, True, Ctx);
            end loop;

            --  Locate the Instance_Info minted by the renamer (same
            --  class, same span) and complete it.
            for I in 1 .. M.Instances.Last_Index loop
               if M.Instances (I).Of_Class = Cl_Id
                 and then Diagnostics."="
                            (M.Instances (I).Span, N.Span)
               then
                  M.Instances (I).Head_Vars := Order;
                  M.Instances (I).Context := Ctx;
               end if;
            end loop;
         end;
      end Do_Instance;

      --  Cache a declared synonym's rhs as a Core type, with fresh
      --  Core tyvars standing for the parameters. After this pass,
      --  expansion never needs the syntax arena - which is the
      --  point: importing modules cannot read it (Syntax_Rhs ids
      --  are private to the defining module's arena).
      procedure Do_Synonym (N : Decl_Node) is
         Syn   : Builtins.Syn_Rec := Env.Synonyms (N.S_Name);
         TvEnv : Tv_Maps.Map;
         Order : TyVar_Vectors.Vector;
         R     : Core.Type_Id;
         K     : Core.Kind_Id;
      begin
         if Core."/=" (Syn.Core_Rhs, Core.No_Type) then
            return;   --  wired-in (String)
         end if;
         for V of N.S_Vars loop
            declare
               KM : constant Core.Real_Kind_Id := Fresh_KMeta;
               Tv : constant Core.Real_TyVar_Id :=
                 M.Mint_TyVar ((Name => V.Name,
                                Tv_Kind => Core.Kind_Id (KM)));
               Ty : constant Core.Type_Id := Core.Type_Id
                 (M.Add (Core.Type_Node'
                    (Kind => Core.TVar_T, Tv => Tv)));
            begin
               TvEnv.Include
                 (V.Name, Tv_Entry'(Ty => Ty,
                                    Tv_Kind => Core.Kind_Id (KM)));
               Syn.Core_Vars.Append (Tv);
            end;
         end loop;
         Convert (N.S_Rhs, TvEnv, Order,
                  Implicit => False, Depth => 0,
                  Result => R, Kind => K);
         Syn.Core_Rhs := R;
         Syn.Bad := Core."=" (R, Core.No_Type);
         Env.Synonyms.Include (N.S_Name, Syn);
      end Do_Synonym;

      Method_Selectors : Sig_Maps.Map;   --  selector set (value unused)

   begin
      --  Data/newtype first (mutual recursion between types works
      --  because each user tycon's kind is a meta structure that other
      --  conversions unify against).
      for D of Arena.Top_Decls loop
         declare
            N : constant Decl_Node := Arena.Node (D);
         begin
            if N.Kind in Data_D | Newtype_D then
               Do_Data (N);
            end if;
         end;
      end loop;

      --  Synonyms next (data kinds now exist): cache each declared
      --  synonym's Core rhs so every later conversion - and every
      --  importing module - expands from the cached form instead of
      --  this arena.
      for D of Arena.Top_Decls loop
         declare
            N : constant Decl_Node := Arena.Node (D);
         begin
            if N.Kind = Type_Syn_D then
               Do_Synonym (N);
            end if;
         end;
      end loop;

      for D of Arena.Top_Decls loop
         declare
            N : constant Decl_Node := Arena.Node (D);
         begin
            if N.Kind = Class_D then
               Do_Class (D, N);
            end if;
         end;
      end loop;

      --  Mark method selectors so plain signature conversion skips them.
      for Cl in 1 .. M.Last_Class loop
         for Mth of M.Classes (Core.Real_Class_Id (Cl)).Methods loop
            if Core."/=" (Mth.Selector, Core.No_Var) then
               Method_Selectors.Include
                 (Core.Real_Var_Id (Mth.Selector), Core.No_Scheme);
            end if;
         end loop;
      end loop;

      for D of Arena.Top_Decls loop
         declare
            N : constant Decl_Node := Arena.Node (D);
         begin
            if N.Kind = Instance_D then
               Do_Instance (D, N);
            end if;
         end;
      end loop;

      --  Plain signatures.
      declare
         C : Rename.Var_Sig_Maps.Cursor := Res.Var_Sig.First;
      begin
         while Rename.Var_Sig_Maps.Has_Element (C) loop
            declare
               V : constant Core.Real_Var_Id :=
                 Rename.Var_Sig_Maps.Key (C);
            begin
               if not Method_Selectors.Contains (V) then
                  declare
                     Sch : constant Core.Scheme_Id :=
                       Convert_Scheme
                         (Real_Type_Id
                            (Rename.Var_Sig_Maps.Element (C)),
                          Tv_Maps.Empty_Map,
                          TyVar_Vectors.Empty_Vector,
                          Core.Constraint_Vectors.Empty_Vector);
                  begin
                     if Sch /= Core.No_Scheme then
                        Sigs.Include (V, Sch);
                     end if;
                  end;
               end if;
            end;
            Rename.Var_Sig_Maps.Next (C);
         end loop;
      end;

      --  Foreign imports are bodiless, so occurrences typecheck from
      --  Var_Info.Var_Scheme (exactly as wired builtins do); copy the
      --  just-converted signature scheme onto the binder.
      for D of Arena.Top_Decls loop
         declare
            N : constant Decl_Node := Arena.Node (D);
         begin
            if N.Kind = Foreign_D then
               declare
                  V : constant Core.Var_Id :=
                    Res.Decl_Var (Positive (D));
                  use Sig_Maps;
                  C : Cursor;
               begin
                  if Core."/=" (V, Core.No_Var) then
                     C := Sigs.Find (Core.Real_Var_Id (V));
                     if Has_Element (C) then
                        M.Vars (Core.Real_Var_Id (V)).Var_Scheme :=
                          Element (C);
                     end if;
                  end if;
               end;
            end if;
         end;
      end loop;

      --  Expression and pattern type annotations.
      for I in 1 .. Natural (Arena.Last_Expr) loop
         declare
            N : constant Expr_Node := Arena.Node (Real_Expr_Id (I));
         begin
            if N.Kind = Sig_E then
               declare
                  Sch : constant Core.Scheme_Id :=
                    Convert_Scheme
                      (N.Sig_Type, Tv_Maps.Empty_Map,
                       TyVar_Vectors.Empty_Vector,
                       Core.Constraint_Vectors.Empty_Vector);
               begin
                  if Sch /= Core.No_Scheme then
                     Annos.Include (Syntax.Type_Id (N.Sig_Type), Sch);
                  end if;
               end;
            end if;
         end;
      end loop;
      for I in 1 .. Natural (Arena.Last_Pat) loop
         declare
            N : constant Pat_Node := Arena.Node (Real_Pat_Id (I));
         begin
            if N.Kind = Sig_P then
               declare
                  Sch : constant Core.Scheme_Id :=
                    Convert_Scheme
                      (N.Sig_Type, Tv_Maps.Empty_Map,
                       TyVar_Vectors.Empty_Vector,
                       Core.Constraint_Vectors.Empty_Vector);
               begin
                  if Sch /= Core.No_Scheme then
                     Annos.Include (Syntax.Type_Id (N.Sig_Type), Sch);
                  end if;
               end;
            end if;
         end;
      end loop;

      --  Default declaration types.
      for D of Arena.Top_Decls loop
         declare
            N : constant Decl_Node := Arena.Node (D);
         begin
            if N.Kind = Default_D then
               for T of N.Def_Types loop
                  declare
                     TvEnv : Tv_Maps.Map;
                     Order : TyVar_Vectors.Vector;
                     R : Core.Type_Id;
                     K : Core.Kind_Id;
                  begin
                     Convert (T, TvEnv, Order, False, 0, R, K);
                  end;
               end loop;
            end if;
         end;
      end loop;

      --  Finalize: default residual kind metas to * everywhere.
      for TC in 1 .. M.Last_TyCon loop
         if M.TyCons (Core.Real_TyCon_Id (TC)).TC_Kind /= Core.No_Kind
         then
            M.TyCons (Core.Real_TyCon_Id (TC)).TC_Kind := Core.Kind_Id
              (Final_Kind (Core.Real_Kind_Id
                 (M.TyCons (Core.Real_TyCon_Id (TC)).TC_Kind)));
         end if;
      end loop;
      for Tv in 1 .. M.Last_TyVar loop
         if M.TyVars (Core.Real_TyVar_Id (Tv)).Tv_Kind /= Core.No_Kind
         then
            M.TyVars (Core.Real_TyVar_Id (Tv)).Tv_Kind := Core.Kind_Id
              (Final_Kind (Core.Real_Kind_Id
                 (M.TyVars (Core.Real_TyVar_Id (Tv)).Tv_Kind)));
         end if;
      end loop;
      for Cl in 1 .. M.Last_Class loop
         if M.Classes (Core.Real_Class_Id (Cl)).Var_Kind /= Core.No_Kind
         then
            M.Classes (Core.Real_Class_Id (Cl)).Var_Kind := Core.Kind_Id
              (Final_Kind (Core.Real_Kind_Id
                 (M.Classes (Core.Real_Class_Id (Cl)).Var_Kind)));
         end if;
      end loop;
   end Check_Module;

end AHC.Kinds;
