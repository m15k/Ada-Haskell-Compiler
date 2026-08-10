--  ahc.toml: the project manifest (M129, dependencies M134). Bare
--  `ahc build` in a directory holding one reads it instead of
--  requiring a source argument. Deliberately the smallest honest
--  manifest: flat string/boolean/integer keys for the build itself,
--  plus [package] identity and one [dependencies.NAME] section per
--  dependency. No inline tables, no arrays, no escapes - unknown
--  syntax is an error. Explicit CLI flags and environment variables
--  override manifest values (operator beats project defaults).

with Ada.Strings.Unbounded;
with Ada.Containers.Vectors;

package AHC.Manifest is

   use Ada.Strings.Unbounded;

   --  A [dependencies.NAME] section. Milestone A supports only
   --  path dependencies; the git/version/pin keys parse today so
   --  the grammar is stable, but are rejected until git
   --  dependencies land.
   type Dep_Kind is (Path_Dep, Git_Dep);

   type Dependency is record
      Name    : Unbounded_String;   --  [dependencies.NAME]
      Kind    : Dep_Kind := Path_Dep;
      Path    : Unbounded_String;   --  relative to the manifest's dir
      URL     : Unbounded_String;   --  git = "..." (future)
      Version : Unbounded_String;   --  minimum version (future)
      Pin     : Unbounded_String;   --  exact tag or commit (future)
   end record;

   package Dependency_Vectors is new Ada.Containers.Vectors
     (Positive, Dependency);

   type Project is record
      Main        : Unbounded_String;  --  required: the root .hs file
      Output      : Unbounded_String;  --  default: main minus .hs
      Cflags      : Unbounded_String;  --  appended after AHC_CFLAGS
      Ldflags     : Unbounded_String;  --  appended after AHC_LDFLAGS
      GC          : Unbounded_String;  --  boehm|own|none; env wins
      Unchecked   : Boolean := False;
      No_Opt      : Boolean := False;
      Lib         : Boolean := False;
      Jobs        : Natural := 0;
      Pkg_Name    : Unbounded_String;  --  [package] name
      Pkg_Version : Unbounded_String;  --  [package] version
      Deps        : Dependency_Vectors.Vector;  --  manifest order
   end record;

   function Load (Path : String; P : out Project;
                  Require_Main : Boolean := True) return Boolean;
   --  Parse Path. False (with a message on stderr naming the line)
   --  on a malformed line, an unknown key or section, a duplicate
   --  dependency, a dependency without a path, or - when
   --  Require_Main - a missing main. A dependency's own manifest is
   --  loaded with Require_Main => False: only its [dependencies.*]
   --  matter to a consumer.

end AHC.Manifest;
