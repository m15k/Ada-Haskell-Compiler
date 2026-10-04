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
--
--  Two installed shapes are recognized: a checkout (<root>/prelude,
--  <root>/lib, <root>/runtime beside bin/ahc) and a Unix prefix
--  (<root>/share/ahc/... - so `make install PREFIX=/usr/local` does
--  not scatter Haskell sources through /usr/local/lib).

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

   function Stdlib_Candidates (Rel : String) return String;
   --  Every place Stdlib_File looks for lib/<Rel>, comma separated (for
   --  the "cannot find module" message).

   function Is_Stdlib_File (Path : String) return Boolean;
   --  True when Path lies under the compiler's OWN library: $AHC_LIB or
   --  the installation's lib/ (checkout or prefix) - decided by where
   --  the file IS, not by how it was found. A user project's own ./lib,
   --  or a stdlib module reached through another search path, is
   --  classified by its location alone (M144b).

end AHC.Paths;
