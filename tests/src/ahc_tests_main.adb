--  Unit test runner. Add one Run call per test package.

with Test_Harness;
with Test_Sanity;

procedure AHC_Tests_Main is
begin
   Test_Sanity.Run;

   Test_Harness.Summarize_And_Exit;
end AHC_Tests_Main;
