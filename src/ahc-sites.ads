--  Runtime failure sites (M149).
--
--  A site is a place in the source that can fail at run time: a
--  pattern-match fallthrough, a use of a located partial function
--  (AHC_LOCATED), error and undefined. Desugar encodes each one as a
--  single string literal - the "site literal" - that the runtime reads
--  only on the failure path. It carries GHC 9.4.8's exact text for the
--  exception's show and the material for AHC's own uncaught-error
--  report. A literal stays local to its module's C unit, so separate
--  compilation's per-module cache is unaffected, and it costs nothing
--  until forced.
--
--  Literal format: ten fields separated by ASCII.US; list items
--  inside a field separated by ASCII.RS.
--    0 ghc_text   the exception's GHC show text, without a CallStack
--    1 ghc_stack  GHC's CallStack block, "" when GHC prints none
--    2 headline   the report's headline ("pattern match failure", ...)
--    3 file       the file as given on the command line
--    4 span       "L1:C1-L2:C2", 1-based, end inclusive
--    5 in         the enclosing top-level binding
--    6 snippet    "L|text" per spanned line (at most 6)
--    7 handled    constructor names the alternatives match
--    8 schema     the value-render schema (Schema_Text)
--    9 note       one extra note line, or ""

with Ada.Strings.Unbounded;
with AHC.Diagnostics;
with AHC.Source_Text;

package AHC.Sites is
   use Ada.Strings.Unbounded;

   --  Where a module's sites come from: the file as given on the
   --  command line (GHC prints the same path), the module's name, and
   --  its text. An empty File disables site building: desugar then
   --  falls back to its plain error calls.
   type Site_Context is record
      File   : Unbounded_String;
      Module : Unbounded_String;
      Src    : Source_Text.Source;
   end record;

   No_Context : constant Site_Context := (others => <>);

   function Enabled (Ctx : Site_Context) return Boolean
   is (Length (Ctx.File) > 0);

   type Site is record
      Ghc_Text  : Unbounded_String;
      Ghc_Stack : Unbounded_String;
      Headline  : Unbounded_String;
      Span      : Diagnostics.Source_Span;
      Enclosing : Unbounded_String;
      Handled   : Unbounded_String;   --  names joined by ASCII.RS
      Schema    : Unbounded_String;
      Note      : Unbounded_String;
   end record;

   --  GHC's column of the character at O: characters (not bytes) from
   --  the line start, a tab advancing to the next multiple of 8, 1-based.
   function Ghc_Column
     (Src : Source_Text.Source; O : Source_Text.Byte_Offset) return Positive
     with Pre => Src.In_Range (O);

   --  GHC's span text: "F:L:C1-C2" on one line, "F:(L1,C1)-(L2,C2)"
   --  across lines, the end column inclusive; "F:L:C" for one
   --  character.
   function Ghc_Span
     (Ctx : Site_Context; Span : Diagnostics.Source_Span) return String
     with Pre => Enabled (Ctx);

   --  "F:L:C": GHC's call-stack location of the token at Span.Start.
   function Ghc_Point
     (Ctx : Site_Context; Span : Diagnostics.Source_Span) return String
     with Pre => Enabled (Ctx);

   --  The site literal (format above).
   function Encode (Ctx : Site_Context; S : Site) return String
     with Pre  => Enabled (Ctx),
          Post => Encode'Result'Length > 0;

   --  The constant base-internal frames GHC 9.4.8 prints for a located
   --  Prelude function, each line indented two spaces and ending in a
   --  line feed; "" for error/undefined (whose only frame is the call
   --  site). Recorded from the oracle (tests/conformance/
   --  m149_shown_errors.out).
   function Base_Frames (Fn : String) return String;

   --  True when GHC's last frame is base-internal too, so no user
   --  frame follows (maximum, minimum, foldr1, foldl1 go through
   --  Data.Foldable).
   function Stack_Is_Base_Only (Fn : String) return Boolean;

   --  GHC's CallStack block for a located use of Fn at Span: the
   --  header, Base_Frames, then (unless base-only) the user frame
   --  "  Fn, called at F:L:C in main:Module". No trailing newline.
   function Call_Stack
     (Ctx : Site_Context; Fn : String; Span : Diagnostics.Source_Span)
      return String
     with Pre => Enabled (Ctx);
   --  The located Prelude entities (M149). Desugar rewrites a use of
   --  the Prelude's entity Plain (found by identity through the
   --  Prelude environment, so a user's own `head` is untouched) to
   --  the Prelude-internal Located applied to a site. Stack_Key names
   --  the CallStack GHC prints ("" for none: read, chr,
   --  errorWithoutStackTrace); Headline is the report's.
   Located_Count : constant := 12;
   subtype Located_Index is Positive range 1 .. Located_Count;
   function Located_Plain (I : Located_Index) return String;
   function Located_Name (I : Located_Index) return String;
   function Located_Stack_Key (I : Located_Index) return String;
   function Located_Headline (I : Located_Index) return String;
end AHC.Sites;
