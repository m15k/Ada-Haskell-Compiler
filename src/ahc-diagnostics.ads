--  Source spans and accumulated diagnostics.
--
--  Spans are half-open byte ranges [Start, Stop) over one normalized
--  source buffer, so zero-width spans (layout-inserted virtual tokens)
--  are representable. Phases accumulate into a Diagnostic_Bag instead
--  of failing fast; rendering resolves line/column lazily against the
--  Source. (Single-file for Phase 1; a file table arrives with
--  multi-module compilation.)

with AHC.Source_Text;

private with Ada.Containers.Indefinite_Vectors;

package AHC.Diagnostics is

   use type Source_Text.Byte_Offset;

   type Source_Span is record
      Start : Source_Text.Byte_Offset := 1;
      Stop  : Source_Text.Byte_Offset := 1;  --  exclusive
   end record
     with Dynamic_Predicate => Source_Span.Stop >= Source_Span.Start;

   function Width (Span : Source_Span) return Natural
   is (Natural (Span.Stop - Span.Start));

   function Zero_Width_At (O : Source_Text.Byte_Offset) return Source_Span
   is (Start => O, Stop => O);

   --  Smallest span covering both.
   function Merge (A, B : Source_Span) return Source_Span
   is (Start => Source_Text.Byte_Offset'Min (A.Start, B.Start),
       Stop  => Source_Text.Byte_Offset'Max (A.Stop, B.Stop));

   type Severity_Kind is (Warning, Error);

   type Diag_Code is
     (Lex_Invalid_Character,
      Lex_Unterminated_Comment,
      Lex_Unterminated_String,
      Lex_Invalid_Literal,
      Lex_Invalid_Name,
      Layout_Unmatched_Brace,
      Parse_Error,
      Fixity_Error);

   --  Errors beyond this many are counted but not stored.
   Max_Stored_Errors : constant := 50;

   type Diagnostic_Bag is tagged limited private;

   procedure Add
     (Bag     : in out Diagnostic_Bag;
      Sev     : Severity_Kind;
      Code    : Diag_Code;
      Span    : Source_Span;
      Message : String);

   function Count (Bag : Diagnostic_Bag) return Natural;
   function Error_Count (Bag : Diagnostic_Bag) return Natural;
   function Has_Errors (Bag : Diagnostic_Bag) return Boolean
   is (Bag.Error_Count > 0);

   function Error_Limit_Reached (Bag : Diagnostic_Bag) return Boolean
   is (Bag.Error_Count >= Max_Stored_Errors);

   --  "file:line:col: error: message"
   function Render
     (Bag   : Diagnostic_Bag;
      Over  : Source_Text.Source;
      Index : Positive) return String
     with Pre => Index <= Bag.Count;

   --  Render every stored diagnostic to standard error.
   procedure Print_All
     (Bag : Diagnostic_Bag; Over : Source_Text.Source);

private

   type Diagnostic (Message_Length : Natural) is record
      Sev     : Severity_Kind;
      Code    : Diag_Code;
      Span    : Source_Span;
      Message : String (1 .. Message_Length);
   end record;

   package Diagnostic_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => Diagnostic);

   type Diagnostic_Bag is tagged limited record
      Items  : Diagnostic_Vectors.Vector;
      Errors : Natural := 0;  --  includes errors dropped past the cap
   end record;

end AHC.Diagnostics;
