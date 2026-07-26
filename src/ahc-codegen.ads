--  C code generation (Phase 3, PRD 5.6): dictionary-passing Core to C
--  over the AHC runtime (runtime/ahc_rts.h).
--
--  Model: every lambda and every lazy position (application arguments,
--  let right-hand sides) is closure-converted into a lifted C function
--  over an explicit environment; thunks update in place via ahc_eval.
--  Lets and cases compile to GNU statement expressions, so only true
--  deferral points allocate. Top-level bindings become global CAF
--  nodes initialized as thunks (or functions directly when the body is
--  a lambda). Selector variables compile to dictionary field access;
--  prim variables map to runtime symbols; opaque globals become
--  loud-failure thunks.
--
--  Separate code generation: the program is emitted as one C file per
--  compilation unit (module), plus a shared header. Every emitted
--  name is STABLE - globals are mangled from (unit, source name),
--  locals and lifted functions are numbered per unit - so a unit's
--  generated text depends only on its own Core, and object files can
--  be cached by content hash across builds.

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

with AHC.Builtins;
with AHC.Core;
with AHC.Names;
with AHC.Prelude_Core;

package AHC.CodeGen is

   package UStr_Vectors is new Ada.Containers.Vectors
     (Positive, Ada.Strings.Unbounded.Unbounded_String,
      Ada.Strings.Unbounded."=");

   type Unit_File is record
      Name : Ada.Strings.Unbounded.Unbounded_String;  --  unit name
      Text : Ada.Strings.Unbounded.Unbounded_String;  --  .c content
   end record;

   package Unit_File_Vectors is new Ada.Containers.Vectors
     (Positive, Unit_File);

   --  Owners has one entry per M.Top_Binds group naming its unit;
   --  F_Owners likewise one entry per M.Foreigns import. Units lists
   --  unit names in initialization (dependency) order; the LAST unit
   --  is the root and receives main() - or, in Lib_Mode, a
   --  C-callable ahc_lib_init() that runs the RTS and unit inits.
   --  Foreign exports become C-ABI entry functions in the root unit;
   --  Exports_H is the generated ahc_exports.h content declaring
   --  them. Header is the shared prog.h content (extern globals +
   --  init prototypes); Files holds one C file per unit, in Units
   --  order.
   procedure Emit_Units
     (Table    : in out Names.Name_Table;
      M        : Core.Core_Module;
      Env      : Builtins.Global_Env;
      Prims    : Prelude_Core.Prim_Maps.Map;
      Owners   : UStr_Vectors.Vector;
      F_Owners : UStr_Vectors.Vector;
      Units    : UStr_Vectors.Vector;
      Lib_Mode : Boolean;
      Header   : out Ada.Strings.Unbounded.Unbounded_String;
      Exports_H : out Ada.Strings.Unbounded.Unbounded_String;
      Files    : out Unit_File_Vectors.Vector);

end AHC.CodeGen;
