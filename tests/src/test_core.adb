with AHC.Core;         use AHC.Core;
with AHC.Core.Printer;
with AHC.Diagnostics;
with AHC.Names;

with Test_Harness; use Test_Harness;

package body Test_Core is

   Span : constant AHC.Diagnostics.Source_Span := (Start => 1, Stop => 1);

   Table : AHC.Names.Name_Table;

   procedure Empty_Let is
      M : Core_Module;
      X : constant Real_Var_Id :=
        M.Mint_Var ((Name => Table.Intern ("x"), Span => Span,
                     others => <>));
      B : constant Real_Expr_Id :=
        M.Add (Expr_Node'(Kind => Var_C, Span => Span, V => X));
      E : Real_Expr_Id;
   begin
      E := M.Add (Expr_Node'(Kind => Let_C, Span => Span,
                             Is_Rec => False,
                             Binds => Bind_Vectors.Empty_Vector,
                             Let_Body => B));
      pragma Unreferenced (E);
   end Empty_Let;

   procedure Wrong_Alt_Arity is
      M : Core_Module;
      Star_K_Id : constant Real_Kind_Id := M.Star;
      TC : constant Real_TyCon_Id :=
        M.Mint_TyCon ((Name => Table.Intern ("Pair"), Arity => 0,
                       TC_Kind => Star_K_Id, others => <>));
      DC : constant Real_DataCon_Id :=
        M.Mint_DataCon ((Name => Table.Intern ("MkPair"), TyCon => TC,
                         Tag => 1, Arity => 2, others => <>));
      X : constant Real_Var_Id :=
        M.Mint_Var ((Name => Table.Intern ("x"), Span => Span,
                     others => <>));
      B : constant Real_Expr_Id :=
        M.Add (Expr_Node'(Kind => Var_C, Span => Span, V => X));
      One_Binder : Var_Id_Vectors.Vector;
      A : Real_Alt_Id;
   begin
      One_Binder.Append (X);  --  MkPair has arity 2; one binder is wrong
      A := M.Add (Alt_Node'(Kind => Con_Alt, Span => Span,
                            Alt_Body => B, A_Con => DC,
                            Binders => One_Binder));
      pragma Unreferenced (A);
   end Wrong_Alt_Arity;

   procedure Default_Not_Last is
      M : Core_Module;
      X : constant Real_Var_Id :=
        M.Mint_Var ((Name => Table.Intern ("x"), Span => Span,
                     others => <>));
      B : constant Real_Expr_Id :=
        M.Add (Expr_Node'(Kind => Var_C, Span => Span, V => X));
      D1 : constant Real_Alt_Id :=
        M.Add (Alt_Node'(Kind => Default_Alt, Span => Span,
                         Alt_Body => B));
      D2 : constant Real_Alt_Id :=
        M.Add (Alt_Node'(Kind => Default_Alt, Span => Span,
                         Alt_Body => B));
      Alts : Alt_Id_Vectors.Vector;
      E : Real_Expr_Id;
   begin
      Alts.Append (D1);
      Alts.Append (D2);   --  a default that is not last
      E := M.Add (Expr_Node'(Kind => Case_C, Span => Span,
                             Scrutinee => B, Alts => Alts));
      pragma Unreferenced (E);
   end Default_Not_Last;

   procedure Refinement_Constructed is
      M : Core_Module;
      Star_K_Id : constant Real_Kind_Id := M.Star;
      TC : constant Real_TyCon_Id :=
        M.Mint_TyCon ((Name => Table.Intern ("Int"), Arity => 0,
                       TC_Kind => Star_K_Id, others => <>));
      T : Real_Type_Id;
   begin
      --  A refinement id must name an entry in the arena; the module
      --  has none, so id 1 dangles.
      T := M.Add (Type_Node'(Kind => TCon_T, Con => TC, Refine => 1));
      pragma Unreferenced (T);
   end Refinement_Constructed;

   procedure Run is
   begin
      Start_Suite ("Core");

      --  id = \x -> x, dumped.
      declare
         M : Core_Module;
         X : constant Real_Var_Id :=
           M.Mint_Var ((Name => Table.Intern ("x"), Span => Span,
                        others => <>));
         Id_V : constant Real_Var_Id :=
           M.Mint_Var ((Name => Table.Intern ("id"), Span => Span,
                        Is_Global => True, others => <>));
         Body_E : constant Real_Expr_Id :=
           M.Add (Expr_Node'(Kind => Var_C, Span => Span, V => X));
         Lam : constant Real_Expr_Id :=
           M.Add (Expr_Node'(Kind => Lam_C, Span => Span,
                             Binder => X, Lam_Body => Body_E));
         Group : Top_Bind;
      begin
         Group.Binds.Append (Bind_Pair'(Binder => Id_V, Rhs => Lam));
         M.Top_Binds.Append (Group);
         Check_Equal
           (AHC.Core.Printer.Dump (M, Table),
            "(bind (id_2 (lam x_1 (var x_1))))" & ASCII.LF,
            "id function dumps");
      end;

      --  not = \b -> case b of True -> False; _ -> True
      declare
         M : Core_Module;
         Star_K_Id : constant Real_Kind_Id := M.Star;
         Bool_TC : constant Real_TyCon_Id :=
           M.Mint_TyCon ((Name => Table.Intern ("Bool"), Arity => 0,
                          TC_Kind => Star_K_Id, others => <>));
         False_DC : constant Real_DataCon_Id :=
           M.Mint_DataCon ((Name => Table.Intern ("False"),
                            TyCon => Bool_TC, Tag => 1, Arity => 0,
                            others => <>));
         True_DC : constant Real_DataCon_Id :=
           M.Mint_DataCon ((Name => Table.Intern ("True"),
                            TyCon => Bool_TC, Tag => 2, Arity => 0,
                            others => <>));
         B_V : constant Real_Var_Id :=
           M.Mint_Var ((Name => Table.Intern ("b"), Span => Span,
                        others => <>));
         Not_V : constant Real_Var_Id :=
           M.Mint_Var ((Name => Table.Intern ("not"), Span => Span,
                        Is_Global => True, others => <>));
         Scrut : constant Real_Expr_Id :=
           M.Add (Expr_Node'(Kind => Var_C, Span => Span, V => B_V));
         False_E : constant Real_Expr_Id :=
           M.Add (Expr_Node'(Kind => Con_C, Span => Span,
                             Con => False_DC));
         True_E : constant Real_Expr_Id :=
           M.Add (Expr_Node'(Kind => Con_C, Span => Span,
                             Con => True_DC));
         A1 : constant Real_Alt_Id :=
           M.Add (Alt_Node'(Kind => Con_Alt, Span => Span,
                            Alt_Body => False_E, A_Con => True_DC,
                            Binders => Var_Id_Vectors.Empty_Vector));
         A2 : constant Real_Alt_Id :=
           M.Add (Alt_Node'(Kind => Default_Alt, Span => Span,
                            Alt_Body => True_E));
         Alts : Alt_Id_Vectors.Vector;
         Group : Top_Bind;
      begin
         Alts.Append (A1);
         Alts.Append (A2);
         declare
            Case_E : constant Real_Expr_Id :=
              M.Add (Expr_Node'(Kind => Case_C, Span => Span,
                                Scrutinee => Scrut, Alts => Alts));
            Lam : constant Real_Expr_Id :=
              M.Add (Expr_Node'(Kind => Lam_C, Span => Span,
                                Binder => B_V, Lam_Body => Case_E));
         begin
            Group.Binds.Append
              (Bind_Pair'(Binder => Not_V, Rhs => Lam));
            M.Top_Binds.Append (Group);
            Check_Equal
              (AHC.Core.Printer.Dump (M, Table),
               "(bind (not_2 (lam b_1 (case (var b_1)"
               & " (alt (con True) (con False)) (alt _ (con True))))))"
               & ASCII.LF,
               "case with constructor and default alts dumps");
         end;
      end;

      --  Types, schemes, and the erased-head rule.
      declare
         M : Core_Module;
         Star_K_Id : constant Real_Kind_Id := M.Star;
         Int_TC : constant Real_TyCon_Id :=
           M.Mint_TyCon ((Name => Table.Intern ("Int"), Arity => 0,
                          TC_Kind => Star_K_Id, others => <>));
         A_Tv : constant Real_TyVar_Id :=
           M.Mint_TyVar ((Name => Table.Intern ("a"),
                          Tv_Kind => Star_K_Id));
         A_T : constant Real_Type_Id :=
           M.Add (Type_Node'(Kind => TVar_T, Tv => A_Tv));
         Int_T : constant Real_Type_Id :=
           M.Add (Type_Node'(Kind => TCon_T, Con => Int_TC,
                             Refine => No_Refinement));
         F_T : constant Real_Type_Id :=
           M.Add (Type_Node'(Kind => TFun_T, From => A_T, To => Int_T));
         Sch : Scheme;
      begin
         Check_Equal
           (AHC.Core.Printer.Type_Image (M, Table, F_T),
            "(-> (tv a_1) (tcon Int))", "function type image");

         Sch.Tvs.Append (A_Tv);
         Sch.S_Body := F_T;
         declare
            S : constant Real_Scheme_Id := M.Add (Sch);
         begin
            Check_Equal
              (AHC.Core.Printer.Scheme_Image (M, Table, S),
               "(forall (a_1) (-> (tv a_1) (tcon Int)))",
               "scheme image");
         end;

         --  Design rule 2: heads that differ only in Refine unify.
         declare
            Plain : constant Type_Node :=
              (Kind => TCon_T, Con => Int_TC, Refine => No_Refinement);
            Refined : constant Type_Node :=
              (Kind => TCon_T, Con => Int_TC, Refine => 7);
         begin
            Check (Same_Con_Erased (Plain, Refined),
                   "erased-head equality ignores the refinement slot");
         end;
      end;

      --  Contract violations.
      Check_Assertion_Error
        (Empty_Let'Access, "empty let is rejected");
      Check_Assertion_Error
        (Wrong_Alt_Arity'Access,
         "constructor alt with wrong binder count is rejected");
      Check_Assertion_Error
        (Default_Not_Last'Access,
         "default alternative not last is rejected");
      Check_Assertion_Error
        (Refinement_Constructed'Access,
         "a dangling refinement id is rejected");

      --  Refinement arena (stage 1 of the extension).
      declare
         M : Core_Module;
         Star_K_Id : constant Real_Kind_Id := M.Star;
         pragma Unreferenced (Star_K_Id);
         Int_TC : constant Real_TyCon_Id :=
           M.Mint_TyCon ((Name => Table.Intern ("Int"), Arity => 0,
                          TC_Kind => M.Star, others => <>));
         R : constant Real_Refinement_Id :=
           M.Add (Refinement_Info'(Kind => Range_R, Lo => 0, Hi => 100));
         T : constant Real_Type_Id :=
           M.Add (Type_Node'(Kind => TCon_T, Con => Int_TC,
                             Refine => Refinement_Id (R)));
      begin
         Check (M.Info (R).Lo = 0 and then M.Info (R).Hi = 100,
                "refinement bounds are stored");
         Check_Equal
           (AHC.Core.Printer.Type_Image (M, Table, T),
            "(tcon Int in 0 .. 100)", "refined type image");

         --  Stage 2: predicate refinements name a hidden binder.
         declare
            PV : constant Real_Var_Id :=
              M.Mint_Var ((Name => Table.Intern ("$pred"),
                           Is_Global => True, others => <>));
            PR : constant Real_Refinement_Id :=
              M.Add (Refinement_Info'
                (Kind => Pred_R, Pred_Var => PV,
                 P_Name => AHC.Names.Name_Id (Table.Intern ("even"))));
            PT : constant Real_Type_Id :=
              M.Add (Type_Node'(Kind => TCon_T, Con => Int_TC,
                                Refine => Refinement_Id (PR)));
         begin
            Check (M.Info (PR).Pred_Var = PV,
                   "predicate refinement stores its binder");
            Check_Equal
              (AHC.Core.Printer.Type_Image (M, Table, PT),
               "(tcon Int satisfying even)",
               "predicate refined type image");
         end;

         --  Stage 3: modular refinements store the modulus.
         declare
            MR : constant Real_Refinement_Id :=
              M.Add (Refinement_Info'(Kind => Mod_R, Modulus => 12));
            MT : constant Real_Type_Id :=
              M.Add (Type_Node'(Kind => TCon_T, Con => Int_TC,
                                Refine => Refinement_Id (MR)));
         begin
            Check (M.Info (MR).Modulus = 12,
                   "modular refinement stores its modulus");
            Check_Equal
              (AHC.Core.Printer.Type_Image (M, Table, MT),
               "(tcon Int mod 12)", "modular type image");
         end;

         --  Stage 4: Double ranges keep their bound lexemes.
         declare
            DBL_TC : constant Real_TyCon_Id :=
              M.Mint_TyCon ((Name => Table.Intern ("Double"),
                             Arity => 0, TC_Kind => M.Star,
                             others => <>));
            FR : constant Real_Refinement_Id :=
              M.Add (Refinement_Info'
                (Kind => FRange_R, FLo_Neg => True, FHi_Neg => False,
                 FLo_Text => AHC.Names.Name_Id (Table.Intern ("90.0")),
                 FHi_Text => AHC.Names.Name_Id
                               (Table.Intern ("90.0"))));
            FT : constant Real_Type_Id :=
              M.Add (Type_Node'(Kind => TCon_T, Con => DBL_TC,
                                Refine => Refinement_Id (FR)));
         begin
            Check (M.Info (FR).FLo_Neg and then not M.Info (FR).FHi_Neg,
                   "float range keeps bound signs");
            Check_Equal
              (AHC.Core.Printer.Type_Image (M, Table, FT),
               "(tcon Double in -90.0 .. 90.0)",
               "float range type image");
         end;
      end;
   end Run;

end Test_Core;
