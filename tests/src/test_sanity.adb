with AHC;

with Test_Harness; use Test_Harness;

package body Test_Sanity is

   --  A deliberately violated precondition, to prove contracts are
   --  enabled in the test build.
   procedure Needs_Positive (N : Integer) with Pre => N > 0;

   procedure Needs_Positive (N : Integer) is
   begin
      pragma Unreferenced (N);
   end Needs_Positive;

   procedure Violate_Precondition is
   begin
      Needs_Positive (-1);
   end Violate_Precondition;

   procedure Run is
   begin
      Start_Suite ("Sanity");
      Check (AHC.Version'Length > 0, "version constant is nonempty");
      Check_Assertion_Error
        (Violate_Precondition'Access, "contracts are enabled in test build");
   end Run;

end Test_Sanity;
