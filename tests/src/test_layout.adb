with Ada.Strings.Unbounded;

with AHC.Diagnostics;
with AHC.Layout;
with AHC.Lexer;
with AHC.Names;
with AHC.Source_Text;
with AHC.Tokens;

with Test_Harness; use Test_Harness;

package body Test_Layout is

   use AHC.Tokens;

   --  Lex, apply layout, join Images with '|' (EOF excluded), append
   --  "!errors:N" when diagnostics were produced.
   function Lay (S : String) return String is
      Text   : constant AHC.Source_Text.Source :=
        AHC.Source_Text.Load_String ("t.hs", S);
      Table  : AHC.Names.Name_Table;
      Bag    : AHC.Diagnostics.Diagnostic_Bag;
      Raw    : Token_Vectors.Vector;
      Laid   : AHC.Layout.Layout_Stream;
      T      : Token;
      Result : Ada.Strings.Unbounded.Unbounded_String;
      use Ada.Strings.Unbounded;
   begin
      AHC.Lexer.Scan (Text, Table, Bag, Raw);
      Laid.Start (Raw);
      loop
         Laid.Next (Bag, T);
         exit when T.Kind = End_Of_File;
         if Length (Result) > 0 then
            Append (Result, "|");
         end if;
         Append (Result, Image (T, Table));
      end loop;
      if Bag.Has_Errors then
         Append (Result, "!errors:" & Bag.Error_Count'Image);
      end if;
      return To_String (Result);
   end Lay;

   procedure Next_After_Finished is
      Text  : constant AHC.Source_Text.Source :=
        AHC.Source_Text.Load_String ("t.hs", "x");
      Table : AHC.Names.Name_Table;
      Bag   : AHC.Diagnostics.Diagnostic_Bag;
      Raw   : Token_Vectors.Vector;
      Laid  : AHC.Layout.Layout_Stream;
      T     : Token;
   begin
      AHC.Lexer.Scan (Text, Table, Bag, Raw);
      Laid.Start (Raw);
      loop
         Laid.Next (Bag, T);
         exit when T.Kind = End_Of_File;
      end loop;
      Laid.Next (Bag, T);  --  violates Pre
   end Next_After_Finished;

   procedure Run is
   begin
      Start_Suite ("Layout");

      Check_Equal
        (Lay ("f = x" & ASCII.LF & "g = y"),
         "{v|varid ""f""|=|varid ""x""|;v|varid ""g""|=|varid ""y""|}v",
         "top level without module header");

      Check_Equal
        (Lay ("module M where" & ASCII.LF & "f = x" & ASCII.LF & "g = y"),
         "module|conid ""M""|where|{v|varid ""f""|=|varid ""x""|;v"
         & "|varid ""g""|=|varid ""y""|}v",
         "module header opens the top-level block");

      Check_Equal
        (Lay ("main = do" & ASCII.LF
              & "  a" & ASCII.LF
              & "  b" & ASCII.LF
              & "c = d"),
         "{v|varid ""main""|=|do|{v|varid ""a""|;v|varid ""b""|}v"
         & "|;v|varid ""c""|=|varid ""d""|}v",
         "do block closed by dedent");

      Check_Equal
        (Lay ("f = x where" & ASCII.LF
              & "  a = 1" & ASCII.LF
              & "  b = 2"),
         "{v|varid ""f""|=|varid ""x""|where|{v|varid ""a""|=|int ""1"""
         & "|;v|varid ""b""|=|int ""2""|}v|}v",
         "where block with two bindings");

      Check_Equal
        (Lay ("class C where" & ASCII.LF & "instance D"),
         "{v|class|conid ""C""|where|{v|}v|;v|instance|conid ""D""|}v",
         "empty where block (next token not indented enough)");

      Check_Equal
        (Lay ("f = x where"),
         "{v|varid ""f""|=|varid ""x""|where|{v|}v|}v",
         "layout keyword at end of input opens an empty block");

      Check_Equal
        (Lay ("f = do { x; y }"),
         "{v|varid ""f""|=|do|{|varid ""x""|;|varid ""y""|}|}v",
         "explicit braces suppress layout");

      Check_Equal
        (Lay ("f = x" & ASCII.HT & ASCII.LF & ASCII.HT & "  + y"),
         "{v|varid ""f""|=|varid ""x""|varsym ""+""|varid ""y""|}v",
         "continuation line more indented joins the declaration");

      Check_Equal
        (Lay ("do" & ASCII.LF & ASCII.HT & "a" & ASCII.LF
              & "        b"),
         "{v|do|{v|varid ""a""|;v|varid ""b""|}v|}v",
         "tab column 9 equals eight spaces");

      --  Errors are diagnosed but the implicit contexts still balance.
      Check_Equal
        (Lay ("f = x }"),
         "{v|varid ""f""|=|varid ""x""|}|}v!errors: 1",
         "unmatched close brace is diagnosed");

      Check_Equal
        (Lay ("f = { x"),
         "{v|varid ""f""|=|{|varid ""x""|}v!errors: 1",
         "unclosed explicit brace at end of input is diagnosed");

      --  The parse-error(t) rule: "let x = 1 in x" - the stream alone
      --  keeps 'in' inside the let block; the parser asks to close it.
      declare
         Text  : constant AHC.Source_Text.Source :=
           AHC.Source_Text.Load_String ("t.hs", "f = let x = 1 in x");
         Table : AHC.Names.Name_Table;
         Bag   : AHC.Diagnostics.Diagnostic_Bag;
         Raw   : Token_Vectors.Vector;
         Laid  : AHC.Layout.Layout_Stream;
         T     : Token;
         Closed : Boolean;
      begin
         AHC.Lexer.Scan (Text, Table, Bag, Raw);
         Laid.Start (Raw);
         loop
            Laid.Next (Bag, T);
            exit when T.Kind = Kw_In;
         end loop;
         Check_Equal (Laid.Implicit_Depth, 2,
                      "let block still open at 'in'");

         Laid.Close_On_Parse_Error (Closed);
         Check (Closed, "parse-error close succeeds on implicit context");

         Laid.Next (Bag, T);
         Check (T.Kind = V_Right_Brace,
                "virtual close delivered after parse-error");
         Laid.Next (Bag, T);
         Check (T.Kind = Kw_In, "failing token re-delivered");

         --  Only the explicit top-level context should refuse.
         Laid.Next (Bag, T);      --  varid x
         Laid.Close_On_Parse_Error (Closed);
         Check (Closed, "top-level implicit block can close too");
         Laid.Close_On_Parse_Error (Closed);
         Check (not Closed, "no implicit context left to close");
      end;

      Check_Assertion_Error
        (Next_After_Finished'Access,
         "Next after End_Of_File violates precondition");
   end Run;

end Test_Layout;
