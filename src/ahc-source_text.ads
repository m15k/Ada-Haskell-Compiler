--  Source buffers with offset <-> line/column mapping.
--
--  Newlines are normalized at load time (CRLF and lone CR become LF), so
--  byte offsets always refer to the normalized buffer. LF and FF both
--  terminate a line (Report 2.2 counts formfeed as a newline character).
--  Columns follow Report 10.3: the first column is 1 and tab stops are
--  8 characters apart.

private with Ada.Strings.Unbounded;
private with Ada.Containers.Vectors;

package AHC.Source_Text is

   type Byte_Offset is new Positive;
   type Line_Number is new Positive;
   type Column_Number is new Positive;

   Tab_Stop : constant := 8;

   type Source is tagged private;

   function Load_String (Name, Contents : String) return Source;

   --  Propagates Ada.IO_Exceptions on unreadable paths.
   function Load_File (Path : String) return Source;

   function File_Name (S : Source) return String;

   function Length (S : Source) return Natural;

   function Line_Count (S : Source) return Natural
     with Post => (Line_Count'Result = 0) = (S.Length = 0);

   function In_Range (S : Source; O : Byte_Offset) return Boolean
   is (Natural (O) <= S.Length);

   function Char_At (S : Source; O : Byte_Offset) return Character
     with Pre => S.In_Range (O);

   --  Half-open [From, Stop): Stop = From yields "".
   function Slice (S : Source; From, Stop : Byte_Offset) return String
     with
       Pre  => Stop >= From and then Natural (Stop) <= S.Length + 1,
       Post => Slice'Result'Length = Natural (Stop - From);

   function Line_Of (S : Source; O : Byte_Offset) return Line_Number
     with
       Pre  => S.In_Range (O),
       Post => Natural (Line_Of'Result) <= S.Line_Count;

   --  Byte offset of the first character of line L.
   function Line_Start (S : Source; L : Line_Number) return Byte_Offset
     with Pre => Natural (L) <= S.Line_Count;

   --  Column of the character at O, counting tab stops (Report 10.3).
   function Column_Of (S : Source; O : Byte_Offset) return Column_Number
     with Pre => S.In_Range (O);

private

   package Line_Tables is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Byte_Offset);

   type Source is tagged record
      Name        : Ada.Strings.Unbounded.Unbounded_String;
      Text        : Ada.Strings.Unbounded.Unbounded_String;
      Line_Starts : Line_Tables.Vector;  --  index N = start of line N
   end record;

end AHC.Source_Text;
