--  The untyped abstract syntax tree, PRD 4.2: arena vectors of
--  discriminated variant records addressed by distinct integer id
--  newtypes. A Pat_Id can never index the expression arena - category
--  confusion is a compile-time error - and node addition is guarded by
--  Well_Formed preconditions (child ids in range, a Let has at least
--  one binding, a Case at least one alternative, ...). One Module_Arena
--  owns every node of one module; dropping it frees the whole tree.

with Ada.Containers.Vectors;

with AHC.Diagnostics;
with AHC.Names;

package AHC.Syntax is

   use type Names.Name_Id;

   --  A possibly-qualified name occurrence.
   type QName is record
      Name      : Names.Name_Id := Names.No_Name;
      Qualifier : Names.Name_Id := Names.No_Name;
   end record;

   No_QName : constant QName := (others => <>);

   package QName_Vectors is new Ada.Containers.Vectors (Positive, QName);

   ---------------------------------------------------------------------
   --  Ids (0 = absent)
   ---------------------------------------------------------------------

   type Expr_Id is new Natural;
   type Pat_Id  is new Natural;
   type Type_Id is new Natural;
   type Decl_Id is new Natural;
   type Alt_Id  is new Natural;
   type Stmt_Id is new Natural;
   type Con_Id  is new Natural;

   No_Expr : constant Expr_Id := 0;
   No_Type : constant Type_Id := 0;

   subtype Real_Expr_Id is Expr_Id range 1 .. Expr_Id'Last;
   subtype Real_Pat_Id  is Pat_Id  range 1 .. Pat_Id'Last;
   subtype Real_Type_Id is Type_Id range 1 .. Type_Id'Last;
   subtype Real_Decl_Id is Decl_Id range 1 .. Decl_Id'Last;
   subtype Real_Alt_Id  is Alt_Id  range 1 .. Alt_Id'Last;
   subtype Real_Stmt_Id is Stmt_Id range 1 .. Stmt_Id'Last;
   subtype Real_Con_Id  is Con_Id  range 1 .. Con_Id'Last;

   package Expr_Id_Vectors is new Ada.Containers.Vectors
     (Positive, Real_Expr_Id);
   package Pat_Id_Vectors  is new Ada.Containers.Vectors
     (Positive, Real_Pat_Id);
   package Type_Id_Vectors is new Ada.Containers.Vectors
     (Positive, Real_Type_Id);
   package Decl_Id_Vectors is new Ada.Containers.Vectors
     (Positive, Real_Decl_Id);
   package Alt_Id_Vectors  is new Ada.Containers.Vectors
     (Positive, Real_Alt_Id);
   package Stmt_Id_Vectors is new Ada.Containers.Vectors
     (Positive, Real_Stmt_Id);
   package Con_Id_Vectors  is new Ada.Containers.Vectors
     (Positive, Real_Con_Id);

   ---------------------------------------------------------------------
   --  Shared small structures
   ---------------------------------------------------------------------

   --  One operator occurrence inside a not-yet-resolved chain.
   type Op_Occ is record
      Op        : QName;
      Is_Con    : Boolean := False;        --  consym / backticked conid
      --  Report 3.4: the operand after this operator is prefixed with
      --  unary minus ("a + -b"); resolved at precedence 6 by AHC.Fixity.
      Neg_After : Boolean := False;
      Span      : Diagnostics.Source_Span;
   end record;

   package Op_Occ_Vectors is new Ada.Containers.Vectors (Positive, Op_Occ);

   type Guarded_Rhs is record
      Guard : Real_Expr_Id;
      G_Body : Real_Expr_Id;
   end record;

   package Guarded_Rhs_Vectors is new Ada.Containers.Vectors
     (Positive, Guarded_Rhs);

   --  Right-hand side of a binding or case alternative.
   type Rhs (Guarded : Boolean := False) is record
      case Guarded is
         when False => Plain  : Expr_Id := No_Expr;
         when True  => Guards : Guarded_Rhs_Vectors.Vector;
      end case;
   end record;

   type Field_Assign is record
      Field : QName;
      Value : Real_Expr_Id;
   end record;

   package Field_Assign_Vectors is new Ada.Containers.Vectors
     (Positive, Field_Assign);

   type Field_Pat is record
      Field : QName;
      Value : Real_Pat_Id;
   end record;

   package Field_Pat_Vectors is new Ada.Containers.Vectors
     (Positive, Field_Pat);

   ---------------------------------------------------------------------
   --  Expressions
   ---------------------------------------------------------------------

   type Expr_Kind is
     (Var_E, Con_E,
      Lit_Int_E, Lit_Float_E, Lit_Char_E, Lit_String_E,
      App_E, Op_Chain_E, Neg_E,
      Lambda_E, Let_E, If_E, Case_E, Do_E,
      Tuple_E, List_E,
      Arith_Seq_E,       --  [from [, then] .. [to]]
      List_Comp_E,
      Left_Section_E, Right_Section_E,
      Sig_E,
      Rec_Con_E, Rec_Update_E);

   type Expr_Node (Kind : Expr_Kind := Var_E) is record
      Span : Diagnostics.Source_Span;
      case Kind is
         when Var_E | Con_E =>
            Name : QName;
         when Lit_Int_E | Lit_Float_E | Lit_String_E =>
            Text : Names.Name_Id;      --  literal payload (lexeme/decoded)
         when Lit_Char_E =>
            Char_Value : Natural;
         when App_E =>
            Fun : Real_Expr_Id;
            Arg : Real_Expr_Id;
         when Op_Chain_E =>
            Operands  : Expr_Id_Vectors.Vector;
            Operators : Op_Occ_Vectors.Vector;
            --  Leading unary minus applies to Operands (1).
            Neg_First : Boolean := False;
         when Neg_E =>
            Negated : Real_Expr_Id;
         when Lambda_E =>
            L_Pats : Pat_Id_Vectors.Vector;
            L_Body : Real_Expr_Id;
         when Let_E =>
            Binds    : Decl_Id_Vectors.Vector;
            Let_Body : Real_Expr_Id;
         when If_E =>
            Cond, Then_E, Else_E : Real_Expr_Id;
         when Case_E =>
            Scrutinee : Real_Expr_Id;
            Alts      : Alt_Id_Vectors.Vector;
         when Do_E =>
            Stmts : Stmt_Id_Vectors.Vector;
         when Tuple_E | List_E =>
            Items : Expr_Id_Vectors.Vector;
         when Arith_Seq_E =>
            Seq_From : Real_Expr_Id;
            Seq_Then : Expr_Id := No_Expr;
            Seq_To   : Expr_Id := No_Expr;
         when List_Comp_E =>
            Comp_Expr  : Real_Expr_Id;
            Comp_Quals : Stmt_Id_Vectors.Vector;
         when Left_Section_E | Right_Section_E =>
            Sec_Op   : Op_Occ;
            Sec_Expr : Real_Expr_Id;
         when Sig_E =>
            Sig_Expr : Real_Expr_Id;
            Sig_Type : Real_Type_Id;
         when Rec_Con_E | Rec_Update_E =>
            Rec_Base   : Real_Expr_Id;   --  con ref or updated expr
            Rec_Fields : Field_Assign_Vectors.Vector;
      end case;
   end record;

   ---------------------------------------------------------------------
   --  Patterns
   ---------------------------------------------------------------------

   type Pat_Kind is
     (Var_P, Wild_P,
      Lit_Int_P, Lit_Float_P, Lit_Char_P, Lit_String_P,
      Neg_Int_P, Neg_Float_P,
      Con_P, Con_Chain_P,
      Tuple_P, List_P,
      As_P, Lazy_P, Rec_P, Sig_P);

   type Pat_Node (Kind : Pat_Kind := Wild_P) is record
      Span : Diagnostics.Source_Span;
      case Kind is
         when Var_P =>
            Var : Names.Name_Id;
         when Wild_P =>
            null;
         when Lit_Int_P | Lit_Float_P | Lit_String_P
            | Neg_Int_P | Neg_Float_P =>
            Text : Names.Name_Id;
         when Lit_Char_P =>
            Char_Value : Natural;
         when Con_P =>
            Con      : QName;
            Con_Args : Pat_Id_Vectors.Vector;
         when Con_Chain_P =>
            Operands  : Pat_Id_Vectors.Vector;
            Operators : Op_Occ_Vectors.Vector;
         when Tuple_P | List_P =>
            Items : Pat_Id_Vectors.Vector;
         when As_P =>
            As_Var : Names.Name_Id;
            As_Pat : Real_Pat_Id;
         when Lazy_P =>
            Lazy_Pat : Real_Pat_Id;
         when Rec_P =>
            Rec_Con    : QName;
            Rec_Fields : Field_Pat_Vectors.Vector;
         when Sig_P =>
            Sig_Pat  : Real_Pat_Id;
            Sig_Type : Real_Type_Id;
      end case;
   end record;

   ---------------------------------------------------------------------
   --  Types
   ---------------------------------------------------------------------

   type Type_Kind is
     (Var_T, Con_T, App_T, Fun_T, List_T, Tuple_T, Qual_T, Refined_T);

   type Type_Node (Kind : Type_Kind := Var_T) is record
      Span : Diagnostics.Source_Span;
      case Kind is
         when Var_T =>
            Var : Names.Name_Id;
         when Con_T =>
            Con : QName;    --  including (), [], (->), (,) ...
         when App_T =>
            Fun : Real_Type_Id;
            Arg : Real_Type_Id;
         when Fun_T =>
            From, To : Real_Type_Id;
         when List_T =>
            Elem : Real_Type_Id;
         when Tuple_T =>
            Items : Type_Id_Vectors.Vector;
         when Qual_T =>
            Context : Type_Id_Vectors.Vector;  --  class assertions
            Q_Body  : Real_Type_Id;
         when Refined_T =>
            --  Refinement-types extension: BASE in LO .. HI, with
            --  integer-literal bounds (texts as lexed, sign split off).
            R_Base  : Real_Type_Id;
            Lo_Neg  : Boolean := False;
            Hi_Neg  : Boolean := False;
            Lo_Text : Names.Name_Id;
            Hi_Text : Names.Name_Id;
      end case;
   end record;

   ---------------------------------------------------------------------
   --  Case alternatives and statements
   ---------------------------------------------------------------------

   type Alt_Node is record
      Span      : Diagnostics.Source_Span;
      Pat       : Real_Pat_Id;
      Alt_Rhs   : Rhs;
      Where_Ds  : Decl_Id_Vectors.Vector;
   end record;

   type Stmt_Kind is (Bind_S, Let_S, Expr_S);

   type Stmt_Node (Kind : Stmt_Kind := Expr_S) is record
      Span : Diagnostics.Source_Span;
      case Kind is
         when Bind_S =>
            Bind_Pat  : Real_Pat_Id;
            Bind_Expr : Real_Expr_Id;
         when Let_S =>
            Let_Binds : Decl_Id_Vectors.Vector;
         when Expr_S =>
            Expr : Real_Expr_Id;
      end case;
   end record;

   ---------------------------------------------------------------------
   --  Data constructor declarations
   ---------------------------------------------------------------------

   type Field_Decl is record
      Names_List : QName_Vectors.Vector;   --  field names (unqualified)
      Field_Type : Real_Type_Id;
      Strict     : Boolean := False;
   end record;

   package Field_Decl_Vectors is new Ada.Containers.Vectors
     (Positive, Field_Decl);

   package Boolean_Vectors is new Ada.Containers.Vectors
     (Positive, Boolean);

   type Con_Shape is (Prefix_Con, Infix_Con, Record_Con);

   type Con_Node (Shape : Con_Shape := Prefix_Con) is record
      Span : Diagnostics.Source_Span;
      Name : QName;
      case Shape is
         when Prefix_Con | Infix_Con =>
            Args    : Type_Id_Vectors.Vector;
            Stricts : Boolean_Vectors.Vector;   --  parallel to Args
         when Record_Con =>
            Fields : Field_Decl_Vectors.Vector;
      end case;
   end record;

   ---------------------------------------------------------------------
   --  Declarations
   ---------------------------------------------------------------------

   type Assoc_Kind is (Assoc_None, Assoc_Left, Assoc_Right);

   type Decl_Kind is
     (Sig_D, Fixity_D, Fun_D, Pat_D,
      Data_D, Newtype_D, Type_Syn_D,
      Class_D, Instance_D, Default_D);

   type Decl_Node (Kind : Decl_Kind := Pat_D) is record
      Span : Diagnostics.Source_Span;
      case Kind is
         when Sig_D =>
            Sig_Names : QName_Vectors.Vector;
            Sig_Type  : Real_Type_Id;
         when Fixity_D =>
            Assoc : Assoc_Kind;
            Prec  : Natural range 0 .. 9 := 9;
            Ops   : QName_Vectors.Vector;
         when Fun_D =>
            Fun_Name  : Names.Name_Id;
            Fun_Pats  : Pat_Id_Vectors.Vector;   --  one equation
            Fun_Rhs   : Rhs;
            Fun_Where : Decl_Id_Vectors.Vector;
         when Pat_D =>
            Pat       : Real_Pat_Id;
            Pat_Rhs   : Rhs;
            Pat_Where : Decl_Id_Vectors.Vector;
         when Data_D | Newtype_D =>
            D_Context  : Type_Id_Vectors.Vector;
            D_Name     : Names.Name_Id;
            D_Vars     : QName_Vectors.Vector;    --  type variables
            D_Cons     : Con_Id_Vectors.Vector;
            D_Deriving : QName_Vectors.Vector;
         when Type_Syn_D =>
            S_Name : Names.Name_Id;
            S_Vars : QName_Vectors.Vector;
            S_Rhs  : Real_Type_Id;
         when Class_D =>
            C_Context : Type_Id_Vectors.Vector;
            C_Name    : Names.Name_Id;
            C_Var     : Names.Name_Id;
            C_Decls   : Decl_Id_Vectors.Vector;
         when Instance_D =>
            I_Context : Type_Id_Vectors.Vector;
            I_Class   : QName;
            I_Type    : Real_Type_Id;
            I_Decls   : Decl_Id_Vectors.Vector;
         when Default_D =>
            Def_Types : Type_Id_Vectors.Vector;
      end case;
   end record;

   ---------------------------------------------------------------------
   --  Module header
   ---------------------------------------------------------------------

   type Entity_Kind is (Var_Ent, Type_Ent, Module_Ent);

   --  An export- or import-list item: f, T, T(..), T(a, B), module M.
   type Entity is record
      Kind     : Entity_Kind := Var_Ent;
      Name     : QName;
      Sub_All  : Boolean := False;           --  T(..)
      Subs     : QName_Vectors.Vector;       --  T(a, B)
      Has_Subs : Boolean := False;           --  distinguishes T from T()
   end record;

   package Entity_Vectors is new Ada.Containers.Vectors (Positive, Entity);

   type Import_Decl is record
      Span      : Diagnostics.Source_Span;
      Module    : Names.Name_Id := Names.No_Name;  --  dotted, interned
      Qualified : Boolean := False;
      Alias     : Names.Name_Id := Names.No_Name;
      Has_Spec  : Boolean := False;
      Hiding    : Boolean := False;
      Spec      : Entity_Vectors.Vector;
   end record;

   package Import_Vectors is new Ada.Containers.Vectors
     (Positive, Import_Decl);

   ---------------------------------------------------------------------
   --  The arena
   ---------------------------------------------------------------------

   package Expr_Node_Vectors is new Ada.Containers.Vectors
     (Real_Expr_Id, Expr_Node);
   package Pat_Node_Vectors is new Ada.Containers.Vectors
     (Real_Pat_Id, Pat_Node);
   package Type_Node_Vectors is new Ada.Containers.Vectors
     (Real_Type_Id, Type_Node);
   package Decl_Node_Vectors is new Ada.Containers.Vectors
     (Real_Decl_Id, Decl_Node);
   package Alt_Node_Vectors is new Ada.Containers.Vectors
     (Real_Alt_Id, Alt_Node);
   package Stmt_Node_Vectors is new Ada.Containers.Vectors
     (Real_Stmt_Id, Stmt_Node);
   package Con_Node_Vectors is new Ada.Containers.Vectors
     (Real_Con_Id, Con_Node);

   type Module_Arena is tagged limited record
      Has_Header      : Boolean := False;
      Module_Name     : Names.Name_Id := Names.No_Name;
      Has_Export_List : Boolean := False;
      Exports         : Entity_Vectors.Vector;
      Imports         : Import_Vectors.Vector;
      Top_Decls       : Decl_Id_Vectors.Vector;

      Exprs : Expr_Node_Vectors.Vector;
      Pats  : Pat_Node_Vectors.Vector;
      Types : Type_Node_Vectors.Vector;
      Decls : Decl_Node_Vectors.Vector;
      Alts  : Alt_Node_Vectors.Vector;
      Stmts : Stmt_Node_Vectors.Vector;
      Cons  : Con_Node_Vectors.Vector;
   end record;

   function Last_Expr (A : Module_Arena) return Expr_Id
   is (if A.Exprs.Is_Empty then No_Expr else A.Exprs.Last_Index);
   function Last_Pat (A : Module_Arena) return Pat_Id
   is (if A.Pats.Is_Empty then 0 else A.Pats.Last_Index);
   function Last_Type (A : Module_Arena) return Type_Id
   is (if A.Types.Is_Empty then No_Type else A.Types.Last_Index);
   function Last_Decl (A : Module_Arena) return Decl_Id
   is (if A.Decls.Is_Empty then 0 else A.Decls.Last_Index);
   function Last_Alt (A : Module_Arena) return Alt_Id
   is (if A.Alts.Is_Empty then 0 else A.Alts.Last_Index);
   function Last_Stmt (A : Module_Arena) return Stmt_Id
   is (if A.Stmts.Is_Empty then 0 else A.Stmts.Last_Index);
   function Last_Con (A : Module_Arena) return Con_Id
   is (if A.Cons.Is_Empty then 0 else A.Cons.Last_Index);

   ---------------------------------------------------------------------
   --  Well-formedness: every child id already in the arena, plus the
   --  PRD's structural invariants (nonempty Let bindings, nonempty
   --  Case alternatives, nonempty lambda patterns, chain arities).
   ---------------------------------------------------------------------

   function Well_Formed (A : Module_Arena; N : Expr_Node) return Boolean;
   function Well_Formed (A : Module_Arena; N : Pat_Node) return Boolean;
   function Well_Formed (A : Module_Arena; N : Type_Node) return Boolean;
   function Well_Formed (A : Module_Arena; N : Decl_Node) return Boolean;
   function Well_Formed (A : Module_Arena; N : Alt_Node) return Boolean;
   function Well_Formed (A : Module_Arena; N : Stmt_Node) return Boolean;
   function Well_Formed (A : Module_Arena; N : Con_Node) return Boolean;

   function Add (A : in out Module_Arena; N : Expr_Node) return Real_Expr_Id
     with Pre  => A.Well_Formed (N),
          Post => Add'Result = A.Last_Expr;
   function Add (A : in out Module_Arena; N : Pat_Node) return Real_Pat_Id
     with Pre  => A.Well_Formed (N),
          Post => Add'Result = A.Last_Pat;
   function Add (A : in out Module_Arena; N : Type_Node) return Real_Type_Id
     with Pre  => A.Well_Formed (N),
          Post => Add'Result = A.Last_Type;
   function Add (A : in out Module_Arena; N : Decl_Node) return Real_Decl_Id
     with Pre  => A.Well_Formed (N),
          Post => Add'Result = A.Last_Decl;
   function Add (A : in out Module_Arena; N : Alt_Node) return Real_Alt_Id
     with Pre  => A.Well_Formed (N),
          Post => Add'Result = A.Last_Alt;
   function Add (A : in out Module_Arena; N : Stmt_Node) return Real_Stmt_Id
     with Pre  => A.Well_Formed (N),
          Post => Add'Result = A.Last_Stmt;
   function Add (A : in out Module_Arena; N : Con_Node) return Real_Con_Id
     with Pre  => A.Well_Formed (N),
          Post => Add'Result = A.Last_Con;

   --  Checked accessors.
   function Node (A : Module_Arena; Id : Real_Expr_Id) return Expr_Node
     with Pre => Id <= A.Last_Expr;
   function Node (A : Module_Arena; Id : Real_Pat_Id) return Pat_Node
     with Pre => Id <= A.Last_Pat;
   function Node (A : Module_Arena; Id : Real_Type_Id) return Type_Node
     with Pre => Id <= A.Last_Type;
   function Node (A : Module_Arena; Id : Real_Decl_Id) return Decl_Node
     with Pre => Id <= A.Last_Decl;
   function Node (A : Module_Arena; Id : Real_Alt_Id) return Alt_Node
     with Pre => Id <= A.Last_Alt;
   function Node (A : Module_Arena; Id : Real_Stmt_Id) return Stmt_Node
     with Pre => Id <= A.Last_Stmt;
   function Node (A : Module_Arena; Id : Real_Con_Id) return Con_Node
     with Pre => Id <= A.Last_Con;

end AHC.Syntax;
