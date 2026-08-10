with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Text_IO;

with GNAT.OS_Lib;
with GNAT.SHA256;

with AHC.Shell;

package body AHC.Fetch is

   use AHC.Shell;

   package Sorting is new String_Vectors.Generic_Sorting;

   procedure Err (Msg : String) is
   begin
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error, "ahc: " & Msg);
   end Err;

   function Cache_Root return String is
   begin
      if Ada.Environment_Variables.Exists ("AHC_MOD") then
         return Ada.Environment_Variables.Value ("AHC_MOD");
      end if;
      return (if Ada.Environment_Variables.Exists ("HOME")
              then Ada.Environment_Variables.Value ("HOME")
              else ".") & "/.ahc/mod";
   end Cache_Root;

   function Normalize_URL (URL : String) return String is
      Last : Natural := URL'Last;
   begin
      if Last >= URL'First and then URL (Last) = '/' then
         Last := Last - 1;
      end if;
      if Last - 3 >= URL'First
        and then URL (Last - 3 .. Last) = ".git"
      then
         Last := Last - 4;
      end if;
      return URL (URL'First .. Last);
   end Normalize_URL;

   function Identity_Path (URL : String) return String is
      N : constant String := Normalize_URL (URL);
      S : constant Natural := Ada.Strings.Fixed.Index (N, "://");
      From : Natural :=
        (if S > 0 then S + 3 else N'First);
   begin
      while From <= N'Last and then N (From) = '/' loop
         From := From + 1;   --  file:///tmp/x -> tmp/x
      end loop;
      return N (From .. N'Last);
   end Identity_Path;

   --  Every regular file under Dir, as sorted Dir-relative paths.
   procedure List_Files
     (Dir, Prefix : String; Files : in out String_Vectors.Vector)
   is
      use Ada.Directories;
      It : Search_Type;
      E  : Directory_Entry_Type;
   begin
      Start_Search (It, Dir, "",
                    [Directory => True, Ordinary_File => True,
                     Special_File => False]);
      while More_Entries (It) loop
         Get_Next_Entry (It, E);
         declare
            Simple : constant String := Simple_Name (E);
            Full   : constant String := Dir & "/" & Simple;
         begin
            --  Skip a symlink rather than follow it: a link to a
            --  directory would recurse (a self-link loops, a link
            --  to "/" walks the whole filesystem) and a link to a
            --  file would hash content outside the tree. Kind
            --  follows the link, so test before dispatching, and
            --  guard Kind itself against a dangling entry.
            if Simple /= "." and then Simple /= ".."
              and then not GNAT.OS_Lib.Is_Symbolic_Link (Full)
            then
               begin
                  case Kind (E) is
                     when Ordinary_File =>
                        Files.Append (Prefix & Simple);
                     when Directory =>
                        List_Files (Full, Prefix & Simple & "/",
                                    Files);
                     when Special_File =>
                        null;
                  end case;
               exception
                  when others => null;   --  unstat-able: skip
               end;
            end if;
         end;
      end loop;
      End_Search (It);
   end List_Files;

   function Dirhash (Dir : String) return String is
      Files : String_Vectors.Vector;
      C     : GNAT.SHA256.Context := GNAT.SHA256.Initial_Context;
   begin
      List_Files (Dir, "", Files);
      Sorting.Sort (Files);
      for F of Files loop
         --  Fold each file in as two fixed-width digests -
         --  content then relative path - so the record structure
         --  is unambiguous. A raw "digest  path" line with the
         --  path last is forgeable: a filename containing a
         --  newline could fabricate a second record boundary.
         declare
            Content : constant GNAT.SHA256.Message_Digest :=
              GNAT.SHA256.Digest (Slurp (Dir & "/" & F));
            Name    : constant GNAT.SHA256.Message_Digest :=
              GNAT.SHA256.Digest (F);
         begin
            GNAT.SHA256.Update (C, String (Content));
            GNAT.SHA256.Update (C, String (Name));
         end;
      end loop;
      return GNAT.SHA256.Digest (C);
   end Dirhash;

   --  ahc.sum: one line per entry, "IDENTITY REF h1:HEX". Match
   --  the entry or append it; a present-but-different hash is the
   --  protection firing, never overwritten silently.
   function Check_Sum
     (Sum_Path, Ident, Ref, Hash : String) return Boolean
   is
      use Ada.Text_IO;
      Key : constant String := Ident & " " & Ref;
      F   : File_Type;
   begin
      if Ada.Directories.Exists (Sum_Path) then
         Open (F, In_File, Sum_Path);
         while not End_Of_File (F) loop
            declare
               Line : constant String := Get_Line (F);
            begin
               if Line'Length > Key'Length + 4
                 and then Line (Line'First
                                .. Line'First + Key'Length - 1) = Key
                 and then Line (Line'First + Key'Length
                                .. Line'First + Key'Length + 3)
                          = " h1:"
               then
                  Close (F);
                  if Line (Line'First + Key'Length + 4 .. Line'Last)
                    = Hash
                  then
                     return True;
                  end if;
                  Err (Ident & "@" & Ref & " does not match "
                       & Sum_Path & "; the fetched tree has been"
                       & " modified since it was recorded - delete"
                       & " that ahc.sum line only if you mean it");
                  return False;
               end if;
            end;
         end loop;
         Close (F);
         Open (F, Append_File, Sum_Path);
      else
         Create (F, Out_File, Sum_Path);
      end if;
      Put_Line (F, Key & " h1:" & Hash);
      Close (F);
      return True;
   exception
      when others =>
         if Is_Open (F) then
            Close (F);   --  never leak the handle on an I/O error
         end if;
         Err ("cannot update " & Sum_Path);
         return False;
   end Check_Sum;

   function Is_Commit (Ref : String) return Boolean is
     (Ref'Length = 40
      and then (for all C of Ref =>
                  C in '0' .. '9' | 'a' .. 'f'));

   --  A cache path is built from <identity>@<ref>, and an ahc.sum
   --  line is "<identity> <ref> h1:...". Both fields are
   --  attacker-controlled (a project's own ahc.toml is untrusted
   --  input, as are fetched manifests). Refuse anything that could
   --  escape the cache root or make either delimiter ambiguous: a
   --  control char, a space, an '@', an absolute leading '/', or a
   --  '..' path component.
   function Safe_Segment (S : String) return Boolean is
   begin
      if S'Length = 0 or else S (S'First) = '/' then
         return False;
      end if;
      for C of S loop
         if C <= ' ' or else C = '@' then
            return False;
         end if;
      end loop;
      --  No '..' as a whole '/'-delimited component.
      declare
         From : Positive := S'First;
      begin
         for I in S'Range loop
            if S (I) = '/' then
               if S (From .. I - 1) = ".." then
                  return False;
               end if;
               From := I + 1;
            end if;
         end loop;
         return S (From .. S'Last) /= "..";
      end;
   end Safe_Segment;

   --  The clone URL is handed to `git clone` verbatim. A leading
   --  '-' would be parsed as an OPTION, not a repository - and
   --  `git = "--upload-pack=<cmd>"` runs <cmd> during a local-
   --  transport fetch. Refuse a URL that begins with '-' (never a
   --  real URL) or carries a space/control char, and belt-and-
   --  suspenders the argv with an end-of-options "--" at the call.
   function Safe_URL (S : String) return Boolean is
   begin
      if S'Length = 0 or else S (S'First) = '-' then
         return False;
      end if;
      for C of S loop
         if C <= ' ' then
            return False;
         end if;
      end loop;
      return True;
   end Safe_URL;

   --  A git refname can never contain ':' - and a ':' in the ref
   --  is what let a crafted pin make the cache path look like an
   --  scp-style "host:path", steering the fetch onto a transport
   --  that honours --upload-pack. Versions and 40-hex commits have
   --  none; a tag pin with one is invalid anyway.
   function Safe_Ref (S : String) return Boolean is
     (Safe_Segment (S) and then (for all C of S => C /= ':'));

   function Ensure
     (Clone_URL  : String;
      Ref        : String;
      Is_Version : Boolean;
      Sum_Path   : String;
      Dir        : out Unbounded_String;
      Quiet      : Boolean := False) return Boolean
   is
      Ident : constant String := Identity_Path (Clone_URL);
      Where : constant String :=
        Cache_Root & "/" & Ident & "@" & Ref;
      Tmp   : constant String := Where & ".fetch";

      function Git (Args : String_Vectors.Vector) return Boolean is
         Ok  : Boolean;
         Out_Text : constant String := Capture ("git", Args, Ok);
      begin
         if not Ok and then Out_Text /= "" then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error, Out_Text);
         end if;
         return Ok;
      end Git;

      function Clone_Tag (Tag : String) return Boolean is
         Args : String_Vectors.Vector;
      begin
         Args.Append ("clone");
         Args.Append ("--quiet");
         Args.Append ("--depth");
         Args.Append ("1");
         Args.Append ("--branch");
         Args.Append (Tag);
         Args.Append ("--config");
         Args.Append ("advice.detachedHead=false");
         Args.Append ("--");   --  end of options: URL is positional
         Args.Append (Clone_URL);
         Args.Append (Tmp);
         return Git (Args);
      end Clone_Tag;

      function Clone_Commit return Boolean is
         Args : String_Vectors.Vector;
      begin
         Args.Append ("clone");
         Args.Append ("--quiet");
         Args.Append ("--");   --  end of options: URL is positional
         Args.Append (Clone_URL);
         Args.Append (Tmp);
         if not Git (Args) then
            return False;
         end if;
         Args.Clear;
         Args.Append ("-C");
         Args.Append (Tmp);
         Args.Append ("checkout");
         Args.Append ("--quiet");
         Args.Append ("--detach");
         Args.Append (Ref);
         return Git (Args);
      end Clone_Commit;

   begin
      Dir := To_Unbounded_String (Where);

      if not Safe_URL (Clone_URL) then
         Err ("refusing dependency URL '" & Clone_URL
              & "': a git URL may not begin with '-' (it would be"
              & " read as a git option) or contain whitespace");
         return False;
      end if;
      if not Safe_Segment (Ident) or else not Safe_Ref (Ref) then
         Err ("refusing dependency " & Ident & "@" & Ref
              & ": a URL or ref with '..', ':', whitespace, '@', or"
              & " a leading '/' could escape the module cache or"
              & " redirect the fetch");
         return False;
      end if;

      --  Warm cache: re-verify, never re-fetch.
      if Ada.Directories.Exists (Where) then
         begin
            return Check_Sum (Sum_Path, Ident, Ref, Dirhash (Where));
         exception
            when others =>
               Err ("cannot hash the cached tree for " & Ident
                    & "@" & Ref);
               return False;
         end;
      end if;

      Ada.Environment_Variables.Set ("GIT_TERMINAL_PROMPT", "0");
      --  Confine transports to the ones a dependency legitimately
      --  uses, so neither a crafted URL nor a repo's own config can
      --  reach the ext:: (arbitrary-command) transport.
      Ada.Environment_Variables.Set
        ("GIT_ALLOW_PROTOCOL", "https:http:ssh:git:file");
      --  Never let ssh block the build on a host-key or passphrase
      --  prompt (stdin is inherited); a bad ssh URL fails fast.
      if not Ada.Environment_Variables.Exists ("GIT_SSH_COMMAND") then
         Ada.Environment_Variables.Set
           ("GIT_SSH_COMMAND",
            "ssh -o BatchMode=yes -o StrictHostKeyChecking=yes");
      end if;
      if not Quiet then
         Err ("fetching " & Ident & " " & Ref);
      end if;
      begin
         Ada.Directories.Create_Path
           (Ada.Directories.Containing_Directory (Where));
         if Ada.Directories.Exists (Tmp) then
            Ada.Directories.Delete_Tree (Tmp);
         end if;
      exception
         when others =>
            Err ("cannot prepare cache under " & Cache_Root);
            return False;
      end;

      if not (if Is_Version
              then Clone_Tag ("v" & Ref) or else Clone_Tag (Ref)
              elsif Is_Commit (Ref)
              then Clone_Commit
              else Clone_Tag (Ref))
      then
         Err ("cannot fetch " & Ident & " " & Ref
              & " (from " & Clone_URL & ")");
         return False;
      end if;

      --  Strip .git (it is not part of the package and its
      --  contents are volatile), hash, and verify - all under a
      --  guard, so an unreadable file or an odd .git layout is a
      --  clean error, not a traceback.
      declare
         Matched : Boolean;
      begin
         if Ada.Directories.Exists (Tmp & "/.git") then
            Ada.Directories.Delete_Tree (Tmp & "/.git");
         end if;
         Matched := Check_Sum (Sum_Path, Ident, Ref, Dirhash (Tmp));
         if not Matched then
            Ada.Directories.Delete_Tree (Tmp);
            return False;
         end if;
      exception
         when others =>
            Err ("cannot hash the fetched tree for " & Ident
                 & "@" & Ref);
            begin
               Ada.Directories.Delete_Tree (Tmp);
            exception
               when others => null;
            end;
            return False;
      end;

      declare
         Ok : Boolean;
      begin
         GNAT.OS_Lib.Rename_File (Tmp, Where, Ok);
         if not Ok then
            Err ("cannot move fetched tree into " & Where);
            return False;
         end if;
      end;
      return True;
   end Ensure;

end AHC.Fetch;
