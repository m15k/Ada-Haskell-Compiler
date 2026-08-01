--  The build's second half: compile the C that `ahc emit` wrote and
--  link it (or archive it) against the runtime, caching each object
--  by content hash. This is scripts/ahc-build.sh done natively - the
--  script survives as a shim over `ahc build`.
--
--  The cache contract (proved by scripts/run_separate.sh): an
--  object's name is <unit>_<sha256>.o where the hash covers the
--  unit's generated C, the shared headers, and the effective compile
--  flags - so an unchanged unit is never recompiled, a flag change
--  never reuses a stale object, and the recipe matches the script's
--  byte-for-byte (caches built by either stay warm for the other).
--
--  Environment honored, exactly as the script documented it:
--    AHC_GC       boehm (default; brew-probed) | own | none
--    AHC_CFLAGS   extra compile flags (part of every cache key)
--    AHC_LDFLAGS  extra link flags
--  plus OUT.build/link_flags, collected from OPTIONS_AHC_LINK
--  pragmas by emit.

with Ada.Directories;

package AHC.Build is

   type Options is record
      Lib     : Boolean := False;  --  archive + header, no link
      Verbose : Boolean := False;  --  print each compiler command
   end record;

   function Compile_And_Link
     (Out_Path : String; Opts : Options) return Boolean
     with Pre => Out_Path'Length > 0
                 and then Ada.Directories.Exists (Out_Path & ".build");
   --  Assumes `ahc emit` already populated OUT.build/. True on
   --  success; a C-compiler failure surfaces clang's own message on
   --  stderr and returns False.

end AHC.Build;
