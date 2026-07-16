package body AHC.Layout is

   use AHC.Tokens;

   function Implicit_Depth (S : Layout_Stream) return Natural is
      N : Natural := 0;
   begin
      for C of S.Stack loop
         if C /= 0 then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Implicit_Depth;

   ---------------------------------------------------------------------
   --  Stack and queue plumbing
   ---------------------------------------------------------------------

   function Top (S : Layout_Stream) return Natural
   is (S.Stack.Last_Element)
   with Pre => not S.Stack.Is_Empty;

   --  The PRD's "layout stack never underflows", as a checked contract.
   procedure Pop (S : in out Layout_Stream)
     with Pre => not S.Stack.Is_Empty is
   begin
      S.Stack.Delete_Last;
   end Pop;

   procedure Enqueue (S : in out Layout_Stream; T : Token) is
   begin
      S.Queue.Append (T);
   end Enqueue;

   --  Virtual token positioned at (and zero-width before) At_Token.
   function Virtual (Kind : Virtual_Kind; At_Token : Token) return Token is
   begin
      case Kind is
         when V_Left_Brace =>
            return (Kind => V_Left_Brace,
                    Span => Diagnostics.Zero_Width_At (At_Token.Span.Start),
                    Line => At_Token.Line, Column => At_Token.Column,
                    others => <>);
         when V_Right_Brace =>
            return (Kind => V_Right_Brace,
                    Span => Diagnostics.Zero_Width_At (At_Token.Span.Start),
                    Line => At_Token.Line, Column => At_Token.Column,
                    others => <>);
         when V_Semicolon =>
            return (Kind => V_Semicolon,
                    Span => Diagnostics.Zero_Width_At (At_Token.Span.Start),
                    Line => At_Token.Line, Column => At_Token.Column,
                    others => <>);
      end case;
   end Virtual;

   procedure Open_Implicit
     (S : in out Layout_Stream; Indent : Positive; At_Token : Token) is
   begin
      S.Stack.Append (Indent);
      S.Opens := S.Opens + 1;
      Enqueue (S, Virtual (V_Left_Brace, At_Token));
   end Open_Implicit;

   procedure Close_Implicit (S : in out Layout_Stream; At_Token : Token)
     with Pre => not S.Stack.Is_Empty and then Top (S) /= 0 is
   begin
      Pop (S);
      S.Closes := S.Closes + 1;
      Enqueue (S, Virtual (V_Right_Brace, At_Token));
   end Close_Implicit;

   --  The n = 0 arm of the {n} rule: an empty block, no context pushed.
   procedure Open_And_Close_Empty
     (S : in out Layout_Stream; At_Token : Token) is
   begin
      S.Opens := S.Opens + 1;
      S.Closes := S.Closes + 1;
      Enqueue (S, Virtual (V_Left_Brace, At_Token));
      Enqueue (S, Virtual (V_Right_Brace, At_Token));
   end Open_And_Close_Empty;

   ---------------------------------------------------------------------
   --  Start
   ---------------------------------------------------------------------

   procedure Start
     (S : in out Layout_Stream; Input : Tokens.Token_Vectors.Vector) is
   begin
      S.Input := Input;
      S.Is_Started := True;

      --  Report 10.3: if the first lexeme of a module is neither '{'
      --  nor 'module', it is preceded by {n} where n is its indentation.
      declare
         First : Token renames S.Input (1);
      begin
         S.Await_Open :=
           First.Kind /= Kw_Module
           and then First.Kind /= Left_Brace
           and then First.Kind /= End_Of_File;
      end;
   end Start;

   ---------------------------------------------------------------------
   --  The L function, one decision step at a time
   ---------------------------------------------------------------------

   --  Runs L steps until at least one token is queued.
   procedure Advance
     (S : in out Layout_Stream; Bag : in out Diagnostics.Diagnostic_Bag) is
   begin
      Step : while S.Queue.Is_Empty or else S.Q_First > S.Queue.Last_Index
      loop
         declare
            T : Token renames S.Input (S.I);
            N : constant Positive := Natural (T.Column);
         begin
            --  L [] handling: the End_Of_File token plays the role of
            --  the Report's empty stream.
            if T.Kind = End_Of_File then
               if S.Await_Open then
                  --  {0} at end of input: an empty block.
                  S.Await_Open := False;
                  Open_And_Close_Empty (S, T);
               elsif not S.Stack.Is_Empty then
                  if Top (S) = 0 then
                     Bag.Add (Diagnostics.Error,
                              Diagnostics.Layout_Unmatched_Brace,
                              T.Span, "missing '}' at end of input");
                     Pop (S);  --  recover
                  else
                     Close_Implicit (S, T);
                  end if;
               else
                  Enqueue (S, T);
               end if;

            --  {n}: a block opens before T.
            elsif S.Await_Open then
               S.Await_Open := False;
               S.Newline_Done := True;  --  {n} supersedes T's <n>
               if S.Stack.Is_Empty or else N > Top (S) then
                  Open_Implicit (S, N, T);
               else
                  --  Note 2: the block is empty; T then still starts a
                  --  line for the enclosing context.
                  Open_And_Close_Empty (S, T);
                  S.Newline_Done := False;
               end if;

            --  <n>: T is the first token on its line.
            elsif T.First_On_Line and then not S.Newline_Done
              and then not S.Stack.Is_Empty and then Top (S) /= 0
            then
               if N = Top (S) then
                  S.Newline_Done := True;
                  Enqueue (S, Virtual (V_Semicolon, T));
               elsif N < Top (S) then
                  Close_Implicit (S, T);  --  and re-check the new top
               else
                  S.Newline_Done := True;
               end if;

            --  Ordinary tokens.
            else
               case T.Kind is
                  when Left_Brace =>
                     S.Stack.Append (0);
                     Enqueue (S, T);

                  when Right_Brace =>
                     if not S.Stack.Is_Empty and then Top (S) = 0 then
                        Pop (S);
                     else
                        --  Report: parse-error. Recover by keeping the
                        --  token so the parser sees the mismatch too.
                        Bag.Add (Diagnostics.Error,
                                 Diagnostics.Layout_Unmatched_Brace,
                                 T.Span,
                                 "'}' without matching explicit '{'");
                     end if;
                     Enqueue (S, T);

                  when Kw_Let | Kw_Where | Kw_Do | Kw_Of =>
                     Enqueue (S, T);
                     --  Input always ends with End_Of_File, so I+1 is
                     --  safe: {n} unless an explicit brace follows.
                     S.Await_Open :=
                       S.Input (S.I + 1).Kind /= Left_Brace;

                  when others =>
                     Enqueue (S, T);
               end case;
               S.I := S.I + 1;
               S.Newline_Done := False;
            end if;
         end;
      end loop Step;
   end Advance;

   procedure Next
     (S   : in out Layout_Stream;
      Bag : in out Diagnostics.Diagnostic_Bag;
      T   : out Tokens.Token) is
   begin
      Advance (S, Bag);
      T := S.Queue (S.Q_First);
      if S.Q_First = S.Queue.Last_Index then
         S.Queue.Clear;
         S.Q_First := 1;
      else
         S.Q_First := S.Q_First + 1;
      end if;
      S.Last_Tok := T;
      if T.Kind = End_Of_File then
         S.Is_Finished := True;
      end if;
   end Next;

   procedure Pop_On_Parse_Error
     (S : in out Layout_Stream; Closed : out Boolean) is
   begin
      if S.Stack.Is_Empty or else Top (S) = 0 then
         Closed := False;
         return;
      end if;
      Pop (S);
      S.Closes := S.Closes + 1;
      Closed := True;
   end Pop_On_Parse_Error;

   procedure Close_On_Parse_Error
     (S : in out Layout_Stream; Closed : out Boolean) is
   begin
      if S.Stack.Is_Empty or else Top (S) = 0 then
         Closed := False;
         return;
      end if;

      --  Close the innermost implicit context; the failing token is
      --  re-delivered after the virtual brace. Prepend both, ahead of
      --  anything already queued.
      declare
         Rest : constant Token_Vectors.Vector := S.Queue;
         From : constant Positive := S.Q_First;
      begin
         S.Queue.Clear;
         S.Q_First := 1;
         Pop (S);
         S.Closes := S.Closes + 1;
         Enqueue (S, Virtual (V_Right_Brace, S.Last_Tok));
         Enqueue (S, S.Last_Tok);
         for J in From .. Rest.Last_Index loop
            Enqueue (S, Rest (J));
         end loop;
      end;
      Closed := True;
   end Close_On_Parse_Error;

end AHC.Layout;
