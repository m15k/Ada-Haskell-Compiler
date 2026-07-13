with Ada.Strings.Unbounded;

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

   function Is_Ident_Char (C : Character) return Boolean
   is (Is_Small (C) or else Is_Large (C) or else Is_Digit (C)
       or else C = ''');

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
            Column := Text.Column_Of (Source_Text.Byte_Offset (Len)) + 1;
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
         return Ahead >= 2 and then not Is_Symbol_Char (Peek (Ahead));
      end At_Line_Comment;

      procedure Skip_Line_Comment is
      begin
         while Pos <= Len and then Peek /= ASCII.LF and then Peek /= ASCII.FF
         loop
            Pos := Pos + 1;
         end loop;
      end Skip_Line_Comment;

      --  At "{-". Nested; the contents are not tokenized, so "-}" inside
      --  string syntax still closes (Report 2.3).
      procedure Skip_Block_Comment is
         Start : constant Positive := Pos;
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
      end Skip_Block_Comment;

      ------------------------------------------------------------------
      --  Names
      ------------------------------------------------------------------

      --  Munch identifier characters starting at Pos (which must be a
      --  small or large letter) and leave Pos one past the end.
      function Munch_Ident return Positive is
         Start : constant Positive := Pos;
      begin
         while Pos <= Len and then Is_Ident_Char (Peek) loop
            Pos := Pos + 1;
         end loop;
         return Start;
      end Munch_Ident;

      function Munch_Symbols return Positive is
         Start : constant Positive := Pos;
      begin
         while Pos <= Len and then Is_Symbol_Char (Peek) loop
            Pos := Pos + 1;
         end loop;
         return Start;
      end Munch_Symbols;

      procedure Scan_Small_Ident is
         Start : constant Positive := Munch_Ident;
         Word  : constant String := Slice (Start, Pos);
         Kind  : constant Token_Kind := Word_Kind (Word);
      begin
         if Kind = Varid then
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

               if Pos <= Len and then Is_Large (Peek) then
                  declare
                     Part_Start : constant Positive := Munch_Ident;
                     pragma Unreferenced (Part_Start);
                  begin
                     Qual_Stop := Pos;  --  chain grew; maybe more to come
                  end;
               elsif Pos <= Len and then Is_Small (Peek) then
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
               elsif Pos <= Len and then Is_Symbol_Char (Peek) then
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
