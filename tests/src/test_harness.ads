--  Minimal zero-dependency test harness.
--
--  One test package per production package (Test_Lexer, Test_Layout, ...),
--  each exposing a Run procedure that calls Start_Suite once and then the
--  Check_* assertions. The runner (ahc_tests_main) calls every Run and
--  finishes with Summarize_And_Exit, which sets a nonzero exit status if
--  anything failed.

package Test_Harness is

   procedure Start_Suite (Name : String);

   procedure Check (Condition : Boolean; Label : String);

   procedure Check_Equal (Actual, Expected : String; Label : String);

   procedure Check_Equal (Actual, Expected : Integer; Label : String);

   --  Expects P to propagate an assertion failure (a violated Pre/Post/
   --  Type_Invariant). Fails if P returns normally. Only meaningful in
   --  builds with contracts enabled, which the tests crate guarantees.
   procedure Check_Assertion_Error
     (P : not null access procedure; Label : String);

   function Total_Failures return Natural;

   procedure Summarize_And_Exit;

end Test_Harness;
