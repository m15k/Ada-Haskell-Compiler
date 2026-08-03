with Ada.Containers.Indefinite_Vectors;
with Ada.Containers.Vectors;
with Ada.Environment_Variables;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with GNAT.OS_Lib;
with GNAT.SHA256;

with System.Multiprocessors;

with AHC.Paths;

package body AHC.Build is

   use Ada.Strings.Unbounded;
   use GNAT.OS_Lib;

   package String_Vectors is new Ada.Containers.Indefinite_Vectors
     (Positive, String);
   package Sorting is new String_Vectors.Generic_Sorting;

   --  One C file to compile: everything decided (paths, flags) at
   --  collection time, so compiling is a pure spawn - that is what
   --  makes the parallel pass trivially safe.
   type Job is record
      Src, Obj : Unbounded_String;
      In_Build : Boolean;  --  unit include path (-I OUT.build)
   end record;
   package Job_Vectors is new Ada.Containers.Vectors (Positive, Job);

   function Env (Name : String) return String is
     (if Ada.Environment_Variables.Exists (Name)
      then Ada.Environment_Variables.Value (Name)
      else "");

   function Slurp (Path : String) return String is
      use Ada.Streams.Stream_IO;
      F : File_Type;
   begin
      Open (F, In_File, Path);
      declare
         Len : constant Natural := Natural (Size (F));
         S   : String (1 .. Len);
      begin
         String'Read (Stream (F), S);
         Close (F);
         return S;
      end;
   end Slurp;

   --  $(cat file): command substitution strips trailing newlines.
   function Trim_Trailing (S : String) return String is
      Last : Natural := S'Last;
   begin
      while Last >= S'First
        and then (S (Last) = ASCII.LF or else S (Last) = ASCII.CR
                  or else S (Last) = ' ' or else S (Last) = ASCII.HT)
      loop
         Last := Last - 1;
      end loop;
      return S (S'First .. Last);
   end Trim_Trailing;

   --  A flags string becomes argv words the way the shell's unquoted
   --  expansion did: split on whitespace, empties dropped.
   procedure Append_Words
     (Args : in out String_Vectors.Vector; Flags : String)
   is
      First : Natural := 0;
   begin
      for I in Flags'Range loop
         if Flags (I) = ' ' or else Flags (I) = ASCII.HT
           or else Flags (I) = ASCII.LF or else Flags (I) = ASCII.CR
         then
            if First /= 0 then
               Args.Append (Flags (First .. I - 1));
               First := 0;
            end if;
         elsif First = 0 then
            First := I;
         end if;
      end loop;
      if First /= 0 then
         Args.Append (Flags (First .. Flags'Last));
      end if;
   end Append_Words;

   function To_Arg_List
     (Args : String_Vectors.Vector) return Argument_List_Access
   is
      A : constant Argument_List_Access :=
        new Argument_List (1 .. Natural (Args.Length));
   begin
      for I in A'Range loop
         A (I) := new String'(Args (I));
      end loop;
      return A;
   end To_Arg_List;

   procedure Free_Args (A : in out Argument_List_Access) is
   begin
      for I in A'Range loop
         Free (A (I));
      end loop;
      Free (A);
   end Free_Args;

   procedure Put_Command
     (Prog : String; Args : String_Vectors.Vector)
   is
      Line : Unbounded_String := To_Unbounded_String (Prog);
   begin
      for W of Args loop
         Append (Line, " " & W);
      end loop;
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error, To_String (Line));
   end Put_Command;

   --  Spawn Prog with Args, stdio inherited (a failing clang prints
   --  its own message). True when the exit code is zero.
   function Run
     (Prog : String; Args : String_Vectors.Vector; Verbose : Boolean)
      return Boolean
   is
      Exe : GNAT.OS_Lib.String_Access := Locate_Exec_On_Path (Prog);
      Ok  : Boolean;
   begin
      if Exe = null then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ahc: cannot find '" & Prog & "' on PATH");
         return False;
      end if;
      if Verbose then
         Put_Command (Prog, Args);
      end if;
      declare
         A : Argument_List_Access := To_Arg_List (Args);
      begin
         Ok := Spawn (Exe.all, A.all) = 0;
         Free_Args (A);
      end;
      Free (Exe);
      return Ok;
   end Run;

   --  Spawn Prog with Args, stdout+stderr captured (the script's
   --  `2>/dev/null` probes). Returns the trimmed output; Ok is the
   --  zero-exit test.
   function Capture
     (Prog : String; Arg_1 : String; Arg_2 : String := "";
      Ok : out Boolean) return String
   is
      Exe : GNAT.OS_Lib.String_Access := Locate_Exec_On_Path (Prog);
   begin
      Ok := False;
      if Exe = null then
         return "";
      end if;
      declare
         Tmp_FD   : File_Descriptor;
         Tmp_Name : GNAT.OS_Lib.String_Access;
         Rc       : Integer;
         N_Args   : constant Natural := (if Arg_2 = "" then 1 else 2);
         Args     : Argument_List (1 .. N_Args);
      begin
         Args (1) := new String'(Arg_1);
         if N_Args = 2 then
            Args (2) := new String'(Arg_2);
         end if;
         Create_Temp_File (Tmp_FD, Tmp_Name);
         if Tmp_FD = Invalid_FD then
            Free (Exe);
            return "";
         end if;
         Spawn (Exe.all, Args, Tmp_FD, Rc, Err_To_Out => True);
         Close (Tmp_FD);
         Free (Exe);
         for I in Args'Range loop
            Free (Args (I));
         end loop;
         Ok := Rc = 0;
         declare
            Text    : constant String := Slurp (Tmp_Name.all);
            Success : Boolean;
         begin
            Delete_File (Tmp_Name.all, Success);
            Free (Tmp_Name);
            return Trim_Trailing (Text);
         end;
      end;
   end Capture;

   --  The cache key, byte-for-byte the script's recipe:
   --  sha256(cat FILES; printf '%s' FLAGS).
   function Hash_Of
     (Files : String_Vectors.Vector; Flags : String) return String
   is
      C : GNAT.SHA256.Context := GNAT.SHA256.Initial_Context;
   begin
      for F of Files loop
         GNAT.SHA256.Update (C, Slurp (F));
      end loop;
      GNAT.SHA256.Update (C, Flags);
      return GNAT.SHA256.Digest (C);
   end Hash_Of;

   function Compile_And_Link
     (Out_Path : String; Opts : Options) return Boolean
   is
      Build_Dir : constant String := Out_Path & ".build";
      Cache     : constant String := Build_Dir & "/cache";
      Runtime   : constant String := AHC.Paths.Runtime_Dir;
      Rts_C     : constant String := Runtime & "/ahc_rts.c";
      Rts_H     : constant String := Runtime & "/ahc_rts.h";
      Prog_H    : constant String := Build_Dir & "/ahc_prog.h";

      GC_Cflags  : Unbounded_String;
      GC_Ldflags : Unbounded_String;

      --  A foreign import's Int=long prototype may redeclare a libc
      --  builtin; that mismatch is the documented v1 type model.
      --  macOS marks the whole ucontext API deprecated; the green
      --  threads use it deliberately.
      User_Cflags : constant String :=
        Env ("AHC_CFLAGS")
        & " -Wno-incompatible-library-redeclaration"
        & " -Wno-deprecated-declarations";
      User_Ldflags : Unbounded_String :=
        To_Unbounded_String (Env ("AHC_LDFLAGS"));

      Objects : String_Vectors.Vector;
      Pending : Job_Vectors.Vector;

      function Compile_Args (J : Job) return String_Vectors.Vector is
         Args : String_Vectors.Vector;
      begin
         Args.Append ("-O1");
         Args.Append ("-c");
         Args.Append ("-o");
         Args.Append (To_String (J.Obj));
         Args.Append ("-I");
         Args.Append (Runtime);
         if J.In_Build then
            Args.Append ("-I");
            Args.Append (Build_Dir);
         end if;
         Append_Words (Args, To_String (GC_Cflags));
         Append_Words (Args, User_Cflags);
         Args.Append (To_String (J.Src));
         return Args;
      end Compile_Args;

      --  Compile every pending job with Workers tasks pulling from
      --  a shared counter. Each clang's output lands in its own
      --  temp file and is replayed in JOB order afterwards, so a
      --  parallel build's diagnostics read exactly like a serial
      --  one's - determinism is a property of the build tool too.
      --
      --  The redirection MUST happen in the child (sh -c '... >f'),
      --  never via GNAT.OS_Lib.Spawn's output-descriptor variant:
      --  that variant dup2's the WHOLE PROCESS's stdout/stderr for
      --  the child's entire lifetime, so concurrent workers trample
      --  each other's streams - run_build.sh's failure-surface test
      --  caught exactly that (a vanished link error).
      function Compile_Parallel (Workers : Positive) return Boolean
      is
         Count     : constant Natural := Natural (Pending.Length);
         Ok_Flags  : array (1 .. Count) of Boolean :=
           [others => False];
         Out_Files : array (1 .. Count) of Unbounded_String;
         Clang     : GNAT.OS_Lib.String_Access :=
           Locate_Exec_On_Path ("clang");
         Shell     : GNAT.OS_Lib.String_Access :=
           Locate_Exec_On_Path ("sh");
         All_Ok    : Boolean := True;

         function Sh_Quote (S : String) return String is
            R : Unbounded_String := To_Unbounded_String ("'");
         begin
            for C of S loop
               if C = ''' then
                  Append (R, "'\''");
               else
                  Append (R, C);
               end if;
            end loop;
            Append (R, "'");
            return To_String (R);
         end Sh_Quote;

         protected Queue is
            procedure Next (J : out Natural);
         private
            Cursor : Natural := 0;
         end Queue;

         protected body Queue is
            procedure Next (J : out Natural) is
            begin
               if Cursor < Count then
                  Cursor := Cursor + 1;
                  J := Cursor;
               else
                  J := 0;
               end if;
            end Next;
         end Queue;

         task type Worker;

         task body Worker is
            J : Natural;
         begin
            loop
               Queue.Next (J);
               exit when J = 0;
               declare
                  FD   : File_Descriptor;
                  Name : GNAT.OS_Lib.String_Access;
                  Cmd  : Unbounded_String;
                  Rc   : Integer := 1;
               begin
                  Create_Temp_File (FD, Name);
                  if FD /= Invalid_FD then
                     Close (FD);
                     Out_Files (J) := To_Unbounded_String (Name.all);
                     Cmd := To_Unbounded_String
                       ("exec " & Sh_Quote (Clang.all));
                     for W of Compile_Args (Pending (J)) loop
                        Append (Cmd, " " & Sh_Quote (W));
                     end loop;
                     Append (Cmd,
                             " > " & Sh_Quote (Name.all) & " 2>&1");
                     declare
                        Args : Argument_List_Access :=
                          new Argument_List'
                            (1 => new String'("-c"),
                             2 => new String'(To_String (Cmd)));
                     begin
                        Rc := Spawn (Shell.all, Args.all);
                        Free_Args (Args);
                     end;
                  end if;
                  Free (Name);
                  Ok_Flags (J) := Rc = 0;
               exception
                  when others =>
                     Ok_Flags (J) := False;
               end;
            end loop;
         end Worker;

      begin
         if Clang = null or else Shell = null then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "ahc: cannot find 'clang' and 'sh' on PATH");
            Free (Clang);
            Free (Shell);
            return False;
         end if;
         if Opts.Verbose then
            for J of Pending loop
               Put_Command ("clang", Compile_Args (J));
            end loop;
         end if;
         declare
            Pool : array (1 .. Workers) of Worker;
            pragma Unreferenced (Pool);
         begin
            null;  --  the declare block joins the pool
         end;
         Free (Clang);
         Free (Shell);
         for J in 1 .. Count loop
            if Out_Files (J) /= "" then
               declare
                  Text    : constant String :=
                    Slurp (To_String (Out_Files (J)));
                  Success : Boolean;
               begin
                  Delete_File (To_String (Out_Files (J)), Success);
                  if Text /= "" then
                     Ada.Text_IO.Put_Line
                       (Ada.Text_IO.Standard_Error,
                        Trim_Trailing (Text));
                  end if;
               end;
            end if;
            All_Ok := All_Ok and Ok_Flags (J);
         end loop;
         return All_Ok;
      end Compile_Parallel;

      function Compile_Pending return Boolean is
         Auto : constant Positive :=
           Positive (System.Multiprocessors.Number_Of_CPUs);
         Want : constant Positive :=
           (if Opts.Jobs = 0 then Auto else Opts.Jobs);
         W    : constant Natural :=
           Natural'Min (Want, Natural (Pending.Length));
      begin
         if W <= 1 then
            for J of Pending loop
               if not Run ("clang", Compile_Args (J), Opts.Verbose)
               then
                  return False;
               end if;
            end loop;
            return True;
         end if;
         return Compile_Parallel (W);
      end Compile_Pending;

      procedure Stage (Src, Obj : String; In_Build : Boolean) is
      begin
         if not Ada.Directories.Exists (Obj) then
            Pending.Append
              (Job'(Src      => To_Unbounded_String (Src),
                    Obj      => To_Unbounded_String (Obj),
                    In_Build => In_Build));
         end if;
         Objects.Append (Obj);
      end Stage;

   begin
      if not Ada.Directories.Exists (Rts_C) then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ahc: cannot find the runtime (looked for " & Rts_C
            & "; set AHC_RUNTIME)");
         return False;
      end if;
      Ada.Directories.Create_Path (Cache);

      --  Memory manager selection (collector-design-note.md):
      --  own and none define themselves; boehm is probed - and an
      --  older collector without the coroutine API falls back to
      --  no-GC rather than miscompile the runtime.
      declare
         GC : constant String :=
           (if Env ("AHC_GC") = "" then "boehm" else Env ("AHC_GC"));
      begin
         if GC = "own" then
            GC_Cflags := To_Unbounded_String ("-DAHC_GC_OWN");
         elsif GC /= "none" then
            declare
               Ok     : Boolean;
               Prefix : constant String :=
                 Capture ("brew", "--prefix", "bdw-gc", Ok);
            begin
               if Ok and then Prefix /= ""
                 and then Ada.Directories.Exists (Prefix)
                 and then Ada.Directories.Exists
                   (Prefix & "/include/gc/gc.h")
                 and then Ada.Strings.Fixed.Index
                   (Slurp (Prefix & "/include/gc/gc.h"),
                    "GC_set_stackbottom") > 0
               then
                  GC_Cflags := To_Unbounded_String
                    ("-I" & Prefix
                     & "/include -DAHC_USE_BOEHM -DGC_THREADS");
                  GC_Ldflags := To_Unbounded_String
                    ("-L" & Prefix & "/lib -lgc");
               end if;
            end;
            --  No Homebrew (or no bdw-gc in it): ask pkg-config,
            --  which is how the collector is found everywhere else.
            --  8.2 is the floor - green threads need the coroutine
            --  API (GC_set_stackbottom), and an older collector
            --  falls back to no-GC rather than miscompile.
            if GC_Cflags = "" then
               declare
                  Have : Boolean;
                  Ignore : constant String :=
                    Capture ("pkg-config", "--atleast-version=8.2",
                             "bdw-gc", Have);
                  Cf_Ok, Lf_Ok : Boolean;
               begin
                  pragma Unreferenced (Ignore);
                  if Have then
                     declare
                        Cf : constant String :=
                          Capture ("pkg-config", "--cflags", "bdw-gc",
                                   Cf_Ok);
                        Lf : constant String :=
                          Capture ("pkg-config", "--libs", "bdw-gc",
                                   Lf_Ok);
                     begin
                        if Cf_Ok and then Lf_Ok then
                           GC_Cflags := To_Unbounded_String
                             (Cf & " -DAHC_USE_BOEHM -DGC_THREADS");
                           GC_Ldflags := To_Unbounded_String (Lf);
                        end if;
                     end;
                  end if;
               end;
            end if;
         end if;
      end;

      --  OPTIONS_AHC_LINK pragmas, collected by emit.
      if Ada.Directories.Exists (Build_Dir & "/link_flags") then
         Append (User_Ldflags,
                 " " & Trim_Trailing (Slurp (Build_Dir
                   & "/link_flags")));
      end if;

      declare
         --  Compile flags are part of every cache key: a flag change
         --  must never reuse a stale object.
         Flags_Key : constant String :=
           To_String (GC_Cflags) & " " & User_Cflags;

         Rts_Inputs : String_Vectors.Vector;
      begin
         --  The runtime, cached like any unit.
         Rts_Inputs.Append (Rts_C);
         Rts_Inputs.Append (Rts_H);
         Stage (Rts_C,
                Cache & "/rts_" & Hash_Of (Rts_Inputs, Flags_Key)
                & ".o",
                In_Build => False);

         --  Program units, in the shell glob's sorted order (link
         --  order is part of byte-identical binaries).
         declare
            use Ada.Directories;
            Units  : String_Vectors.Vector;
            Search : Search_Type;
            Item   : Directory_Entry_Type;
         begin
            Start_Search (Search, Build_Dir, "*.c",
                          [Ordinary_File => True, others => False]);
            while More_Entries (Search) loop
               Get_Next_Entry (Search, Item);
               Units.Append (Simple_Name (Item));
            end loop;
            End_Search (Search);
            Sorting.Sort (Units);

            for U of Units loop
               declare
                  Base   : constant String :=
                    U (U'First .. U'Last - 2);
                  Inputs : String_Vectors.Vector;
               begin
                  Inputs.Append (Build_Dir & "/" & U);
                  Inputs.Append (Prog_H);
                  Inputs.Append (Rts_H);
                  Stage (Build_Dir & "/" & U,
                         Cache & "/" & Base & "_"
                         & Hash_Of (Inputs, Flags_Key) & ".o",
                         In_Build => True);
               end;
            end loop;
         end;
      end;

      if not Compile_Pending then
         return False;
      end if;

      if Opts.Lib then
         --  A static archive (runtime object included) plus the
         --  generated export header. The host controls the stack.
         if Ada.Directories.Exists (Out_Path) then
            Ada.Directories.Delete_File (Out_Path);
         end if;
         declare
            Args : String_Vectors.Vector;
         begin
            Args.Append ("rcs");
            Args.Append (Out_Path);
            for O of Objects loop
               Args.Append (O);
            end loop;
            if not Run ("ar", Args, Opts.Verbose) then
               return False;
            end if;
         end;
         Ada.Text_IO.Put_Line
           ("built " & Out_Path & " (header: " & Build_Dir
            & "/ahc_exports.h; link with: " & To_String (GC_Ldflags)
            & " " & To_String (User_Ldflags) & ")");
         return True;
      end if;

      --  Graph reduction evaluates long thunk chains by C recursion;
      --  give the main thread a 1GB (virtual, lazily committed)
      --  stack so depth limits match practical programs. The linker
      --  spelling is per-OS.
      declare
         Ok    : Boolean;
         Uname : constant String := Capture ("uname", "-s", Ok => Ok);
         Stack : constant String :=
           (if Uname = "Darwin"
            then "-Wl,-stack_size,0x40000000"
            else "-Wl,-z,stacksize=0x40000000");
         Args  : String_Vectors.Vector;
      begin
         Args.Append ("-O1");
         Args.Append ("-o");
         Args.Append (Out_Path);
         Args.Append (Stack);
         for O of Objects loop
            Args.Append (O);
         end loop;
         Append_Words (Args, To_String (GC_Ldflags));
         Append_Words (Args, To_String (User_Ldflags));
         if not Run ("clang", Args, Opts.Verbose) then
            return False;
         end if;
      end;
      Ada.Text_IO.Put_Line ("built " & Out_Path);
      return True;
   end Compile_And_Link;

end AHC.Build;
