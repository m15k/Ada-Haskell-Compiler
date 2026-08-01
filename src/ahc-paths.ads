--  Where the compiler's own files live: the Prelude source, the
--  standard-library tree, and the C runtime.
--
--  Resolution order, per file: an explicit environment override
--  (AHC_PRELUDE / AHC_LIB / AHC_RUNTIME), then the current directory
--  (the historical behavior - every in-repo workflow and golden
--  depends on these paths staying relative when running from the
--  checkout root), then the installation the running executable
--  belongs to (<exe>/../prelude and friends). The last arm is what
--  lets ahc compile a source file from ANY working directory: the
--  binary knows where its own tree is.

with Ada.Directories;

package AHC.Paths is

   function Prelude_File return String
     with Post => Prelude_File'Result'Length > 0;
   --  The Prelude source compiled ahead of every user module. When
   --  no candidate exists the CWD-relative default is returned so
   --  the "cannot open" diagnostic names the expected place.

   function Runtime_Dir return String
     with Post => Runtime_Dir'Result'Length > 0;
   --  The directory holding ahc_rts.{h,c} (used by ahc build to
   --  compile and link against the runtime).

   function Stdlib_File (Rel : String) return String
     with Pre  => Rel'Length > 0,
          Post => Stdlib_File'Result'Length = 0
                  or else Ada.Directories.Exists (Stdlib_File'Result);
   --  Resolve lib/<Rel> through the cascade, checking each candidate
   --  for existence (AHC_LIB keeps its historical advisory meaning:
   --  a module absent there still falls through to the other arms).
   --  Returns "" when the module exists nowhere.

end AHC.Paths;
