--  The Haskell layout (off-side) rule: Report 10.3's function L as a
--  pull-based token-stream transformer between lexer and parser.
--
--  The lexer's First_On_Line/Column annotations stand in for the
--  Report's <n> pseudo-tokens; {n} insertion points (after let/where/
--  do/of without an explicit brace, and before a module body that does
--  not start with 'module' or '{') are recomputed here. The stream
--  emits V_Left_Brace/V_Right_Brace/V_Semicolon virtual tokens with
--  zero-width spans.
--
--  The Report's "parse-error(t)" side condition cannot be decided by a
--  stream, so it is exposed as Close_On_Parse_Error: when the parser
--  cannot proceed and the innermost context is implicit, it asks the
--  stream to close that context; the token that failed is re-delivered
--  after the virtual close ("let x = 1 in x" needs this for 'in').
--
--  Contracts guarantee the PRD's layout invariants: the context stack
--  never underflows (checked Pre on the internal Pop), every implicit
--  open is matched by exactly one implicit close (Balanced is a type
--  invariant over emission counters), and a delivered End_Of_File
--  implies all implicit contexts were closed.

with AHC.Diagnostics;
with AHC.Tokens;

private with Ada.Containers.Vectors;

package AHC.Layout is

   use type Tokens.Token_Kind;

   type Layout_Stream is tagged limited private
     with Type_Invariant => Balanced (Layout_Stream);

   --  Pop the innermost implicit context WITHOUT emitting tokens; the
   --  parser synthesizes the V_Right_Brace itself. Needed when parser
   --  lookahead has already drained tokens past the failing one (the
   --  queue-based Close_On_Parse_Error cannot help there).
   procedure Pop_On_Parse_Error
     (S : in out Layout_Stream; Closed : out Boolean);

   function Balanced (S : Layout_Stream) return Boolean;

   --  Number of implicit layout contexts currently open.
   function Implicit_Depth (S : Layout_Stream) return Natural;

   function Started (S : Layout_Stream) return Boolean;

   --  True once End_Of_File has been delivered.
   function Finished (S : Layout_Stream) return Boolean;

   --  Input must be a whole raw lexer stream (its trailing End_Of_File
   --  drives final context closing).
   procedure Start
     (S : in out Layout_Stream; Input : Tokens.Token_Vectors.Vector)
     with
       Pre  => not Input.Is_Empty
               and then Input.Last_Element.Kind = Tokens.End_Of_File,
       Post => S.Started and then not S.Finished;

   procedure Next
     (S   : in out Layout_Stream;
      Bag : in out Diagnostics.Diagnostic_Bag;
      T   : out Tokens.Token)
     with
       Pre  => S.Started and then not S.Finished,
       Post => (if T.Kind = Tokens.End_Of_File
                then S.Finished and then S.Implicit_Depth = 0
                else not S.Finished);

   --  Report 10.3, the parse-error(t) clause. If the innermost context
   --  is implicit: close it (Closed = True); the next two calls to Next
   --  deliver a V_Right_Brace and then the token whose delivery caused
   --  the parse error. Otherwise Closed = False and the stream is
   --  unchanged.
   procedure Close_On_Parse_Error
     (S : in out Layout_Stream; Closed : out Boolean)
     with
       Pre  => S.Started and then not S.Finished,
       Post => S.Implicit_Depth =
                 S.Implicit_Depth'Old - (if Closed then 1 else 0);

private

   --  A layout context: 0 for an explicit brace, else the indentation
   --  column of an implicit block (Report uses the same encoding).
   package Context_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Natural);

   type Layout_Stream is tagged limited record
      Input        : Tokens.Token_Vectors.Vector;
      I            : Positive := 1;      --  next unconsumed input token
      Stack        : Context_Vectors.Vector;
      Queue        : Tokens.Token_Vectors.Vector;   --  FIFO out buffer
      Q_First      : Positive := 1;
      Await_Open   : Boolean := False;   --  {n} pending before Input(I)
      Newline_Done : Boolean := False;   --  Input(I)'s <n> already used
      Is_Started   : Boolean := False;
      Is_Finished  : Boolean := False;
      Last_Tok     : Tokens.Token;       --  last token delivered
      Opens        : Natural := 0;       --  V_Left_Brace emitted
      Closes       : Natural := 0;       --  V_Right_Brace emitted
   end record;

   function Balanced (S : Layout_Stream) return Boolean
   is (S.Opens = S.Closes + S.Implicit_Depth);

   function Started (S : Layout_Stream) return Boolean is (S.Is_Started);
   function Finished (S : Layout_Stream) return Boolean is (S.Is_Finished);

end AHC.Layout;
