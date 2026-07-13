--  Unit test runner. Add one Run call per test package.

with Test_Harness;
with Test_Sanity;
with Test_Source_Text;
with Test_Names;
with Test_Diagnostics;
with Test_Tokens;

procedure AHC_Tests_Main is
begin
   Test_Sanity.Run;
   Test_Source_Text.Run;
   Test_Names.Run;
   Test_Diagnostics.Run;
   Test_Tokens.Run;

   Test_Harness.Summarize_And_Exit;
end AHC_Tests_Main;
