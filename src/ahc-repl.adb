with Ada.Calendar;
with Ada.Command_Line;
with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.IO_Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

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
   Loaded_Path : Unbounded_String;

   Root    : Unbounded_String;   --  compiler tree (bin/..)
   Scratch : Unbounded_String;   --  session working directory

   function "+" (S : String) return Unbounded_String
     renames To_Unbounded_String;

   function S (U : Unbounded_String) return String renames To_String;

   ------------------------------------------------------------------
   --  Small utilities
   ------------------------------------------------------------------

   function Trim (T : String) return String
   is (Ada.Strings.Fixed.Trim (T, Ada.Strings.Both));

   function Starts (T, Prefix : String) return Boolean
   is (T'Length >= Prefix'Length
       and then T (T'First .. T'First + Prefix'Length - 1) = Prefix);

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
         Put_Line (F, S (L));
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
            then
               Put_Line (L);
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
         Put_Line (Get_Line (F));
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
      Lines.Append (+"module Repl where");
      for L of Imports loop
         Lines.Append (L);
      end loop;
      for L of Loaded_Body loop
         Lines.Append (L);
      end loop;
      for L of Decls loop
         Lines.Append (L);
      end loop;
      Write_File (Path_Of ("Repl.hs"), Lines);
   end Write_Repl;

   procedure Write_Expr_Module
     (Name : String; Expr : String; Runner : String)
   is
      Lines : Line_Vectors.Vector;
   begin
      Lines.Append (+"module Main where");
      Lines.Append (+"import Repl");
      --  Imported names are visible in Repl but not exported by
      --  it; the expression module needs the same imports.
      for L of Imports loop
         Lines.Append (L);
      end loop;
      Lines.Append (+("it = " & Expr));
      if Runner /= "" then
         Lines.Append (+("main :: IO ()"));
         Lines.Append (+("main = " & Runner));
      end if;
      Write_File (Path_Of (Name), Lines);
   end Write_Expr_Module;

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
      Lines.Append (+"module ParseProbe where");
      Lines.Append (+Line);
      Write_File (Path_Of ("ParseProbe.hs"), Lines);
      Args.Append (+"parse");
      Args.Append (+Path_Of ("ParseProbe.hs"));
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
      if not Check (Path_Of ("Repl.hs")) then
         Into := Saved;
         Write_Repl;
      end if;
   end Add_Entry;

   procedure Eval (Expr : String) is
   begin
      Write_Repl;
      Write_Expr_Module ("Probe.hs", Expr, "");
      if not Check (Path_Of ("Probe.hs")) then
         return;
      end if;
      declare
         Ty : constant String := It_Type (Path_Of (Cap_File));
      begin
         Write_Expr_Module
           ("Main.hs", Expr,
            (if Is_IO (Ty) then "it" else "print it"));
      end;
      if not Build then
         return;
      end if;
      declare
         Rc : constant Integer := Spawn_Plain (Path_Of ("main"));
      begin
         if Rc /= 0 then
            Put_Line ("*** exit code" & Integer'Image (Rc));
         end if;
      end;
   end Eval;

   procedure Show_Type (Expr : String) is
   begin
      Write_Repl;
      Write_Expr_Module ("Probe.hs", Expr, "");
      if Check (Path_Of ("Probe.hs")) then
         declare
            Ty : constant String := It_Type (Path_Of (Cap_File));
         begin
            if Ty /= "" then
               Put_Line (Expr & " :: " & Ty);
            end if;
         end;
      end if;
   end Show_Type;

   procedure Load (Path : String) is
      Saved_I : constant Line_Vectors.Vector := Imports;
      Saved_D : constant Line_Vectors.Vector := Decls;
      Saved_B : constant Line_Vectors.Vector := Loaded_Body;
      F       : File_Type;
      In_Header : Boolean := False;
      First     : Boolean := True;
   begin
      Open (F, In_File, Path);
      Imports.Clear;
      Decls.Clear;
      Loaded_Body.Clear;
      while not End_Of_File (F) loop
         declare
            L : constant String := Get_Line (F);
         begin
            if First and then Starts (Trim (L), "module ") then
               --  Skip the header (possibly a multi-line export
               --  list) through its closing 'where'.
               In_Header :=
                 Ada.Strings.Fixed.Index (L, "where") = 0;
            elsif In_Header then
               In_Header :=
                 Ada.Strings.Fixed.Index (L, "where") = 0;
            else
               Loaded_Body.Append (+L);
            end if;
            First := False;
         end;
      end loop;
      Close (F);
      Write_Repl;
      if Check (Path_Of ("Repl.hs")) then
         Loaded_Path := +Path;
         Put_Line ("loaded: " & Path);
      else
         Imports := Saved_I;
         Decls := Saved_D;
         Loaded_Body := Saved_B;
         Write_Repl;
      end if;
   exception
      when Ada.IO_Exceptions.Name_Error =>
         Put_Line ("cannot open: " & Path);
   end Load;

   procedure Help is
   begin
      Put_Line ("commands:");
      Put_Line ("  :help :h        this text");
      Put_Line ("  :quit :q        leave the repl");
      Put_Line ("  :type E, :t E   show E's inferred type");
      Put_Line ("  :load P, :l P   load file P (resets the session)");
      Put_Line ("  :reload :r      reload the last :load");
      Put_Line ("  :clear          empty the session");
      Put_Line ("anything else: an import, a declaration, or an");
      Put_Line ("expression. several declarations fit one line with");
      Put_Line ("';' (f :: Int -> Int; f x = x + 1). a loaded main");
      Put_Line ("runs as the expression Repl.main. IO results are");
      Put_Line ("not printed; 'it' is not kept between entries.");
   end Help;

   procedure Command (Line : String) is
      W    : constant String := First_Word (Line);
      Rest : constant String :=
        Trim (Line (Line'First + W'Length .. Line'Last));
   begin
      if W = ":help" or else W = ":h" or else W = ":?" then
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
         Loaded_Path := Null_Unbounded_String;
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
