package body AHC.Syntax is

   use type Ada.Containers.Count_Type;

   ---------------------------------------------------------------------
   --  Validity helpers
   ---------------------------------------------------------------------

   function Ok (A : Module_Arena; Id : Expr_Id) return Boolean
   is (Id <= A.Last_Expr);
   function Ok (A : Module_Arena; Id : Pat_Id) return Boolean
   is (Id <= A.Last_Pat);
   function Ok (A : Module_Arena; Id : Type_Id) return Boolean
   is (Id <= A.Last_Type);
   function Ok (A : Module_Arena; Id : Decl_Id) return Boolean
   is (Id <= A.Last_Decl);
   function Ok (A : Module_Arena; Id : Alt_Id) return Boolean
   is (Id <= A.Last_Alt);
   function Ok (A : Module_Arena; Id : Stmt_Id) return Boolean
   is (Id <= A.Last_Stmt);

   function All_Ok
     (A : Module_Arena; V : Expr_Id_Vectors.Vector) return Boolean
   is (for all Id of V => Ok (A, Id));
   function All_Ok
     (A : Module_Arena; V : Pat_Id_Vectors.Vector) return Boolean
   is (for all Id of V => Ok (A, Id));
   function All_Ok
     (A : Module_Arena; V : Type_Id_Vectors.Vector) return Boolean
   is (for all Id of V => Ok (A, Id));
   function All_Ok
     (A : Module_Arena; V : Decl_Id_Vectors.Vector) return Boolean
   is (for all Id of V => Ok (A, Id));
   function All_Ok
     (A : Module_Arena; V : Alt_Id_Vectors.Vector) return Boolean
   is (for all Id of V => Ok (A, Id));
   function All_Ok
     (A : Module_Arena; V : Stmt_Id_Vectors.Vector) return Boolean
   is (for all Id of V => Ok (A, Id));

   function Rhs_Ok (A : Module_Arena; R : Rhs) return Boolean
   is (if R.Guarded
       then R.Guards.Length >= 1
            and then (for all G of R.Guards =>
                        Ok (A, G.Guard) and then Ok (A, G.G_Body))
       else R.Plain in Real_Expr_Id and then Ok (A, R.Plain));

   ---------------------------------------------------------------------
   --  Well_Formed
   ---------------------------------------------------------------------

   function Well_Formed (A : Module_Arena; N : Expr_Node) return Boolean is
   begin
      case N.Kind is
         when Var_E | Con_E =>
            return N.Name.Name /= Names.No_Name;
         when Lit_Int_E | Lit_Float_E =>
            return N.Text /= Names.No_Name;
         when Lit_String_E | Lit_Char_E =>
            return True;
         when App_E =>
            return Ok (A, N.Fun) and then Ok (A, N.Arg);
         when Op_Chain_E =>
            return N.Operands.Length >= 2
              and then N.Operands.Length = N.Operators.Length + 1
              and then All_Ok (A, N.Operands);
         when Neg_E =>
            return Ok (A, N.Negated);
         when Lambda_E =>
            return N.L_Pats.Length >= 1
              and then All_Ok (A, N.L_Pats) and then Ok (A, N.L_Body);
         when Let_E =>
            --  PRD 4.2: a Let always has at least one declaration.
            return N.Binds.Length >= 1
              and then All_Ok (A, N.Binds) and then Ok (A, N.Let_Body);
         when If_E =>
            return Ok (A, N.Cond) and then Ok (A, N.Then_E)
              and then Ok (A, N.Else_E);
         when Case_E =>
            return N.Alts.Length >= 1
              and then Ok (A, N.Scrutinee) and then All_Ok (A, N.Alts);
         when Do_E =>
            return N.Stmts.Length >= 1 and then All_Ok (A, N.Stmts);
         when Tuple_E =>
            return N.Items.Length >= 2 and then All_Ok (A, N.Items);
         when List_E =>
            return All_Ok (A, N.Items);
         when Arith_Seq_E =>
            return Ok (A, N.Seq_From)
              and then Ok (A, N.Seq_Then) and then Ok (A, N.Seq_To);
         when List_Comp_E =>
            return N.Comp_Quals.Length >= 1
              and then Ok (A, N.Comp_Expr)
              and then All_Ok (A, N.Comp_Quals);
         when Left_Section_E | Right_Section_E =>
            return Ok (A, N.Sec_Expr);
         when Sig_E =>
            return Ok (A, N.Sig_Expr) and then Ok (A, N.Sig_Type);
         when Rec_Con_E | Rec_Update_E =>
            return Ok (A, N.Rec_Base)
              and then (for all F of N.Rec_Fields => Ok (A, F.Value))
              and then (N.Kind = Rec_Con_E
                        or else N.Rec_Fields.Length >= 1);
      end case;
   end Well_Formed;

   function Well_Formed (A : Module_Arena; N : Pat_Node) return Boolean is
   begin
      case N.Kind is
         when Var_P =>
            return N.Var /= Names.No_Name;
         when Wild_P | Lit_Char_P =>
            return True;
         when Lit_Int_P | Lit_Float_P | Lit_String_P
            | Neg_Int_P | Neg_Float_P =>
            return N.Text /= Names.No_Name;
         when Con_P =>
            return N.Con.Name /= Names.No_Name
              and then All_Ok (A, N.Con_Args);
         when Con_Chain_P =>
            return N.Operands.Length >= 2
              and then N.Operands.Length = N.Operators.Length + 1
              and then All_Ok (A, N.Operands);
         when Tuple_P =>
            return N.Items.Length >= 2 and then All_Ok (A, N.Items);
         when List_P =>
            return All_Ok (A, N.Items);
         when As_P =>
            return N.As_Var /= Names.No_Name and then Ok (A, N.As_Pat);
         when Lazy_P =>
            return Ok (A, N.Lazy_Pat);
         when Rec_P =>
            return N.Rec_Con.Name /= Names.No_Name
              and then (for all F of N.Rec_Fields => Ok (A, F.Value));
         when Sig_P =>
            return Ok (A, N.Sig_Pat) and then Ok (A, N.Sig_Type);
      end case;
   end Well_Formed;

   function Well_Formed (A : Module_Arena; N : Type_Node) return Boolean is
   begin
      case N.Kind is
         when Var_T =>
            return N.Var /= Names.No_Name;
         when Con_T =>
            return N.Con.Name /= Names.No_Name;
         when App_T =>
            return Ok (A, N.Fun) and then Ok (A, N.Arg);
         when Fun_T =>
            return Ok (A, N.From) and then Ok (A, N.To);
         when List_T =>
            return Ok (A, N.Elem);
         when Tuple_T =>
            return N.Items.Length >= 2 and then All_Ok (A, N.Items);
         when Qual_T =>
            return All_Ok (A, N.Context) and then Ok (A, N.Q_Body);
         when Refined_T =>
            return Ok (A, N.R_Base)
              and then N.Lo_Text /= Names.No_Name
              and then N.Hi_Text /= Names.No_Name;
      end case;
   end Well_Formed;

   function Well_Formed (A : Module_Arena; N : Decl_Node) return Boolean is
   begin
      case N.Kind is
         when Sig_D =>
            return N.Sig_Names.Length >= 1 and then Ok (A, N.Sig_Type);
         when Fixity_D =>
            return N.Ops.Length >= 1;
         when Fun_D =>
            return N.Fun_Name /= Names.No_Name
              and then N.Fun_Pats.Length >= 1
              and then All_Ok (A, N.Fun_Pats)
              and then Rhs_Ok (A, N.Fun_Rhs)
              and then All_Ok (A, N.Fun_Where);
         when Pat_D =>
            return Ok (A, N.Pat)
              and then Rhs_Ok (A, N.Pat_Rhs)
              and then All_Ok (A, N.Pat_Where);
         when Data_D | Newtype_D =>
            return N.D_Name /= Names.No_Name
              and then All_Ok (A, N.D_Context)
              and then (for all C of N.D_Cons => C <= A.Last_Con)
              and then (N.Kind = Data_D or else N.D_Cons.Length = 1);
         when Type_Syn_D =>
            return N.S_Name /= Names.No_Name and then Ok (A, N.S_Rhs);
         when Class_D =>
            return N.C_Name /= Names.No_Name
              and then N.C_Var /= Names.No_Name
              and then All_Ok (A, N.C_Context)
              and then All_Ok (A, N.C_Decls);
         when Instance_D =>
            return N.I_Class.Name /= Names.No_Name
              and then All_Ok (A, N.I_Context)
              and then Ok (A, N.I_Type)
              and then All_Ok (A, N.I_Decls);
         when Default_D =>
            return All_Ok (A, N.Def_Types);
      end case;
   end Well_Formed;

   function Well_Formed (A : Module_Arena; N : Alt_Node) return Boolean
   is (Ok (A, N.Pat)
       and then Rhs_Ok (A, N.Alt_Rhs)
       and then All_Ok (A, N.Where_Ds));

   function Well_Formed (A : Module_Arena; N : Stmt_Node) return Boolean is
   begin
      case N.Kind is
         when Bind_S =>
            return Ok (A, N.Bind_Pat) and then Ok (A, N.Bind_Expr);
         when Let_S =>
            return N.Let_Binds.Length >= 1
              and then All_Ok (A, N.Let_Binds);
         when Expr_S =>
            return Ok (A, N.Expr);
      end case;
   end Well_Formed;

   function Well_Formed (A : Module_Arena; N : Con_Node) return Boolean is
   begin
      if N.Name.Name = Names.No_Name then
         return False;
      end if;
      case N.Shape is
         when Prefix_Con =>
            return N.Args.Length = N.Stricts.Length
              and then All_Ok (A, N.Args);
         when Infix_Con =>
            return N.Args.Length = 2 and then N.Stricts.Length = 2
              and then All_Ok (A, N.Args);
         when Record_Con =>
            return (for all F of N.Fields =>
                      F.Names_List.Length >= 1
                      and then Ok (A, F.Field_Type));
      end case;
   end Well_Formed;

   ---------------------------------------------------------------------
   --  Add / Node
   ---------------------------------------------------------------------

   function Add (A : in out Module_Arena; N : Expr_Node) return Real_Expr_Id
   is
   begin
      A.Exprs.Append (N);
      return A.Exprs.Last_Index;
   end Add;

   function Add (A : in out Module_Arena; N : Pat_Node) return Real_Pat_Id
   is
   begin
      A.Pats.Append (N);
      return A.Pats.Last_Index;
   end Add;

   function Add (A : in out Module_Arena; N : Type_Node) return Real_Type_Id
   is
   begin
      A.Types.Append (N);
      return A.Types.Last_Index;
   end Add;

   function Add (A : in out Module_Arena; N : Decl_Node) return Real_Decl_Id
   is
   begin
      A.Decls.Append (N);
      return A.Decls.Last_Index;
   end Add;

   function Add (A : in out Module_Arena; N : Alt_Node) return Real_Alt_Id
   is
   begin
      A.Alts.Append (N);
      return A.Alts.Last_Index;
   end Add;

   function Add (A : in out Module_Arena; N : Stmt_Node) return Real_Stmt_Id
   is
   begin
      A.Stmts.Append (N);
      return A.Stmts.Last_Index;
   end Add;

   function Add (A : in out Module_Arena; N : Con_Node) return Real_Con_Id
   is
   begin
      A.Cons.Append (N);
      return A.Cons.Last_Index;
   end Add;

   function Node (A : Module_Arena; Id : Real_Expr_Id) return Expr_Node
   is (A.Exprs (Id));
   function Node (A : Module_Arena; Id : Real_Pat_Id) return Pat_Node
   is (A.Pats (Id));
   function Node (A : Module_Arena; Id : Real_Type_Id) return Type_Node
   is (A.Types (Id));
   function Node (A : Module_Arena; Id : Real_Decl_Id) return Decl_Node
   is (A.Decls (Id));
   function Node (A : Module_Arena; Id : Real_Alt_Id) return Alt_Node
   is (A.Alts (Id));
   function Node (A : Module_Arena; Id : Real_Stmt_Id) return Stmt_Node
   is (A.Stmts (Id));
   function Node (A : Module_Arena; Id : Real_Con_Id) return Con_Node
   is (A.Cons (Id));

end AHC.Syntax;
