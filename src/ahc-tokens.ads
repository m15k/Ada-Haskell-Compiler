--  Haskell 2010 tokens (Report 2.2-2.6) as a discriminated record over a
--  Token_Kind enumeration. Every token carries its span plus the line and
--  layout column of its first character; the lexer marks the first token
--  of each line so AHC.Layout can reconstruct the Report's <n> / {n}
--  pseudo-tokens without re-scanning.

with AHC.Diagnostics;
with AHC.Names;
with AHC.Source_Text;

with Ada.Containers.Vectors;

package AHC.Tokens is

   use type Names.Name_Id;

   type Token_Kind is
     (--  Reserved words (Report 2.4 reservedid)
      Kw_Case, Kw_Class, Kw_Data, Kw_Default, Kw_Deriving, Kw_Do,
      Kw_Else, Kw_Foreign, Kw_If, Kw_Import, Kw_In, Kw_Infix,
      Kw_Infixl, Kw_Infixr, Kw_Instance, Kw_Let, Kw_Module,
      Kw_Newtype, Kw_Of, Kw_Then, Kw_Type, Kw_Where, Underscore,

      --  Reserved operators (Report 2.4 reservedop)
      Dot_Dot, Colon, Colon_Colon, Equals, Backslash, Pipe,
      Left_Arrow, Right_Arrow, At_Sign, Tilde, Fat_Arrow,

      --  Names (qualified variants carry a module qualifier)
      Varid, Conid, Varsym, Consym, Qvarid, Qconid, Qvarsym, Qconsym,

      --  Literals
      Int_Lit, Float_Lit, Char_Lit, String_Lit,

      --  Special characters (Report 2.2 special)
      Left_Paren, Right_Paren, Left_Bracket, Right_Bracket,
      Comma, Semicolon, Backtick, Left_Brace, Right_Brace,

      --  Inserted by AHC.Layout, never by the lexer
      V_Left_Brace, V_Right_Brace, V_Semicolon,

      End_Of_File, Error_Token);

   subtype Reserved_Word_Kind is Token_Kind range Kw_Case .. Underscore;
   subtype Reserved_Op_Kind   is Token_Kind range Dot_Dot .. Fat_Arrow;
   subtype Name_Kind          is Token_Kind range Varid .. Qconsym;
   subtype Qualified_Kind     is Token_Kind range Qvarid .. Qconsym;
   subtype Literal_Kind       is Token_Kind range Int_Lit .. String_Lit;
   subtype Special_Kind       is Token_Kind
     range Left_Paren .. Right_Brace;
   subtype Virtual_Kind       is Token_Kind
     range V_Left_Brace .. V_Semicolon;

   --  The keywords that open an implicit layout block (Report 10.3).
   subtype Layout_Keyword_Kind is Token_Kind
     with Static_Predicate =>
       Layout_Keyword_Kind in Kw_Let | Kw_Where | Kw_Do | Kw_Of;

   subtype Code_Point is Natural range 0 .. 16#10FFFF#;

   type Token (Kind : Token_Kind := End_Of_File) is record
      Span          : Diagnostics.Source_Span;
      Line          : Source_Text.Line_Number := 1;
      Column        : Source_Text.Column_Number := 1;
      First_On_Line : Boolean := False;
      case Kind is
         when Name_Kind =>
            Name      : Names.Real_Name_Id;
            --  No_Name unless Kind in Qualified_Kind
            Qualifier : Names.Name_Id := Names.No_Name;
         when Int_Lit =>
            Int_Text : Names.Real_Name_Id;    --  lexeme, radix preserved
         when Float_Lit =>
            Float_Text : Names.Real_Name_Id;  --  lexeme
         when Char_Lit =>
            Char_Value : Code_Point;          --  decoded
         when String_Lit =>
            String_Value : Names.Name_Id;     --  decoded ("" = No_Name)
         when others =>
            null;
      end case;
   end record
     with Dynamic_Predicate =>
       (if Token.Kind in Qualified_Kind
        then Token.Qualifier /= Names.No_Name
        elsif Token.Kind in Name_Kind
        then Token.Qualifier = Names.No_Name);

   package Token_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Token);

   --  Stable one-line rendering for `ahc lex` dumps and golden tests,
   --  e.g. `varid "length"`, `qconid "Data.Map"`, `int "0x1F"`, `{v`.
   function Image (T : Token; Table : Names.Name_Table) return String;

end AHC.Tokens;
