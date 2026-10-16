with Ada.Strings.Unbounded;
with AHC.Unicode;

package body AHC.Lexer is

   use AHC.Tokens;
   use type Source_Text.Column_Number;

   ---------------------------------------------------------------------
   --  Character classes (Report 2.2, ASCII subset for Phase 1)
   ---------------------------------------------------------------------

   function Is_Symbol_Char (C : Character) return Boolean
   is (C in '!' | '#' | '$' | '%' | '&' | '*' | '+' | '.' | '/' | '<'
         | '=' | '>' | '?' | '@' | '\' | '^' | '|' | '-' | '~' | ':');

   function Is_Small (C : Character) return Boolean
   is (C in 'a' .. 'z' or else C = '_');

   function Is_Large (C : Character) return Boolean
   is (C in 'A' .. 'Z');

   function Is_Digit (C : Character) return Boolean
   is (C in '0' .. '9');

   function Is_White (C : Character) return Boolean
   is (C in ' ' | ASCII.HT | ASCII.LF | ASCII.FF | ASCII.VT);

   --  Varid if S is not a reserved word.
   function Word_Kind (S : String) return Token_Kind
   is (if    S = "case"     then Kw_Case
       elsif S = "class"    then Kw_Class
       elsif S = "data"     then Kw_Data
       elsif S = "default"  then Kw_Default
       elsif S = "deriving" then Kw_Deriving
       elsif S = "do"       then Kw_Do
       elsif S = "else"     then Kw_Else
       elsif S = "foreign"  then Kw_Foreign
       elsif S = "if"       then Kw_If
       elsif S = "import"   then Kw_Import
       elsif S = "in"       then Kw_In
       elsif S = "infix"    then Kw_Infix
       elsif S = "infixl"   then Kw_Infixl
       elsif S = "infixr"   then Kw_Infixr
       elsif S = "instance" then Kw_Instance
       elsif S = "let"      then Kw_Let
       elsif S = "module"   then Kw_Module
       elsif S = "newtype"  then Kw_Newtype
       elsif S = "of"       then Kw_Of
       elsif S = "then"     then Kw_Then
       elsif S = "type"     then Kw_Type
       elsif S = "where"    then Kw_Where
       elsif S = "_"        then Underscore
       else Varid);

   type String_Access is not null access constant String;

   --  ASCII mnemonic escapes (Report 2.6 charesc); index = code point,
   --  except DEL at the end.
   Mnemonics : constant array (Tokens.Code_Point range 0 .. 33) of
     String_Access :=
       [new String'("NUL"), new String'("SOH"), new String'("STX"),
        new String'("ETX"), new String'("EOT"), new String'("ENQ"),
        new String'("ACK"), new String'("BEL"), new String'("BS"),
        new String'("HT"),  new String'("LF"),  new String'("VT"),
        new String'("FF"),  new String'("CR"),  new String'("SO"),
        new String'("SI"),  new String'("DLE"), new String'("DC1"),
        new String'("DC2"), new String'("DC3"), new String'("DC4"),
        new String'("NAK"), new String'("SYN"), new String'("ETB"),
        new String'("CAN"), new String'("EM"),  new String'("SUB"),
        new String'("ESC"), new String'("FS"),  new String'("GS"),
        new String'("RS"),  new String'("US"),  new String'("SP"),
        new String'("DEL")];

   function Mnemonic_Code (Index : Tokens.Code_Point)
     return Tokens.Code_Point
   is (if Index = 33 then 127 else Index);

   --  Varsym if S is not a reserved operator.
   function Symbol_Kind (S : String) return Token_Kind
   is (if    S = ".."  then Dot_Dot
       elsif S = ":"   then Colon
       elsif S = "::"  then Colon_Colon
       elsif S = "="   then Equals
       elsif S = "\"   then Backslash
       elsif S = "|"   then Pipe
       elsif S = "<-"  then Left_Arrow
       elsif S = "->"  then Right_Arrow
       elsif S = "@"   then At_Sign
       elsif S = "~"   then Tilde
       elsif S = "=>"  then Fat_Arrow
       elsif S (S'First) = ':' then Consym
       else Varsym);

   ---------------------------------------------------------------------
   --  Scan
   ---------------------------------------------------------------------

   procedure Scan
     (Text   : Source_Text.Source;
      Table  : in out Names.Name_Table;
      Bag    : in out Diagnostics.Diagnostic_Bag;
      Result : out Tokens.Token_Vectors.Vector)
   is
      Ignore : Span_Vectors.Vector;
   begin
      Scan (Text, Table, Bag, Result, Ignore);
   end Scan;

   procedure Scan
     (Text    : Source_Text.Source;
      Table   : in out Names.Name_Table;
      Bag     : in out Diagnostics.Diagnostic_Bag;
      Result  : out Tokens.Token_Vectors.Vector;
      Pragmas : out Span_Vectors.Vector)
   is
      Len : constant Natural := Text.Length;

      Pos       : Positive := 1;   --  next unconsumed offset
      Last_Line : Natural  := 0;   --  line of the previous emitted token

      function Peek (Ahead : Natural := 0) return Character
      is (if Pos + Ahead <= Len
          then Text.Char_At (Source_Text.Byte_Offset (Pos + Ahead))
          else ASCII.NUL);

      function Slice (From, Stop : Positive) return String
      is (Text.Slice (Source_Text.Byte_Offset (From),
                      Source_Text.Byte_Offset (Stop)));

      function At_Offset (I : Positive) return Character
      is (Text.Char_At (Source_Text.Byte_Offset (I)));

      --  Line/column of O, clamped so the end-of-file position (one past
      --  the buffer) renders as just after the last character.
      procedure Position_Of
        (O      : Positive;
         Line   : out Source_Text.Line_Number;
         Column : out Source_Text.Column_Number) is
      begin
         if Len = 0 then
            Line := 1;
            Column := 1;
         elsif O <= Len then
            Line := Text.Line_Of (Source_Text.Byte_Offset (O));
            Column := Text.Column_Of (Source_Text.Byte_Offset (O));
         else
            Line := Text.Line_Of (Source_Text.Byte_Offset (Len));
            --  One past the last character; a trailing continuation
            --  byte is already past it (columns count code points).
            Column := Text.Column_Of (Source_Text.Byte_Offset (Len))
              + (if Character'Pos (At_Offset (Len)) in 16#80# .. 16#BF#
                 then 0 else 1);
         end if;
      end Position_Of;

      --  Fill in position fields and append. Start is the token's first
      --  offset; Pos must already be one past its last character.
      procedure Emit (T : Token; Start : Positive) is
         Placed : Token := T;
         Line   : Source_Text.Line_Number;
         Column : Source_Text.Column_Number;
      begin
         Position_Of (Start, Line, Column);
         Placed.Span :=
           (Start => Source_Text.Byte_Offset (Start),
            Stop  => Source_Text.Byte_Offset (Pos));
         Placed.Line := Line;
         Placed.Column := Column;
         Placed.First_On_Line := Natural (Line) > Last_Line;
         Last_Line := Natural (Line);
         Result.Append (Placed);
      end Emit;

      --  Aggregates need static discriminants; a constrained default-
      --  initialized object does not, which is how payload-free tokens
      --  of a computed kind get built.
      procedure Emit_Plain (Kind : Token_Kind; Start : Positive)
        with Pre => Kind not in Name_Kind | Literal_Kind
      is
         T : Token (Kind);
         pragma Warnings
           (Off, T, Reason => "payload-free kinds carry only defaults");
      begin
         Emit (T, Start);
      end Emit_Plain;

      procedure Error
        (Code : Diagnostics.Diag_Code; Start : Positive; Message : String)
      is
      begin
         Bag.Add
           (Diagnostics.Error, Code,
            (Start => Source_Text.Byte_Offset (Start),
             Stop  => Source_Text.Byte_Offset (Pos)),
            Message);
      end Error;

      ------------------------------------------------------------------
      --  Characters beyond ASCII (Report 2.2, M150)
      ------------------------------------------------------------------

      --  The code point whose UTF-8 sequence starts at byte I and the
      --  sequence's length in bytes; Width = 0 when the bytes there
      --  are not one well-formed sequence.
      procedure Decode_At
        (I : Positive; Code : out Natural; Width : out Natural)
      is
         Lead : constant Natural :=
           (if I <= Len then Character'Pos (At_Offset (I)) else 0);
         Need : Natural;
      begin
         Code := 0;
         Width := 0;
         if I > Len then
            return;
         elsif Lead < 16#80# then
            Code := Lead;
            Width := 1;
            return;
         elsif Lead in 16#C2# .. 16#DF# then
            Need := 1;
            Code := Lead mod 32;
         elsif Lead in 16#E0# .. 16#EF# then
            Need := 2;
            Code := Lead mod 16;
         elsif Lead in 16#F0# .. 16#F4# then
            Need := 3;
            Code := Lead mod 8;
         else
            return;
         end if;
         for K in 1 .. Need loop
            if I + K > Len
              or else Character'Pos (At_Offset (I + K))
                        not in 16#80# .. 16#BF#
            then
               Code := 0;
               return;
            end if;
            Code := Code * 64 + Character'Pos (At_Offset (I + K)) mod 64;
         end loop;
         if Code > 16#10FFFF#
           or else Code in 16#D800# .. 16#DFFF#
           or else (Need = 2 and then Code < 16#800#)
           or else (Need = 3 and then Code < 16#1_0000#)
         then
            Code := 0;
            return;
         end if;
         Width := Need + 1;
      end Decode_At;

      --  GHC's lexical class of a character (Lexer.x's adj_c, over
      --  GHC 9.4.8's generalCategory): Small and Large start a varid
      --  and a conid; Digit, Modifier and Mark only continue one;
      --  Symbol is an operator character; Other is everything else,
      --  including Ps/Pe/Pi/Pf, whitespace and malformed UTF-8.
      type Char_Class is
        (Small, Large, Digit, Modifier, Mark, Symbol, Other);

      subtype Ident_Class is Char_Class range Small .. Mark;

      function Class_At (I : Positive) return Char_Class is
         C : constant Character := At_Offset (I);
      begin
         if Character'Pos (C) < 16#80# then
            return (if Is_Small (C) then Small
                    elsif Is_Large (C) then Large
                    elsif Is_Digit (C) then Digit
                    elsif C = ''' then Mark
                    elsif Is_Symbol_Char (C) then Symbol
                    else Other);
         end if;
         declare
            Code  : Natural;
            Width : Natural;
         begin
            Decode_At (I, Code, Width);
            if Width = 0 then
               return Other;
            end if;
            case Unicode.Category (Code) is
               when Unicode.Ll | Unicode.Lo => return Small;
               when Unicode.Lu | Unicode.Lt => return Large;
               when Unicode.Nd | Unicode.Nl | Unicode.No => return Digit;
               when Unicode.Lm => return Modifier;
               when Unicode.Mn => return Mark;
               when Unicode.Pc | Unicode.Pd | Unicode.Po | Unicode.Sm
                  | Unicode.Sc | Unicode.Sk | Unicode.So => return Symbol;
               when others => return Other;
            end case;
         end;
      end Class_At;

      --  Bytes in the character at I: its UTF-8 length, 1 for ASCII
      --  and for a malformed byte.
      function Width_At (I : Positive) return Positive is
         Code  : Natural;
         Width : Natural;
      begin
         Decode_At (I, Code, Width);
         return Positive'Max (Width, 1);
      end Width_At;

      --  Data.Char.isAlphaNum of the character at I: a letter (L*) or
      --  a number (N*).
      function Alnum_At (I : Positive) return Boolean
      is (Class_At (I) in Small | Large | Digit | Modifier);

      --  The first byte of the character that ends just before I.
      function Prev_Start (I : Positive) return Positive
        with Pre => I > 1
      is
         J : Positive := I - 1;
      begin
         while J > 1
           and then Character'Pos (At_Offset (J)) in 16#80# .. 16#BF#
         loop
            J := J - 1;
         end loop;
         return J;
      end Prev_Start;
      pragma Unreferenced (Alnum_At, Prev_Start);  --  A4 uses them

      ------------------------------------------------------------------
      --  Comments and whitespace
      ------------------------------------------------------------------

      --  At "--"; a run of dashes is a line comment only when the run is
      --  not followed by another symbol character ("-->" is an operator).
      function At_Line_Comment return Boolean is
         Ahead : Natural := 0;
      begin
         while Peek (Ahead) = '-' loop
            Ahead := Ahead + 1;
         end loop;
         return Ahead >= 2
           and then not (Pos + Ahead <= Len
                         and then Class_At (Pos + Ahead) = Symbol);
      end At_Line_Comment;

      procedure Skip_Line_Comment is
      begin
         while Pos <= Len and then Peek /= ASCII.LF and then Peek /= ASCII.FF
         loop
            Pos := Pos + 1;
         end loop;
      end Skip_Line_Comment;

      --  At "{-". Nested; the contents are not tokenized, so "-}" inside
      --  string syntax still closes (Report 2.3). Pragma comments
      --  ({-# ... #-}) additionally record their span for
      --  AHC.Contracts; the layout engine never sees any of this.
      procedure Skip_Block_Comment is
         Start : constant Positive := Pos;
         Is_Pragma : constant Boolean := Peek (2) = '#';
         Depth : Natural := 1;
      begin
         Pos := Pos + 2;
         while Depth > 0 loop
            if Pos > Len then
               Error (Diagnostics.Lex_Unterminated_Comment, Start,
                      "unterminated block comment");
               return;
            elsif Peek = '{' and then Peek (1) = '-' then
               Depth := Depth + 1;
               Pos := Pos + 2;
            elsif Peek = '-' and then Peek (1) = '}' then
               Depth := Depth - 1;
               Pos := Pos + 2;
            else
               Pos := Pos + 1;
            end if;
         end loop;
         if Is_Pragma then
            Pragmas.Append
              (Diagnostics.Source_Span'
                 (Start => Source_Text.Byte_Offset (Start),
                  Stop  => Source_Text.Byte_Offset (Pos)));
         end if;
      end Skip_Block_Comment;

      ------------------------------------------------------------------
      --  Names
      ------------------------------------------------------------------

      --  Munch identifier characters starting at Pos (which must be a
      --  small or large letter) and leave Pos one past the end.
      function Munch_Ident return Positive is
         Start : constant Positive := Pos;
      begin
         while Pos <= Len and then Class_At (Pos) in Ident_Class loop
            Pos := Pos + Width_At (Pos);
         end loop;
         return Start;
      end Munch_Ident;

      function Munch_Symbols return Positive is
         Start : constant Positive := Pos;
      begin
         while Pos <= Len and then Class_At (Pos) = Symbol loop
            Pos := Pos + Width_At (Pos);
         end loop;
         return Start;
      end Munch_Symbols;

      --  `->` follows on this line (after blanks), as a whole symbol.
      function Arrow_Follows return Boolean is
         K : Natural := 0;
      begin
         while Peek (K) = ' ' or else Peek (K) = ASCII.HT loop
            K := K + 1;
         end loop;
         return Peek (K) = '-' and then Peek (K + 1) = '>'
           and then not Is_Symbol_Char (Peek (K + 2));
      end Arrow_Follows;

      procedure Scan_Small_Ident is
         Start : constant Positive := Munch_Ident;
         Word  : constant String := Slice (Start, Pos);
         Kind  : constant Token_Kind := Word_Kind (Word);
      begin
         --  `\cases` (M148) - but `\cases -> e` is Haskell 2010's
         --  lambda with a parameter named `cases` (M148 review).
         if Kind = Varid and then Word = "cases"
           and then not Result.Is_Empty
           and then Result.Last_Element.Kind = Backslash
           and then not Arrow_Follows
         then
            Emit_Plain (Kw_Cases, Start);   --  `\cases` (M148)
         elsif Kind = Varid then
            Emit ((Kind => Varid, Name => Table.Intern (Word),
                   others => <>), Start);
         else
            Emit_Plain (Kind, Start);
         end if;
      end Scan_Small_Ident;

      --  At a large letter: conid, or a qualified name (Report 2.4).
      --  Maximal munch with backtracking: "F.g" is one qvarid, "F.." is
      --  the qualified "." operator, but "F.where" and "F..." fall back
      --  to conid F (reserved words/ops cannot be qualified).
      procedure Scan_Large_Ident is
         Start      : constant Positive := Munch_Ident;
         Qual_Start : constant Positive := Start;
         Qual_Stop  : Positive := Pos;   --  exclusive end of module chain
      begin
         loop
            --  Try to extend across "." with another name component.
            if Peek /= '.' then
               exit;
            end if;

            declare
               Dot_Pos : constant Positive := Pos;
            begin
               Pos := Pos + 1;

               if Pos <= Len and then Class_At (Pos) = Large then
                  declare
                     Part_Start : constant Positive := Munch_Ident;
                     pragma Unreferenced (Part_Start);
                  begin
                     Qual_Stop := Pos;  --  chain grew; maybe more to come
                  end;
               elsif Pos <= Len and then Class_At (Pos) = Small then
                  declare
                     Part_Start : constant Positive := Munch_Ident;
                     Word       : constant String := Slice (Part_Start, Pos);
                  begin
                     if Word_Kind (Word) = Varid then
                        Emit ((Kind      => Qvarid,
                               Name      => Table.Intern (Word),
                               Qualifier =>
                                 Table.Intern (Slice (Qual_Start, Dot_Pos)),
                               others    => <>), Start);
                        return;
                     end if;
                     Pos := Dot_Pos;  --  "F.where": not qualifiable
                     exit;
                  end;
               elsif Pos <= Len and then Class_At (Pos) = Symbol then
                  declare
                     Sym_Start : constant Positive := Munch_Symbols;
                     Sym       : constant String := Slice (Sym_Start, Pos);
                     Kind      : constant Token_Kind := Symbol_Kind (Sym);
                  begin
                     if Kind = Varsym then
                        Emit ((Kind      => Qvarsym,
                               Name      => Table.Intern (Sym),
                               Qualifier =>
                                 Table.Intern (Slice (Qual_Start, Dot_Pos)),
                               others    => <>), Start);
                        return;
                     elsif Kind = Consym then
                        Emit ((Kind      => Qconsym,
                               Name      => Table.Intern (Sym),
                               Qualifier =>
                                 Table.Intern (Slice (Qual_Start, Dot_Pos)),
                               others    => <>), Start);
                        return;
                     end if;
                     Pos := Dot_Pos;  --  "F...", "F.=": reserved op
                     exit;
                  end;
               else
                  Pos := Dot_Pos;     --  "F." at end or before junk
                  exit;
               end if;
            end;
         end loop;

         --  No trailing varid/varsym: the last chain component is the
         --  conid itself, anything before it the qualifier.
         declare
            Last_Dot : Natural := 0;
            Chain    : constant String := Slice (Qual_Start, Qual_Stop);
         begin
            Pos := Qual_Stop;
            for I in reverse Chain'Range loop
               if Chain (I) = '.' then
                  Last_Dot := I;
                  exit;
               end if;
            end loop;
            if Last_Dot = 0 then
               Emit ((Kind => Conid, Name => Table.Intern (Chain),
                      others => <>), Start);
            else
               Emit ((Kind      => Qconid,
                      Name      =>
                        Table.Intern (Chain (Last_Dot + 1 .. Chain'Last)),
                      Qualifier =>
                        Table.Intern (Chain (Chain'First .. Last_Dot - 1)),
                      others    => <>), Start);
            end if;
         end;
      end Scan_Large_Ident;

      procedure Scan_Operator is
         Start : constant Positive := Munch_Symbols;
         Sym   : constant String := Slice (Start, Pos);
         Kind  : constant Token_Kind := Symbol_Kind (Sym);
      begin
         if Kind = Varsym then
            Emit ((Kind => Varsym, Name => Table.Intern (Sym),
                   others => <>), Start);
         elsif Kind = Consym then
            Emit ((Kind => Consym, Name => Table.Intern (Sym),
                   others => <>), Start);
         else
            Emit_Plain (Kind, Start);
         end if;
      end Scan_Operator;

      ------------------------------------------------------------------
      --  Numeric literals (Report 2.5)
      ------------------------------------------------------------------

      function Is_Octal (C : Character) return Boolean
      is (C in '0' .. '7');
      function Is_Hex (C : Character) return Boolean
      is (Is_Digit (C) or else C in 'a' .. 'f' | 'A' .. 'F');

      procedure Munch (Valid : not null access
                         function (C : Character) return Boolean) is
      begin
         while Pos <= Len and then Valid (Peek) loop
            Pos := Pos + 1;
         end loop;
      end Munch;

      procedure Scan_Number is
         Start    : constant Positive := Pos;
         Is_Float : Boolean := False;
      begin
         if Peek = '0' and then Peek (1) in 'x' | 'X'
           and then Is_Hex (Peek (2))
         then
            Pos := Pos + 2;
            Munch (Is_Hex'Access);
         elsif Peek = '0' and then Peek (1) in 'o' | 'O'
           and then Is_Octal (Peek (2))
         then
            Pos := Pos + 2;
            Munch (Is_Octal'Access);
         else
            Munch (Is_Digit'Access);

            --  "1.5" is a float but "1..2" is 1 .. 2; the dot only joins
            --  when a digit follows (maximal munch, Report 2.5).
            if Peek = '.' and then Is_Digit (Peek (1)) then
               Pos := Pos + 1;
               Munch (Is_Digit'Access);
               Is_Float := True;
            end if;

            if Peek in 'e' | 'E'
              and then (Is_Digit (Peek (1))
                        or else (Peek (1) in '+' | '-'
                                 and then Is_Digit (Peek (2))))
            then
               Pos := Pos + 2;  --  'e' plus digit or sign
               Munch (Is_Digit'Access);
               Is_Float := True;
            end if;
         end if;

         if Is_Float then
            Emit ((Kind => Float_Lit,
                   Float_Text => Table.Intern (Slice (Start, Pos)),
                   others => <>), Start);
         else
            Emit ((Kind => Int_Lit,
                   Int_Text => Table.Intern (Slice (Start, Pos)),
                   others => <>), Start);
         end if;
      end Scan_Number;

      ------------------------------------------------------------------
      --  Character and string literals (Report 2.6)
      ------------------------------------------------------------------

      type Escape_Result is (Escaped_Char, Empty_Escape, Gap, Bad_Escape);
      --  Pos is just past a backslash inside a literal. Decodes one
      --  escape; on Bad_Escape a diagnostic has been reported and Pos
      --  advanced by at least one character.
      procedure Scan_Escape
        (In_String : Boolean;
         Result    : out Escape_Result;
         Value     : out Code_Point)
      is
         Start : constant Positive := Pos - 1;  --  the backslash

         procedure Numeric
           (Valid : not null access function (C : Character) return Boolean;
            Base  : Code_Point)
         is
            First : constant Positive := Pos;
            Acc   : Code_Point := 0;
            Overflowed : Boolean := False;
         begin
            Munch (Valid);
            for I in First .. Pos - 1 loop
               declare
                  C : constant Character := At_Offset (I);
                  D : constant Code_Point :=
                    (if Is_Digit (C) then Character'Pos (C) - 48
                     elsif C in 'a' .. 'f' then Character'Pos (C) - 87
                     else Character'Pos (C) - 55);
               begin
                  if Acc > (Code_Point'Last - D) / Base then
                     Overflowed := True;
                  else
                     Acc := Acc * Base + D;
                  end if;
               end;
            end loop;
            if Overflowed then
               Error (Diagnostics.Lex_Invalid_Literal, Start,
                      "numeric escape out of range");
               Result := Bad_Escape;
               Value := 16#FFFD#;
            else
               Result := Escaped_Char;
               Value := Acc;
            end if;
         end Numeric;

         C : constant Character := Peek;
      begin
         Result := Escaped_Char;
         Value := 16#FFFD#;

         if Pos > Len then
            Error (Diagnostics.Lex_Invalid_Literal, Start,
                   "incomplete escape");
            Result := Bad_Escape;
         elsif In_String and then Is_White (C) then
            --  Gap: backslash, whitespace, backslash (Report 2.6).
            Munch (Is_White'Access);
            if Peek = '\' then
               Pos := Pos + 1;
               Result := Gap;
            else
               Pos := Pos + 1;
               Error (Diagnostics.Lex_Invalid_Literal, Start,
                      "string gap must end with a backslash");
               Result := Bad_Escape;
            end if;
         elsif C = '&' then
            Pos := Pos + 1;
            Result := Empty_Escape;
         elsif Is_Digit (C) then
            Numeric (Is_Digit'Access, 10);
         elsif C = 'x' and then Is_Hex (Peek (1)) then
            Pos := Pos + 1;
            Numeric (Is_Hex'Access, 16);
         elsif C = 'o' and then Is_Octal (Peek (1)) then
            Pos := Pos + 1;
            Numeric (Is_Octal'Access, 8);
         elsif C = '^'
           and then (Is_Large (Peek (1))
                     or else Peek (1) in '@' | '[' | '\' | ']' | '^' | '_')
         then
            Pos := Pos + 2;
            Value := Character'Pos (At_Offset (Pos - 1)) - 64;
         else
            case C is
               when 'a' => Value := 7;   when 'b'  => Value := 8;
               when 'f' => Value := 12;  when 'n'  => Value := 10;
               when 'r' => Value := 13;  when 't'  => Value := 9;
               when 'v' => Value := 11;  when '\'  => Value := 92;
               when ''' => Value := 39;  when '"'  => Value := 34;
               when others => Value := Code_Point'Last;
            end case;

            if Value /= Code_Point'Last then
               Pos := Pos + 1;
            else
               --  ASCII mnemonics, longest match first ("SOH" over "SO").
               declare
                  Found : Boolean := False;
               begin
                  for Length in reverse 2 .. 3 loop
                     if not Found and then Pos + Length - 1 <= Len then
                        declare
                           Word : constant String :=
                             Slice (Pos, Pos + Length);
                        begin
                           for I in Mnemonics'Range loop
                              if Mnemonics (I).all = Word then
                                 Value := Mnemonic_Code (I);
                                 Pos := Pos + Length;
                                 Found := True;
                                 exit;
                              end if;
                           end loop;
                        end;
                     end if;
                  end loop;
                  if not Found then
                     Pos := Pos + 1;
                     Error (Diagnostics.Lex_Invalid_Literal, Start,
                            "unknown escape '\" & C & "'");
                     Result := Bad_Escape;
                     Value := 16#FFFD#;
                  end if;
               end;
            end if;
         end if;
      end Scan_Escape;

      procedure Append_Code_Point
        (Buffer : in out Ada.Strings.Unbounded.Unbounded_String;
         Value  : Code_Point)
      is
         use Ada.Strings.Unbounded;
      begin
         --  UTF-8 encode; the intern table stores byte strings.
         if Value < 16#80# then
            Append (Buffer, Character'Val (Value));
         elsif Value < 16#800# then
            Append (Buffer, Character'Val (16#C0# + Value / 2**6));
            Append (Buffer, Character'Val (16#80# + Value mod 2**6));
         elsif Value < 16#1_0000# then
            Append (Buffer, Character'Val (16#E0# + Value / 2**12));
            Append (Buffer,
                    Character'Val (16#80# + (Value / 2**6) mod 2**6));
            Append (Buffer, Character'Val (16#80# + Value mod 2**6));
         else
            Append (Buffer, Character'Val (16#F0# + Value / 2**18));
            Append (Buffer,
                    Character'Val (16#80# + (Value / 2**12) mod 2**6));
            Append (Buffer,
                    Character'Val (16#80# + (Value / 2**6) mod 2**6));
            Append (Buffer, Character'Val (16#80# + Value mod 2**6));
         end if;
      end Append_Code_Point;

      procedure Scan_Char is
         Start  : constant Positive := Pos;
         Value  : Code_Point := 16#FFFD#;
         Broken : Boolean := False;

         --  A raw non-ASCII character literal ('λ'): the lead byte
         --  is already consumed into Value; pull the continuation
         --  bytes of one UTF-8 sequence. Source files must be valid
         --  UTF-8 - malformed input is an invalid literal here, not
         --  a U+FFFD (that replacement policy is the runtime's, for
         --  data; source text can and should be rejected).
         procedure Decode_Utf8_Tail is
            Lead : constant Natural := Natural (Value);
            V    : Natural;   --  accumulate outside Code_Point's range
            Need : Natural;

            procedure Fail is
            begin
               Error (Diagnostics.Lex_Invalid_Literal, Start,
                      "invalid UTF-8 in character literal");
               Broken := True;
            end Fail;
         begin
            if Lead in 16#C2# .. 16#DF# then
               Need := 1;
               V := Lead mod 32;
            elsif Lead in 16#E0# .. 16#EF# then
               Need := 2;
               V := Lead mod 16;
            elsif Lead in 16#F0# .. 16#F4# then
               Need := 3;
               V := Lead mod 8;
            else
               Fail;
               return;
            end if;
            for I in 1 .. Need loop
               if Pos > Len
                 or else Character'Pos (Peek) not in 16#80# .. 16#BF#
               then
                  Fail;
                  return;
               end if;
               V := V * 64 + Character'Pos (Peek) mod 64;
               Pos := Pos + 1;
            end loop;
            if V > 16#10FFFF#
              or else V in 16#D800# .. 16#DFFF#
              or else (Need = 2 and then V < 16#800#)
              or else (Need = 3 and then V < 16#1_0000#)
            then
               Fail;
            else
               Value := Code_Point (V);
            end if;
         end Decode_Utf8_Tail;
      begin
         Pos := Pos + 1;  --  opening quote

         if Pos > Len or else Peek = ASCII.LF then
            Error (Diagnostics.Lex_Invalid_Literal, Start,
                   "unterminated character literal");
            Broken := True;
         elsif Peek = '\' then
            Pos := Pos + 1;
            declare
               Result : Escape_Result;
            begin
               Scan_Escape (In_String => False,
                            Result => Result, Value => Value);
               if Result in Empty_Escape | Gap then
                  Error (Diagnostics.Lex_Invalid_Literal, Start,
                         "escape not allowed in character literal");
                  Broken := True;
               elsif Result = Bad_Escape then
                  Broken := True;
               end if;
            end;
         elsif Peek = ''' then
            Error (Diagnostics.Lex_Invalid_Literal, Start,
                   "empty character literal");
            Pos := Pos + 1;
            Emit_Plain (Error_Token, Start);
            return;
         else
            Value := Character'Pos (Peek);
            Pos := Pos + 1;
            if Value >= 16#80# then
               Decode_Utf8_Tail;
            end if;
         end if;

         if Pos <= Len and then Peek = ''' then
            Pos := Pos + 1;
         elsif not Broken then
            Error (Diagnostics.Lex_Invalid_Literal, Start,
                   "unterminated character literal");
            Broken := True;
         end if;

         if Broken then
            Emit_Plain (Error_Token, Start);
         else
            Emit ((Kind => Char_Lit, Char_Value => Value, others => <>),
                  Start);
         end if;
      end Scan_Char;

      procedure Scan_String is
         use Ada.Strings.Unbounded;
         Start  : constant Positive := Pos;
         Buffer : Unbounded_String;
         Broken : Boolean := False;
      begin
         Pos := Pos + 1;  --  opening quote

         loop
            if Pos > Len or else Peek = ASCII.LF then
               Error (Diagnostics.Lex_Unterminated_String, Start,
                      "unterminated string literal");
               Broken := True;
               exit;
            elsif Peek = '"' then
               Pos := Pos + 1;
               exit;
            elsif Peek = '\' then
               Pos := Pos + 1;
               declare
                  Result : Escape_Result;
                  Value  : Code_Point;
               begin
                  Scan_Escape (In_String => True,
                               Result => Result, Value => Value);
                  case Result is
                     when Escaped_Char => Append_Code_Point (Buffer, Value);
                     when Empty_Escape | Gap => null;
                     when Bad_Escape => Broken := True;
                  end case;
               end;
            else
               Append (Buffer, Peek);
               Pos := Pos + 1;
            end if;
         end loop;

         if Broken then
            Emit_Plain (Error_Token, Start);
         else
            Emit ((Kind => String_Lit,
                   String_Value =>
                     (if Length (Buffer) = 0 then Names.No_Name
                      else Names.Name_Id
                             (Table.Intern (To_String (Buffer)))),
                   others => <>), Start);
         end if;
      end Scan_String;

      Special : Token_Kind;

   begin
      Result.Clear;

      while Pos <= Len loop
         declare
            C : constant Character := Peek;
         begin
            if Is_White (C) then
               Pos := Pos + 1;
            elsif C = '-' and then At_Line_Comment then
               Skip_Line_Comment;
            elsif C = '{' and then Peek (1) = '-' then
               Skip_Block_Comment;
            elsif Is_Small (C) then
               Scan_Small_Ident;
            elsif Is_Large (C) then
               Scan_Large_Ident;
            elsif Is_Digit (C) then
               Scan_Number;
            elsif C = ''' then
               Scan_Char;
            elsif C = '"' then
               Scan_String;
            elsif Is_Symbol_Char (C) then
               Scan_Operator;
            elsif Character'Pos (C) >= 16#80# then
               --  Unicode letters and symbols (Report 2.2, M150).
               case Class_At (Pos) is
                  when Small => Scan_Small_Ident;
                  when Large => Scan_Large_Ident;
                  when Symbol => Scan_Operator;
                  when others =>
                     declare
                        Start : constant Positive := Pos;
                     begin
                        Pos := Pos + Width_At (Pos);
                        Error (Diagnostics.Lex_Invalid_Character, Start,
                               "invalid character '" & Slice (Start, Pos)
                               & "'");
                        Emit_Plain (Error_Token, Start);
                     end;
               end case;
            else
               case C is
                  when '(' => Special := Left_Paren;
                  when ')' => Special := Right_Paren;
                  when '[' => Special := Left_Bracket;
                  when ']' => Special := Right_Bracket;
                  when ',' => Special := Comma;
                  when ';' => Special := Semicolon;
                  when '`' => Special := Backtick;
                  when '{' => Special := Left_Brace;
                  when '}' => Special := Right_Brace;
                  when others => Special := Error_Token;
               end case;

               declare
                  Start : constant Positive := Pos;
               begin
                  Pos := Pos + 1;
                  if Special = Error_Token then
                     Error (Diagnostics.Lex_Invalid_Character, Start,
                            "invalid character '" & C & "'");
                  end if;
                  Emit_Plain (Special, Start);
               end;
            end if;
         end;
      end loop;

      Emit_Plain (End_Of_File, Pos);
   end Scan;

end AHC.Lexer;
