--  The fetcher's pure parts: URL identity and the directory hash.
--  No git anywhere - the network paths belong to run_pkg.sh.

with Ada.Directories;
with Ada.Text_IO;

with AHC.Fetch;

with Test_Harness; use Test_Harness;

package body Test_Fetch is

   Scratch : constant String := "unit_scratch_fetch";

   procedure Write_File (Path, Content : String) is
      use Ada.Text_IO;
      F : File_Type;
   begin
      Create (F, Out_File, Path);
      Put (F, Content);
      Close (F);
   end Write_File;

   procedure Run is
   begin
      Start_Suite ("Fetch");

      Check_Equal
        (AHC.Fetch.Normalize_URL ("https://github.com/u/foo.git"),
         "https://github.com/u/foo", ".git suffix stripped");
      Check_Equal
        (AHC.Fetch.Normalize_URL ("https://github.com/u/foo/"),
         "https://github.com/u/foo", "trailing slash stripped");
      Check_Equal
        (AHC.Fetch.Normalize_URL ("https://github.com/u/foo"),
         "https://github.com/u/foo", "clean URL unchanged");
      Check_Equal
        (AHC.Fetch.Identity_Path ("https://github.com/u/foo.git"),
         "github.com/u/foo", "identity drops the scheme");
      Check_Equal
        (AHC.Fetch.Identity_Path ("file:///tmp/repos/foo"),
         "tmp/repos/foo", "file identity drops the leading slash");

      --  Dirhash: stable, content-sensitive, layout-sensitive.
      if Ada.Directories.Exists (Scratch) then
         Ada.Directories.Delete_Tree (Scratch);
      end if;
      Ada.Directories.Create_Path (Scratch & "/a/sub");
      Write_File (Scratch & "/a/one.txt", "alpha");
      Write_File (Scratch & "/a/sub/two.txt", "beta");
      declare
         H1 : constant String := AHC.Fetch.Dirhash (Scratch & "/a");
         H2 : constant String := AHC.Fetch.Dirhash (Scratch & "/a");
      begin
         Check (H1'Length = 64, "dirhash is a sha256 hex string");
         Check_Equal (H2, H1, "dirhash is stable");
         Write_File (Scratch & "/a/one.txt", "ALPHA");
         Check (AHC.Fetch.Dirhash (Scratch & "/a") /= H1,
                "content change changes the hash");
         Write_File (Scratch & "/a/one.txt", "alpha");
         Check_Equal (AHC.Fetch.Dirhash (Scratch & "/a"), H1,
                      "restoring content restores the hash");
         Ada.Directories.Rename
           (Scratch & "/a/sub/two.txt", Scratch & "/a/two.txt");
         Check (AHC.Fetch.Dirhash (Scratch & "/a") /= H1,
                "moving a file changes the hash");
      end;
      Ada.Directories.Delete_Tree (Scratch);
   end Run;

end Test_Fetch;
