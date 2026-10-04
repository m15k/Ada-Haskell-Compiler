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
with Ada.Containers.Ordered_Maps;
with Ada.Containers.Vectors;

with AHC.Builtins;
with AHC.Core;
with AHC.Diagnostics;
with AHC.Fixity;
with AHC.Modules;
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
   package DataCon_Res_Vectors is new Ada.Containers.Vectors
     (Positive, Core.DataCon_Id, Core."=");
   package Inst_Res_Vectors is new Ada.Containers.Vectors
     (Positive, Core.Instance_Id, Core."=");

   --  A Con_T occurrence that resolved to a type synonym (M75):
   --  either one this module declares - Kinds expands it from its
   --  own table, which it caches as it goes - or an imported or
   --  Prelude one, whose already-cached record travels with the
   --  resolution. Kinds never looks a synonym up by name.
   type Syn_Ref is record
      Is_Own : Boolean := False;
      Name   : Names.Name_Id := Names.No_Name;
      Rec    : Builtins.Syn_Rec;   --  meaningful when not Is_Own
   end record;

   package Syn_Res_Maps is new Ada.Containers.Ordered_Maps
     (Positive, Syn_Ref);

   --  Rec_Update_E -> the selector each assigned field resolved to,
   --  in Rec_Fields order (M75: fields are found through scope, by
   --  identity, never by name across the program).
   package Field_Res_Maps is new Ada.Containers.Ordered_Maps
     (Positive, Core.Var_Id_Vectors.Vector, "=" => Core.Var_Id_Vectors."=");

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
      --  Declaration -> entity. Later phases must NEVER re-find an
      --  entity by name: two modules may declare the same type or
      --  constructor, and only the renamer knows which one a given
      --  declaration minted (M75).
      Decl_TyCon : TyCon_Res_Vectors.Vector;   --  Data_D/Newtype_D
      Decl_Con   : DataCon_Res_Vectors.Vector; --  Con_Node id
      --  Instance_D -> the Instance_Info it minted. Kinds and the
      --  desugarer complete THAT instance; they used to find it by
      --  source span, and spans are per-file offsets - an instance in
      --  one module whose span equalled one in another (the Prelude's
      --  Show 6-tuple) had its method bodies overwritten (M142).
      Decl_Inst  : Inst_Res_Vectors.Vector;
      Syn_Res    : Syn_Res_Maps.Map;          --  Con_T -> synonym
      Field_Res  : Field_Res_Maps.Map;        --  Rec_Update_E fields
      Own_Syns   : Builtins.Syn_Maps.Map;     --  this module's, uncached
      Own_Values : Builtins.Var_Maps.Map;     --  this module's top level
      Var_Sig   : Var_Sig_Maps.Map;           --  binder -> signature type
      --  The Prelude pass only (no registry): what its export list
      --  names, resolved against the flat environment (M144b).
      Public    : Modules.Iface;
   end record;

   --  Reg carries the module registry: Base (builtins + Prelude
   --  snapshot) plus each already-compiled module's exports; on
   --  return this module's own exports are appended. Fixities is the
   --  module's top-level fixity table, stored with its entry.
   procedure Resolve_Module
     (Arena : Syntax.Module_Arena;
      Table : in out Names.Name_Table;
      Bag   : in out Diagnostics.Diagnostic_Bag;
      M     : in out Core.Core_Module;
      Env   : in out Builtins.Global_Env;
      Res   : in out Resolutions;
      Reg   : access Modules.Registry := null;
      Fixities : Fixity.Fixity_Maps.Map :=
        Fixity.Fixity_Maps.Empty_Map)
     --  Every synonym occurrence resolves either to this module's own
     --  declaration, or to a record already CACHED in Core (or marked
     --  Bad): an imported Syntax_Rhs indexes another module's arena,
     --  and expanding it here would read the wrong nodes (M75).
     with Post =>
       (for all R of Res.Syn_Res =>
          (if R.Is_Own then Res.Own_Syns.Contains (R.Name)
           else R.Rec.Bad or else Core."/=" (R.Rec.Core_Rhs, Core.No_Type)))
       --  Every instance declaration minted its Instance_Info unless
       --  resolving it failed (and said so): Kinds and the desugarer
       --  find it ONLY through Decl_Inst (M142).
       and then Natural (Res.Decl_Inst.Length) = Natural (Arena.Last_Decl)
       and then
         (Diagnostics.Has_Errors (Bag)
          or else
            (for all D of Arena.Top_Decls =>
               (if Syntax."=" (Arena.Node (D).Kind, Syntax.Instance_D)
                then Core."/=" (Res.Decl_Inst (Positive (D)), 0))));

end AHC.Rename;
