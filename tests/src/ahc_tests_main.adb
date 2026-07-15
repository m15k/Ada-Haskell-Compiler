--  Unit test runner. Add one Run call per test package.

with Test_Harness;
with Test_Sanity;
with Test_Source_Text;
with Test_Names;
with Test_Diagnostics;
with Test_Tokens;
with Test_Lexer;
with Test_Layout;
with Test_Parser;
with Test_Fixity;
with Test_Core;
with Test_Rename;
with Test_Kinds;
with Test_Desugar;
with Test_Typechecker;

procedure AHC_Tests_Main is
begin
   Test_Sanity.Run;
   Test_Source_Text.Run;
   Test_Names.Run;
   Test_Diagnostics.Run;
   Test_Tokens.Run;
   Test_Lexer.Run;
   Test_Layout.Run;
   Test_Parser.Run;
   Test_Fixity.Run;
   Test_Core.Run;
   Test_Rename.Run;
   Test_Kinds.Run;
   Test_Desugar.Run;
   Test_Typechecker.Run;

   Test_Harness.Summarize_And_Exit;
end AHC_Tests_Main;
