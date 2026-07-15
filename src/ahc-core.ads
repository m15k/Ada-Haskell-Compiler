--  The Core intermediate representation (PRD 5.3, Phase 2): a small
--  System-FC-like language the whole middle end works on. Same design
--  as AHC.Syntax: arena vectors of discriminated variant records
--  addressed by distinct id newtypes, node addition guarded by
--  Well_Formed preconditions.
--
--  One Core_Module owns every entity of one compilation: the wired-in
--  Prelude signature installed by AHC.Builtins, the renamer's variable
--  table, and the desugared/elaborated Core bindings.
--
--  Binders are unique integer Var_Ids minted by the renamer, so
--  variable capture is impossible by construction (the property
--  de Bruijn indices buy, without the shift/lift bug class). Types
--  attach to binders in the Var table, not to expressions; every
--  expression's type is synthesizable from its binders.
--
--  Refinement design rules (docs/refinement-types-design-note.md):
--  (1) TCon_T carries an optional Refine slot, reserved and never
--      constructed in Phase 2;
--  (2) type-head equality for unification is Same_Con_Erased, which
--      ignores the Refine slot by definition.

with Ada.Containers.Vectors;

with AHC.Diagnostics;
with AHC.Names;

package AHC.Core is

   use type Names.Name_Id;

   ---------------------------------------------------------------------
   --  Ids (0 = absent)
   ---------------------------------------------------------------------

   type Var_Id      is new Natural;
   type TyCon_Id    is new Natural;
   type DataCon_Id  is new Natural;
   type Class_Id    is new Natural;
   type Instance_Id is new Natural;
   type TyVar_Id    is new Natural;
   type Meta_Id     is new Natural;   --  unification vars; cells live
                                      --  in the typechecker's state
   type Kind_Id     is new Natural;
   type Type_Id     is new Natural;
   type Scheme_Id   is new Natural;
   type Expr_Id     is new Natural;
   type Alt_Id      is new Natural;

   --  Refinement-types extension (docs/refinement-types-design-note.md,
   --  stage 1): a refinement is an inclusive integer range attached to
   --  a scalar TCon. Reserved through Phases 2-4 (design rule 1), now
   --  populated by AHC.Kinds from `Int in LO .. HI` surface types.
   type Refinement_Id is new Natural;
   No_Refinement : constant Refinement_Id := 0;
   subtype Real_Refinement_Id is
     Refinement_Id range 1 .. Refinement_Id'Last;

   type Refinement_Info is record
      Lo, Hi : Long_Long_Integer;
   end record;

   package Refinement_Vectors is new Ada.Containers.Vectors
     (Positive, Refinement_Info);

   No_Var    : constant Var_Id    := 0;
   No_TyCon  : constant TyCon_Id  := 0;
   No_Class  : constant Class_Id  := 0;
   No_Kind   : constant Kind_Id   := 0;
   No_Type   : constant Type_Id   := 0;
   No_Scheme : constant Scheme_Id := 0;
   No_Expr   : constant Expr_Id   := 0;

   subtype Real_Var_Id      is Var_Id      range 1 .. Var_Id'Last;
   subtype Real_TyCon_Id    is TyCon_Id    range 1 .. TyCon_Id'Last;
   subtype Real_DataCon_Id  is DataCon_Id  range 1 .. DataCon_Id'Last;
   subtype Real_Class_Id    is Class_Id    range 1 .. Class_Id'Last;
   subtype Real_Instance_Id is Instance_Id range 1 .. Instance_Id'Last;
   subtype Real_TyVar_Id    is TyVar_Id    range 1 .. TyVar_Id'Last;
   subtype Real_Meta_Id     is Meta_Id     range 1 .. Meta_Id'Last;
   subtype Real_Kind_Id     is Kind_Id     range 1 .. Kind_Id'Last;
   subtype Real_Type_Id     is Type_Id     range 1 .. Type_Id'Last;
   subtype Real_Scheme_Id   is Scheme_Id   range 1 .. Scheme_Id'Last;
   subtype Real_Expr_Id     is Expr_Id     range 1 .. Expr_Id'Last;
   subtype Real_Alt_Id      is Alt_Id      range 1 .. Alt_Id'Last;

   package Var_Id_Vectors is new Ada.Containers.Vectors
     (Positive, Real_Var_Id);
   package DataCon_Id_Vectors is new Ada.Containers.Vectors
     (Positive, Real_DataCon_Id);
   package Class_Id_Vectors is new Ada.Containers.Vectors
     (Positive, Real_Class_Id);
   package Instance_Id_Vectors is new Ada.Containers.Vectors
     (Positive, Real_Instance_Id);
   package TyVar_Id_Vectors is new Ada.Containers.Vectors
     (Positive, Real_TyVar_Id);
   package Type_Id_Vectors is new Ada.Containers.Vectors
     (Positive, Real_Type_Id);
   package Expr_Id_Vectors is new Ada.Containers.Vectors
     (Positive, Real_Expr_Id);
   package Alt_Id_Vectors is new Ada.Containers.Vectors
     (Positive, Real_Alt_Id);
   package Name_Id_Vectors is new Ada.Containers.Vectors
     (Positive, Names.Name_Id);
   package Boolean_Vectors is new Ada.Containers.Vectors
     (Positive, Boolean);

   ---------------------------------------------------------------------
   --  Kinds:  * | k1 -> k2 | kind meta (AHC.Kinds only)
   ---------------------------------------------------------------------

   type Kind_Kind is (Star_K, KFun_K, KMeta_K);

   type Kind_Node (Kind : Kind_Kind := Star_K) is record
      case Kind is
         when Star_K  => null;
         when KFun_K  => KFrom, KTo : Real_Kind_Id;
         when KMeta_K => KMeta : Positive;
      end case;
   end record;

   ---------------------------------------------------------------------
   --  Types
   ---------------------------------------------------------------------

   type Type_Kind is (TVar_T, TMeta_T, TCon_T, TApp_T, TFun_T);

   type Type_Node (Kind : Type_Kind := TCon_T) is record
      case Kind is
         when TVar_T =>
            Tv : Real_TyVar_Id;
         when TMeta_T =>
            Meta : Real_Meta_Id;
         when TCon_T =>
            Con : Real_TyCon_Id;
            --  Range refinement on this occurrence of the TyCon;
            --  No_Refinement for the unrefined base type.
            Refine : Refinement_Id := No_Refinement;
         when TApp_T =>
            T_Fun, T_Arg : Real_Type_Id;
         when TFun_T =>
            From, To : Real_Type_Id;
      end case;
   end record;

   --  Design rule 2: the unifier's constructor-head equality. Compares
   --  the TyCon only and ignores Refine by definition, so types
   --  differing only in refinement annotations always unify.
   function Same_Con_Erased (A, B : Type_Node) return Boolean
   is (A.Kind = TCon_T and then B.Kind = TCon_T
       and then A.Con = B.Con);

   --  A class constraint C t.
   type Constraint is record
      Class : Real_Class_Id;
      Arg   : Real_Type_Id;
      Span  : Diagnostics.Source_Span;
   end record;

   package Constraint_Vectors is new Ada.Containers.Vectors
     (Positive, Constraint);

   --  forall tvs. context => body (the forall is implicit).
   type Scheme is record
      Tvs     : TyVar_Id_Vectors.Vector;
      Context : Constraint_Vectors.Vector;
      S_Body  : Type_Id := No_Type;
   end record;

   ---------------------------------------------------------------------
   --  Entity tables
   ---------------------------------------------------------------------

   type Var_Info is record
      Name      : Names.Name_Id := Names.No_Name;
      Span      : Diagnostics.Source_Span;
      Is_Global : Boolean := False;
      Var_Type  : Type_Id := No_Type;      --  monomorphic type, if known
      Var_Scheme : Scheme_Id := No_Scheme; --  polymorphic, if generalized
      --  Binder came from a surface pattern binding (Report 4.5.5:
      --  the monomorphism restriction applies to its group).
      From_Pattern_Binding : Boolean := False;
   end record;

   type TyVar_Info is record
      Name    : Names.Name_Id := Names.No_Name;
      Tv_Kind : Kind_Id := No_Kind;
   end record;

   type TyCon_Info is record
      Name       : Names.Name_Id := Names.No_Name;
      Arity      : Natural := 0;
      TC_Kind    : Kind_Id := No_Kind;
      Cons       : DataCon_Id_Vectors.Vector;
      Is_Newtype : Boolean := False;
      Is_Builtin : Boolean := False;
   end record;

   type DataCon_Info is record
      Name        : Names.Name_Id := Names.No_Name;
      TyCon       : TyCon_Id := No_TyCon;
      Tag         : Positive := 1;         --  1-based within the TyCon
      Arity       : Natural := 0;
      Field_Names : Name_Id_Vectors.Vector;  --  empty if positional
      Stricts     : Boolean_Vectors.Vector;
      Con_Scheme  : Scheme_Id := No_Scheme;
   end record;

   type Method_Info is record
      Name          : Names.Name_Id := Names.No_Name;
      Method_Scheme : Scheme_Id := No_Scheme;  --  incl. the class constraint
      Selector      : Var_Id := No_Var;
      Has_Default   : Boolean := False;
   end record;

   package Method_Info_Vectors is new Ada.Containers.Vectors
     (Positive, Method_Info);

   --  One binder = rhs pair (used in Core lets, top-level groups, and
   --  class/instance method bodies).
   type Bind_Pair is record
      Binder : Real_Var_Id;
      Rhs    : Real_Expr_Id;
   end record;

   package Bind_Vectors is new Ada.Containers.Vectors
     (Positive, Bind_Pair);

   type Class_Info is record
      Name       : Names.Name_Id := Names.No_Name;
      Var_Kind   : Kind_Id := No_Kind;     --  kind of the class tyvar
      Supers     : Class_Id_Vectors.Vector;
      Methods    : Method_Info_Vectors.Vector;
      Dict_TyCon : TyCon_Id := No_TyCon;
      Dict_Con   : DataCon_Id := 0;
      Instances  : Instance_Id_Vectors.Vector;
      --  Desugared default-method bodies (binder = fresh local var).
      Default_Binds : Bind_Vectors.Vector;
      --  One selector global per superclass (extracts that dictionary
      --  field); parallel to Supers.
      Super_Sels : Var_Id_Vectors.Vector;
   end record;

   --  Haskell 2010 instance heads are always C (T a1..an), so keying
   --  on the head TyCon is complete. Head_Vars lists a1..an in order;
   --  Context constraints mention only these, so matching a wanted
   --  C (T t1..tn) instantiates the context by position.
   type Instance_Info is record
      Of_Class    : Class_Id := No_Class;
      Head        : TyCon_Id := No_TyCon;
      Head_Vars   : TyVar_Id_Vectors.Vector;
      Context     : Constraint_Vectors.Vector;
      Dict_Global : Var_Id := No_Var;
      --  Desugared method implementations (binder = local var).
      Method_Binds : Bind_Vectors.Vector;
      --  Dictionary lambda parameters, one per Context constraint;
      --  minted by the typechecker (method bodies reference them as
      --  given evidence), consumed by AHC.Elaborate.
      Param_Vars  : Var_Id_Vectors.Vector;
      Span        : Diagnostics.Source_Span;
   end record;

   ---------------------------------------------------------------------
   --  Expressions
   ---------------------------------------------------------------------

   type Literal_Kind is (L_Int, L_Float, L_Char, L_String);

   type Literal (Kind : Literal_Kind := L_Int) is record
      case Kind is
         when L_Int | L_Float | L_String =>
            Text : Names.Name_Id := Names.No_Name;  --  "" for L_String
         when L_Char =>
            Code : Natural := 0;
      end case;
   end record;

   type Expr_Kind is (Var_C, Lit_C, Con_C, App_C, Lam_C, Let_C, Case_C);

   type Expr_Node (Kind : Expr_Kind := Var_C) is record
      Span : Diagnostics.Source_Span;
      case Kind is
         when Var_C =>
            V : Real_Var_Id;
         when Lit_C =>
            Lit : Literal;
         when Con_C =>
            Con : Real_DataCon_Id;   --  atom; saturation via App_C
         when App_C =>
            Fun, Arg : Real_Expr_Id;
         when Lam_C =>
            Binder   : Real_Var_Id;
            Lam_Body : Real_Expr_Id;
         when Let_C =>
            Is_Rec   : Boolean := False;
            Binds    : Bind_Vectors.Vector;
            Let_Body : Real_Expr_Id;
         when Case_C =>
            Scrutinee : Real_Expr_Id;
            Alts      : Alt_Id_Vectors.Vector;
      end case;
   end record;

   type Alt_Kind is (Con_Alt, Lit_Alt, Default_Alt);

   type Alt_Node (Kind : Alt_Kind := Default_Alt) is record
      Span     : Diagnostics.Source_Span;
      Alt_Body : Real_Expr_Id;
      case Kind is
         when Con_Alt =>
            A_Con   : Real_DataCon_Id;
            Binders : Var_Id_Vectors.Vector;
         when Lit_Alt =>
            A_Lit : Literal;
         when Default_Alt =>
            null;
      end case;
   end record;

   ---------------------------------------------------------------------
   --  The store: one Core_Module owns every arena and table
   ---------------------------------------------------------------------

   package Var_Info_Vectors is new Ada.Containers.Vectors
     (Real_Var_Id, Var_Info);
   package TyVar_Info_Vectors is new Ada.Containers.Vectors
     (Real_TyVar_Id, TyVar_Info);
   package TyCon_Info_Vectors is new Ada.Containers.Vectors
     (Real_TyCon_Id, TyCon_Info);
   package DataCon_Info_Vectors is new Ada.Containers.Vectors
     (Real_DataCon_Id, DataCon_Info);
   package Class_Info_Vectors is new Ada.Containers.Vectors
     (Real_Class_Id, Class_Info);
   package Instance_Info_Vectors is new Ada.Containers.Vectors
     (Real_Instance_Id, Instance_Info);
   package Kind_Node_Vectors is new Ada.Containers.Vectors
     (Real_Kind_Id, Kind_Node);
   package Type_Node_Vectors is new Ada.Containers.Vectors
     (Real_Type_Id, Type_Node);
   package Scheme_Vectors is new Ada.Containers.Vectors
     (Real_Scheme_Id, Scheme);
   package Expr_Node_Vectors is new Ada.Containers.Vectors
     (Real_Expr_Id, Expr_Node);
   package Alt_Node_Vectors is new Ada.Containers.Vectors
     (Real_Alt_Id, Alt_Node);

   type Top_Bind is record
      Is_Rec : Boolean := False;
      Binds  : Bind_Vectors.Vector;
   end record;

   package Top_Bind_Vectors is new Ada.Containers.Vectors
     (Positive, Top_Bind);

   type Core_Module is tagged limited record
      Vars      : Var_Info_Vectors.Vector;
      TyVars    : TyVar_Info_Vectors.Vector;
      TyCons    : TyCon_Info_Vectors.Vector;
      DataCons  : DataCon_Info_Vectors.Vector;
      Classes   : Class_Info_Vectors.Vector;
      Instances : Instance_Info_Vectors.Vector;
      Kinds     : Kind_Node_Vectors.Vector;
      Types     : Type_Node_Vectors.Vector;
      Schemes   : Scheme_Vectors.Vector;
      Exprs     : Expr_Node_Vectors.Vector;
      Alts      : Alt_Node_Vectors.Vector;
      Top_Binds : Top_Bind_Vectors.Vector;
      Refinements : Refinement_Vectors.Vector;
      Star_Cache : Kind_Id := No_Kind;
   end record;

   function Last_Var (M : Core_Module) return Var_Id
   is (if M.Vars.Is_Empty then No_Var else M.Vars.Last_Index);
   function Last_TyVar (M : Core_Module) return TyVar_Id
   is (if M.TyVars.Is_Empty then 0 else M.TyVars.Last_Index);
   function Last_TyCon (M : Core_Module) return TyCon_Id
   is (if M.TyCons.Is_Empty then No_TyCon else M.TyCons.Last_Index);
   function Last_DataCon (M : Core_Module) return DataCon_Id
   is (if M.DataCons.Is_Empty then 0 else M.DataCons.Last_Index);
   function Last_Class (M : Core_Module) return Class_Id
   is (if M.Classes.Is_Empty then No_Class else M.Classes.Last_Index);
   function Last_Instance (M : Core_Module) return Instance_Id
   is (if M.Instances.Is_Empty then 0 else M.Instances.Last_Index);
   function Last_Kind (M : Core_Module) return Kind_Id
   is (if M.Kinds.Is_Empty then No_Kind else M.Kinds.Last_Index);
   function Last_Type (M : Core_Module) return Type_Id
   is (if M.Types.Is_Empty then No_Type else M.Types.Last_Index);
   function Last_Scheme (M : Core_Module) return Scheme_Id
   is (if M.Schemes.Is_Empty then No_Scheme else M.Schemes.Last_Index);
   function Last_Expr (M : Core_Module) return Expr_Id
   is (if M.Exprs.Is_Empty then No_Expr else M.Exprs.Last_Index);
   function Last_Alt (M : Core_Module) return Alt_Id
   is (if M.Alts.Is_Empty then 0 else M.Alts.Last_Index);
   function Last_Refinement (M : Core_Module) return Refinement_Id
   is (if M.Refinements.Is_Empty then No_Refinement
       else Refinement_Id (M.Refinements.Last_Index));

   ---------------------------------------------------------------------
   --  Well-formedness and addition (the AHC.Syntax protocol)
   ---------------------------------------------------------------------

   function Well_Formed (M : Core_Module; N : Kind_Node) return Boolean;
   function Well_Formed (M : Core_Module; N : Type_Node) return Boolean;
   function Well_Formed (M : Core_Module; S : Scheme) return Boolean;
   function Well_Formed (M : Core_Module; N : Expr_Node) return Boolean;
   function Well_Formed (M : Core_Module; N : Alt_Node) return Boolean;

   function Add (M : in out Core_Module; N : Kind_Node) return Real_Kind_Id
     with Pre => M.Well_Formed (N), Post => Add'Result = M.Last_Kind;
   function Add (M : in out Core_Module; N : Type_Node) return Real_Type_Id
     with Pre => M.Well_Formed (N), Post => Add'Result = M.Last_Type;
   function Add (M : in out Core_Module; S : Scheme) return Real_Scheme_Id
     with Pre => M.Well_Formed (S), Post => Add'Result = M.Last_Scheme;
   function Add (M : in out Core_Module; N : Expr_Node) return Real_Expr_Id
     with Pre => M.Well_Formed (N), Post => Add'Result = M.Last_Expr;
   function Add (M : in out Core_Module; N : Alt_Node) return Real_Alt_Id
     with Pre => M.Well_Formed (N), Post => Add'Result = M.Last_Alt;
   function Add
     (M : in out Core_Module; R : Refinement_Info)
      return Real_Refinement_Id
     with Pre  => R.Lo <= R.Hi,
          Post => Add'Result = M.Last_Refinement;

   --  Entity minting (no structural invariants beyond a real name
   --  where one is required; cross-links are filled in as passes run).
   function Mint_Var
     (M : in out Core_Module; Info : Var_Info) return Real_Var_Id
     with Pre  => Info.Name /= Names.No_Name,
          Post => Mint_Var'Result = M.Last_Var;
   function Mint_TyVar
     (M : in out Core_Module; Info : TyVar_Info) return Real_TyVar_Id
     with Post => Mint_TyVar'Result = M.Last_TyVar;
   function Mint_TyCon
     (M : in out Core_Module; Info : TyCon_Info) return Real_TyCon_Id
     with Pre  => Info.Name /= Names.No_Name,
          Post => Mint_TyCon'Result = M.Last_TyCon;
   function Mint_DataCon
     (M : in out Core_Module; Info : DataCon_Info) return Real_DataCon_Id
     with Pre  => Info.Name /= Names.No_Name
                  and then Info.TyCon in 1 .. M.Last_TyCon,
          Post => Mint_DataCon'Result = M.Last_DataCon;
   function Mint_Class
     (M : in out Core_Module; Info : Class_Info) return Real_Class_Id
     with Pre  => Info.Name /= Names.No_Name,
          Post => Mint_Class'Result = M.Last_Class;
   function Mint_Instance
     (M : in out Core_Module; Info : Instance_Info)
      return Real_Instance_Id
     with Pre  => Info.Of_Class in 1 .. M.Last_Class
                  and then Info.Head in 1 .. M.Last_TyCon,
          Post => Mint_Instance'Result = M.Last_Instance;

   --  Checked accessors.
   function Node (M : Core_Module; Id : Real_Kind_Id) return Kind_Node
     with Pre => Id <= M.Last_Kind;
   function Node (M : Core_Module; Id : Real_Type_Id) return Type_Node
     with Pre => Id <= M.Last_Type;
   function Node (M : Core_Module; Id : Real_Scheme_Id) return Scheme
     with Pre => Id <= M.Last_Scheme;
   function Node (M : Core_Module; Id : Real_Expr_Id) return Expr_Node
     with Pre => Id <= M.Last_Expr;
   function Node (M : Core_Module; Id : Real_Alt_Id) return Alt_Node
     with Pre => Id <= M.Last_Alt;

   function Info (M : Core_Module; Id : Real_Var_Id) return Var_Info
     with Pre => Id <= M.Last_Var;
   function Info (M : Core_Module; Id : Real_TyVar_Id) return TyVar_Info
     with Pre => Id <= M.Last_TyVar;
   function Info (M : Core_Module; Id : Real_TyCon_Id) return TyCon_Info
     with Pre => Id <= M.Last_TyCon;
   function Info (M : Core_Module; Id : Real_DataCon_Id) return DataCon_Info
     with Pre => Id <= M.Last_DataCon;
   function Info (M : Core_Module; Id : Real_Class_Id) return Class_Info
     with Pre => Id <= M.Last_Class;
   function Info (M : Core_Module; Id : Real_Instance_Id)
     return Instance_Info
     with Pre => Id <= M.Last_Instance;
   function Info (M : Core_Module; Id : Real_Refinement_Id)
     return Refinement_Info
     with Pre => Id <= M.Last_Refinement;

   --  The kind *, allocated once per module.
   function Star (M : in out Core_Module) return Real_Kind_Id
     with Post => M.Node (Star'Result).Kind = Star_K;

   --  Build a dictionary value: MkDict$C applied to the superclass
   --  dictionaries then the method implementations. The precondition
   --  is the PRD's dictionary-arity promise: a dictionary can only be
   --  built with exactly the right number of fields.
   function Mk_Dict
     (M       : in out Core_Module;
      Class   : Real_Class_Id;
      Supers  : Expr_Id_Vectors.Vector;
      Methods : Expr_Id_Vectors.Vector;
      Span    : Diagnostics.Source_Span) return Real_Expr_Id
     with
       Pre => Class <= M.Last_Class
              and then M.Info (Class).Dict_Con in 1 .. M.Last_DataCon
              and then Natural (Supers.Length) =
                         Natural (M.Info (Class).Supers.Length)
              and then Natural (Methods.Length) =
                         Natural (M.Info (Class).Methods.Length);

end AHC.Core;
