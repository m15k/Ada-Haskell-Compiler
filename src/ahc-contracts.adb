with AHC.Parser;
with AHC.Tokens;

package body AHC.Contracts is

   use AHC.Tokens;
   use type Names.Name_Id;

   procedure Collect
     (Text  : Source_Text.Source;
      Spans : Lexer.Span_Vectors.Vector;
      Table : in out Names.Name_Table;
      Bag   : in out Diagnostics.Diagnostic_Bag;
      Arena : in out Syntax.Module_Arena;
      Out_C : in out Contract_Vectors.Vector)
   is
      Pre_N  : constant Names.Name_Id :=
        Names.Name_Id (Table.Intern ("PRE"));
      Post_N : constant Names.Name_Id :=
        Names.Name_Id (Table.Intern ("POST"));
   begin
      for Sp of Spans loop
         declare
            --  Interior of {-# ... #-}.
            From : constant Positive := Positive (Sp.Start) + 3;
            To   : constant Natural  := Natural (Sp.Stop) - 4;
         begin
            if To < From then
               goto Next_Pragma;
            end if;
            declare
               --  A copy of the whole module text with everything
               --  OUTSIDE the pragma interior blanked (newlines
               --  kept): fragment tokens then carry their TRUE byte
               --  spans, so every later diagnostic lands on the real
               --  source position.
               Blanked : String :=
                 Text.Slice (1, Source_Text.Byte_Offset (Text.Length));
               F_Text  : Source_Text.Source;
               F_Bag   : Diagnostics.Diagnostic_Bag;
               F_Toks  : Tokens.Token_Vectors.Vector;
            begin
               for I in Blanked'Range loop
                  if (I < From or else I > To)
                    and then Blanked (I) /= ASCII.LF
                  then
                     Blanked (I) := ' ';
                  end if;
               end loop;
               F_Text := Source_Text.Load_String
                 (Text.File_Name, Blanked);
               Lexer.Scan (F_Text, Table, F_Bag, F_Toks);

               --  Expect: PRE|POST  fname  <expression>  EOF.
               if Natural (F_Toks.Length) < 4
                 or else F_Toks (1).Kind /= Conid
                 or else (F_Toks (1).Name /= Pre_N
                          and then F_Toks (1).Name /= Post_N)
               then
                  goto Next_Pragma;   --  some other pragma; ignore
               end if;
               if F_Toks (2).Kind /= Varid then
                  Bag.Add (Diagnostics.Error, Diagnostics.Parse_Error,
                           Sp, "contract pragma needs a function"
                               & " name after PRE/POST");
                  goto Next_Pragma;
               end if;

               declare
                  Kind : constant Contract_Kind :=
                    (if F_Toks (1).Name = Pre_N then Pre_C
                     else Post_C);
                  Fn : constant Names.Name_Id := F_Toks (2).Name;
                  Bind : constant Names.Name_Id :=
                    Names.Name_Id (Table.Intern
                      ((if Kind = Pre_C then "$pre$" else "$post$")
                       & Table.Text (Names.Real_Name_Id (Fn))));
                  Stream : Tokens.Token_Vectors.Vector;
                  Col : Source_Text.Column_Number := 3;
               begin
                  --  Refuse duplicates with a decent message (the
                  --  renamer's duplicate-binder error would fire
                  --  anyway, but on the mangled name).
                  for C of Out_C loop
                     if C.Kind = Kind and then C.Fn_Name = Fn then
                        Bag.Add
                          (Diagnostics.Error,
                           Diagnostics.Rename_Duplicate, Sp,
                           "duplicate "
                           & (if Kind = Pre_C then "PRE"
                              else "POST")
                           & " contract for '"
                           & Table.Text (Names.Real_Name_Id (Fn))
                           & "'");
                        goto Next_Pragma;
                     end if;
                  end loop;

                  --  Synthesize `$pre$f = <expr>` and parse it into
                  --  the module arena as an ordinary declaration.
                  --  All tokens claim line 1 / increasing columns so
                  --  the layout algorithm sees one plain line; SPANS
                  --  keep the true source positions.
                  Stream.Append
                    (Token'(Kind => Varid,
                            Span => F_Toks (2).Span,
                            Line => 1, Column => 1,
                            First_On_Line => True,
                            Name => Names.Real_Name_Id (Bind),
                            Qualifier => Names.No_Name));
                  Stream.Append
                    (Token'(Kind => Equals,
                            Span => F_Toks (2).Span,
                            Line => 1, Column => 2,
                            First_On_Line => False));
                  for TI in 3 .. F_Toks.Last_Index loop
                     declare
                        T : Token := F_Toks (TI);
                     begin
                        T.Line := 1;
                        T.Column := Col;
                        T.First_On_Line := False;
                        Col := Source_Text.Column_Number
                          (Natural (Col) + 1);
                        Stream.Append (T);
                     end;
                  end loop;

                  Parser.Parse_Module (Stream, Table, Bag, Arena);

                  Out_C.Append
                    (Contract_Decl'
                       (Kind => Kind, Fn_Name => Fn,
                        Bind_Name => Bind, Span => Sp));
               end;
            end;
         end;
         <<Next_Pragma>> null;
      end loop;
   end Collect;

end AHC.Contracts;
