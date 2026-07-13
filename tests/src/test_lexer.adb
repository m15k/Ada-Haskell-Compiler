with AHC.Diagnostics;
with AHC.Lexer;
with AHC.Names;
with AHC.Source_Text;
with AHC.Tokens;

with Test_Harness; use Test_Harness;

package body Test_Lexer is

   use AHC.Tokens;

   --  Lex S and render every token except the trailing EOF as its Image,
   --  joined with '|'. Lexical errors append "!errors:N".
   function Lex (S : String) return String is
      Text   : constant AHC.Source_Text.Source :=
        AHC.Source_Text.Load_String ("t.hs", S);
      Table  : AHC.Names.Name_Table;
      Bag    : AHC.Diagnostics.Diagnostic_Bag;
      Stream : Token_Vectors.Vector;

      function Join (From : Positive) return String
      is (if From > Stream.Last_Index - 1 then ""
          elsif From = Stream.Last_Index - 1
          then Image (Stream (From), Table)
          else Image (Stream (From), Table) & "|" & Join (From + 1));
   begin
      AHC.Lexer.Scan (Text, Table, Bag, Stream);
      return Join (1)
        & (if Bag.Has_Errors
           then "!errors:" & Bag.Error_Count'Image else "");
   end Lex;

   procedure Run is
   begin
      Start_Suite ("Lexer");

      Check_Equal
        (Lex ("f x = x + 1"),
         "varid ""f""|varid ""x""|=|varid ""x""|varsym ""+""|int ""1""",
         "simple binding");

      Check_Equal
        (Lex ("let _ = x in wherever"),
         "let|_|=|varid ""x""|in|varid ""wherever""",
         "keywords, underscore, keyword-prefixed varid");

      Check_Equal
        (Lex ("x :: Int -> Int"),
         "varid ""x""|::|conid ""Int""|->|conid ""Int""",
         "reserved operators");

      Check_Equal
        (Lex ("a `div` b"),
         "varid ""a""|`|varid ""div""|`|varid ""b""",
         "backtick-quoted function");

      Check_Equal
        (Lex (":+ : :: xs"),
         "consym "":+""|:|::|varid ""xs""",
         "consym vs reserved colon forms");

      --  Comments
      Check_Equal (Lex ("x -- comment" & ASCII.LF & "y"),
                   "varid ""x""|varid ""y""", "line comment");
      Check_Equal (Lex ("x ----" & ASCII.LF & "y"),
                   "varid ""x""|varid ""y""", "all-dash line comment");
      Check_Equal (Lex ("x --> y"),
                   "varid ""x""|varsym ""-->""|varid ""y""",
                   "dashes then symbol is an operator");
      Check_Equal (Lex ("x --|| y"),
                   "varid ""x""|varsym ""--||""|varid ""y""",
                   "dashes then pipe is an operator");
      Check_Equal (Lex ("x {- a {- nested -} b -} y"),
                   "varid ""x""|varid ""y""", "nested block comment");
      --  Report 2.3: comment text is not tokenized, so the -} inside the
      --  string quotes closes the comment; the stray quote then opens an
      --  unterminated string that swallows the rest of the line.
      Check_Equal (Lex ("x {- ""-}"" ignores strings -} y"),
                   "varid ""x""|<error>!errors: 1",
                   "block comment close inside quotes still closes");
      Check_Equal (Lex ("x {- open"),
                   "varid ""x""!errors: 1", "unterminated block comment");

      --  Qualified names (Report 2.4)
      Check_Equal (Lex ("F.g"), "qvarid ""F.g""", "qualified varid");
      Check_Equal (Lex ("f.g"),
                   "varid ""f""|varsym "".""|varid ""g""",
                   "lowercase dot is three tokens");
      Check_Equal (Lex ("F.."), "qvarsym ""F..""",
                   "qualified dot operator");
      Check_Equal (Lex ("F."), "conid ""F""|varsym "".""",
                   "trailing dot falls back to conid");
      Check_Equal (Lex ("F.where"),
                   "conid ""F""|varsym "".""|where",
                   "reserved word cannot be qualified");
      Check_Equal (Lex ("F..."), "conid ""F""|varsym ""...""",
                   "reserved op cannot be qualified");
      Check_Equal (Lex ("Data.Map.empty"), "qvarid ""Data.Map.empty""",
                   "multi-component module chain");
      Check_Equal (Lex ("A.B.C"), "qconid ""A.B.C""",
                   "qualified conid");
      Check_Equal (Lex ("A.:+"), "qconsym ""A.:+""",
                   "qualified consym");

      --  Integer literals (floats/chars/strings are Milestone 3)
      Check_Equal (Lex ("42 0x1F 0o17 0X2a"),
                   "int ""42""|int ""0x1F""|int ""0o17""|int ""0X2a""",
                   "integer radixes");
      Check_Equal (Lex ("0x"), "int ""0""|varid ""x""",
                   "0x without hex digit is 0 then x");

      --  Float literals (Report 2.5)
      Check_Equal (Lex ("1.5 1e10 1.5e-3 2E+7"),
                   "float ""1.5""|float ""1e10""|float ""1.5e-3"""
                   & "|float ""2E+7""",
                   "float forms");
      Check_Equal (Lex ("1..2"), "int ""1""|..|int ""2""",
                   "dots after int are the range operator");
      Check_Equal (Lex ("1.e2"),
                   "int ""1""|varsym "".""|varid ""e2""",
                   "dot without following digit is not a float");
      Check_Equal (Lex ("1e"), "int ""1""|varid ""e""",
                   "e without digits is not an exponent");

      --  Char literals (Report 2.6)
      Check_Equal (Lex ("'a' '\n' '\\' '\'' '\x41' '\137' '\o17'"),
                   "char 'a'|char \10|char '\'|char '''|char 'A'"
                   & "|char \137|char \15",
                   "char escapes");
      Check_Equal (Lex ("'\SOH' '\SO' '\DEL' '\^A' '\SP'"),
                   "char \1|char \14|char \127|char \1|char ' '",
                   "mnemonic and control escapes, longest munch");
      Check_Equal (Lex ("''"), "<error>!errors: 1",
                   "empty char literal");
      Check_Equal (Lex ("'ab'"),
                   "<error>|varid ""b'""!errors: 1",
                   "overlong char literal recovers (b' is a prime varid)");
      Check_Equal (Lex ("'\&'"), "<error>!errors: 1",
                   "empty escape not allowed in char");

      --  String literals
      Check_Equal (Lex ("""hello"""), "string ""hello""",
                   "plain string");
      Check_Equal (Lex ("""a\nb"""),
                   "string ""a" & ASCII.LF & "b""",
                   "escape decoded in string");
      Check_Equal (Lex (""""""), "string """"",
                   "empty string");
      Check_Equal (Lex ("""\x41\&BC"""), "string ""ABC""",
                   "empty escape separates hex escape from text");
      Check_Equal (Lex ("""foo\" & ASCII.LF & "   \bar"""),
                   "string ""foobar""",
                   "gap spanning a newline is ignored");
      Check_Equal (Lex ("""abc"), "<error>!errors: 1",
                   "unterminated string");
      Check_Equal (Lex ("""a\ x"""),
                   "<error>!errors: 1",
                   "gap must end with a backslash");

      --  Errors keep the stream going
      Check_Equal (Lex ("x " & ASCII.BEL & " y"),
                   "varid ""x""|<error>|varid ""y""!errors: 1",
                   "invalid character recovers");

      --  First_On_Line markers
      declare
         Text   : constant AHC.Source_Text.Source :=
           AHC.Source_Text.Load_String
             ("t.hs", "a b" & ASCII.LF & "  c");
         Table  : AHC.Names.Name_Table;
         Bag    : AHC.Diagnostics.Diagnostic_Bag;
         Stream : Token_Vectors.Vector;
      begin
         AHC.Lexer.Scan (Text, Table, Bag, Stream);
         Check (Stream (1).First_On_Line, "first token starts a line");
         Check (not Stream (2).First_On_Line, "second token does not");
         Check (Stream (3).First_On_Line, "token after newline does");
         Check_Equal (Integer (Stream (3).Column), 3,
                      "indented token column");
      end;
   end Run;

end Test_Lexer;
