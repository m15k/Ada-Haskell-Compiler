with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Text_IO;

with System.Assertions;

package body Test_Harness is

   use Ada.Text_IO;

   Passed : Natural := 0;
   Failed : Natural := 0;

   procedure Start_Suite (Name : String) is
   begin
      Put_Line ("== " & Name);
   end Start_Suite;

   procedure Report (Ok : Boolean; Label : String) is
   begin
      if Ok then
         Passed := Passed + 1;
         Put_Line ("   ok: " & Label);
      else
         Failed := Failed + 1;
         Put_Line (" FAIL: " & Label);
      end if;
   end Report;

   procedure Check (Condition : Boolean; Label : String) is
   begin
      Report (Condition, Label);
   end Check;

   procedure Check_Equal (Actual, Expected : String; Label : String) is
   begin
      if Actual = Expected then
         Report (True, Label);
      else
         Report (False, Label);
         Put_Line ("       expected: """ & Expected & """");
         Put_Line ("       actual:   """ & Actual & """");
      end if;
   end Check_Equal;

   procedure Check_Equal (Actual, Expected : Integer; Label : String) is
   begin
      if Actual = Expected then
         Report (True, Label);
      else
         Report (False, Label);
         Put_Line ("       expected:" & Expected'Image);
         Put_Line ("       actual:  " & Actual'Image);
      end if;
   end Check_Equal;

   procedure Check_Assertion_Error
     (P : not null access procedure; Label : String) is
   begin
      P.all;
      Report (False, Label & " (no assertion raised)");
   exception
      when System.Assertions.Assert_Failure =>
         Report (True, Label);
      when E : others =>
         Report (False, Label & " (unexpected exception)");
         Put_Line ("       " & Ada.Exceptions.Exception_Information (E));
   end Check_Assertion_Error;

   function Total_Failures return Natural is (Failed);

   procedure Summarize_And_Exit is
   begin
      New_Line;
      Put_Line ("passed:" & Passed'Image & ", failed:" & Failed'Image);
      Ada.Command_Line.Set_Exit_Status
        (if Failed = 0 then 0 else 1);
   end Summarize_And_Exit;

end Test_Harness;
