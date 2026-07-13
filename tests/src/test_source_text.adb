with AHC.Source_Text; use AHC.Source_Text;

with Test_Harness; use Test_Harness;

package body Test_Source_Text is

   procedure Out_Of_Range_Access is
      S : constant Source := Load_String ("t.hs", "ab");
      C : Character;
   begin
      C := S.Char_At (3);
      pragma Unreferenced (C);
   end Out_Of_Range_Access;

   procedure Run is
   begin
      Start_Suite ("Source_Text");

      declare
         S : constant Source := Load_String ("t.hs", "ab" & ASCII.LF & "cd");
      begin
         Check_Equal (S.Length, 5, "length");
         Check_Equal (S.Line_Count, 2, "line count");
         Check (S.Char_At (4) = 'c', "char at offset");
         Check_Equal (Integer (S.Line_Of (4)), 2, "line of offset");
         Check_Equal (Integer (S.Column_Of (4)), 1, "column at line start");
         Check_Equal (Integer (S.Column_Of (5)), 2, "column mid-line");
         Check_Equal (Integer (S.Line_Start (2)), 4, "line start offset");
         Check_Equal (S.Slice (1, 3), "ab", "slice is half-open");
         Check_Equal (S.Slice (2, 2), "", "zero-width slice");
      end;

      declare
         S : constant Source :=
           Load_String ("t.hs", "a" & ASCII.CR & ASCII.LF & "b");
      begin
         Check_Equal (S.Length, 3, "CRLF normalized to LF");
         Check (S.Char_At (2) = ASCII.LF, "CRLF becomes single LF");
         Check_Equal (Integer (S.Line_Of (3)), 2, "line after CRLF");
      end;

      declare
         S : constant Source := Load_String ("t.hs", "a" & ASCII.CR & "b");
      begin
         Check_Equal (S.Length, 3, "lone CR keeps length");
         Check (S.Char_At (2) = ASCII.LF, "lone CR normalized to LF");
      end;

      declare
         S : constant Source := Load_String ("t.hs", "a" & ASCII.FF & "b");
      begin
         Check_Equal (Integer (S.Line_Of (3)), 2,
                      "formfeed terminates a line");
      end;

      declare
         S : constant Source := Load_String ("t.hs", ASCII.HT & "x");
      begin
         Check_Equal (Integer (S.Column_Of (2)), 9,
                      "tab advances to column 9");
      end;

      declare
         S : constant Source := Load_String ("t.hs", "ab" & ASCII.HT & "c");
      begin
         Check_Equal (Integer (S.Column_Of (4)), 9,
                      "tab stop from mid-line is next multiple of 8 + 1");
      end;

      declare
         S : constant Source :=
           Load_String ("t.hs", ASCII.HT & ASCII.HT & "x");
      begin
         Check_Equal (Integer (S.Column_Of (3)), 17, "consecutive tabs");
      end;

      declare
         S : constant Source := Load_String ("t.hs", "");
      begin
         Check_Equal (S.Length, 0, "empty source length");
         Check_Equal (S.Line_Count, 0, "empty source has no lines");
      end;

      Check_Assertion_Error
        (Out_Of_Range_Access'Access, "Char_At out of range is rejected");
   end Run;

end Test_Source_Text;
