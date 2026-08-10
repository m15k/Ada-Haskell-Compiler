--  Collect_Roots over real fixture trees built in a scratch
--  directory (transitive order, diamond dedup, the error space),
--  and Resolve over a synthetic dependency graph - the callback
--  injection exists exactly so MVS is testable without git.
--  Negative cases print to stderr - expected noise in the log.

with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with AHC.Deps;
with AHC.Manifest;

with Test_Harness; use Test_Harness;

package body Test_Deps is

   use Ada.Strings.Unbounded;

   --  Synthetic-graph vocabulary: dependency declarations the way
   --  a manifest would carry them.
   function Git (Name, URL, Version, Pin : String)
                 return AHC.Manifest.Dependency is
     (Name    => To_Unbounded_String (Name),
      Kind    => AHC.Manifest.Git_Dep,
      Path    => Null_Unbounded_String,
      URL     => To_Unbounded_String (URL),
      Version => To_Unbounded_String (Version),
      Pin     => To_Unbounded_String (Pin));

   function Path_D (Name : String)
                    return AHC.Manifest.Dependency is
     (Name    => To_Unbounded_String (Name),
      Kind    => AHC.Manifest.Path_Dep,
      Path    => To_Unbounded_String ("somewhere"),
      URL     => Null_Unbounded_String,
      Version => Null_Unbounded_String,
      Pin     => Null_Unbounded_String);

   --  The graph the callback serves:
   --    liba@* needs greet >= 1.0.0
   --    libb@* needs greet >= 1.1.0, and at >= 2.0.0 needs extra
   --    vend@* pins greet at tag v1.2.0
   --    cpin@* pins greet at a commit
   --  everything else has no dependencies.
   function Fake_Deps
     (Clone_URL, Ref : String;
      Is_Version     : Boolean;
      Deps           : out AHC.Manifest.Dependency_Vectors.Vector)
      return Boolean
   is
      pragma Unreferenced (Is_Version);
      G : constant String := "https://x/greet";
   begin
      Deps.Clear;
      if Clone_URL = "https://x/liba" then
         Deps.Append (Git ("greet", G, "1.0.0", ""));
      elsif Clone_URL = "https://x/libb" then
         Deps.Append (Git ("greet", G, "1.1.0", ""));
         if Ref = "2.0.0" then
            Deps.Append
              (Git ("extra", "https://x/extra", "1.0.0", ""));
         end if;
      elsif Clone_URL = "https://x/vend" then
         Deps.Append (Git ("greet", G, "", "v1.2.0"));
      elsif Clone_URL = "https://x/cpin" then
         Deps.Append
           (Git ("greet", G, "",
                 "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"));
      end if;
      return True;
   end Fake_Deps;

   function Ref_Of
     (Sel : AHC.Deps.Selection_Vectors.Vector; URL : String)
      return String is
   begin
      for S of Sel loop
         if To_String (S.URL) = URL then
            return To_String (S.Ref);
         end if;
      end loop;
      return "(absent)";
   end Ref_Of;

   Scratch : constant String := "unit_scratch_deps";

   procedure Write_File (Path, Content : String) is
      use Ada.Text_IO;
      F : File_Type;
   begin
      Create (F, Out_File, Path);
      Put (F, Content);
      Close (F);
   end Write_File;

   procedure Make_Pkg (Dir : String; Manifest : String := "") is
   begin
      Ada.Directories.Create_Path (Scratch & "/" & Dir);
      if Manifest /= "" then
         Write_File (Scratch & "/" & Dir & "/ahc.toml", Manifest);
      end if;
   end Make_Pkg;

   --  The suffix of a collected root, relative to the scratch tree
   --  (roots come back normalized-absolute).
   function Tail (S : Unbounded_String) return String is
      F : constant String := To_String (S);
      P : constant String := "/" & Scratch & "/";
   begin
      for I in F'First .. F'Last - P'Length + 1 loop
         if F (I .. I + P'Length - 1) = P then
            return F (I + P'Length .. F'Last);
         end if;
      end loop;
      return F;
   end Tail;

   procedure Run is
      Roots : AHC.Deps.Root_Vectors.Vector;
      pragma Warnings
        (Off, Roots, Reason => "out param probed for the result");
   begin
      Start_Suite ("Deps");
      if Ada.Directories.Exists (Scratch) then
         Ada.Directories.Delete_Tree (Scratch);
      end if;

      --  No manifest at all: fine, nothing to collect.
      Make_Pkg ("bare");
      Check (AHC.Deps.Collect_Roots (Scratch & "/bare", Roots),
             "no manifest collects nothing, successfully");
      Check (Roots.Is_Empty, "no manifest yields empty roots");

      --  Chain root -> a -> b, depth-first order [a, b]; libc is a
      --  bare module tree (no manifest of its own).
      Make_Pkg ("liba",
                "[dependencies.b]" & ASCII.LF
                & "path = ""../libb""" & ASCII.LF);
      Make_Pkg ("libb");
      Make_Pkg ("libc");
      Make_Pkg ("root",
                "main = ""Main.hs""" & ASCII.LF
                & "[dependencies.a]" & ASCII.LF
                & "path = ""../liba""" & ASCII.LF
                & "[dependencies.c]" & ASCII.LF
                & "path = ""../libc""" & ASCII.LF);
      Check (AHC.Deps.Collect_Roots (Scratch & "/root", Roots),
             "transitive chain collects");
      Check_Equal (Integer (Roots.Length), 3,
                   "chain yields three roots");
      Check_Equal (Tail (Roots (1).Dir), "liba",
                   "a dependency precedes its own dependencies");
      Check_Equal (Tail (Roots (2).Dir), "libb",
                   "a transitive dependency follows its introducer");
      Check_Equal (Tail (Roots (3).Dir), "libc",
                   "a later sibling follows the whole subtree");

      --  Diamond: root -> {a, d}, both a and d -> b; b once, first
      --  occurrence wins.
      Make_Pkg ("libd",
                "[dependencies.b]" & ASCII.LF
                & "path = ""../libb""" & ASCII.LF);
      Make_Pkg ("diamond",
                "[dependencies.a]" & ASCII.LF
                & "path = ""../liba""" & ASCII.LF
                & "[dependencies.d]" & ASCII.LF
                & "path = ""../libd""" & ASCII.LF);
      Check (AHC.Deps.Collect_Roots (Scratch & "/diamond", Roots),
             "diamond collects");
      Check_Equal (Integer (Roots.Length), 3,
                   "diamond dedups the shared dependency");

      --  Errors.
      Make_Pkg ("cyc1",
                "[dependencies.two]" & ASCII.LF
                & "path = ""../cyc2""" & ASCII.LF);
      Make_Pkg ("cyc2",
                "[dependencies.one]" & ASCII.LF
                & "path = ""../cyc1""" & ASCII.LF);
      Check (not AHC.Deps.Collect_Roots (Scratch & "/cyc1", Roots),
             "a dependency cycle is an error");

      Make_Pkg ("ghostly",
                "[dependencies.ghost]" & ASCII.LF
                & "path = ""../nowhere""" & ASCII.LF);
      Check (not AHC.Deps.Collect_Roots
               (Scratch & "/ghostly", Roots),
             "a missing dependency directory is an error");

      --  One name meaning two paths: root calls libd 'a', but the
      --  chain already bound 'a' to liba via a transitive manifest.
      Make_Pkg ("clash",
                "[dependencies.x]" & ASCII.LF
                & "path = ""../libe""" & ASCII.LF
                & "[dependencies.a]" & ASCII.LF
                & "path = ""../libd""" & ASCII.LF);
      Make_Pkg ("libe",
                "[dependencies.a]" & ASCII.LF
                & "path = ""../liba""" & ASCII.LF);
      Check (not AHC.Deps.Collect_Roots (Scratch & "/clash", Roots),
             "one name bound to two directories is an error");

      --  Same name, same directory, from two manifests: benign.
      Make_Pkg ("agree",
                "[dependencies.x]" & ASCII.LF
                & "path = ""../libe""" & ASCII.LF
                & "[dependencies.a]" & ASCII.LF
                & "path = ""../liba""" & ASCII.LF);
      Check (AHC.Deps.Collect_Roots (Scratch & "/agree", Roots),
             "two manifests agreeing on a name is benign");

      --  Adversarial review: a path that exists but is a FILE, not
      --  a directory, must be rejected, not silently added.
      Make_Pkg ("filedep",
                "[dependencies.f]" & ASCII.LF
                & "path = ""../liba/ahc.toml""" & ASCII.LF);
      Check (not AHC.Deps.Collect_Roots
               (Scratch & "/filedep", Roots),
             "a path dependency pointing at a file is an error");

      Ada.Directories.Delete_Tree (Scratch);

      --  Minimal version selection over the synthetic graph.
      declare
         Root, Locals : AHC.Manifest.Dependency_Vectors.Vector;
         Sel          : AHC.Deps.Selection_Vectors.Vector;
         pragma Warnings
           (Off, Sel, Reason => "out param probed for the result");
      begin
         --  Max of minimums: liba asks greet>=1.0.0, libb asks
         --  greet>=1.1.0, the root asks both mids at 1.0.0.
         Root.Append (Git ("liba", "https://x/liba", "1.0.0", ""));
         Root.Append (Git ("libb", "https://x/libb", "1.0.0", ""));
         Check (AHC.Deps.Resolve (Root, Locals, Fake_Deps'Access,
                                  Sel),
                "synthetic graph resolves");
         Check_Equal (Ref_Of (Sel, "https://x/greet"), "1.1.0",
                      "MVS takes the max of the minimums");
         Check_Equal (Integer (Sel.Length), 3,
                      "selection covers the whole closure");
         Check (To_String (Sel (1).URL) < To_String (Sel (2).URL)
                and then To_String (Sel (2).URL)
                       < To_String (Sel (3).URL),
                "selection is sorted by URL");

         --  A raised minimum re-expands: at 2.0.0 libb grows a
         --  dependency that 1.0.0 does not have.
         Root.Clear;
         Root.Append (Git ("liba", "https://x/liba", "1.0.0", ""));
         Root.Append (Git ("libb", "https://x/libb", "2.0.0", ""));
         Check (AHC.Deps.Resolve (Root, Locals, Fake_Deps'Access,
                                  Sel),
                "re-expansion graph resolves");
         Check_Equal (Ref_Of (Sel, "https://x/extra"), "1.0.0",
                      "a raised minimum re-expands its manifest");

         --  A root pin beats every transitive minimum.
         Root.Append (Git ("greet", "https://x/greet", "",
                           "v1.0.0"));
         Check (AHC.Deps.Resolve (Root, Locals, Fake_Deps'Access,
                                  Sel),
                "pinned graph resolves");
         Check_Equal (Ref_Of (Sel, "https://x/greet"), "v1.0.0",
                      "root pin overrides transitive minimums");

         --  Adversarial review: the root giving both a version and
         --  a pin for one URL is a contradiction, not a silent
         --  pin-wins.
         Root.Clear;
         Root.Append (Git ("a", "https://x/greet", "1.0.0", ""));
         Root.Append (Git ("b", "https://x/greet", "", "v2.0.0"));
         Check (not AHC.Deps.Resolve (Root, Locals,
                                      Fake_Deps'Access, Sel),
                "root version + root pin for one URL is an error");
         Root.Clear;   --  and in the other declaration order
         Root.Append (Git ("b", "https://x/greet", "", "v2.0.0"));
         Root.Append (Git ("a", "https://x/greet", "1.0.0", ""));
         Check (not AHC.Deps.Resolve (Root, Locals,
                                      Fake_Deps'Access, Sel),
                "order-independent: pin then version is also an error");

         --  A transitive tag pin only demotes to a minimum.
         Root.Clear;
         Root.Append (Git ("vend", "https://x/vend", "1.0.0", ""));
         Check (AHC.Deps.Resolve (Root, Locals, Fake_Deps'Access,
                                  Sel),
                "tag-pin graph resolves");
         Check_Equal (Ref_Of (Sel, "https://x/greet"), "1.2.0",
                      "transitive tag pin demotes to a minimum");

         --  A transitive commit pin without a root pin refuses.
         Root.Clear;
         Root.Append (Git ("cpin", "https://x/cpin", "1.0.0", ""));
         Check (not AHC.Deps.Resolve (Root, Locals,
                                      Fake_Deps'Access, Sel),
                "transitive commit pin without root pin refuses");
         Root.Append
           (Git ("greet", "https://x/greet", "",
                 "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"));
         Check (AHC.Deps.Resolve (Root, Locals, Fake_Deps'Access,
                                  Sel),
                "root commit pin legitimizes the transitive one");

         --  A root path entry overrides a like-named git dep.
         Root.Clear;
         Root.Append (Path_D ("greet"));
         Root.Append (Git ("liba", "https://x/liba", "1.0.0", ""));
         Check (AHC.Deps.Resolve (Root, Locals, Fake_Deps'Access,
                                  Sel),
                "path-override graph resolves");
         Check_Equal (Ref_Of (Sel, "https://x/greet"), "(absent)",
                      "root path dep overrides the git dep");

         --  One nickname for two URLs is an error.
         Root.Clear;
         Root.Append (Git ("dup", "https://x/liba", "1.0.0", ""));
         Root.Append (Git ("dup", "https://x/libb", "1.0.0", ""));
         Check (not AHC.Deps.Resolve (Root, Locals,
                                      Fake_Deps'Access, Sel),
                "one name for two URLs is an error");

         --  URL identity: .git and trailing / collapse together.
         Root.Clear;
         Root.Append (Git ("liba", "https://x/liba.git", "1.0.0",
                           ""));
         Root.Append (Git ("liba2", "https://x/liba/", "1.0.0",
                           ""));
         Check (AHC.Deps.Resolve (Root, Locals, Fake_Deps'Access,
                                  Sel),
                "normalized-identical URLs resolve");
         Check_Equal (Integer (Sel.Length), 1,
                      "spellings of one URL merge into one entry");
      end;
   end Run;

end Test_Deps;
