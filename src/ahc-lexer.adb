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
      --  Numeric literals (decimal/octal/hex integers here; floats and
      --  the char/string literals arrive with Milestone 3)
      ------------------------------------------------------------------

      procedure Scan_Number is
         Start : constant Positive := Pos;

         procedure Munch (Valid : not null access
                            function (C : Character) return Boolean) is
         begin
            while Pos <= Len and then Valid (Peek) loop
               Pos := Pos + 1;
            end loop;
         end Munch;

         function Is_Octal (C : Character) return Boolean
         is (C in '0' .. '7');
         function Is_Hex (C : Character) return Boolean
         is (Is_Digit (C) or else C in 'a' .. 'f' | 'A' .. 'F');
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
         end if;
         Emit ((Kind => Int_Lit,
                Int_Text => Table.Intern (Slice (Start, Pos)),
                others => <>), Start);
      end Scan_Number;

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
