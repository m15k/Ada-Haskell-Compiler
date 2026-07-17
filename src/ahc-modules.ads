--  Module interfaces for multi-module programs (Report ch. 5).
--
--  AHC compiles a program whole: the driver discovers imports from
--  the root file, topologically orders the module graph, and runs
--  each module through the frontend into the shared Core module.
--  Each module leaves behind an Iface - the entities its export list
--  admits - and the renamer resolves names through its own top
--  levels, then its imports' Ifaces, then the Base snapshot
--  (builtins + the compiled Prelude), never through other modules'
--  private names.

with Ada.Containers.Vectors;

with AHC.Builtins;
with AHC.Fixity;
with AHC.Names;

package AHC.Modules is

   type Iface is record
      Values   : Builtins.Var_Maps.Map;
      TyCons   : Builtins.TyCon_Maps.Map;
      DataCons : Builtins.DataCon_Maps.Map;
      Classes  : Builtins.Class_Maps.Map;
      --  Synonyms expand by name from the flat environment; the
      --  iface records which names are visible.
      Synonyms : Fixity.Fixity_Maps.Map;   --  used as a name set
      Fixities : Fixity.Fixity_Maps.Map;
   end record;

   type Module_Entry is record
      Name    : Names.Name_Id := Names.No_Name;
      Exports : Iface;
   end record;

   function Never_Eq (A, B : Module_Entry) return Boolean;

   package Entry_Vectors is new Ada.Containers.Vectors
     (Positive, Module_Entry, "=" => Never_Eq);

   type Registry is record
      Base : Iface;                    --  builtins + Prelude snapshot
      Mods : Entry_Vectors.Vector;     --  compiled modules' exports
   end record;

   function Find
     (Reg : Registry; Name : Names.Name_Id) return Natural;
   --  Index into Reg.Mods, 0 if absent.

end AHC.Modules;
