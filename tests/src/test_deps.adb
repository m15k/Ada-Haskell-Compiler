--  Collect_Roots over real fixture trees built in a scratch
--  directory: transitive order, diamond dedup, and the error
--  space (cycle, missing directory, one name for two paths).
--  Negative cases print to stderr - expected noise in the log.

with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with AHC.Deps;

with Test_Harness; use Test_Harness;

package body Test_Deps is

   use Ada.Strings.Unbounded;

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

      Ada.Directories.Delete_Tree (Scratch);
   end Run;

end Test_Deps;
