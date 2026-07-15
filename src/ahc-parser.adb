with AHC.Layout;

package body AHC.Parser is

   use AHC.Tokens;
   use AHC.Syntax;
   use type Names.Name_Id;

   Parse_Failure : exception;

   procedure Parse_Module
     (Raw   : Tokens.Token_Vectors.Vector;
      Table : in out Names.Name_Table;
      Bag   : in out Diagnostics.Diagnostic_Bag;
      Arena : in out Syntax.Module_Arena)
   is
      Laid : Layout.Layout_Stream;
      Tok  : Token;

      --  Lookahead buffer; tokens already pulled from the stream but
      --  not yet consumed. Tok is always the current token.
      Pending : Token_Vectors.Vector;
      P_First : Positive := 1;

      Minus_Name : constant Names.Real_Name_Id := Table.Intern ("-");
      Bang_Name  : constant Names.Real_Name_Id := Table.Intern ("!");
      Unit_Name  : constant Names.Real_Name_Id := Table.Intern ("()");
      Nil_Name   : constant Names.Real_Name_Id := Table.Intern ("[]");
      Arrow_Name : constant Names.Real_Name_Id := Table.Intern ("(->)");
      Colon_Name : constant Names.Real_Name_Id := Table.Intern (":");

      ------------------------------------------------------------------
      --  Token plumbing
      ------------------------------------------------------------------

      procedure Advance is
      begin
         if not Pending.Is_Empty and then P_First <= Pending.Last_Index
         then
            Tok := Pending (P_First);
            if P_First = Pending.Last_Index then
               Pending.Clear;
               P_First := 1;
            else
               P_First := P_First + 1;
            end if;
         elsif Laid.Finished then
            null;  --  stay on End_Of_File
         else
            Laid.Next (Bag, Tok);
         end if;
      end Advance;

      --  Token N positions after Tok (Peek (1) = next token).
      function Peek (N : Positive := 1) return Token is
         T : Token;
      begin
         while Natural (Pending.Length) - (P_First - 1) < N loop
            if Laid.Finished then
               return Pending.Last_Element;   --  End_Of_File
            end if;
            Laid.Next (Bag, T);
            Pending.Append (T);
         end loop;
         return Pending (P_First + N - 1);
      end Peek;

      function At_K (K : Token_Kind) return Boolean is (Tok.Kind = K);

      procedure Fail (Message : String) with No_Return is
      begin
         Bag.Add (Diagnostics.Error, Diagnostics.Parse_Error, Tok.Span,
                  Message & " (found '" & Image (Tok, Table) & "')");
         raise Parse_Failure;
      end Fail;

      --  The layout parse-error(t) hook. True if an implicit context
      --  was closed; Tok then is the V_Right_Brace.
      function Try_Layout_Close return Boolean is
         Closed : Boolean;
      begin
         if not Pending.Is_Empty and then P_First <= Pending.Last_Index
         then
            return False;  --  stream is ahead of us; cannot close here
         end if;
         if Laid.Finished then
            return False;
         end if;
         Laid.Close_On_Parse_Error (Closed);
         if Closed then
            Advance;  --  the V_Right_Brace
         end if;
         return Closed;
      end Try_Layout_Close;

      procedure Expect (K : Token_Kind; What : String) is
      begin
         if Tok.Kind = K then
            Advance;
         elsif Try_Layout_Close and then Tok.Kind = K then
            Advance;
         else
            Fail ("expected " & What);
         end if;
      end Expect;

      ------------------------------------------------------------------
      --  Small helpers
      ------------------------------------------------------------------

      function Tok_QName return QName
      is (Name => Tok.Name, Qualifier => Tok.Qualifier);

      function Is_Minus return Boolean
      is (Tok.Kind = Varsym and then Tok.Qualifier = Names.No_Name
          and then Tok.Name = Minus_Name);

      function Is_Bang return Boolean
      is (Tok.Kind = Varsym and then Tok.Qualifier = Names.No_Name
          and then Tok.Name = Bang_Name);

      --  Operators usable in expression chains, including the reserved
      --  cons ':' (an operator everywhere except declarations heads).
      function At_Op return Boolean
      is (Tok.Kind in Varsym | Consym | Qvarsym | Qconsym
          or else Tok.Kind = Colon
          or else Tok.Kind = Backtick);

      --  Consume an operator occurrence: symbol or `name`.
      function Parse_Op return Op_Occ is
         R : Op_Occ;
      begin
         R.Span := Tok.Span;
         case Tok.Kind is
            when Varsym | Qvarsym =>
               R.Op := Tok_QName;
               Advance;
            when Consym | Qconsym =>
               R.Op := Tok_QName;
               R.Is_Con := True;
               Advance;
            when Colon =>
               R.Op := (Name => Colon_Name, Qualifier => Names.No_Name);
               R.Is_Con := True;
               Advance;
            when Backtick =>
               Advance;
               if Tok.Kind in Varid | Qvarid then
                  R.Op := Tok_QName;
               elsif Tok.Kind in Conid | Qconid then
                  R.Op := Tok_QName;
                  R.Is_Con := True;
               else
                  Fail ("expected name between backticks");
               end if;
               Advance;
               Expect (Backtick, "closing backtick");
            when others =>
               Fail ("expected operator");
         end case;
         return R;
      end Parse_Op;

      --  Dotted module name from a Conid/Qconid token.
      function Module_Name_Of (T : Token) return Names.Real_Name_Id
      is (if T.Qualifier = Names.No_Name then T.Name
          else Table.Intern
                 (Table.Text (T.Qualifier) & "." & Table.Text (T.Name)));

      --  Scan ahead for '<-' at bracket depth 0, stopping at any of the
      --  stop kinds at depth 0. Distinguishes 'pat <- exp' from plain
      --  expressions in do-statements and list-comprehension quals.
      function Arrow_Ahead return Boolean is
         Depth : Natural := 0;
         N     : Positive := 1;
      begin
         if Tok.Kind = Left_Arrow then
            return False;
         end if;
         --  Current token first.
         case Tok.Kind is
            when Left_Paren | Left_Bracket | Left_Brace | V_Left_Brace =>
               Depth := 1;
            when others =>
               null;
         end case;
         loop
            declare
               T : constant Token := Peek (N);
            begin
               case T.Kind is
                  when Left_Paren | Left_Bracket | Left_Brace
                     | V_Left_Brace =>
                     Depth := Depth + 1;
                  when Right_Paren | Right_Bracket | Right_Brace
                     | V_Right_Brace =>
                     if Depth = 0 then
                        return False;
                     end if;
                     Depth := Depth - 1;
                  when Left_Arrow =>
                     if Depth = 0 then
                        return True;
                     end if;
                  when Comma | Pipe | Semicolon | V_Semicolon
                     | End_Of_File =>
                     if Depth = 0 then
                        return False;
                     end if;
                  when others =>
                     null;
               end case;
            end;
            N := N + 1;
         end loop;
      end Arrow_Ahead;

      ------------------------------------------------------------------
      --  Forward declarations
      ------------------------------------------------------------------

      function Parse_Type return Real_Type_Id;
      function Parse_Expr return Real_Expr_Id;
      function Parse_Pat return Real_Pat_Id;
      procedure Parse_Decl_Block (Into : in out Decl_Id_Vectors.Vector);
      function Parse_Paren_Exp
        (Span : Diagnostics.Source_Span) return Real_Expr_Id;
      function Parse_Bracket_Exp
        (Span : Diagnostics.Source_Span) return Real_Expr_Id;
      function Parse_Qual return Real_Stmt_Id;
      procedure Parse_Stmt_Block (Into : in out Stmt_Id_Vectors.Vector);
      procedure Parse_Alt_Block (Into : in out Alt_Id_Vectors.Vector);

      ------------------------------------------------------------------
      --  Types (Report 4.1.2)
      ------------------------------------------------------------------

      function Can_Start_AType return Boolean
      is (Tok.Kind in Varid | Conid | Qconid | Left_Paren | Left_Bracket);

      function Parse_AType return Real_Type_Id is
         Span : constant Diagnostics.Source_Span := Tok.Span;
      begin
         case Tok.Kind is
            when Varid =>
               declare
                  V : constant Names.Name_Id := Tok.Name;
               begin
                  Advance;
                  return Arena.Add
                    (Type_Node'(Kind => Var_T, Span => Span, Var => V));
               end;
            when Conid | Qconid =>
               declare
                  Q : constant QName := Tok_QName;
               begin
                  Advance;
                  return Arena.Add
                    (Type_Node'(Kind => Con_T, Span => Span, Con => Q));
               end;
            when Left_Paren =>
               Advance;
               if At_K (Right_Paren) then
                  Advance;
                  return Arena.Add
                    (Type_Node'(Kind => Con_T, Span => Span,
                                Con => (Unit_Name, Names.No_Name)));
               elsif At_K (Right_Arrow) then
                  Advance;
                  Expect (Right_Paren, "')'");
                  return Arena.Add
                    (Type_Node'(Kind => Con_T, Span => Span,
                                Con => (Arrow_Name, Names.No_Name)));
               end if;
               declare
                  First : constant Real_Type_Id := Parse_Type;
                  Items : Type_Id_Vectors.Vector;
               begin
                  if At_K (Comma) then
                     Items.Append (First);
                     while At_K (Comma) loop
                        Advance;
                        Items.Append (Parse_Type);
                     end loop;
                     Expect (Right_Paren, "')'");
                     return Arena.Add
                       (Type_Node'(Kind => Tuple_T, Span => Span,
                                   Items => Items));
                  end if;
                  Expect (Right_Paren, "')'");
                  return First;
               end;
            when Left_Bracket =>
               Advance;
               if At_K (Right_Bracket) then
                  Advance;
                  return Arena.Add
                    (Type_Node'(Kind => Con_T, Span => Span,
                                Con => (Nil_Name, Names.No_Name)));
               end if;
               declare
                  Elem : constant Real_Type_Id := Parse_Type;
               begin
                  Expect (Right_Bracket, "']'");
                  return Arena.Add
                    (Type_Node'(Kind => List_T, Span => Span,
                                Elem => Elem));
               end;
            when others =>
               Fail ("expected a type");
         end case;
      end Parse_AType;

      function Parse_BType return Real_Type_Id is
         Span   : constant Diagnostics.Source_Span := Tok.Span;
         Result : Real_Type_Id := Parse_AType;
      begin
         while Can_Start_AType loop
            Result := Arena.Add
              (Type_Node'(Kind => App_T, Span => Span,
                          Fun => Result, Arg => Parse_AType));
         end loop;
         return Result;
      end Parse_BType;

      --  Split a pre-'=>' type into context assertions.
      function To_Context (Id : Real_Type_Id) return Type_Id_Vectors.Vector
      is
         N   : constant Type_Node := Arena.Node (Id);
         Ctx : Type_Id_Vectors.Vector;
      begin
         if N.Kind = Tuple_T then
            Ctx := N.Items;
         else
            Ctx.Append (Id);
         end if;
         return Ctx;
      end To_Context;

      --  Refinement bound: [-] integer literal.
      procedure Parse_Bound
        (Neg : out Boolean; Text : out Names.Name_Id) is
      begin
         Neg := False;
         Text := Names.No_Name;
         if Is_Minus then
            Neg := True;
            Advance;
         end if;
         if At_K (Int_Lit) then
            Text := Names.Name_Id (Tok.Int_Text);
            Advance;
         else
            Fail ("expected an integer literal refinement bound");
         end if;
      end Parse_Bound;

      --  'in' introduces a refinement only when followed by a bound;
      --  otherwise it belongs to an enclosing let (types can appear
      --  in let-block signatures).
      function At_Refinement return Boolean
      is (At_K (Kw_In)
          and then (Peek (1).Kind = Int_Lit
                    or else (Peek (1).Kind = Varsym
                             and then Peek (1).Qualifier = Names.No_Name
                             and then Peek (1).Name = Minus_Name
                             and then Peek (2).Kind = Int_Lit)));

      function Parse_Type return Real_Type_Id is
         Span   : constant Diagnostics.Source_Span := Tok.Span;
         Result : Real_Type_Id := Parse_BType;
      begin
         if At_Refinement then
            Advance;   --  'in'
            declare
               Lo_Neg, Hi_Neg   : Boolean;
               Lo_Text, Hi_Text : Names.Name_Id;
            begin
               Parse_Bound (Lo_Neg, Lo_Text);
               Expect (Dot_Dot, "'..'");
               Parse_Bound (Hi_Neg, Hi_Text);
               Result := Arena.Add
                 (Type_Node'(Kind => Refined_T, Span => Span,
                             R_Base => Result,
                             Lo_Neg => Lo_Neg, Hi_Neg => Hi_Neg,
                             Lo_Text => Lo_Text, Hi_Text => Hi_Text));
            end;
         end if;
         if At_K (Fat_Arrow) then
            Advance;
            declare
               Ctx : constant Type_Id_Vectors.Vector := To_Context (Result);
            begin
               return Arena.Add
                 (Type_Node'(Kind => Qual_T, Span => Span,
                             Context => Ctx, Q_Body => Parse_Type));
            end;
         elsif At_K (Right_Arrow) then
            Advance;
            return Arena.Add
              (Type_Node'(Kind => Fun_T, Span => Span,
                          From => Result, To => Parse_Type));
         end if;
         return Result;
      end Parse_Type;

      ------------------------------------------------------------------
      --  Patterns (Report 3.17)
      ------------------------------------------------------------------

      function Can_Start_APat return Boolean
      is (Tok.Kind in Varid | Conid | Qconid | Underscore
            | Int_Lit | Float_Lit | Char_Lit | String_Lit
            | Left_Paren | Left_Bracket | Tilde);

      function Parse_APat return Real_Pat_Id is
         Span : constant Diagnostics.Source_Span := Tok.Span;
      begin
         case Tok.Kind is
            when Varid =>
               declare
                  V : constant Names.Name_Id := Tok.Name;
               begin
                  Advance;
                  if At_K (At_Sign) then
                     Advance;
                     return Arena.Add
                       (Pat_Node'(Kind => As_P, Span => Span,
                                  As_Var => V, As_Pat => Parse_APat));
                  end if;
                  return Arena.Add
                    (Pat_Node'(Kind => Var_P, Span => Span, Var => V));
               end;
            when Underscore =>
               Advance;
               return Arena.Add (Pat_Node'(Kind => Wild_P, Span => Span));
            when Int_Lit =>
               declare
                  T : constant Names.Name_Id := Tok.Int_Text;
               begin
                  Advance;
                  return Arena.Add
                    (Pat_Node'(Kind => Lit_Int_P, Span => Span, Text => T));
               end;
            when Float_Lit =>
               declare
                  T : constant Names.Name_Id := Tok.Float_Text;
               begin
                  Advance;
                  return Arena.Add
                    (Pat_Node'
                       (Kind => Lit_Float_P, Span => Span, Text => T));
               end;
            when Char_Lit =>
               declare
                  V : constant Natural := Tok.Char_Value;
               begin
                  Advance;
                  return Arena.Add
                    (Pat_Node'(Kind => Lit_Char_P, Span => Span,
                               Char_Value => V));
               end;
            when String_Lit =>
               declare
                  T : constant Names.Name_Id := Tok.String_Value;
               begin
                  Advance;
                  return Arena.Add
                    (Pat_Node'
                       (Kind => Lit_String_P, Span => Span, Text => T));
               end;
            when Conid | Qconid =>
               declare
                  C : constant QName := Tok_QName;
               begin
                  Advance;
                  if At_K (Left_Brace) then
                     Advance;
                     declare
                        Fields : Field_Pat_Vectors.Vector;
                     begin
                        while not At_K (Right_Brace) loop
                           declare
                              F : QName;
                           begin
                              if Tok.Kind not in Varid | Qvarid then
                                 Fail ("expected field name");
                              end if;
                              F := Tok_QName;
                              Advance;
                              Expect (Equals, "'='");
                              Fields.Append
                                (Field_Pat'(Field => F,
                                            Value => Parse_Pat));
                           end;
                           exit when not At_K (Comma);
                           Advance;
                        end loop;
                        Expect (Right_Brace, "'}'");
                        return Arena.Add
                          (Pat_Node'(Kind => Rec_P, Span => Span,
                                     Rec_Con => C, Rec_Fields => Fields));
                     end;
                  end if;
                  return Arena.Add
                    (Pat_Node'(Kind => Con_P, Span => Span,
                               Con => C,
                               Con_Args => Pat_Id_Vectors.Empty_Vector));
               end;
            when Tilde =>
               Advance;
               return Arena.Add
                 (Pat_Node'(Kind => Lazy_P, Span => Span,
                            Lazy_Pat => Parse_APat));
            when Left_Paren =>
               Advance;
               if At_K (Right_Paren) then
                  Advance;
                  return Arena.Add
                    (Pat_Node'(Kind => Con_P, Span => Span,
                               Con => (Unit_Name, Names.No_Name),
                               Con_Args => Pat_Id_Vectors.Empty_Vector));
               end if;
               declare
                  First : constant Real_Pat_Id := Parse_Pat;
                  Items : Pat_Id_Vectors.Vector;
               begin
                  if At_K (Comma) then
                     Items.Append (First);
                     while At_K (Comma) loop
                        Advance;
                        Items.Append (Parse_Pat);
                     end loop;
                     Expect (Right_Paren, "')'");
                     return Arena.Add
                       (Pat_Node'(Kind => Tuple_P, Span => Span,
                                  Items => Items));
                  end if;
                  Expect (Right_Paren, "')'");
                  return First;
               end;
            when Left_Bracket =>
               Advance;
               declare
                  Items : Pat_Id_Vectors.Vector;
               begin
                  if not At_K (Right_Bracket) then
                     Items.Append (Parse_Pat);
                     while At_K (Comma) loop
                        Advance;
                        Items.Append (Parse_Pat);
                     end loop;
                  end if;
                  Expect (Right_Bracket, "']'");
                  return Arena.Add
                    (Pat_Node'(Kind => List_P, Span => Span,
                               Items => Items));
               end;
            when others =>
               Fail ("expected a pattern");
         end case;
      end Parse_APat;

      function Parse_Pat10 return Real_Pat_Id is
         Span : constant Diagnostics.Source_Span := Tok.Span;
      begin
         --  Negative literal.
         if Is_Minus
           and then Peek (1).Kind in Int_Lit | Float_Lit
         then
            Advance;
            if At_K (Int_Lit) then
               declare
                  T : constant Names.Name_Id := Tok.Int_Text;
               begin
                  Advance;
                  return Arena.Add
                    (Pat_Node'(Kind => Neg_Int_P, Span => Span, Text => T));
               end;
            else
               declare
                  T : constant Names.Name_Id := Tok.Float_Text;
               begin
                  Advance;
                  return Arena.Add
                    (Pat_Node'
                       (Kind => Neg_Float_P, Span => Span, Text => T));
               end;
            end if;
         end if;

         --  Constructor application (only a bare conid can take args;
         --  'Just x' but a parenthesized '(Just) x' is not a pattern).
         if Tok.Kind in Conid | Qconid
           and then Peek (1).Kind /= Left_Brace
         then
            declare
               C    : constant QName := Tok_QName;
               Args : Pat_Id_Vectors.Vector;
            begin
               Advance;
               while Can_Start_APat loop
                  Args.Append (Parse_APat);
               end loop;
               return Arena.Add
                 (Pat_Node'(Kind => Con_P, Span => Span,
                            Con => C, Con_Args => Args));
            end;
         end if;

         return Parse_APat;
      end Parse_Pat10;

      function Parse_Pat return Real_Pat_Id is
         Span      : constant Diagnostics.Source_Span := Tok.Span;
         First     : constant Real_Pat_Id := Parse_Pat10;
         Operands  : Pat_Id_Vectors.Vector;
         Operators : Op_Occ_Vectors.Vector;
      begin
         if not (Tok.Kind in Consym | Qconsym or else At_K (Colon)) then
            return First;
         end if;
         Operands.Append (First);
         while Tok.Kind in Consym | Qconsym or else At_K (Colon) loop
            Operators.Append (Parse_Op);
            Operands.Append (Parse_Pat10);
         end loop;
         return Arena.Add
           (Pat_Node'(Kind => Con_Chain_P, Span => Span,
                      Operands => Operands, Operators => Operators));
      end Parse_Pat;

      ------------------------------------------------------------------
      --  Expressions (Report 3)
      ------------------------------------------------------------------

      function Can_Start_AExp return Boolean
      is (Tok.Kind in Varid | Qvarid | Conid | Qconid
            | Int_Lit | Float_Lit | Char_Lit | String_Lit
            | Left_Paren | Left_Bracket);

      function Parse_Guarded
        (Sep : Token_Kind; Sep_Name : String) return Rhs;

      procedure Parse_Where (Into : in out Decl_Id_Vectors.Vector);

      --  aexp with record construction/update suffixes.
      function Parse_AExp return Real_Expr_Id is
         Span   : constant Diagnostics.Source_Span := Tok.Span;
         Result : Real_Expr_Id;

         procedure Parse_Record_Suffix is
         begin
            while At_K (Left_Brace) loop
               Advance;
               declare
                  Fields  : Field_Assign_Vectors.Vector;
                  Base    : constant Expr_Node := Arena.Node (Result);
                  Is_Con  : constant Boolean := Base.Kind = Con_E;
               begin
                  while not At_K (Right_Brace) loop
                     declare
                        F : QName;
                     begin
                        if Tok.Kind not in Varid | Qvarid then
                           Fail ("expected field name");
                        end if;
                        F := Tok_QName;
                        Advance;
                        Expect (Equals, "'='");
                        Fields.Append
                          (Field_Assign'(Field => F, Value => Parse_Expr));
                     end;
                     exit when not At_K (Comma);
                     Advance;
                  end loop;
                  Expect (Right_Brace, "'}'");
                  if Is_Con then
                     Result := Arena.Add
                       (Expr_Node'(Kind => Rec_Con_E, Span => Span,
                                   Rec_Base => Result,
                                   Rec_Fields => Fields));
                  else
                     Result := Arena.Add
                       (Expr_Node'(Kind => Rec_Update_E, Span => Span,
                                   Rec_Base => Result,
                                   Rec_Fields => Fields));
                  end if;
               end;
            end loop;
         end Parse_Record_Suffix;
      begin
         case Tok.Kind is
            when Varid | Qvarid =>
               Result := Arena.Add
                 (Expr_Node'(Kind => Var_E, Span => Span,
                             Name => Tok_QName));
               Advance;
            when Conid | Qconid =>
               Result := Arena.Add
                 (Expr_Node'(Kind => Con_E, Span => Span,
                             Name => Tok_QName));
               Advance;
            when Int_Lit =>
               Result := Arena.Add
                 (Expr_Node'(Kind => Lit_Int_E, Span => Span,
                             Text => Tok.Int_Text));
               Advance;
            when Float_Lit =>
               Result := Arena.Add
                 (Expr_Node'(Kind => Lit_Float_E, Span => Span,
                             Text => Tok.Float_Text));
               Advance;
            when Char_Lit =>
               Result := Arena.Add
                 (Expr_Node'(Kind => Lit_Char_E, Span => Span,
                             Char_Value => Tok.Char_Value));
               Advance;
            when String_Lit =>
               Result := Arena.Add
                 (Expr_Node'(Kind => Lit_String_E, Span => Span,
                             Text => Tok.String_Value));
               Advance;
            when Left_Paren =>
               Result := Parse_Paren_Exp (Span);
            when Left_Bracket =>
               Result := Parse_Bracket_Exp (Span);
            when others =>
               Fail ("expected an expression");
         end case;
         Parse_Record_Suffix;
         return Result;
      end Parse_AExp;

      function Parse_FExp return Real_Expr_Id is
         Span   : constant Diagnostics.Source_Span := Tok.Span;
         Result : Real_Expr_Id := Parse_AExp;
      begin
         while Can_Start_AExp loop
            Result := Arena.Add
              (Expr_Node'(Kind => App_E, Span => Span,
                          Fun => Result, Arg => Parse_AExp));
         end loop;
         return Result;
      end Parse_FExp;

      --  lexp: lambda, let, if, case, do, or fexp.
      function Parse_LExp return Real_Expr_Id is
         Span : constant Diagnostics.Source_Span := Tok.Span;
      begin
         case Tok.Kind is
            when Backslash =>
               Advance;
               declare
                  Pats : Pat_Id_Vectors.Vector;
               begin
                  Pats.Append (Parse_APat);
                  while Can_Start_APat loop
                     Pats.Append (Parse_APat);
                  end loop;
                  Expect (Right_Arrow, "'->'");
                  return Arena.Add
                    (Expr_Node'(Kind => Lambda_E, Span => Span,
                                L_Pats => Pats, L_Body => Parse_Expr));
               end;
            when Kw_Let =>
               Advance;
               declare
                  Binds : Decl_Id_Vectors.Vector;
               begin
                  Parse_Decl_Block (Binds);
                  Expect (Kw_In, "'in'");
                  if Binds.Is_Empty then
                     Fail ("empty let block");
                  end if;
                  return Arena.Add
                    (Expr_Node'(Kind => Let_E, Span => Span,
                                Binds => Binds, Let_Body => Parse_Expr));
               end;
            when Kw_If =>
               Advance;
               declare
                  C : constant Real_Expr_Id := Parse_Expr;
               begin
                  if At_K (Semicolon) or else At_K (V_Semicolon) then
                     Advance;  --  Haskell 2010 optional semicolons
                  end if;
                  Expect (Kw_Then, "'then'");
                  declare
                     T : constant Real_Expr_Id := Parse_Expr;
                  begin
                     if At_K (Semicolon) or else At_K (V_Semicolon) then
                        Advance;
                     end if;
                     Expect (Kw_Else, "'else'");
                     return Arena.Add
                       (Expr_Node'(Kind => If_E, Span => Span,
                                   Cond => C, Then_E => T,
                                   Else_E => Parse_Expr));
                  end;
               end;
            when Kw_Case =>
               Advance;
               declare
                  Scrut : constant Real_Expr_Id := Parse_Expr;
                  Alts  : Alt_Id_Vectors.Vector;
               begin
                  Expect (Kw_Of, "'of'");
                  Parse_Alt_Block (Alts);
                  if Alts.Is_Empty then
                     Fail ("empty case block");
                  end if;
                  return Arena.Add
                    (Expr_Node'(Kind => Case_E, Span => Span,
                                Scrutinee => Scrut, Alts => Alts));
               end;
            when Kw_Do =>
               Advance;
               declare
                  Stmts : Stmt_Id_Vectors.Vector;
               begin
                  Parse_Stmt_Block (Stmts);
                  if Stmts.Is_Empty then
                     Fail ("empty do block");
                  end if;
                  return Arena.Add
                    (Expr_Node'(Kind => Do_E, Span => Span,
                                Stmts => Stmts));
               end;
            when others =>
               return Parse_FExp;
         end case;
      end Parse_LExp;

      --  infixexp as a flat chain; resolved by AHC.Fixity later.
      function Parse_Op_Chain
        (Allow_Left_Section : Boolean;
         Section_Op         : out Op_Occ;
         Is_Section         : out Boolean) return Real_Expr_Id
      is
         Span      : constant Diagnostics.Source_Span := Tok.Span;
         Operands  : Expr_Id_Vectors.Vector;
         Operators : Op_Occ_Vectors.Vector;
         Neg_First : Boolean := False;
      begin
         Is_Section := False;
         if Is_Minus then
            Advance;
            Neg_First := True;
         end if;
         Operands.Append (Parse_LExp);

         while At_Op loop
            declare
               Op : Op_Occ := Parse_Op;
            begin
               if Allow_Left_Section and then At_K (Right_Paren) then
                  Section_Op := Op;
                  Is_Section := True;
                  exit;
               end if;
               if Is_Minus then
                  Advance;
                  Op.Neg_After := True;
               end if;
               Operators.Append (Op);
               Operands.Append (Parse_LExp);
            end;
         end loop;

         if Operators.Is_Empty then
            if Neg_First then
               return Arena.Add
                 (Expr_Node'(Kind => Neg_E, Span => Span,
                             Negated => Operands (1)));
            end if;
            return Operands (1);
         end if;
         return Arena.Add
           (Expr_Node'(Kind => Op_Chain_E, Span => Span,
                       Operands => Operands, Operators => Operators,
                       Neg_First => Neg_First));
      end Parse_Op_Chain;

      function Parse_Simple_Chain return Real_Expr_Id is
         Op : Op_Occ;
         Is_Sec : Boolean;
      begin
         return Parse_Op_Chain (False, Op, Is_Sec);
      end Parse_Simple_Chain;

      function Parse_Expr return Real_Expr_Id is
         Span   : constant Diagnostics.Source_Span := Tok.Span;
         Result : constant Real_Expr_Id := Parse_Simple_Chain;
      begin
         if At_K (Colon_Colon) then
            Advance;
            return Arena.Add
              (Expr_Node'(Kind => Sig_E, Span => Span,
                          Sig_Expr => Result, Sig_Type => Parse_Type));
         end if;
         return Result;
      end Parse_Expr;

      ------------------------------------------------------------------
      --  Parenthesized and bracketed expressions
      ------------------------------------------------------------------

      function Parse_Paren_Exp
        (Span : Diagnostics.Source_Span) return Real_Expr_Id
      is
      begin
         Advance;  --  '('

         --  () and operator references / right sections.
         if At_K (Right_Paren) then
            Advance;
            return Arena.Add
              (Expr_Node'(Kind => Con_E, Span => Span,
                          Name => (Unit_Name, Names.No_Name)));
         end if;

         --  Tuple constructors (,) (,,) ...
         if At_K (Comma) then
            declare
               Commas : Natural := 0;
            begin
               while At_K (Comma) loop
                  Commas := Commas + 1;
                  Advance;
               end loop;
               Expect (Right_Paren, "')'");
               declare
                  Text : String (1 .. Commas + 2);
               begin
                  Text (1) := '(';
                  Text (Text'Last) := ')';
                  for I in 2 .. Text'Last - 1 loop
                     Text (I) := ',';
                  end loop;
                  return Arena.Add
                    (Expr_Node'(Kind => Con_E, Span => Span,
                                Name => (Table.Intern (Text),
                                         Names.No_Name)));
               end;
            end;
         end if;

         --  Operator at the head: '(+)' reference, '(+ x)' right
         --  section, or '(- x)' negation.
         if At_Op and then not Is_Minus then
            declare
               Op : constant Op_Occ := Parse_Op;
            begin
               if At_K (Right_Paren) then
                  Advance;
                  if Op.Is_Con then
                     return Arena.Add
                       (Expr_Node'(Kind => Con_E, Span => Span,
                                   Name => Op.Op));
                  end if;
                  return Arena.Add
                    (Expr_Node'(Kind => Var_E, Span => Span,
                                Name => Op.Op));
               end if;
               declare
                  E : constant Real_Expr_Id := Parse_Simple_Chain;
               begin
                  Expect (Right_Paren, "')'");
                  return Arena.Add
                    (Expr_Node'(Kind => Right_Section_E, Span => Span,
                                Sec_Op => Op, Sec_Expr => E));
               end;
            end;
         end if;

         if Is_Minus and then Peek (1).Kind = Right_Paren then
            Advance;
            Advance;
            return Arena.Add
              (Expr_Node'(Kind => Var_E, Span => Span,
                          Name => (Minus_Name, Names.No_Name)));
         end if;

         --  General expression; maybe left section, maybe tuple.
         declare
            Sec_Op : Op_Occ;
            Is_Sec : Boolean;
            First  : Real_Expr_Id :=
              Parse_Op_Chain (True, Sec_Op, Is_Sec);
         begin
            if Is_Sec then
               Expect (Right_Paren, "')'");
               return Arena.Add
                 (Expr_Node'(Kind => Left_Section_E, Span => Span,
                             Sec_Op => Sec_Op, Sec_Expr => First));
            end if;
            if At_K (Colon_Colon) then
               Advance;
               First := Arena.Add
                 (Expr_Node'(Kind => Sig_E, Span => Span,
                             Sig_Expr => First, Sig_Type => Parse_Type));
            end if;
            if At_K (Comma) then
               declare
                  Items : Expr_Id_Vectors.Vector;
               begin
                  Items.Append (First);
                  while At_K (Comma) loop
                     Advance;
                     Items.Append (Parse_Expr);
                  end loop;
                  Expect (Right_Paren, "')'");
                  return Arena.Add
                    (Expr_Node'(Kind => Tuple_E, Span => Span,
                                Items => Items));
               end;
            end if;
            Expect (Right_Paren, "')'");
            return First;
         end;
      end Parse_Paren_Exp;

      function Parse_Bracket_Exp
        (Span : Diagnostics.Source_Span) return Real_Expr_Id
      is
      begin
         Advance;  --  '['
         if At_K (Right_Bracket) then
            Advance;
            return Arena.Add
              (Expr_Node'(Kind => Con_E, Span => Span,
                          Name => (Nil_Name, Names.No_Name)));
         end if;

         declare
            First : constant Real_Expr_Id := Parse_Expr;
         begin
            if At_K (Dot_Dot) then
               Advance;
               declare
                  To : Expr_Id := No_Expr;
               begin
                  if not At_K (Right_Bracket) then
                     To := Parse_Expr;
                  end if;
                  Expect (Right_Bracket, "']'");
                  return Arena.Add
                    (Expr_Node'(Kind => Arith_Seq_E, Span => Span,
                                Seq_From => First, Seq_Then => No_Expr,
                                Seq_To => To));
               end;
            elsif At_K (Pipe) then
               Advance;
               declare
                  Quals : Stmt_Id_Vectors.Vector;
               begin
                  loop
                     Quals.Append (Parse_Qual);
                     exit when not At_K (Comma);
                     Advance;
                  end loop;
                  Expect (Right_Bracket, "']'");
                  return Arena.Add
                    (Expr_Node'(Kind => List_Comp_E, Span => Span,
                                Comp_Expr => First,
                                Comp_Quals => Quals));
               end;
            elsif At_K (Comma) then
               Advance;
               declare
                  Second : constant Real_Expr_Id := Parse_Expr;
               begin
                  if At_K (Dot_Dot) then
                     Advance;
                     declare
                        To : Expr_Id := No_Expr;
                     begin
                        if not At_K (Right_Bracket) then
                           To := Parse_Expr;
                        end if;
                        Expect (Right_Bracket, "']'");
                        return Arena.Add
                          (Expr_Node'(Kind => Arith_Seq_E, Span => Span,
                                      Seq_From => First,
                                      Seq_Then => Second, Seq_To => To));
                     end;
                  end if;
                  declare
                     Items : Expr_Id_Vectors.Vector;
                  begin
                     Items.Append (First);
                     Items.Append (Second);
                     while At_K (Comma) loop
                        Advance;
                        Items.Append (Parse_Expr);
                     end loop;
                     Expect (Right_Bracket, "']'");
                     return Arena.Add
                       (Expr_Node'(Kind => List_E, Span => Span,
                                   Items => Items));
                  end;
               end;
            end if;
            Expect (Right_Bracket, "']'");
            declare
               Items : Expr_Id_Vectors.Vector;
            begin
               Items.Append (First);
               return Arena.Add
                 (Expr_Node'(Kind => List_E, Span => Span,
                             Items => Items));
            end;
         end;
      end Parse_Bracket_Exp;

      ------------------------------------------------------------------
      --  Statements (do blocks and comprehension qualifiers)
      ------------------------------------------------------------------

      function Parse_Qual return Real_Stmt_Id is
         Span : constant Diagnostics.Source_Span := Tok.Span;
      begin
         if At_K (Kw_Let) then
            Advance;
            declare
               Binds : Decl_Id_Vectors.Vector;
            begin
               Parse_Decl_Block (Binds);
               if At_K (Kw_In) then
                  --  It was a let-expression guard, not a let-qual.
                  Advance;
                  declare
                     B : constant Real_Expr_Id := Parse_Expr;
                     E : constant Real_Expr_Id := Arena.Add
                       (Expr_Node'(Kind => Let_E, Span => Span,
                                   Binds => Binds, Let_Body => B));
                  begin
                     return Arena.Add
                       (Stmt_Node'(Kind => Syntax.Expr_S, Span => Span,
                                   Expr => E));
                  end;
               end if;
               if Binds.Is_Empty then
                  Fail ("empty let block");
               end if;
               return Arena.Add
                 (Stmt_Node'(Kind => Let_S, Span => Span,
                             Let_Binds => Binds));
            end;
         elsif Arrow_Ahead then
            declare
               P : constant Real_Pat_Id := Parse_Pat;
            begin
               Expect (Left_Arrow, "'<-'");
               return Arena.Add
                 (Stmt_Node'(Kind => Bind_S, Span => Span,
                             Bind_Pat => P, Bind_Expr => Parse_Expr));
            end;
         else
            return Arena.Add
              (Stmt_Node'(Kind => Syntax.Expr_S, Span => Span,
                          Expr => Parse_Expr));
         end if;
      end Parse_Qual;

      procedure Parse_Stmt_Block (Into : in out Stmt_Id_Vectors.Vector) is
         Explicit : constant Boolean := At_K (Left_Brace);
      begin
         if not (Explicit or else At_K (V_Left_Brace)) then
            Fail ("expected a do block");
         end if;
         Advance;
         loop
            while At_K (Semicolon) or else At_K (V_Semicolon) loop
               Advance;
            end loop;
            exit when (Explicit and then At_K (Right_Brace))
              or else (not Explicit and then At_K (V_Right_Brace));
            if At_K (End_Of_File) then
               if Explicit then
                  Fail ("unterminated '{' block");
               end if;
               return;
            end if;
            --  A token that cannot start a statement closes an
            --  implicit block via the parse-error(t) rule ('where'
            --  at the same indentation as the do statements).
            if not Explicit
              and then Tok.Kind in Kw_Where | Kw_In | Kw_Then
                         | Kw_Else | Right_Paren | Right_Bracket
                         | Comma
              and then Try_Layout_Close
            then
               null;   --  Tok is the V_Right_Brace; loop exits above
            else
               Into.Append (Parse_Qual);
               if At_K (Semicolon) or else At_K (V_Semicolon) then
                  Advance;
               elsif (Explicit and then At_K (Right_Brace))
                 or else (not Explicit and then At_K (V_Right_Brace))
               then
                  null;
               elsif not Explicit and then Try_Layout_Close then
                  null;  --  Tok is now the V_Right_Brace
               else
                  Fail ("expected ';' or end of do block");
               end if;
            end if;
         end loop;
         Advance;  --  closing brace
      end Parse_Stmt_Block;

      ------------------------------------------------------------------
      --  Alternatives (case blocks)
      ------------------------------------------------------------------

      procedure Parse_Alt_Block (Into : in out Alt_Id_Vectors.Vector) is
         Explicit : constant Boolean := At_K (Left_Brace);
      begin
         if not (Explicit or else At_K (V_Left_Brace)) then
            Fail ("expected case alternatives");
         end if;
         Advance;
         loop
            while At_K (Semicolon) or else At_K (V_Semicolon) loop
               Advance;
            end loop;
            exit when (Explicit and then At_K (Right_Brace))
              or else (not Explicit and then At_K (V_Right_Brace));
            if At_K (End_Of_File) then
               if Explicit then
                  Fail ("unterminated '{' block");
               end if;
               return;
            end if;
            declare
               Span : constant Diagnostics.Source_Span := Tok.Span;
               P    : constant Real_Pat_Id := Parse_Pat;
               R    : constant Rhs := Parse_Guarded (Right_Arrow, "'->'");
               W    : Decl_Id_Vectors.Vector;
            begin
               Parse_Where (W);
               Into.Append
                 (Arena.Add
                    (Alt_Node'(Span => Span, Pat => P,
                               Alt_Rhs => R, Where_Ds => W)));
            end;
            if At_K (Semicolon) or else At_K (V_Semicolon) then
               Advance;
            elsif (Explicit and then At_K (Right_Brace))
              or else (not Explicit and then At_K (V_Right_Brace))
            then
               null;
            elsif not Explicit and then Try_Layout_Close then
               null;
            else
               Fail ("expected ';' or end of case block");
            end if;
         end loop;
         Advance;
      end Parse_Alt_Block;

      ------------------------------------------------------------------
      --  Right-hand sides
      ------------------------------------------------------------------

      function Parse_Guarded
        (Sep : Token_Kind; Sep_Name : String) return Rhs is
      begin
         if At_K (Pipe) then
            declare
               Guards : Guarded_Rhs_Vectors.Vector;
            begin
               while At_K (Pipe) loop
                  Advance;
                  declare
                     G : constant Real_Expr_Id := Parse_Expr;
                  begin
                     Expect (Sep, Sep_Name);
                     Guards.Append
                       (Guarded_Rhs'(Guard => G, G_Body => Parse_Expr));
                  end;
               end loop;
               return Rhs'(Guarded => True, Guards => Guards);
            end;
         end if;
         Expect (Sep, Sep_Name);
         return Rhs'(Guarded => False, Plain => Parse_Expr);
      end Parse_Guarded;

      procedure Parse_Where (Into : in out Decl_Id_Vectors.Vector) is
      begin
         if At_K (Kw_Where) then
            Advance;
            Parse_Decl_Block (Into);
         end if;
      end Parse_Where;

      ------------------------------------------------------------------
      --  Declarations
      ------------------------------------------------------------------

      --  A var in binding position: x or (+).
      function At_Paren_Op return Boolean
      is (At_K (Left_Paren)
          and then Peek (1).Kind in Varsym | Consym
          and then Peek (2).Kind = Right_Paren);

      function Parse_Var_Name return Names.Name_Id is
      begin
         if At_K (Varid) then
            declare
               V : constant Names.Name_Id := Tok.Name;
            begin
               Advance;
               return V;
            end;
         elsif At_Paren_Op then
            Advance;
            declare
               V : constant Names.Name_Id := Tok.Name;
            begin
               Advance;
               Advance;  --  ')'
               return V;
            end;
         else
            Fail ("expected a variable name");
         end if;
      end Parse_Var_Name;

      function Parse_Sig_Decl
        (Span : Diagnostics.Source_Span) return Real_Decl_Id
      is
         Vars : QName_Vectors.Vector;
      begin
         Vars.Append (QName'(Parse_Var_Name, Names.No_Name));
         while At_K (Comma) loop
            Advance;
            Vars.Append (QName'(Parse_Var_Name, Names.No_Name));
         end loop;
         Expect (Colon_Colon, "'::'");
         return Arena.Add
           (Decl_Node'(Kind => Sig_D, Span => Span,
                       Sig_Names => Vars, Sig_Type => Parse_Type));
      end Parse_Sig_Decl;

      function Parse_Fixity_Decl
        (Span : Diagnostics.Source_Span) return Real_Decl_Id
      is
         Assoc : constant Assoc_Kind :=
           (case Tok.Kind is
              when Kw_Infixl => Assoc_Left,
              when Kw_Infixr => Assoc_Right,
              when others    => Assoc_None);
         Prec : Natural range 0 .. 9 := 9;
         Ops  : QName_Vectors.Vector;
      begin
         Advance;
         if At_K (Int_Lit) then
            declare
               T : constant String := Table.Text (Tok.Int_Text);
            begin
               if T'Length = 1 and then T (T'First) in '0' .. '9' then
                  Prec := Character'Pos (T (T'First)) - 48;
               else
                  Fail ("fixity precedence must be 0..9");
               end if;
            end;
            Advance;
         end if;
         loop
            declare
               Op : constant Op_Occ := Parse_Op;
            begin
               Ops.Append (Op.Op);
            end;
            exit when not At_K (Comma);
            Advance;
         end loop;
         return Arena.Add
           (Decl_Node'(Kind => Fixity_D, Span => Span,
                       Assoc => Assoc, Prec => Prec, Ops => Ops));
      end Parse_Fixity_Decl;

      --  simpletype: Conid tyvars.
      procedure Parse_Simple_Type
        (Name : out Names.Name_Id; Vars : out QName_Vectors.Vector) is
      begin
         if not At_K (Conid) then
            Fail ("expected a type constructor name");
         end if;
         Name := Tok.Name;
         Advance;
         while At_K (Varid) loop
            Vars.Append (QName'(Tok.Name, Names.No_Name));
            Advance;
         end loop;
      end Parse_Simple_Type;

      function Parse_Constructor return Real_Con_Id is
         Span : constant Diagnostics.Source_Span := Tok.Span;

         function Parse_Banged_AType
           (Strict : out Boolean) return Real_Type_Id is
         begin
            Strict := False;
            if Is_Bang then
               Strict := True;
               Advance;
            end if;
            return Parse_AType;
         end Parse_Banged_AType;
      begin
         --  Record constructor.
         if Tok.Kind in Conid | Qconid
           and then Peek (1).Kind = Left_Brace
         then
            declare
               C      : constant QName := Tok_QName;
               Fields : Field_Decl_Vectors.Vector;
            begin
               Advance;
               Advance;  --  '{'
               while not At_K (Right_Brace) loop
                  declare
                     FNames : QName_Vectors.Vector;
                     Strict : Boolean := False;
                  begin
                     FNames.Append (QName'(Parse_Var_Name, Names.No_Name));
                     while At_K (Comma) loop
                        Advance;
                        FNames.Append
                          (QName'(Parse_Var_Name, Names.No_Name));
                     end loop;
                     Expect (Colon_Colon, "'::'");
                     if Is_Bang then
                        Strict := True;
                        Advance;
                     end if;
                     Fields.Append
                       (Field_Decl'(Names_List => FNames,
                                    Field_Type => Parse_Type,
                                    Strict => Strict));
                  end;
                  exit when not At_K (Comma);
                  Advance;
               end loop;
               Expect (Right_Brace, "'}'");
               return Arena.Add
                 (Con_Node'(Shape => Record_Con, Span => Span,
                            Name => C, Fields => Fields));
            end;
         end if;

         --  Prefix constructor, possibly turning infix.
         if Tok.Kind in Conid | Qconid then
            declare
               C       : constant QName := Tok_QName;
               Args    : Type_Id_Vectors.Vector;
               Stricts : Boolean_Vectors.Vector;
            begin
               Advance;
               while Is_Bang or else Can_Start_AType loop
                  declare
                     Strict : Boolean;
                     T      : constant Real_Type_Id :=
                       Parse_Banged_AType (Strict);
                  begin
                     Args.Append (T);
                     Stricts.Append (Strict);
                  end;
               end loop;

               if Tok.Kind in Consym | Qconsym then
                  --  'T a :+: U b': what we parsed is the left operand.
                  declare
                     Op  : constant Op_Occ := Parse_Op;
                     Lhs : Real_Type_Id := Arena.Add
                       (Type_Node'(Kind => Con_T, Span => Span, Con => C));
                     L_Strict : constant Boolean := False;
                     R_Strict : Boolean;
                     Rhs_T : Real_Type_Id;
                     I_Args : Type_Id_Vectors.Vector;
                     I_Stricts : Boolean_Vectors.Vector;
                  begin
                     for I in 1 .. Args.Last_Index loop
                        Lhs := Arena.Add
                          (Type_Node'(Kind => App_T, Span => Span,
                                      Fun => Lhs, Arg => Args (I)));
                     end loop;
                     Rhs_T := Parse_Banged_AType (R_Strict);
                     while Can_Start_AType loop
                        Rhs_T := Arena.Add
                          (Type_Node'(Kind => App_T, Span => Span,
                                      Fun => Rhs_T,
                                      Arg => Parse_AType));
                     end loop;
                     I_Args.Append (Lhs);
                     I_Args.Append (Rhs_T);
                     I_Stricts.Append (L_Strict);
                     I_Stricts.Append (R_Strict);
                     return Arena.Add
                       (Con_Node'(Shape => Infix_Con, Span => Span,
                                  Name => Op.Op,
                                  Args => I_Args, Stricts => I_Stricts));
                  end;
               end if;

               return Arena.Add
                 (Con_Node'(Shape => Prefix_Con, Span => Span,
                            Name => C, Args => Args, Stricts => Stricts));
            end;
         end if;

         --  Infix with a non-conid left side: 'Int :+: Bool'.
         declare
            L_Strict : Boolean;
            Lhs      : Real_Type_Id;
            R_Strict : Boolean;
            Rhs_T    : Real_Type_Id;
            I_Args    : Type_Id_Vectors.Vector;
            I_Stricts : Boolean_Vectors.Vector;
         begin
            Lhs := Parse_Banged_AType (L_Strict);
            if Tok.Kind not in Consym | Qconsym then
               Fail ("expected a constructor");
            end if;
            declare
               Op : constant Op_Occ := Parse_Op;
            begin
               Rhs_T := Parse_Banged_AType (R_Strict);
               I_Args.Append (Lhs);
               I_Args.Append (Rhs_T);
               I_Stricts.Append (L_Strict);
               I_Stricts.Append (R_Strict);
               return Arena.Add
                 (Con_Node'(Shape => Infix_Con, Span => Span,
                            Name => Op.Op,
                            Args => I_Args, Stricts => I_Stricts));
            end;
         end;
      end Parse_Constructor;

      procedure Parse_Deriving (Into : in out QName_Vectors.Vector) is
      begin
         if not At_K (Kw_Deriving) then
            return;
         end if;
         Advance;
         if At_K (Left_Paren) then
            Advance;
            if not At_K (Right_Paren) then
               loop
                  if Tok.Kind not in Conid | Qconid then
                     Fail ("expected a class name");
                  end if;
                  Into.Append (Tok_QName);
                  Advance;
                  exit when not At_K (Comma);
                  Advance;
               end loop;
            end if;
            Expect (Right_Paren, "')'");
         else
            if Tok.Kind not in Conid | Qconid then
               Fail ("expected a class name");
            end if;
            Into.Append (Tok_QName);
            Advance;
         end if;
      end Parse_Deriving;

      function Parse_Data_Decl
        (Span : Diagnostics.Source_Span; Is_Newtype : Boolean)
         return Real_Decl_Id
      is
         Context : Type_Id_Vectors.Vector;
         Name    : Names.Name_Id;
         Vars    : QName_Vectors.Vector;
         Cons    : Con_Id_Vectors.Vector;
         Derivs  : QName_Vectors.Vector;
      begin
         Advance;  --  data / newtype

         --  Optional context: scan for '=>' before '=' at depth 0.
         declare
            Depth : Natural := 0;
            N     : Positive := 1;
            Has_Ctx : Boolean := False;
            T : Token := Tok;
         begin
            loop
               case T.Kind is
                  when Left_Paren | Left_Bracket => Depth := Depth + 1;
                  when Right_Paren | Right_Bracket =>
                     exit when Depth = 0;
                     Depth := Depth - 1;
                  when Fat_Arrow =>
                     if Depth = 0 then
                        Has_Ctx := True;
                        exit;
                     end if;
                  when Equals | Kw_Deriving | Semicolon | V_Semicolon
                     | V_Right_Brace | Right_Brace | End_Of_File =>
                     exit when Depth = 0;
                  when others => null;
               end case;
               T := Peek (N);
               N := N + 1;
            end loop;
            if Has_Ctx then
               Context := To_Context (Parse_BType);
               Expect (Fat_Arrow, "'=>'");
            end if;
         end;

         Parse_Simple_Type (Name, Vars);

         if At_K (Equals) then
            Advance;
            loop
               Cons.Append (Parse_Constructor);
               exit when not At_K (Pipe);
               Advance;
            end loop;
         end if;

         Parse_Deriving (Derivs);

         if Is_Newtype and then Natural (Cons.Length) /= 1 then
            Bag.Add (Diagnostics.Error, Diagnostics.Parse_Error, Span,
                     "newtype needs exactly one constructor");
            raise Parse_Failure;
         end if;

         if Is_Newtype then
            return Arena.Add
              (Decl_Node'(Kind => Newtype_D, Span => Span,
                          D_Context => Context, D_Name => Name,
                          D_Vars => Vars, D_Cons => Cons,
                          D_Deriving => Derivs));
         end if;
         return Arena.Add
           (Decl_Node'(Kind => Data_D, Span => Span,
                       D_Context => Context, D_Name => Name,
                       D_Vars => Vars, D_Cons => Cons,
                       D_Deriving => Derivs));
      end Parse_Data_Decl;

      function Parse_Type_Syn
        (Span : Diagnostics.Source_Span) return Real_Decl_Id
      is
         Name : Names.Name_Id;
         Vars : QName_Vectors.Vector;
      begin
         Advance;  --  type
         Parse_Simple_Type (Name, Vars);
         Expect (Equals, "'='");
         return Arena.Add
           (Decl_Node'(Kind => Type_Syn_D, Span => Span,
                       S_Name => Name, S_Vars => Vars,
                       S_Rhs => Parse_Type));
      end Parse_Type_Syn;

      function Parse_Class_Decl
        (Span : Diagnostics.Source_Span) return Real_Decl_Id
      is
         Context : Type_Id_Vectors.Vector;
         Head    : Real_Type_Id;
         Decls   : Decl_Id_Vectors.Vector;
         C_Name  : Names.Name_Id := Names.No_Name;
         C_Var   : Names.Name_Id := Names.No_Name;
      begin
         Advance;  --  class
         Head := Parse_BType;
         if At_K (Fat_Arrow) then
            Advance;
            Context := To_Context (Head);
            Head := Parse_BType;
         end if;

         --  Expect the shape C a.
         declare
            N : constant Type_Node := Arena.Node (Head);
         begin
            if N.Kind = App_T
              and then Arena.Node (N.Fun).Kind = Con_T
              and then Arena.Node (N.Arg).Kind = Var_T
            then
               C_Name := Arena.Node (N.Fun).Con.Name;
               C_Var := Arena.Node (N.Arg).Var;
            else
               Fail ("expected 'class C a'");
            end if;
         end;

         Parse_Where (Decls);
         return Arena.Add
           (Decl_Node'(Kind => Class_D, Span => Span,
                       C_Context => Context, C_Name => C_Name,
                       C_Var => C_Var, C_Decls => Decls));
      end Parse_Class_Decl;

      function Parse_Instance_Decl
        (Span : Diagnostics.Source_Span) return Real_Decl_Id
      is
         Context : Type_Id_Vectors.Vector;
         Head    : Real_Type_Id;
         Decls   : Decl_Id_Vectors.Vector;
         Class_N : QName;
         Inst_T  : Real_Type_Id;
      begin
         Advance;  --  instance
         Head := Parse_BType;
         if At_K (Fat_Arrow) then
            Advance;
            Context := To_Context (Head);
            Head := Parse_BType;
         end if;

         --  Expect the shape C t.
         declare
            N : constant Type_Node := Arena.Node (Head);
         begin
            if N.Kind = App_T and then Arena.Node (N.Fun).Kind = Con_T
            then
               Class_N := Arena.Node (N.Fun).Con;
               Inst_T := N.Arg;
            else
               Fail ("expected 'instance C t'");
            end if;
         end;

         Parse_Where (Decls);
         return Arena.Add
           (Decl_Node'(Kind => Instance_D, Span => Span,
                       I_Context => Context, I_Class => Class_N,
                       I_Type => Inst_T, I_Decls => Decls));
      end Parse_Instance_Decl;

      function Parse_Default_Decl
        (Span : Diagnostics.Source_Span) return Real_Decl_Id
      is
         Types : Type_Id_Vectors.Vector;
      begin
         Advance;  --  default
         Expect (Left_Paren, "'('");
         if not At_K (Right_Paren) then
            loop
               Types.Append (Parse_Type);
               exit when not At_K (Comma);
               Advance;
            end loop;
         end if;
         Expect (Right_Paren, "')'");
         return Arena.Add
           (Decl_Node'(Kind => Default_D, Span => Span,
                       Def_Types => Types));
      end Parse_Default_Decl;

      --  Function equation or pattern binding.
      function Parse_Binding
        (Span : Diagnostics.Source_Span) return Real_Decl_Id
      is
         Where_Ds : Decl_Id_Vectors.Vector;
      begin
         --  Prefix equation: var apat+ ...
         if (At_K (Varid)
             and then (Peek (1).Kind
                         in Varid | Conid | Qconid | Underscore
                          | Int_Lit | Float_Lit | Char_Lit | String_Lit
                          | Left_Paren | Left_Bracket | Tilde))
           or else (At_Paren_Op
                    and then Peek (3).Kind
                         in Varid | Conid | Qconid | Underscore
                          | Int_Lit | Float_Lit | Char_Lit | String_Lit
                          | Left_Paren | Left_Bracket | Tilde)
         then
            declare
               Name : constant Names.Name_Id := Parse_Var_Name;
               Pats : Pat_Id_Vectors.Vector;
            begin
               while Can_Start_APat loop
                  Pats.Append (Parse_APat);
               end loop;
               declare
                  R : constant Rhs := Parse_Guarded (Equals, "'='");
               begin
                  Parse_Where (Where_Ds);
                  return Arena.Add
                    (Decl_Node'(Kind => Fun_D, Span => Span,
                                Fun_Name => Name, Fun_Pats => Pats,
                                Fun_Rhs => R, Fun_Where => Where_Ds));
               end;
            end;
         end if;

         --  Pattern first; then either an infix equation or a binding.
         declare
            P : constant Real_Pat_Id := Parse_Pat;
         begin
            if Tok.Kind = Varsym or else At_K (Backtick) then
               --  Infix equation: pat `op` pat = rhs defines op.
               declare
                  Op  : constant Op_Occ := Parse_Op;
                  P2  : constant Real_Pat_Id := Parse_Pat10;
                  Pats : Pat_Id_Vectors.Vector;
               begin
                  Pats.Append (P);
                  Pats.Append (P2);
                  declare
                     R : constant Rhs := Parse_Guarded (Equals, "'='");
                  begin
                     Parse_Where (Where_Ds);
                     return Arena.Add
                       (Decl_Node'(Kind => Fun_D, Span => Span,
                                   Fun_Name => Op.Op.Name,
                                   Fun_Pats => Pats,
                                   Fun_Rhs => R,
                                   Fun_Where => Where_Ds));
                  end;
               end;
            end if;
            declare
               R : constant Rhs := Parse_Guarded (Equals, "'='");
            begin
               Parse_Where (Where_Ds);
               return Arena.Add
                 (Decl_Node'(Kind => Pat_D, Span => Span,
                             Pat => P, Pat_Rhs => R,
                             Pat_Where => Where_Ds));
            end;
         end;
      end Parse_Binding;

      function Parse_Decl return Real_Decl_Id is
         Span : constant Diagnostics.Source_Span := Tok.Span;
      begin
         case Tok.Kind is
            when Kw_Infix | Kw_Infixl | Kw_Infixr =>
               return Parse_Fixity_Decl (Span);
            when Kw_Type =>
               return Parse_Type_Syn (Span);
            when Kw_Data =>
               return Parse_Data_Decl (Span, Is_Newtype => False);
            when Kw_Newtype =>
               return Parse_Data_Decl (Span, Is_Newtype => True);
            when Kw_Class =>
               return Parse_Class_Decl (Span);
            when Kw_Instance =>
               return Parse_Instance_Decl (Span);
            when Kw_Default =>
               return Parse_Default_Decl (Span);
            when Varid =>
               if Peek (1).Kind in Comma | Colon_Colon then
                  return Parse_Sig_Decl (Span);
               end if;
               return Parse_Binding (Span);
            when Left_Paren =>
               if At_Paren_Op
                 and then Peek (3).Kind in Comma | Colon_Colon
               then
                  return Parse_Sig_Decl (Span);
               end if;
               return Parse_Binding (Span);
            when others =>
               return Parse_Binding (Span);
         end case;
      end Parse_Decl;

      --  Skip to the next declaration boundary after an error.
      procedure Skip_Decl is
         Depth : Natural := 0;
      begin
         loop
            case Tok.Kind is
               when End_Of_File =>
                  return;
               when Left_Brace | V_Left_Brace =>
                  Depth := Depth + 1;
               when Right_Brace | V_Right_Brace =>
                  if Depth = 0 then
                     return;   --  leave block close for the caller
                  end if;
                  Depth := Depth - 1;
               when Semicolon | V_Semicolon =>
                  if Depth = 0 then
                     return;
                  end if;
               when others =>
                  null;
            end case;
            Advance;
         end loop;
      end Skip_Decl;

      procedure Parse_Decl_Block (Into : in out Decl_Id_Vectors.Vector) is
         Explicit : constant Boolean := At_K (Left_Brace);
      begin
         if not (Explicit or else At_K (V_Left_Brace)) then
            Fail ("expected a block");
         end if;
         Advance;
         loop
            while At_K (Semicolon) or else At_K (V_Semicolon) loop
               Advance;
            end loop;
            exit when (Explicit and then At_K (Right_Brace))
              or else (not Explicit and then At_K (V_Right_Brace));
            if At_K (End_Of_File) then
               if Explicit then
                  Bag.Add (Diagnostics.Error, Diagnostics.Parse_Error,
                           Tok.Span, "unterminated '{' block");
               end if;
               return;
            end if;
            begin
               Into.Append (Parse_Decl);
            exception
               when Parse_Failure =>
                  Skip_Decl;
            end;
            if At_K (Semicolon) or else At_K (V_Semicolon) then
               Advance;
            elsif (Explicit and then At_K (Right_Brace))
              or else (not Explicit and then At_K (V_Right_Brace))
              or else At_K (End_Of_File)
            then
               null;
            elsif not Explicit and then Try_Layout_Close then
               null;   --  Tok is the V_Right_Brace; loop exits above
            else
               Bag.Add (Diagnostics.Error, Diagnostics.Parse_Error,
                        Tok.Span,
                        "expected ';' or end of block (found '"
                        & Image (Tok, Table) & "')");
               Skip_Decl;
            end if;
         end loop;
         Advance;  --  closing brace
      end Parse_Decl_Block;

      ------------------------------------------------------------------
      --  Module header, exports, imports
      ------------------------------------------------------------------

      function Parse_Entity (Allow_Module : Boolean) return Entity is
         E : Entity;
      begin
         if Allow_Module and then At_K (Kw_Module) then
            Advance;
            if Tok.Kind not in Conid | Qconid then
               Fail ("expected a module name");
            end if;
            E := (Kind => Module_Ent,
                  Name => (Module_Name_Of (Tok), Names.No_Name),
                  others => <>);
            Advance;
            return E;
         end if;

         if At_K (Varid) then
            E := (Kind => Var_Ent, Name => Tok_QName, others => <>);
            Advance;
            return E;
         end if;

         if At_Paren_Op then
            Advance;
            E := (Kind => Var_Ent, Name => Tok_QName, others => <>);
            Advance;
            Advance;
            return E;
         end if;

         if Tok.Kind in Conid | Qconid then
            E := (Kind => Type_Ent, Name => Tok_QName, others => <>);
            Advance;
            if At_K (Left_Paren) then
               Advance;
               E.Has_Subs := True;
               if At_K (Dot_Dot) then
                  Advance;
                  E.Sub_All := True;
               elsif not At_K (Right_Paren) then
                  loop
                     if Tok.Kind in Varid | Conid | Qvarid | Qconid then
                        E.Subs.Append (Tok_QName);
                        Advance;
                     elsif At_K (Left_Paren)
                       and then Peek (1).Kind in Varsym | Consym
                       and then Peek (2).Kind = Right_Paren
                     then
                        Advance;
                        E.Subs.Append (Tok_QName);
                        Advance;
                        Advance;
                     else
                        Fail ("expected a name");
                     end if;
                     exit when not At_K (Comma);
                     Advance;
                  end loop;
               end if;
               Expect (Right_Paren, "')'");
            end if;
            return E;
         end if;

         Fail ("expected an export/import item");
      end Parse_Entity;

      procedure Parse_Entity_List
        (Into : in out Entity_Vectors.Vector; Allow_Module : Boolean) is
      begin
         Expect (Left_Paren, "'('");
         if not At_K (Right_Paren) then
            loop
               Into.Append (Parse_Entity (Allow_Module));
               exit when not At_K (Comma);
               Advance;
               --  Trailing comma is allowed in export lists.
               exit when At_K (Right_Paren);
            end loop;
         end if;
         Expect (Right_Paren, "')'");
      end Parse_Entity_List;

      procedure Parse_Import is
         Imp : Import_Decl;
         Qualified_Name : constant Names.Real_Name_Id :=
           Table.Intern ("qualified");
         Hiding_Name : constant Names.Real_Name_Id :=
           Table.Intern ("hiding");
         As_Name : constant Names.Real_Name_Id := Table.Intern ("as");
      begin
         Imp.Span := Tok.Span;
         Advance;  --  import

         if At_K (Varid) and then Tok.Name = Qualified_Name then
            Imp.Qualified := True;
            Advance;
         end if;

         if Tok.Kind not in Conid | Qconid then
            Fail ("expected a module name");
         end if;
         Imp.Module := Module_Name_Of (Tok);
         Advance;

         if At_K (Varid) and then Tok.Name = As_Name then
            Advance;
            if Tok.Kind not in Conid | Qconid then
               Fail ("expected a module alias");
            end if;
            Imp.Alias := Module_Name_Of (Tok);
            Advance;
         end if;

         if At_K (Varid) and then Tok.Name = Hiding_Name then
            Imp.Hiding := True;
            Advance;
         end if;

         if At_K (Left_Paren) then
            Imp.Has_Spec := True;
            Parse_Entity_List (Imp.Spec, Allow_Module => False);
         elsif Imp.Hiding then
            Fail ("expected '(' after 'hiding'");
         end if;

         Arena.Imports.Append (Imp);
      end Parse_Import;

      ------------------------------------------------------------------
      --  Top level
      ------------------------------------------------------------------

      procedure Parse_Top is
         Explicit : Boolean;
      begin
         if At_K (Kw_Module) then
            Arena.Has_Header := True;
            Advance;
            if Tok.Kind not in Conid | Qconid then
               Fail ("expected a module name");
            end if;
            Arena.Module_Name := Module_Name_Of (Tok);
            Advance;
            if At_K (Left_Paren) then
               Arena.Has_Export_List := True;
               Parse_Entity_List (Arena.Exports, Allow_Module => True);
            end if;
            Expect (Kw_Where, "'where'");
         end if;

         if not (At_K (Left_Brace) or else At_K (V_Left_Brace)) then
            Fail ("expected the module body");
         end if;
         Explicit := At_K (Left_Brace);
         Advance;

         --  Imports first (Report 5.1), then declarations.
         loop
            while At_K (Semicolon) or else At_K (V_Semicolon) loop
               Advance;
            end loop;
            exit when not At_K (Kw_Import);
            begin
               Parse_Import;
            exception
               when Parse_Failure =>
                  Skip_Decl;
            end;
         end loop;

         loop
            while At_K (Semicolon) or else At_K (V_Semicolon) loop
               Advance;
            end loop;
            exit when (Explicit and then At_K (Right_Brace))
              or else (not Explicit and then At_K (V_Right_Brace))
              or else At_K (End_Of_File);
            begin
               Arena.Top_Decls.Append (Parse_Decl);
            exception
               when Parse_Failure =>
                  Skip_Decl;
            end;
            if At_K (Semicolon) or else At_K (V_Semicolon) then
               Advance;
            elsif (Explicit and then At_K (Right_Brace))
              or else (not Explicit and then At_K (V_Right_Brace))
              or else At_K (End_Of_File)
            then
               null;
            else
               Bag.Add (Diagnostics.Error, Diagnostics.Parse_Error,
                        Tok.Span,
                        "expected ';' or end of module (found '"
                        & Image (Tok, Table) & "')");
               Skip_Decl;
            end if;
         end loop;
      end Parse_Top;

   begin
      Laid.Start (Raw);
      Advance;
      begin
         Parse_Top;
      exception
         when Parse_Failure =>
            null;  --  already diagnosed
      end;
   end Parse_Module;

end AHC.Parser;
