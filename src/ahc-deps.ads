--  Dependency roots (M134). A project's ahc.toml names path
--  dependencies; each dependency is a module tree (package root =
--  module root) that may in turn carry its own ahc.toml naming
--  more. Collect_Roots walks that graph once, up front, and hands
--  the driver a flat, deterministic list of directories to search
--  after the project's own - the module DFS itself stays untouched.

with Ada.Strings.Unbounded;
with Ada.Containers.Vectors;

package AHC.Deps is

   use Ada.Strings.Unbounded;

   type Dep_Root is record
      Name : Unbounded_String;  --  the [dependencies.NAME] label
      Dir  : Unbounded_String;  --  normalized absolute directory
   end record;

   package Root_Vectors is new Ada.Containers.Vectors
     (Positive, Dep_Root);

   function Collect_Roots
     (Manifest_Dir : String;
      Roots        : out Root_Vectors.Vector) return Boolean;
   --  Read Manifest_Dir/ahc.toml (absent => True with empty Roots)
   --  and walk its path dependencies depth-first in manifest order,
   --  a dependency's own dependencies immediately after it. Each
   --  dependency directory is normalized to an absolute path;
   --  revisiting one is a benign dedup (first occurrence wins)
   --  unless it is still on the walk's stack - that is a cycle.
   --  False (message on stderr) for: a dependency directory that
   --  does not exist, a manifest that fails to parse, a dependency
   --  cycle, or one name bound to two different directories.

end AHC.Deps;
