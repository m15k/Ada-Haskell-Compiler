with Ada.Calendar;
with Ada.Command_Line;
with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.IO_Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Ada.Text_IO.Text_Streams;

with GNAT.OS_Lib;

package body AHC.Repl is

   use Ada.Strings.Unbounded;
   use Ada.Text_IO;

   package Line_Vectors is new Ada.Containers.Vectors
     (Positive, Unbounded_String);

   ------------------------------------------------------------------
   --  Session state
   ------------------------------------------------------------------

   Imports     : Line_Vectors.Vector;   --  entered import lines
   Decls       : Line_Vectors.Vector;   --  entered declarations
   Loaded_Body : Line_Vectors.Vector;   --  :load'ed file, verbatim
   Pragmas     : Line_Vectors.Vector;   --  its leading {-# ... #-} lines
   Loaded_Path : Unbounded_String;
   Loaded_Dir  : Unbounded_String;   --  its directory (module search)
   Orig_Path   : Unbounded_String;   --  $AHC_PATH at startup

   Root    : Unbounded_String;   --  compiler tree (bin/..)
   Scratch : Unbounded_String;   --  session working directory

   function "+" (S : String) return Unbounded_String
     renames To_Unbounded_String;

   --  The generated modules. Their names are chosen so that no user
   --  program imports one (a sibling named Repl or Probe used to be
   --  shadowed by the scratch directory), and they carry GHCi's
   --  scoping: {-# OPTIONS_AHC_SHADOW #-} makes the module's own names
   --  shadow imports and the Prelude instead of being ambiguous with
   --  them (`it = 4`, `lookup = 10`, a loaded `main`).
   Session_Mod : constant String := "AhcReplSession_";
   Expr_Mod    : constant String := "AhcReplExpr_";
   Parse_Mod   : constant String := "AhcReplParse_";
   Shadow_Pragma : constant String := "{-# OPTIONS_AHC_SHADOW #-}";

   --  Raw bytes OUT: the source is UTF-8 and must stay so (Text_IO's
   --  Put re-encoded every byte above 127, so "ünï" reached the
   --  program as mojibake); writing through the file's stream does not.
   procedure Put_Raw_Line (F : File_Type; T : String) is
   begin
      String'Write (Ada.Text_IO.Text_Streams.Stream (F), T & ASCII.LF);
   end Put_Raw_Line;

   function S (U : Unbounded_String) return String renames To_String;

   ------------------------------------------------------------------
   --  Small utilities
   ------------------------------------------------------------------

   function Trim (T : String) return String
   is (Ada.Strings.Fixed.Trim (T, Ada.Strings.Both));

   function Starts (T, Prefix : String) return Boolean
   is (T'Length >= Prefix'Length
       and then T (T'First .. T'First + Prefix'Length - 1) = Prefix);

   --  Point the compiler's module search ($AHC_PATH) at Dir (the
   --  directory of the loaded file) followed by whatever the user
   --  had set; "" restores the startup value.
   procedure Set_Module_Path (Dir : String) is
      Joined : constant String :=
        (if Dir = "" then S (Orig_Path)
         elsif Orig_Path = Null_Unbounded_String then Dir
         else Dir & ":" & S (Orig_Path));
   begin
      if Joined = "" then
         Ada.Environment_Variables.Clear ("AHC_PATH");
      else
         Ada.Environment_Variables.Set ("AHC_PATH", Joined);
      end if;
   end Set_Module_Path;

   --  First whitespace-delimited token of T.
   function First_Word (T : String) return String is
      I : Natural := T'First;
   begin
      while I <= T'Last and then T (I) /= ' ' loop
         I := I + 1;
      end loop;
      return T (T'First .. I - 1);
   end First_Word;

   procedure Write_File (Path : String; Lines : Line_Vectors.Vector) is
      F : File_Type;
   begin
      Create (F, Out_File, Path);
      for L of Lines loop
         Put_Raw_Line (F, S (L));
      end loop;
      Close (F);
   end Write_File;

   ------------------------------------------------------------------
   --  Spawning
   ------------------------------------------------------------------

   --  Run Prog with the given arguments, stdout+stderr captured to
   --  Cap. Returns the exit code (-1 when the spawn itself fails).
   function Spawn_Cap
     (Prog : String; Args : Line_Vectors.Vector; Cap : String)
      return Integer
   is
      use GNAT.OS_Lib;
      A       : Argument_List (1 .. Natural (Args.Length));
      Ok      : Boolean;
      Rc      : Integer;
   begin
      for I in A'Range loop
         A (I) := new String'(S (Args (I)));
      end loop;
      Spawn (Prog, A, Cap, Ok, Rc, Err_To_Out => True);
      for I in A'Range loop
         Free (A (I));
      end loop;
      return (if Ok then Rc else -1);
   end Spawn_Cap;

   --  Run Prog with inherited stdio (interactive programs work).
   function Spawn_Plain (Prog : String) return Integer is
      use GNAT.OS_Lib;
      A : Argument_List (1 .. 0);
   begin
      return Spawn (Prog, A);
   end Spawn_Plain;

   --  Print the diagnostic lines (": error:"/": warning:") of Cap.
   procedure Put_Diagnostics (Cap : String) is
      F : File_Type;
   begin
      Open (F, In_File, Cap);
      while not End_Of_File (F) loop
         declare
            L : constant String := Get_Line (F);
         begin
            if Ada.Strings.Fixed.Index (L, ": error:") > 0
              or else Ada.Strings.Fixed.Index (L, ": warning:") > 0
              or else Starts (L, "ahc: ")
            then
               Put_Raw_Line (Current_Output, L);
            end if;
         end;
      end loop;
      Close (F);
   exception
      when Ada.IO_Exceptions.Name_Error =>
         null;
   end Put_Diagnostics;

   --  Print Cap in full (build failures: clang's message matters).
   procedure Put_All (Cap : String) is
      F : File_Type;
   begin
      Open (F, In_File, Cap);
      while not End_Of_File (F) loop
         Put_Raw_Line (Current_Output, Get_Line (F));
      end loop;
      Close (F);
   exception
      when Ada.IO_Exceptions.Name_Error =>
         null;
   end Put_All;

   --  The scheme printed for `it` by `ahc check`, "" if absent.
   function It_Type (Cap : String) return String is
      F : File_Type;
      R : Unbounded_String;
   begin
      Open (F, In_File, Cap);
      while not End_Of_File (F) loop
         declare
            L : constant String := Get_Line (F);
         begin
            if Starts (L, "it :: ") then
               R := +(L (L'First + 6 .. L'Last));
            end if;
         end;
      end loop;
      Close (F);
      return S (R);
   exception
      when Ada.IO_Exceptions.Name_Error =>
         return "";
   end It_Type;

   --  True if the (context-stripped) type is an IO action.
   function Is_IO (Ty : String) return Boolean is
      I : constant Natural := Ada.Strings.Fixed.Index (Ty, "=> ");
      B : constant String :=
        (if I > 0 then Ty (I + 3 .. Ty'Last) else Ty);
   begin
      return B = "IO" or else Starts (B, "IO ");
   end Is_IO;

   ------------------------------------------------------------------
   --  Generated sources
   ------------------------------------------------------------------

   function Path_Of (Name : String) return String
   is (S (Scratch) & "/" & Name);

   procedure Write_Repl is
      Lines : Line_Vectors.Vector;
   begin
      for L of Pragmas loop
         Lines.Append (L);
      end loop;
      Lines.Append (+Shadow_Pragma);
      Lines.Append (+("module " & Session_Mod & " where"));
      for L of Imports loop
         Lines.Append (L);
      end loop;
      for L of Loaded_Body loop
         Lines.Append (L);
      end loop;
      for L of Decls loop
         Lines.Append (L);
      end loop;
      Write_File (Path_Of (Session_Mod & ".hs"), Lines);
   end Write_Repl;

   --  The expression module: the session's names (shadowing the
   --  Prelude, as in GHCi) plus the session's imports, and `it`.
   --  Main only runs it, so a session's own `it` or `main` never
   --  collides with the runner.
   procedure Write_Expr_Module (Expr : String) is
      Lines : Line_Vectors.Vector;
   begin
      for L of Pragmas loop
         Lines.Append (L);
      end loop;
      Lines.Append (+Shadow_Pragma);
      Lines.Append (+("module " & Expr_Mod & " where"));
      Lines.Append (+("import " & Session_Mod));
      for L of Imports loop
         Lines.Append (L);
      end loop;
      Lines.Append (+("it = " & Expr));
      Write_File (Path_Of (Expr_Mod & ".hs"), Lines);
   end Write_Expr_Module;

   procedure Write_Main (Runner : String) is
      Lines : Line_Vectors.Vector;
   begin
      Lines.Append (+"module Main where");
      Lines.Append (+("import qualified " & Expr_Mod & " as E"));
      Lines.Append (+"main :: IO ()");
      Lines.Append (+("main = " & Runner));
      Write_File (Path_Of ("Main.hs"), Lines);
   end Write_Main;

   ------------------------------------------------------------------
   --  Pipeline steps
   ------------------------------------------------------------------

   function Ahc return String is (S (Root) & "/bin/ahc");

   Cap_File : constant String := "check.out";

   --  ahc check PATH; diagnostics printed on failure.
   function Check (Path : String; Quiet : Boolean := False)
     return Boolean
   is
      Args : Line_Vectors.Vector;
      Rc   : Integer;
   begin
      Args.Append (+"check");
      Args.Append (+Path);
      Rc := Spawn_Cap (Ahc, Args, Path_Of (Cap_File));
      if Rc /= 0 and then not Quiet then
         Put_Diagnostics (Path_Of (Cap_File));
      end if;
      return Rc = 0;
   end Check;

   --  Parse probe for line classification: does the line parse as a
   --  top-level declaration?
   function Parses_As_Decl (Line : String) return Boolean is
      Lines : Line_Vectors.Vector;
      Args  : Line_Vectors.Vector;
   begin
      Lines.Append (+("module " & Parse_Mod & " where"));
      Lines.Append (+Line);
      Write_File (Path_Of (Parse_Mod & ".hs"), Lines);
      Args.Append (+"parse");
      Args.Append (+Path_Of (Parse_Mod & ".hs"));
      return Spawn_Cap (Ahc, Args, Path_Of ("parse.out")) = 0;
   end Parses_As_Decl;

   --  Build Main.hs to a binary; True on success. `ahc build`
   --  directly (M124) - no bash, no scripts/ dependency, so a
   --  session works against a bare installed bin/ahc. A separate
   --  process on purpose: each entry's compile keeps its arenas out
   --  of the long-lived REPL image, and the object cache makes the
   --  rebuild cheap anyway.
   function Build return Boolean is
      Args : Line_Vectors.Vector;
      Rc   : Integer;
   begin
      Args.Append (+"build");
      Args.Append (+Path_Of ("Main.hs"));
      Args.Append (+Path_Of ("main"));
      Rc := Spawn_Cap (Ahc, Args, Path_Of ("build.out"));
      if Rc /= 0 then
         Put_All (Path_Of ("build.out"));
      end if;
      return Rc = 0;
   end Build;

   ------------------------------------------------------------------
   --  Entry handling
   ------------------------------------------------------------------

   Decl_Keywords : constant array (1 .. 8) of Unbounded_String :=
     [+"data", +"newtype", +"type", +"class", +"instance",
      +"infix", +"infixl", +"infixr"];

   function Is_Decl_Keyword (W : String) return Boolean is
   begin
      for K of Decl_Keywords loop
         if W = S (K) then
            return True;
         end if;
      end loop;
      return False;
   end Is_Decl_Keyword;

   --  Add a declaration (or import) entry; validated, rolled back
   --  on error.
   procedure Add_Entry
     (Line : String; Into : in out Line_Vectors.Vector)
   is
      Saved : constant Line_Vectors.Vector := Into;
   begin
      Into.Append (+Line);
      Write_Repl;
      if not Check (Path_Of (Session_Mod & ".hs")) then
         Into := Saved;
         Write_Repl;
      end if;
   end Add_Entry;

   function Img (N : Integer) return String is
     (Ada.Strings.Fixed.Trim (Integer'Image (N), Ada.Strings.Both));

   procedure Eval (Expr : String) is
   begin
      Write_Repl;
      Write_Expr_Module (Expr);
      if not Check (Path_Of (Expr_Mod & ".hs")) then
         return;
      end if;
      declare
         Ty : constant String := It_Type (Path_Of (Cap_File));
      begin
         Write_Main (if Is_IO (Ty) then "E.it" else "print E.it");
      end;
      if not Build then
         return;
      end if;
      declare
         Rc : constant Integer := Spawn_Plain (Path_Of ("main"));
      begin
         if Rc /= 0 then
            Put_Line ("*** exit code " & Img (Rc));
         end if;
      end;
   end Eval;

   procedure Show_Type (Expr : String) is
   begin
      Write_Repl;
      Write_Expr_Module (Expr);
      if Check (Path_Of (Expr_Mod & ".hs")) then
         declare
            Ty : constant String := It_Type (Path_Of (Cap_File));
         begin
            if Ty /= "" then
               Put_Line (Expr & " :: " & Ty);
            end if;
         end;
      end if;
   end Show_Type;

   --  Advance the block-comment nesting depth over one line of
   --  Haskell source, skipping string literals and line comments, so
   --  an `import` inside {- ... -} is not mistaken for a real one.
   procedure Scan_Depth (L : String; Depth : in out Natural) is
      Quote : constant Character := '"';
      Tick  : constant Character := ''';
      I : Natural := L'First;
   begin
      while I <= L'Last loop
         if Depth = 0 and then L (I) = Quote then
            I := I + 1;
            while I <= L'Last and then L (I) /= Quote loop
               if L (I) = '\' then
                  I := I + 1;
               end if;
               I := I + 1;
            end loop;
         elsif Depth = 0 and then L (I) = Tick
           and then I + 2 <= L'Last and then L (I + 2) = Tick
         then
            I := I + 2;   --  a character literal such as '"'
         elsif Depth = 0 and then L (I) = '-' and then I < L'Last
           and then L (I + 1) = '-'
           and then (I + 1 = L'Last
                     or else L (I + 2) not in
                       '!' | '#' | '$' | '%' | '&' | '*' | '+' | '.'
                       | '/' | '<' | '=' | '>' | '?' | '@' | '\'
                       | '^' | '|' | '~' | ':')
         then
            return;   --  a line comment: the rest is not code
         elsif L (I) = '{' and then I < L'Last and then L (I + 1) = '-'
         then
            Depth := Depth + 1;
            I := I + 1;
         elsif Depth > 0 and then L (I) = '-' and then I < L'Last
           and then L (I + 1) = '}'
         then
            Depth := Depth - 1;
            I := I + 1;
         end if;
         I := I + 1;
      end loop;
   end Scan_Depth;

   procedure Load (Path : String) is
      Saved_I : constant Line_Vectors.Vector := Imports;
      Saved_D : constant Line_Vectors.Vector := Decls;
      Saved_B : constant Line_Vectors.Vector := Loaded_Body;
      Saved_P : constant Line_Vectors.Vector := Pragmas;
      Saved_Dir : constant Unbounded_String := Loaded_Dir;
      F       : File_Type;
      In_Header : Boolean := False;
      In_Import : Boolean := False;
      Header_Done : Boolean := False;
      Code_Seen : Boolean := False;
      Depth     : Natural := 0;
   begin
      Open (F, In_File, Path);
      Imports.Clear;
      Decls.Clear;
      Loaded_Body.Clear;
      Pragmas.Clear;
      --  Sibling modules resolve from the loaded file's directory,
      --  as in GHCi (the generated session module lives elsewhere).
      Loaded_Dir := +(if Ada.Strings.Fixed.Index (Path, "/") = 0
                      then "."
                      else Ada.Directories.Containing_Directory (Path));
      Set_Module_Path (S (Loaded_Dir));
      while not End_Of_File (F) loop
         declare
            L : constant String := Get_Line (F);
            T : constant String := Trim (L);
            Start_Depth : constant Natural := Depth;
         begin
            Scan_Depth (L, Depth);
            if Start_Depth > 0 then
               In_Import := False;
               Loaded_Body.Append (+L);   --  inside a block comment
            elsif In_Header then
               --  A (possibly multi-line) export list, through 'where'.
               In_Header := Ada.Strings.Fixed.Index (L, "where") = 0;
            elsif not Header_Done and then not Code_Seen
              and then Starts (T, "module ")
            then
               Header_Done := True;
               In_Header := Ada.Strings.Fixed.Index (L, "where") = 0;
            elsif not Code_Seen and then Starts (T, "{-#") then
               Pragmas.Append (+L);   --  must precede the module header
            elsif Starts (L, "import ") then
               --  The file's imports are session imports, so the
               --  expression module sees them (GHCi's *Main> scope).
               In_Import := True;
               Code_Seen := True;
               Imports.Append (+L);
            elsif In_Import and then L'Length > 0
              and then (L (L'First) = ' ' or else L (L'First) = ASCII.HT)
            then
               Imports.Append (+L);   --  continuation of an import
            else
               In_Import := False;
               if T /= "" and then not Starts (T, "--")
                 and then not Starts (T, "{-")
               then
                  Code_Seen := True;
               end if;
               Loaded_Body.Append (+L);
            end if;
         end;
      end loop;
      Close (F);
      Write_Repl;
      if Check (Path_Of (Session_Mod & ".hs")) then
         Loaded_Path := +Path;
         Put_Line ("loaded: " & Path);
      else
         Imports := Saved_I;
         Decls := Saved_D;
         Loaded_Body := Saved_B;
         Pragmas := Saved_P;
         Loaded_Dir := Saved_Dir;
         Set_Module_Path (S (Loaded_Dir));
         Write_Repl;
      end if;
   exception
      when Ada.IO_Exceptions.Name_Error
         | Ada.IO_Exceptions.Device_Error
         | Ada.IO_Exceptions.Use_Error =>
         if Is_Open (F) then
            Close (F);
         end if;
         Put_Line ("cannot open: " & Path);
   end Load;

   procedure Help is
   begin
      Put_Line ("commands:");
      Put_Line ("  :help :h        this text");
      Put_Line ("  :quit :q        leave the repl");
      Put_Line ("  :type E, :t E   show E's inferred type");
      Put_Line ("  :load P, :l P   load file P (resets the session;");
      Put_Line ("                  its sibling modules are found beside it)");
      Put_Line ("  :reload :r      reload the last :load");
      Put_Line ("  :! CMD          run a shell command");
      Put_Line ("  :clear          empty the session");
      Put_Line ("anything else: an import, a declaration, or an");
      Put_Line ("expression. several declarations fit one line with");
      Put_Line ("';' (f :: Int -> Int; f x = x + 1). a loaded main");
      Put_Line ("runs by typing main. IO results are");
      Put_Line ("not printed; 'it' is not kept between entries.");
   end Help;

   --  `:! CMD` / `:!CMD`: a shell command, as in GHCi - the way a
   --  session edits a sibling module between :reloads.
   procedure Shell (Cmd : String) is
      use GNAT.OS_Lib;
      A  : Argument_List (1 .. 2) :=
        [new String'("-c"), new String'(Cmd)];
      Rc : constant Integer := Spawn ("/bin/sh", A);
   begin
      Free (A (1));
      Free (A (2));
      if Rc /= 0 then
         Put_Line ("*** exit code " & Img (Rc));
      end if;
   end Shell;

   procedure Command (Line : String) is
      W    : constant String := First_Word (Line);
      Rest : constant String :=
        Trim (Line (Line'First + W'Length .. Line'Last));
   begin
      if Starts (Line, ":!") then
         if Trim (Line (Line'First + 2 .. Line'Last)) /= "" then
            Shell (Trim (Line (Line'First + 2 .. Line'Last)));
         end if;
      elsif W = ":help" or else W = ":h" or else W = ":?" then
         Help;
      elsif W = ":type" or else W = ":t" then
         if Rest /= "" then
            Show_Type (Rest);
         end if;
      elsif W = ":load" or else W = ":l" then
         if Rest /= "" then
            Load (Rest);
         end if;
      elsif W = ":reload" or else W = ":r" then
         if Loaded_Path = Null_Unbounded_String then
            Put_Line ("nothing loaded");
         else
            Load (S (Loaded_Path));
         end if;
      elsif W = ":clear" then
         Imports.Clear;
         Decls.Clear;
         Loaded_Body.Clear;
         Pragmas.Clear;
         Loaded_Path := Null_Unbounded_String;
         Loaded_Dir := Null_Unbounded_String;
         Set_Module_Path ("");
         Write_Repl;
      else
         Put_Line ("unknown command " & W & " (:h for help)");
      end if;
   end Command;

   procedure Handle (Raw : String) is
      Line : constant String := Trim (Raw);
   begin
      if Line = "" then
         return;
      end if;
      if Line (Line'First) = ':' then
         Command (Line);
      elsif Starts (Line, "import ") or else Line = "import" then
         Add_Entry (Line, Imports);
      elsif Starts (Line, "let ")
        and then Parses_As_Decl
                   (Line (Line'First + 4 .. Line'Last))
      then
         Add_Entry (Line (Line'First + 4 .. Line'Last), Decls);
      elsif Is_Decl_Keyword (First_Word (Line))
        or else Starts (Line, "{-#")
      then
         Add_Entry (Line, Decls);
      elsif not Starts (Line, "let ")
        and then Parses_As_Decl (Line)
      then
         Add_Entry (Line, Decls);
      else
         Eval (Line);
      end if;
   end Handle;

   ------------------------------------------------------------------
   --  Setup and the loop
   ------------------------------------------------------------------

   procedure Setup is
      use GNAT.OS_Lib;
      Cmd : constant String := Ada.Command_Line.Command_Name;
      Exe : GNAT.OS_Lib.String_Access :=
        (if Ada.Strings.Fixed.Index (Cmd, "/") > 0
         then new String'(Normalize_Pathname (Cmd))
         else Locate_Exec_On_Path (Cmd));
   begin
      if Exe = null then
         Exe := new String'(Normalize_Pathname ("bin/ahc"));
      end if;
      Root := +Normalize_Pathname
        (Ada.Directories.Containing_Directory (Exe.all) & "/..");
      Free (Exe);
      --  The stdlib resolves through AHC_LIB, so the session works
      --  from any directory.
      Ada.Environment_Variables.Set
        ("AHC_LIB", S (Root) & "/lib");
      if Ada.Environment_Variables.Exists ("AHC_REPL_DIR") then
         Scratch := +Ada.Environment_Variables.Value ("AHC_REPL_DIR");
      else
         declare
            use type Ada.Calendar.Time;
            Stamp : constant Duration :=
              Ada.Calendar.Clock - Ada.Calendar.Time_Of (2026, 1, 1);
            Img : String := Duration'Image (Stamp);
         begin
            for C of Img loop
               if C = ' ' or else C = '.' then
                  C := '_';
               end if;
            end loop;
            Scratch := +("/tmp/ahc-repl" & Img);
         end;
      end if;
      if Ada.Environment_Variables.Exists ("AHC_PATH") then
         Orig_Path := +Ada.Environment_Variables.Value ("AHC_PATH");
      end if;
      Ada.Directories.Create_Path (S (Scratch));
      Write_Repl;
   end Setup;

   procedure Run is
   begin
      Setup;
      Put_Line ("ahc repl - :h for help, :q to quit");
      loop
         Put ("ahc> ");
         Flush;
         declare
            Line : constant String := Get_Line;
            T    : constant String := Trim (Line);
         begin
            exit when T = ":q" or else T = ":quit";
            Handle (Line);
         end;
      end loop;
   exception
      when Ada.IO_Exceptions.End_Error =>
         New_Line;
   end Run;

end AHC.Repl;
