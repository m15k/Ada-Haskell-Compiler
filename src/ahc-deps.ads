--  Dependency roots (M134 paths, M135 git). A project's ahc.toml
--  names path dependencies (local module trees) and git
--  dependencies (fetched into the shared cache). Collect_All walks
--  the whole graph up front - path closure, then minimal version
--  selection over the git closure, then the fetched trees - and
--  hands the driver a flat, deterministic list of directories to
--  search after the project's own. No solver anywhere: selection
--  is the max of declared minimums, and only the ROOT manifest's
--  pins (or its path entries, which override a like-named git
--  dependency outright) can force anything else.

with Ada.Strings.Unbounded;
with Ada.Containers.Vectors;

with AHC.Manifest;

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
   --  The path-only walk: read Manifest_Dir/ahc.toml (absent =>
   --  True with empty Roots) and walk its path dependencies
   --  depth-first in manifest order, a dependency's own
   --  dependencies immediately after it; git dependencies are
   --  ignored here. Directories are normalized-absolute and
   --  deduplicated (first occurrence wins) unless still on the
   --  walk's stack - that is a cycle. False (message on stderr)
   --  for: a missing dependency directory, a manifest parse error,
   --  a cycle, or one name bound to two different directories.

   --  One selected git dependency: identity is the normalized URL,
   --  Ref is a version image ("1.2.0") or a pin as written.
   type Selection is record
      Name       : Unbounded_String;  --  first nickname seen
      URL        : Unbounded_String;  --  normalized identity
      Clone_URL  : Unbounded_String;  --  as written, for git
      Ref        : Unbounded_String;
      Is_Version : Boolean := True;   --  False when Ref is a pin
   end record;

   package Selection_Vectors is new Ada.Containers.Vectors
     (Positive, Selection);

   function Resolve
     (Root_Deps  : AHC.Manifest.Dependency_Vectors.Vector;
      Local_Deps : AHC.Manifest.Dependency_Vectors.Vector;
      Deps_Of    : access function
        (Clone_URL, Ref : String;
         Is_Version     : Boolean;
         Deps           : out AHC.Manifest.Dependency_Vectors.Vector)
        return Boolean;
      Selected   : out Selection_Vectors.Vector) return Boolean;
   --  Minimal version selection with root pins, injected with a
   --  manifest reader so tests can hand it a synthetic graph.
   --  Root_Deps is the root manifest verbatim: its path entries
   --  override like-named git dependencies anywhere in the graph,
   --  its pins select exactly, its versions are minimums.
   --  Local_Deps are git dependencies gathered from transitive
   --  path manifests: demoted - a version or a semver tag pin is a
   --  minimum, a commit pin without a root pin is an error.
   --  Deps_Of (Clone_URL, Ref, ...) returns the named version's
   --  own dependencies; requirements it raises re-enter the
   --  worklist, so the fixpoint is the max of minimums per URL.
   --  Selected comes back sorted by URL. False (message on
   --  stderr) for: one name meaning two URLs, conflicting root
   --  pins, a transitive commit pin with no root pin, or a
   --  Deps_Of failure.

   function Collect_All
     (Manifest_Dir : String;
      Roots        : out Root_Vectors.Vector;
      Fetch_Only   : Boolean := False;
      Quiet        : Boolean := False) return Boolean;
   --  The whole story: path walk, then - when any git dependency
   --  exists - Resolve over AHC.Fetch (ahc.sum lives beside the
   --  root manifest), then each selected tree is appended (sorted
   --  by URL, after all path roots) and walked for its own
   --  vendored path dependencies. A git dependency declared only
   --  inside a fetched tree's vendored subtree is an error - the
   --  resolver never saw it. Fetch_Only stops after resolution
   --  (everything fetched and verified, Roots left empty).

end AHC.Deps;
