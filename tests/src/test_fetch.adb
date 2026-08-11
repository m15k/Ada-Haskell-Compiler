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
         "https/github.com/u/foo",
         "identity keeps the scheme as a clean path segment");
      Check_Equal
        (AHC.Fetch.Identity_Path ("file:///tmp/repos/foo"),
         "file/tmp/repos/foo",
         "file identity drops the extra leading slashes");
      --  Adversarial/security review: http and https to one host
      --  are DISTINCT identities, so a weaker scheme cannot shadow
      --  a stronger one's cache entry or ahc.sum line.
      Check (AHC.Fetch.Identity_Path ("http://h/x")
             /= AHC.Fetch.Identity_Path ("https://h/x"),
             "http and https identities differ");
      Check_Equal (AHC.Fetch.Identity_Path ("http://h/x"),
                   "http/h/x", "http scheme kept");

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
