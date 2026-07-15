--  Desugaring (Phase 2): renamed AST to untyped Core, Report chapter 3
--  translation rules by the book. Core cannot represent sugar, so
--  sugar-freeness holds by construction.
--
--  Highlights:
--    - do-notation -> >>= / >> / fail on refutable binds (3.14)
--    - list comprehensions -> concatMap/if chains (3.11)
--    - multi-equation definitions, guards, where and nested patterns
--      via a sequential match compiler with Let-bound join points, so
--      fall-through never duplicates code
--    - literal patterns become == tests (correct for overloading)
--    - records: construction/update/pattern -> positional
--    - numeric literals -> fromInteger / fromRational applications
--    - expression signatures 'e :: T' become fresh let bindings whose
--      binder carries T as an ordinary signature (added to Sigs)
--
--  Only run on a module with no errors so far: the desugarer assumes
--  every occurrence is resolved.

with AHC.Builtins;
with AHC.Core;
with AHC.Diagnostics;
with AHC.Kinds;
with AHC.Names;
with AHC.Rename;
with AHC.Syntax;

package AHC.Desugar is

   procedure Desugar_Module
     (Arena : Syntax.Module_Arena;
      Res   : Rename.Resolutions;
      Table : in out Names.Name_Table;
      Bag   : in out Diagnostics.Diagnostic_Bag;
      M     : in out Core.Core_Module;
      Env   : in out Builtins.Global_Env;
      Sigs  : in out Kinds.Sig_Maps.Map;
      Annos : Kinds.Anno_Maps.Map);

end AHC.Desugar;
