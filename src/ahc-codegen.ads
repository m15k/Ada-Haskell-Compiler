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

with Ada.Strings.Unbounded;

with AHC.Builtins;
with AHC.Core;
with AHC.Names;
with AHC.Prelude_Core;

package AHC.CodeGen is

   function Emit
     (Table : in out Names.Name_Table;
      M     : Core.Core_Module;
      Env   : Builtins.Global_Env;
      Prims : Prelude_Core.Prim_Maps.Map)
      return Ada.Strings.Unbounded.Unbounded_String;

end AHC.CodeGen;
