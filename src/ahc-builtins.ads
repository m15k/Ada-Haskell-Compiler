--  The wired-in Prelude signature (Phase 2). Real Prelude source
--  arrives in Phase 4; until then the compiler knows the Report's
--  built-in types, the standard class hierarchy with method schemes,
--  signature-only instances (opaque dictionary globals), and the value
--  vocabulary the desugarer emits.
--
--  Class methods are exposed as ordinary global variables (selectors)
--  whose schemes carry the class constraint, so the typechecker treats
--  method occurrences and constrained functions identically.

with Ada.Containers.Hashed_Maps;

with AHC.Core;
with AHC.Names;
with AHC.Syntax;

package AHC.Builtins is

   use type Names.Name_Id;

   function Name_Hash (N : Names.Name_Id) return Ada.Containers.Hash_Type
   is (Ada.Containers.Hash_Type (N));

   package Var_Maps is new Ada.Containers.Hashed_Maps
     (Names.Name_Id, Core.Real_Var_Id, Name_Hash, "=", Core."=");
   package TyCon_Maps is new Ada.Containers.Hashed_Maps
     (Names.Name_Id, Core.Real_TyCon_Id, Name_Hash, "=", Core."=");
   package DataCon_Maps is new Ada.Containers.Hashed_Maps
     (Names.Name_Id, Core.Real_DataCon_Id, Name_Hash, "=", Core."=");
   package Class_Maps is new Ada.Containers.Hashed_Maps
     (Names.Name_Id, Core.Real_Class_Id, Name_Hash, "=", Core."=");

   --  A type synonym: wired-in ones carry a Core rhs; user synonyms
   --  carry their surface rhs until AHC.Kinds converts it.
   type Syn_Rec is record
      Arity      : Natural := 0;
      Vars       : Syntax.QName_Vectors.Vector;   --  user synonyms
      Syntax_Rhs : Syntax.Type_Id := 0;
      Core_Rhs   : Core.Type_Id := Core.No_Type;  --  filled by AHC.Kinds
      --  Parameter tyvars of the cached Core_Rhs, in declaration
      --  order. Syntax_Rhs is only meaningful inside the defining
      --  module's arena, so cross-module expansion MUST go through
      --  Core_Rhs/Core_Vars (AHC.Kinds caches them at the
      --  declaration).
      Core_Vars  : Core.TyVar_Id_Vectors.Vector;
      --  Caching failed (e.g. a cyclic synonym): the error is
      --  already reported; expansion yields No_Type silently.
      Bad        : Boolean := False;
   end record;

   package Syn_Maps is new Ada.Containers.Hashed_Maps
     (Names.Name_Id, Syn_Rec, Name_Hash, "=");

   Max_Tuple : constant := 7;
   type Tuple_TC_Array is array (2 .. Max_Tuple) of Core.TyCon_Id;
   type Tuple_DC_Array is array (2 .. Max_Tuple) of Core.DataCon_Id;

   type Global_Env is tagged limited record
      --  Name -> entity maps (extended by the renamer with user
      --  declarations).
      Values   : Var_Maps.Map;
      TyCons   : TyCon_Maps.Map;
      DataCons : DataCon_Maps.Map;
      Classes  : Class_Maps.Map;
      Synonyms : Syn_Maps.Map;

      --  Well-known handles.
      Int_TC, Integer_TC, Float_TC, Double_TC, Char_TC, Bool_TC,
      Unit_TC, List_TC, IO_TC, Ordering_TC, Rational_TC, Maybe_TC,
      Arrow_TC, Ptr_TC, FunPtr_TC
        : Core.TyCon_Id := Core.No_TyCon;
      Tuple_TCs : Tuple_TC_Array := [others => Core.No_TyCon];

      True_DC, False_DC, Unit_DC, Nil_DC, Cons_DC, Nothing_DC, Just_DC
        : Core.DataCon_Id := 0;
      Tuple_DCs : Tuple_DC_Array := [others => 0];

      Eq_Cl, Ord_Cl, Show_Cl, Functor_Cl, Monad_Cl, Num_Cl, Real_Cl,
      Fractional_Cl, Enum_Cl, Bounded_Cl,
      Integral_Cl, Floating_Cl, RealFrac_Cl, RealFloat_Cl
        : Core.Class_Id := Core.No_Class;

      --  Selector/global vars the desugarer references directly.
      Bind_V, Then_V, Return_V, Fail_V,
      Map_V, Filter_V, Concat_Map_V, Append_V,
      Enum_From_V, Enum_From_Then_V, Enum_From_To_V,
      Enum_From_Then_To_V,
      From_Integer_V, From_Rational_V, Negate_V,
      Error_V, Otherwise_V : Core.Var_Id := Core.No_Var;
   end record;

   --  Populate M with the wired-in signature and fill Env. Must run on
   --  a fresh Core_Module, before renaming.
   procedure Install
     (M     : in out Core.Core_Module;
      Table : in out Names.Name_Table;
      Env   : in out Global_Env)
     with Pre => Core."=" (M.Last_TyCon, Core.No_TyCon);

end AHC.Builtins;
