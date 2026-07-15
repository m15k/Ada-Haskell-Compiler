--  Name resolution (Phase 2): the pass between fixity resolution and
--  desugaring. Two sub-passes over the syntax arena:
--
--  Pass A (declare): populate the Global_Env with the module's data
--  types, classes, instances, synonyms, top-level value binders, and
--  record-field selector globals; group multi-equation Fun_Ds into
--  Binding_Units (Report 4.4.3: equations of one function must be
--  contiguous and share an arity).
--
--  Pass B (resolve): walk every expression, pattern, and type, filling
--  side vectors indexed by the syntax arena ids. Every occurrence of a
--  variable resolves to a unique Core Var_Id (locals minted here,
--  which is what makes capture impossible downstream); constructor
--  occurrences resolve to DataCon_Ids; type constructors to TyCon_Ids
--  or synonyms; context heads to Class_Ids. Scope errors (out of
--  scope, duplicates, signatures without bindings, unknown fields or
--  methods) are diagnosed here, before any Core exists.
--
--  Class-method occurrences resolve to their selector globals, whose
--  schemes carry the class constraint, so the typechecker needs no
--  special method case.

with Ada.Containers.Hashed_Maps;
with Ada.Containers.Vectors;

with AHC.Builtins;
with AHC.Core;
with AHC.Diagnostics;
with AHC.Names;
with AHC.Syntax;

package AHC.Rename is

   use type Core.Var_Id;
   use type Names.Name_Id;

   type Res_Kind is (Unresolved, Var_Res, Data_Res);

   type Resolution (Kind : Res_Kind := Unresolved) is record
      case Kind is
         when Unresolved => null;
         when Var_Res    => Var : Core.Real_Var_Id;
         when Data_Res   => Con : Core.Real_DataCon_Id;
      end case;
   end record;

   package Res_Vectors is new Ada.Containers.Vectors
     (Positive, Resolution);
   package TyCon_Res_Vectors is new Ada.Containers.Vectors
     (Positive, Core.TyCon_Id, Core."=");
   package Class_Res_Vectors is new Ada.Containers.Vectors
     (Positive, Core.Class_Id, Core."=");
   package Var_Res_Vectors is new Ada.Containers.Vectors
     (Positive, Core.Var_Id, Core."=");

   function Var_Hash (V : Core.Real_Var_Id) return Ada.Containers.Hash_Type
   is (Ada.Containers.Hash_Type (V));

   package Var_Sig_Maps is new Ada.Containers.Hashed_Maps
     (Core.Real_Var_Id, Syntax.Type_Id,
      Hash => Var_Hash, Equivalent_Keys => Core."=", "=" => Syntax."=");

   --  One value binding: a run of equations for one function, or one
   --  pattern binding.
   type Unit_Kind is (Fun_Unit, Pat_Unit);

   type Binding_Unit is record
      Kind      : Unit_Kind := Pat_Unit;
      Name      : Names.Name_Id := Names.No_Name;   --  Fun_Unit only
      Equations : Syntax.Decl_Id_Vectors.Vector;    --  1+ decls
      Arity     : Natural := 0;
      Span      : Diagnostics.Source_Span;
   end record;

   package Unit_Vectors is new Ada.Containers.Vectors
     (Positive, Binding_Unit);

   --  Group a declaration list into value Binding_Units, skipping
   --  non-value declarations. Also used by the desugarer. Diagnoses
   --  non-contiguous equations and arity mismatches.
   function Group
     (Arena : Syntax.Module_Arena;
      Decls : Syntax.Decl_Id_Vectors.Vector;
      Bag   : in out Diagnostics.Diagnostic_Bag)
      return Unit_Vectors.Vector;

   type Resolutions is tagged limited record
      --  Indexed by Positive (Syntax arena ids converted); Unresolved /
      --  0 where not applicable.
      Expr_Res  : Res_Vectors.Vector;
      Pat_Res   : Res_Vectors.Vector;
      Ty_Res    : TyCon_Res_Vectors.Vector;   --  Con_T -> TyCon
      Class_Res : Class_Res_Vectors.Vector;   --  Con_T in class position
      Decl_Var  : Var_Res_Vectors.Vector;     --  Fun_D/Pat_D -> binder
      Decl_Class : Class_Res_Vectors.Vector;  --  Class_D/Instance_D
      Var_Sig   : Var_Sig_Maps.Map;           --  binder -> signature type
   end record;

   procedure Resolve_Module
     (Arena : Syntax.Module_Arena;
      Table : in out Names.Name_Table;
      Bag   : in out Diagnostics.Diagnostic_Bag;
      M     : in out Core.Core_Module;
      Env   : in out Builtins.Global_Env;
      Res   : in out Resolutions);

end AHC.Rename;
