with Ada.Text_IO;

package body AHC.Diagnostics is

   procedure Add
     (Bag     : in out Diagnostic_Bag;
      Sev     : Severity_Kind;
      Code    : Diag_Code;
      Span    : Source_Span;
      Message : String) is
   begin
      if Sev = Error then
         Bag.Errors := Bag.Errors + 1;
         if Bag.Errors > Max_Stored_Errors then
            return;
         end if;
      end if;
      Bag.Items.Append
        (Diagnostic'(Message_Length => Message'Length,
                     Sev            => Sev,
                     Code           => Code,
                     Span           => Span,
                     Origin         => Bag.Current,
                     Message        => Message));
   end Add;

   procedure Set_Origin (Bag : in out Diagnostic_Bag; Tag : Natural)
   is
   begin
      Bag.Current := Tag;
   end Set_Origin;

   function Origin_Of
     (Bag : Diagnostic_Bag; Index : Positive) return Natural
   is (Bag.Items (Index).Origin);

   function Count (Bag : Diagnostic_Bag) return Natural
   is (Natural (Bag.Items.Length));

   function Error_Count (Bag : Diagnostic_Bag) return Natural
   is (Bag.Errors);

   function Render
     (Bag   : Diagnostic_Bag;
      Over  : Source_Text.Source;
      Index : Positive) return String
   is
      D : Diagnostic renames Bag.Items (Index);

      --  A zero-width span at end-of-file may point one past the buffer;
      --  clamp to the last real character for position rendering.
      Anchor : constant Source_Text.Byte_Offset :=
        (if Over.In_Range (D.Span.Start) or else Over.Length = 0
         then D.Span.Start
         else Source_Text.Byte_Offset (Over.Length));

      function Position return String is
      begin
         if Over.Length = 0 then
            return "1:1";
         end if;
         declare
            Line : constant String :=
              Over.Line_Of (Anchor)'Image;
            Col  : constant String :=
              Over.Column_Of (Anchor)'Image;
         begin
            return Line (2 .. Line'Last) & ":" & Col (2 .. Col'Last);
         end;
      end Position;

      Label : constant String :=
        (case D.Sev is when Warning => "warning", when Error => "error");
   begin
      return Over.File_Name & ":" & Position & ": " & Label & ": "
        & D.Message;
   end Render;

   procedure Print_All
     (Bag : Diagnostic_Bag; Over : Source_Text.Source) is
   begin
      for I in 1 .. Bag.Count loop
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error, Bag.Render (Over, I));
      end loop;
      if Bag.Errors > Max_Stored_Errors then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            Over.File_Name & ": too many errors, further errors omitted");
      end if;
   end Print_All;

end AHC.Diagnostics;
