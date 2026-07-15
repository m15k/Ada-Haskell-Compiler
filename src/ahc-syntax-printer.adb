with Ada.Strings.Unbounded;

package body AHC.Syntax.Printer is

   function Dump
     (A : Module_Arena; Table : Names.Name_Table) return String
   is
      use Ada.Strings.Unbounded;

      Out_Buf : Unbounded_String;

      function QN (Q : QName) return String
      is (if Q.Name = Names.No_Name then "?"
          elsif Q.Qualifier = Names.No_Name then Table.Text (Q.Name)
          else Table.Text (Q.Qualifier) & "." & Table.Text (Q.Name));

      function NM (N : Names.Name_Id) return String
      is (if N = Names.No_Name then "?" else Table.Text (N));

      function Img (N : Natural) return String is
         S : constant String := N'Image;
      begin
         return S (2 .. S'Last);
      end Img;

      function Expr_S (Id : Real_Expr_Id) return String;
      function Pat_S (Id : Real_Pat_Id) return String;
      function Type_S (Id : Real_Type_Id) return String;
      function Decl_S (Id : Real_Decl_Id) return String;
      function Stmt_S (Id : Real_Stmt_Id) return String;

      function Op_S (O : Op_Occ) return String is (QN (O.Op));

      function Exprs_S (V : Expr_Id_Vectors.Vector) return String is
         R : Unbounded_String;
      begin
         for Id of V loop
            Append (R, " " & Expr_S (Id));
         end loop;
         return To_String (R);
      end Exprs_S;

      function Pats_S (V : Pat_Id_Vectors.Vector) return String is
         R : Unbounded_String;
      begin
         for Id of V loop
            Append (R, " " & Pat_S (Id));
         end loop;
         return To_String (R);
      end Pats_S;

      function Types_S (V : Type_Id_Vectors.Vector) return String is
         R : Unbounded_String;
      begin
         for Id of V loop
            Append (R, " " & Type_S (Id));
         end loop;
         return To_String (R);
      end Types_S;

      function Decls_S (V : Decl_Id_Vectors.Vector) return String is
         R : Unbounded_String;
      begin
         for Id of V loop
            Append (R, " " & Decl_S (Id));
         end loop;
         return To_String (R);
      end Decls_S;

      function Stmts_S (V : Stmt_Id_Vectors.Vector) return String is
         R : Unbounded_String;
      begin
         for Id of V loop
            Append (R, " " & Stmt_S (Id));
         end loop;
         return To_String (R);
      end Stmts_S;

      function QNs_S (V : QName_Vectors.Vector) return String is
         R : Unbounded_String;
      begin
         for Q of V loop
            Append (R, " " & QN (Q));
         end loop;
         return To_String (R);
      end QNs_S;

      function Rhs_S (R : Rhs) return String is
         Buf : Unbounded_String;
      begin
         if R.Guarded then
            Append (Buf, "(guards");
            for G of R.Guards loop
               Append
                 (Buf, " (" & Expr_S (G.Guard) & " " & Expr_S (G.G_Body)
                       & ")");
            end loop;
            Append (Buf, ")");
            return To_String (Buf);
         else
            return Expr_S (R.Plain);
         end if;
      end Rhs_S;

      function Where_S (V : Decl_Id_Vectors.Vector) return String
      is (if V.Is_Empty then ""
          else " (where" & Decls_S (V) & ")");

      function Chain_S
        (Operands : Expr_Id_Vectors.Vector;
         Operators : Op_Occ_Vectors.Vector;
         Neg_First : Boolean) return String
      is
         R : Unbounded_String;
      begin
         Append (R, "(opchain ");
         Append (R, (if Neg_First then "(neg " & Expr_S (Operands (1)) & ")"
                     else Expr_S (Operands (1))));
         for I in 1 .. Operators.Last_Index loop
            Append (R, " " & Op_S (Operators (I)) & " "
                       & Expr_S (Operands (I + 1)));
         end loop;
         Append (R, ")");
         return To_String (R);
      end Chain_S;

      function Expr_S (Id : Real_Expr_Id) return String is
         N : constant Expr_Node := A.Node (Id);
      begin
         case N.Kind is
            when Var_E => return "(var " & QN (N.Name) & ")";
            when Con_E => return "(con " & QN (N.Name) & ")";
            when Lit_Int_E => return "(int " & NM (N.Text) & ")";
            when Lit_Float_E => return "(float " & NM (N.Text) & ")";
            when Lit_Char_E => return "(char " & Img (N.Char_Value) & ")";
            when Lit_String_E =>
               return "(str """
                 & (if N.Text = Names.No_Name then ""
                    else Table.Text (N.Text)) & """)";
            when App_E =>
               return "(app " & Expr_S (N.Fun) & " " & Expr_S (N.Arg) & ")";
            when Op_Chain_E =>
               return Chain_S (N.Operands, N.Operators, N.Neg_First);
            when Neg_E => return "(neg " & Expr_S (N.Negated) & ")";
            when Lambda_E =>
               return "(lam (pats" & Pats_S (N.L_Pats) & ") "
                 & Expr_S (N.L_Body) & ")";
            when Let_E =>
               return "(let (binds" & Decls_S (N.Binds) & ") "
                 & Expr_S (N.Let_Body) & ")";
            when If_E =>
               return "(if " & Expr_S (N.Cond) & " " & Expr_S (N.Then_E)
                 & " " & Expr_S (N.Else_E) & ")";
            when Case_E =>
               declare
                  R : Unbounded_String;
               begin
                  Append (R, "(case " & Expr_S (N.Scrutinee));
                  for Alt_Id of N.Alts loop
                     declare
                        Alt : constant Alt_Node := A.Node (Alt_Id);
                     begin
                        Append (R, " (alt " & Pat_S (Alt.Pat) & " "
                                   & Rhs_S (Alt.Alt_Rhs)
                                   & Where_S (Alt.Where_Ds) & ")");
                     end;
                  end loop;
                  Append (R, ")");
                  return To_String (R);
               end;
            when Do_E =>
               return "(do" & Stmts_S (N.Stmts) & ")";
            when Tuple_E =>
               return "(tuple" & Exprs_S (N.Items) & ")";
            when List_E =>
               return "(list" & Exprs_S (N.Items) & ")";
            when Arith_Seq_E =>
               return "(range " & Expr_S (N.Seq_From)
                 & (if N.Seq_Then /= No_Expr
                    then " then " & Expr_S (N.Seq_Then) else "")
                 & (if N.Seq_To /= No_Expr
                    then " to " & Expr_S (N.Seq_To) else "")
                 & ")";
            when List_Comp_E =>
               return "(comp " & Expr_S (N.Comp_Expr)
                 & Stmts_S (N.Comp_Quals) & ")";
            when Left_Section_E =>
               return "(lsec " & Expr_S (N.Sec_Expr) & " "
                 & Op_S (N.Sec_Op) & ")";
            when Right_Section_E =>
               return "(rsec " & Op_S (N.Sec_Op) & " "
                 & Expr_S (N.Sec_Expr) & ")";
            when Sig_E =>
               return "(sig " & Expr_S (N.Sig_Expr) & " "
                 & Type_S (N.Sig_Type) & ")";
            when Rec_Con_E | Rec_Update_E =>
               declare
                  R : Unbounded_String;
               begin
                  Append (R, (if N.Kind = Rec_Con_E
                              then "(reccon " else "(recupd "));
                  Append (R, Expr_S (N.Rec_Base));
                  for F of N.Rec_Fields loop
                     Append (R, " (" & QN (F.Field) & " "
                                & Expr_S (F.Value) & ")");
                  end loop;
                  Append (R, ")");
                  return To_String (R);
               end;
         end case;
      end Expr_S;

      function Pat_S (Id : Real_Pat_Id) return String is
         N : constant Pat_Node := A.Node (Id);
      begin
         case N.Kind is
            when Var_P => return "(pvar " & NM (N.Var) & ")";
            when Wild_P => return "(pwild)";
            when Lit_Int_P => return "(pint " & NM (N.Text) & ")";
            when Lit_Float_P => return "(pfloat " & NM (N.Text) & ")";
            when Lit_String_P => return "(pstr """ & NM (N.Text) & """)";
            when Lit_Char_P => return "(pchar " & Img (N.Char_Value) & ")";
            when Neg_Int_P => return "(pint -" & NM (N.Text) & ")";
            when Neg_Float_P => return "(pfloat -" & NM (N.Text) & ")";
            when Con_P =>
               return "(pcon " & QN (N.Con) & Pats_S (N.Con_Args) & ")";
            when Con_Chain_P =>
               declare
                  R : Unbounded_String;
               begin
                  Append (R, "(pchain " & Pat_S (N.Operands (1)));
                  for I in 1 .. N.Operators.Last_Index loop
                     Append (R, " " & Op_S (N.Operators (I)) & " "
                                & Pat_S (N.Operands (I + 1)));
                  end loop;
                  Append (R, ")");
                  return To_String (R);
               end;
            when Tuple_P => return "(ptuple" & Pats_S (N.Items) & ")";
            when List_P => return "(plist" & Pats_S (N.Items) & ")";
            when As_P =>
               return "(pas " & NM (N.As_Var) & " "
                 & Pat_S (N.As_Pat) & ")";
            when Lazy_P => return "(plazy " & Pat_S (N.Lazy_Pat) & ")";
            when Rec_P =>
               declare
                  R : Unbounded_String;
               begin
                  Append (R, "(prec " & QN (N.Rec_Con));
                  for F of N.Rec_Fields loop
                     Append (R, " (" & QN (F.Field) & " "
                                & Pat_S (F.Value) & ")");
                  end loop;
                  Append (R, ")");
                  return To_String (R);
               end;
            when Sig_P =>
               return "(psig " & Pat_S (N.Sig_Pat) & " "
                 & Type_S (N.Sig_Type) & ")";
         end case;
      end Pat_S;

      function Type_S (Id : Real_Type_Id) return String is
         N : constant Type_Node := A.Node (Id);
      begin
         case N.Kind is
            when Var_T => return "(tvar " & NM (N.Var) & ")";
            when Con_T => return "(tcon " & QN (N.Con) & ")";
            when App_T =>
               return "(tap " & Type_S (N.Fun) & " " & Type_S (N.Arg) & ")";
            when Fun_T =>
               return "(-> " & Type_S (N.From) & " " & Type_S (N.To) & ")";
            when List_T => return "(tlist " & Type_S (N.Elem) & ")";
            when Tuple_T => return "(ttuple" & Types_S (N.Items) & ")";
            when Qual_T =>
               return "(ctx (" & Types_S (N.Context) & ") "
                 & Type_S (N.Q_Body) & ")";
            when Refined_T =>
               return "(refined " & Type_S (N.R_Base) & " "
                 & (if N.Lo_Neg then "-" else "") & NM (N.Lo_Text) & " "
                 & (if N.Hi_Neg then "-" else "") & NM (N.Hi_Text) & ")";
            when Pred_T =>
               return "(satisfying " & Type_S (N.P_Base) & " "
                 & Expr_S (N.P_Expr) & ")";
         end case;
      end Type_S;

      function Stmt_S (Id : Real_Stmt_Id) return String is
         N : constant Stmt_Node := A.Node (Id);
      begin
         case N.Kind is
            when Bind_S =>
               return "(bind " & Pat_S (N.Bind_Pat) & " "
                 & Expr_S (N.Bind_Expr) & ")";
            when Let_S =>
               return "(letstmt" & Decls_S (N.Let_Binds) & ")";
            when Syntax.Expr_S =>
               return Expr_S (N.Expr);
         end case;
      end Stmt_S;

      function Con_S (Id : Real_Con_Id) return String is
         N : constant Con_Node := A.Node (Id);
         R : Unbounded_String;
      begin
         case N.Shape is
            when Prefix_Con | Infix_Con =>
               Append (R, (if N.Shape = Prefix_Con
                           then "(con " else "(infixcon ") & QN (N.Name));
               for I in 1 .. N.Args.Last_Index loop
                  Append (R, " " & (if N.Stricts (I) then "!" else "")
                             & Type_S (N.Args (I)));
               end loop;
            when Record_Con =>
               Append (R, "(reccon " & QN (N.Name));
               for F of N.Fields loop
                  Append (R, " ((" & QNs_S (F.Names_List) & " )"
                             & (if F.Strict then " !" else " ")
                             & Type_S (F.Field_Type) & ")");
               end loop;
         end case;
         Append (R, ")");
         return To_String (R);
      end Con_S;

      function Decl_S (Id : Real_Decl_Id) return String is
         N : constant Decl_Node := A.Node (Id);
         R : Unbounded_String;
      begin
         case N.Kind is
            when Sig_D =>
               return "(sig (" & QNs_S (N.Sig_Names) & " ) "
                 & Type_S (N.Sig_Type) & ")";
            when Fixity_D =>
               return "("
                 & (case N.Assoc is
                      when Assoc_None  => "infix",
                      when Assoc_Left  => "infixl",
                      when Assoc_Right => "infixr")
                 & " " & Img (N.Prec) & QNs_S (N.Ops) & ")";
            when Fun_D =>
               return "(fun " & NM (N.Fun_Name)
                 & " (pats" & Pats_S (N.Fun_Pats) & ") "
                 & Rhs_S (N.Fun_Rhs) & Where_S (N.Fun_Where) & ")";
            when Pat_D =>
               return "(patbind " & Pat_S (N.Pat) & " "
                 & Rhs_S (N.Pat_Rhs) & Where_S (N.Pat_Where) & ")";
            when Data_D | Newtype_D =>
               Append (R, (if N.Kind = Data_D
                           then "(data " else "(newtype "));
               if not N.D_Context.Is_Empty then
                  Append (R, "(ctx" & Types_S (N.D_Context) & ") ");
               end if;
               Append (R, NM (N.D_Name) & " (vars" & QNs_S (N.D_Vars)
                          & ") (cons");
               for C of N.D_Cons loop
                  Append (R, " " & Con_S (C));
               end loop;
               Append (R, ")");
               if not N.D_Deriving.Is_Empty then
                  Append (R, " (deriving" & QNs_S (N.D_Deriving) & ")");
               end if;
               Append (R, ")");
               return To_String (R);
            when Type_Syn_D =>
               return "(tysyn " & NM (N.S_Name) & " (vars"
                 & QNs_S (N.S_Vars) & ") " & Type_S (N.S_Rhs) & ")";
            when Class_D =>
               Append (R, "(class ");
               if not N.C_Context.Is_Empty then
                  Append (R, "(ctx" & Types_S (N.C_Context) & ") ");
               end if;
               Append (R, NM (N.C_Name) & " " & NM (N.C_Var));
               if not N.C_Decls.Is_Empty then
                  Append (R, " (where" & Decls_S (N.C_Decls) & ")");
               end if;
               Append (R, ")");
               return To_String (R);
            when Instance_D =>
               Append (R, "(instance ");
               if not N.I_Context.Is_Empty then
                  Append (R, "(ctx" & Types_S (N.I_Context) & ") ");
               end if;
               Append (R, QN (N.I_Class) & " " & Type_S (N.I_Type));
               if not N.I_Decls.Is_Empty then
                  Append (R, " (where" & Decls_S (N.I_Decls) & ")");
               end if;
               Append (R, ")");
               return To_String (R);
            when Default_D =>
               return "(default" & Types_S (N.Def_Types) & ")";
         end case;
      end Decl_S;

      function Entity_S (E : Entity) return String is
      begin
         case E.Kind is
            when Module_Ent => return "(module " & QN (E.Name) & ")";
            when Var_Ent => return "(var " & QN (E.Name) & ")";
            when Type_Ent =>
               if E.Sub_All then
                  return "(type " & QN (E.Name) & " (..))";
               elsif E.Has_Subs then
                  return "(type " & QN (E.Name) & " ("
                    & QNs_S (E.Subs) & " ))";
               else
                  return "(type " & QN (E.Name) & ")";
               end if;
         end case;
      end Entity_S;

   begin
      --  Header
      if A.Has_Header then
         Append (Out_Buf, "(module " & NM (A.Module_Name));
         if A.Has_Export_List then
            Append (Out_Buf, " (exports");
            for E of A.Exports loop
               Append (Out_Buf, " " & Entity_S (E));
            end loop;
            Append (Out_Buf, ")");
         end if;
         Append (Out_Buf, ")" & ASCII.LF);
      else
         Append (Out_Buf, "(module)" & ASCII.LF);
      end if;

      for Imp of A.Imports loop
         Append (Out_Buf, "(import " & NM (Imp.Module));
         if Imp.Qualified then
            Append (Out_Buf, " qualified");
         end if;
         if Imp.Alias /= Names.No_Name then
            Append (Out_Buf, " as " & NM (Imp.Alias));
         end if;
         if Imp.Has_Spec then
            Append (Out_Buf,
                    (if Imp.Hiding then " (hiding" else " (spec"));
            for E of Imp.Spec loop
               Append (Out_Buf, " " & Entity_S (E));
            end loop;
            Append (Out_Buf, ")");
         end if;
         Append (Out_Buf, ")" & ASCII.LF);
      end loop;

      for D of A.Top_Decls loop
         Append (Out_Buf, Decl_S (D) & ASCII.LF);
      end loop;

      return To_String (Out_Buf);
   end Dump;

end AHC.Syntax.Printer;
