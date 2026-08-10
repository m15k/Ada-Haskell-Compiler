--  The manifest reader: flat keys (M129 back-compat), [package],
--  [dependencies.NAME] sections, and the validation errors. The
--  negative cases print their diagnostics to stderr - that noise
--  is expected in the test log.

with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with AHC.Manifest;

with Test_Harness; use Test_Harness;

package body Test_Manifest is

   use Ada.Strings.Unbounded;

   Scratch : constant String := "unit_scratch_manifest";

   procedure Write_File (Path, Content : String) is
      use Ada.Text_IO;
      F : File_Type;
   begin
      Create (F, Out_File, Path);
      Put (F, Content);
      Close (F);
   end Write_File;

   function Load (Content : String;
                  P : out AHC.Manifest.Project;
                  Require_Main : Boolean := True) return Boolean is
      Path : constant String := Scratch & "/ahc.toml";
   begin
      Write_File (Path, Content);
      return AHC.Manifest.Load (Path, P, Require_Main);
   end Load;

   procedure Run is
      P : AHC.Manifest.Project;
   begin
      Start_Suite ("Manifest");
      Ada.Directories.Create_Path (Scratch);

      --  M129 flat manifest parses exactly as before.
      Check (Load ("main = ""app.hs""" & ASCII.LF
                   & "output = ""app""" & ASCII.LF
                   & "jobs = 4" & ASCII.LF
                   & "lib = true" & ASCII.LF, P),
             "flat manifest still parses");
      Check_Equal (To_String (P.Main), "app.hs", "flat main");
      Check_Equal (To_String (P.Output), "app", "flat output");
      Check_Equal (Integer (P.Jobs), 4, "flat jobs");
      Check (P.Lib, "flat lib");
      Check (P.Deps.Is_Empty, "flat manifest has no deps");

      --  [package] identity.
      Check (Load ("main = ""m.hs""" & ASCII.LF
                   & "[package]" & ASCII.LF
                   & "name = ""app""" & ASCII.LF
                   & "version = ""0.1.0""" & ASCII.LF, P),
             "[package] section parses");
      Check_Equal (To_String (P.Pkg_Name), "app", "package name");
      Check_Equal (To_String (P.Pkg_Version), "0.1.0",
                   "package version");

      --  Dependencies, in manifest order, comments and all.
      Check (Load ("main = ""m.hs""  # root" & ASCII.LF
                   & "[dependencies.jsonlite]" & ASCII.LF
                   & "path = ""../jsonlite""" & ASCII.LF
                   & "[dependencies.fmt]" & ASCII.LF
                   & "path = ""vendor/fmt""" & ASCII.LF, P),
             "two dependency sections parse");
      Check_Equal (Integer (P.Deps.Length), 2, "two deps recorded");
      Check_Equal (To_String (P.Deps (1).Name), "jsonlite",
                   "first dep name in manifest order");
      Check_Equal (To_String (P.Deps (1).Path), "../jsonlite",
                   "first dep path");
      Check_Equal (To_String (P.Deps (2).Name), "fmt",
                   "second dep name in manifest order");

      --  Negative space.
      Check (not Load ("main = ""m.hs""" & ASCII.LF
                       & "[dependencies.a]" & ASCII.LF
                       & "path = ""x""" & ASCII.LF
                       & "[dependencies.a]" & ASCII.LF
                       & "path = ""y""" & ASCII.LF, P),
             "duplicate dependency name is an error");
      Check (not Load ("main = ""m.hs""" & ASCII.LF
                       & "[dependencies.a]" & ASCII.LF, P),
             "dependency without path is an error");
      Check (not Load ("main = ""m.hs""" & ASCII.LF
                       & "[profile]" & ASCII.LF, P),
             "unknown section is an error");
      Check (not Load ("main = ""m.hs""" & ASCII.LF
                       & "[dependencies.a]" & ASCII.LF
                       & "git = ""https://x/y""" & ASCII.LF, P),
             "git key is rejected until its milestone");
      Check (not Load ("main = ""m.hs""" & ASCII.LF
                       & "[package]" & ASCII.LF
                       & "author = ""me""" & ASCII.LF, P),
             "unknown key in [package] is an error");
      Check (not Load ("main = ""m.hs""" & ASCII.LF
                       & "[dependencies.a b]" & ASCII.LF, P),
             "dependency name with a space is an error");
      Check (not Load ("[package]" & ASCII.LF
                       & "name = ""x""" & ASCII.LF, P),
             "missing main still fails by default");

      --  A dependency's own manifest needs no main.
      Check (Load ("[dependencies.a]" & ASCII.LF
                   & "path = ""x""" & ASCII.LF, P,
                   Require_Main => False),
             "Require_Main => False accepts a main-less manifest");
      Check_Equal (Integer (P.Deps.Length), 1,
                   "main-less manifest still yields its deps");

      Ada.Directories.Delete_Tree (Scratch);
   end Run;

end Test_Manifest;
