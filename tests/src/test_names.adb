with AHC.Names; use AHC.Names;

with Test_Harness; use Test_Harness;

package body Test_Names is

   procedure Stale_Id_Lookup is
      T : Name_Table;
      Ignore : constant Real_Name_Id := T.Intern ("only");
      S : constant String := T.Text (Ignore + 1);
      pragma Unreferenced (S);
   begin
      null;
   end Stale_Id_Lookup;

   procedure Run is
      T : Name_Table;
   begin
      Start_Suite ("Names");

      Check_Equal (Integer (T.Last_Id), Integer (No_Name),
                   "fresh table is empty");

      declare
         A  : constant Real_Name_Id := T.Intern ("foldr");
         B  : constant Real_Name_Id := T.Intern ("Maybe");
         A2 : constant Real_Name_Id := T.Intern ("foldr");
      begin
         Check (A = A2, "same text interns to same id");
         Check (A /= B, "different text interns to different ids");
         Check_Equal (T.Text (A), "foldr", "text roundtrip");
         Check_Equal (T.Text (B), "Maybe", "text roundtrip (second)");
         Check_Equal (Integer (T.Last_Id), 2, "two distinct names stored");
      end;

      Check_Assertion_Error
        (Stale_Id_Lookup'Access, "Text on unknown id is rejected");
   end Run;

end Test_Names;
