--  Binding generation: idiomatic per-language glue over the C-ABI
--  entry functions that `foreign export ccall` produces. The C ABI
--  is the hub; each language here is a spoke - the generated file
--  wraps ahc_exports.h in that language's own idiom (RAII class,
--  safe Rust module, cgo package with a locked OS thread, GHC
--  foreign imports).

with Ada.Strings.Unbounded;

with AHC.Core;
with AHC.Names;

package AHC.Bindgen is

   --  Supported: "cpp", "rust", "go", "ghc".
   function Supported (Lang : String) return Boolean;

   --  Name of the generated file for Lang, e.g. "ahc_exports.hpp".
   function File_Name (Lang : String) return String
     with Pre => Supported (Lang);

   --  Generate the binding text. Lib is the archive file name the
   --  consumer links (e.g. "mathlib.a"), used in comments and cgo
   --  directives.
   function Generate
     (Lang    : String;
      Lib     : String;
      Exports : Core.Foreign_Vectors.Vector;
      Table   : Names.Name_Table)
      return Ada.Strings.Unbounded.Unbounded_String
     with Pre => Supported (Lang);

end AHC.Bindgen;
