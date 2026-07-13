with AHC.Diagnostics; use AHC.Diagnostics;
with AHC.Source_Text; use AHC.Source_Text;

with Test_Harness; use Test_Harness;

package body Test_Diagnostics is

   procedure Backwards_Span is
      Span : Source_Span := (Start => 5, Stop => 3);
      pragma Unreferenced (Span);
   begin
      null;
   end Backwards_Span;

   procedure Run is
   begin
      Start_Suite ("Diagnostics");

      declare
         Span : constant Source_Span := (Start => 2, Stop => 5);
      begin
         Check_Equal (Width (Span), 3, "span width");
         Check_Equal (Width (Zero_Width_At (7)), 0, "zero-width span");
         Check (Merge ((2, 4), (3, 8)) = (2, 8), "merge takes the hull");
      end;

      declare
         S   : constant Source :=
           Load_String ("test.hs", "abc" & ASCII.LF & "def");
         Bag : Diagnostic_Bag;
      begin
         Bag.Add (Error, Parse_Error, (Start => 6, Stop => 7),
                  "unexpected thing");
         Check_Equal (Bag.Render (S, 1),
                      "test.hs:2:2: error: unexpected thing",
                      "render error with position");

         Bag.Add (Warning, Fixity_Error, (Start => 1, Stop => 2), "meh");
         Check_Equal (Bag.Render (S, 2),
                      "test.hs:1:1: warning: meh",
                      "render warning");

         Check_Equal (Bag.Count, 2, "both stored");
         Check_Equal (Bag.Error_Count, 1, "one error");
         Check (Bag.Has_Errors, "has errors");
      end;

      declare
         S   : constant Source := Load_String ("test.hs", "x");
         Bag : Diagnostic_Bag;
      begin
         for I in 1 .. Max_Stored_Errors + 10 loop
            Bag.Add (Error, Lex_Invalid_Character, (1, 2), "boom");
         end loop;
         Check_Equal (Bag.Count, Max_Stored_Errors,
                      "storage capped at Max_Stored_Errors");
         Check_Equal (Bag.Error_Count, Max_Stored_Errors + 10,
                      "all errors still counted");
         Check (Bag.Error_Limit_Reached, "limit reached");
         Check_Equal (Bag.Render (S, 1), "test.hs:1:1: error: boom",
                      "render capped bag");
      end;

      Check_Assertion_Error
        (Backwards_Span'Access, "backwards span violates predicate");
   end Run;

end Test_Diagnostics;
