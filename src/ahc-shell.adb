with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

package body AHC.Shell is

   use Ada.Strings.Unbounded;
   use GNAT.OS_Lib;

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

   function Capture
     (Prog : String; Args : String_Vectors.Vector;
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
         A        : Argument_List_Access := To_Arg_List (Args);
      begin
         Create_Temp_File (Tmp_FD, Tmp_Name);
         if Tmp_FD = Invalid_FD then
            Free_Args (A);
            Free (Exe);
            return "";
         end if;
         Spawn (Exe.all, A.all, Tmp_FD, Rc, Err_To_Out => True);
         Close (Tmp_FD);
         Free (Exe);
         Free_Args (A);
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

   function Capture
     (Prog : String; Arg_1 : String; Arg_2 : String := "";
      Ok : out Boolean) return String
   is
      Args : String_Vectors.Vector;
   begin
      Args.Append (Arg_1);
      if Arg_2 /= "" then
         Args.Append (Arg_2);
      end if;
      return Capture (Prog, Args, Ok);
   end Capture;

end AHC.Shell;
