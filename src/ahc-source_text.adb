with Ada.Direct_IO;
with Ada.Directories;

package body AHC.Source_Text is

   use Ada.Strings.Unbounded;

   function Is_Line_Terminator (C : Character) return Boolean
   is (C = ASCII.LF or else C = ASCII.FF);

   function Build (Name, Normalized : String) return Source is
      S : Source;
   begin
      S.Name := To_Unbounded_String (Name);
      S.Text := To_Unbounded_String (Normalized);
      if Normalized'Length > 0 then
         S.Line_Starts.Append (Byte_Offset'First);
         for I in Normalized'Range loop
            if Is_Line_Terminator (Normalized (I))
              and then I < Normalized'Last
            then
               S.Line_Starts.Append
                 (Byte_Offset (I - Normalized'First + 2));
            end if;
         end loop;
      end if;
      return S;
   end Build;

   function Normalize (Raw : String) return String is
      Result : String (1 .. Raw'Length);
      Last   : Natural := 0;
      I      : Positive := Raw'First;
   begin
      while I <= Raw'Last loop
         if Raw (I) = ASCII.CR then
            Last := Last + 1;
            Result (Last) := ASCII.LF;
            if I < Raw'Last and then Raw (I + 1) = ASCII.LF then
               I := I + 1;
            end if;
         else
            Last := Last + 1;
            Result (Last) := Raw (I);
         end if;
         I := I + 1;
      end loop;
      return Result (1 .. Last);
   end Normalize;

   function Load_String (Name, Contents : String) return Source
   is (Build (Name, Normalize (Contents)));

   function Load_File (Path : String) return Source is
      Size : constant Ada.Directories.File_Size :=
        Ada.Directories.Size (Path);
      subtype Contents_String is String (1 .. Natural (Size));
      package Contents_IO is new Ada.Direct_IO (Contents_String);
      File : Contents_IO.File_Type;
      Raw  : Contents_String;
   begin
      Contents_IO.Open (File, Contents_IO.In_File, Path);
      Contents_IO.Read (File, Raw);
      Contents_IO.Close (File);
      return Build (Path, Normalize (Raw));
   end Load_File;

   function File_Name (S : Source) return String is (To_String (S.Name));

   function Length (S : Source) return Natural is (Length (S.Text));

   function Line_Count (S : Source) return Natural
   is (Natural (S.Line_Starts.Length));

   function Char_At (S : Source; O : Byte_Offset) return Character
   is (Element (S.Text, Natural (O)));

   function Slice (S : Source; From, Stop : Byte_Offset) return String
   is (Slice (S.Text, Natural (From), Natural (Stop) - 1));

   function Line_Of (S : Source; O : Byte_Offset) return Line_Number is
      --  Binary search: greatest line whose start is <= O.
      Lo : Positive := 1;
      Hi : Positive := S.Line_Starts.Last_Index;
   begin
      while Lo < Hi loop
         declare
            Mid : constant Positive := (Lo + Hi + 1) / 2;
         begin
            if S.Line_Starts (Mid) <= O then
               Lo := Mid;
            else
               Hi := Mid - 1;
            end if;
         end;
      end loop;
      return Line_Number (Lo);
   end Line_Of;

   function Line_Start (S : Source; L : Line_Number) return Byte_Offset
   is (S.Line_Starts (Positive (L)));

   function Column_Of (S : Source; O : Byte_Offset) return Column_Number is
      Col : Positive := 1;
   begin
      for I in S.Line_Start (S.Line_Of (O)) .. O - 1 loop
         if S.Char_At (I) = ASCII.HT then
            Col := Col + (Tab_Stop - (Col - 1) mod Tab_Stop);
         else
            Col := Col + 1;
         end if;
      end loop;
      return Column_Number (Col);
   end Column_Of;

end AHC.Source_Text;
