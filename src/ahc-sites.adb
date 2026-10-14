package body AHC.Sites is

   use type Source_Text.Byte_Offset;

   LF : constant Character := ASCII.LF;
   US : constant Character := ASCII.US;
   RS : constant Character := ASCII.RS;

   function Img (N : Natural) return String is
      S : constant String := Natural'Image (N);
   begin
      return S (S'First + 1 .. S'Last);
   end Img;

   ----------------
   -- Ghc_Column --
   ----------------

   function Ghc_Column
     (Src : Source_Text.Source; O : Source_Text.Byte_Offset) return Positive
   is
      Start : constant Source_Text.Byte_Offset :=
        Src.Line_Start (Src.Line_Of (O));
      Col : Positive := 1;
      I : Source_Text.Byte_Offset := Start;
   begin
      while I < O loop
         declare
            C : constant Character := Src.Char_At (I);
         begin
            if C = ASCII.HT then
               Col := ((Col - 1) / 8 + 1) * 8 + 1;
            elsif Character'Pos (C) not in 16#80# .. 16#BF# then
               Col := Col + 1;   --  a UTF-8 continuation byte adds none
            end if;
         end;
         I := I + 1;
      end loop;
      return Col;
   end Ghc_Column;

   --  Line and GHC column of the first and the last character of Span.
   procedure Ends
     (Ctx : Site_Context; Span : Diagnostics.Source_Span;
      L1, C1, L2, C2 : out Positive)
   is
      Last : constant Source_Text.Byte_Offset :=
        (if Span.Stop > Span.Start then Span.Stop - 1 else Span.Start);
   begin
      L1 := Positive (Ctx.Src.Line_Of (Span.Start));
      C1 := Ghc_Column (Ctx.Src, Span.Start);
      L2 := Positive (Ctx.Src.Line_Of (Last));
      C2 := Ghc_Column (Ctx.Src, Last);
   end Ends;

   --------------
   -- Ghc_Span --
   --------------

   function Normalise (Path : String) return String is
      F : Natural := Path'First;
   begin
      while F + 1 <= Path'Last and then Path (F .. F + 1) = "./" loop
         F := F + 2;
      end loop;
      return Path (F .. Path'Last);
   end Normalise;

   function Ghc_Span
     (Ctx : Site_Context; Span : Diagnostics.Source_Span) return String
   is
      L1, C1, L2, C2 : Positive;
      F : constant String :=
        (if Length (Ctx.Span_File) > 0 then To_String (Ctx.Span_File)
         else To_String (Ctx.File));
   begin
      Ends (Ctx, Span, L1, C1, L2, C2);
      if L1 /= L2 then
         return F & ":(" & Img (L1) & "," & Img (C1) & ")-("
           & Img (L2) & "," & Img (C2) & ")";
      elsif C1 = C2 then
         return F & ":" & Img (L1) & ":" & Img (C1);
      else
         return F & ":" & Img (L1) & ":" & Img (C1) & "-" & Img (C2);
      end if;
   end Ghc_Span;

   ---------------
   -- Ghc_Point --
   ---------------

   function Ghc_Point
     (Ctx : Site_Context; Span : Diagnostics.Source_Span) return String is
   begin
      return To_String (Ctx.File) & ":"
        & Img (Positive (Ctx.Src.Line_Of (Span.Start))) & ":"
        & Img (Ghc_Column (Ctx.Src, Span.Start));
   end Ghc_Point;

   ------------
   -- Encode --
   ------------

   --  A literal's separators must not occur inside a field: a raw
   --  U+001F or U+001E in a source line (a comment, say) shifted every
   --  later field (M149 review). They become spaces.
   function Clean (S : String) return String is
      R : String := S;
   begin
      for C of R loop
         if C = US or else C = RS then
            C := ' ';
         end if;
      end loop;
      return R;
   end Clean;

   function Encode (Ctx : Site_Context; S : Site) return String is
      L1, C1, L2, C2 : Positive;
      Snip : Unbounded_String;
   begin
      Ends (Ctx, S.Span, L1, C1, L2, C2);
      for L in L1 .. Positive'Min (L2, L1 + 5) loop
         declare
            From : constant Source_Text.Byte_Offset :=
              Ctx.Src.Line_Start (Source_Text.Line_Number (L));
            Stop : Source_Text.Byte_Offset := From;
         begin
            while Ctx.Src.In_Range (Stop)
              and then Ctx.Src.Char_At (Stop) /= LF
            loop
               Stop := Stop + 1;
            end loop;
            if L > L1 then
               Append (Snip, RS);
            end if;
            Append (Snip, Img (L) & "|" & Clean (Ctx.Src.Slice (From, Stop)));
         end;
      end loop;
      return Clean (To_String (S.Ghc_Text)) & US
        & Clean (To_String (S.Ghc_Stack)) & US
        & Clean (To_String (S.Headline)) & US
        & Clean (To_String (Ctx.File)) & US
        & Img (L1) & ":" & Img (C1) & "-" & Img (L2) & ":" & Img (C2) & US
        & Clean (To_String (S.Enclosing)) & US
        & To_String (Snip) & US
        & To_String (S.Handled) & US
        & Clean (To_String (S.Schema)) & US
        & Clean (To_String (S.Note));
   end Encode;

   -----------------
   -- Base_Frames --
   -----------------

   function Base_Frames (Fn : String) return String is
      Err_List : constant String :=
        "  error, called at libraries/base/GHC/List.hs:1646:3 in "
        & "base:GHC.List" & LF;
      function Empty (Line : String) return String is
        (Err_List & "  errorEmptyList, called at libraries/base/GHC/List.hs:"
         & Line & " in base:GHC.List" & LF);
   begin
      if Fn = "head" then
         return Empty ("85:11")
           & "  badHead, called at libraries/base/GHC/List.hs:81:28 in "
           & "base:GHC.List" & LF;
      elsif Fn = "tail" then
         return Empty ("128:28");
      elsif Fn = "init" then
         return Empty ("178:28");
      elsif Fn = "last" then
         return Empty ("156:13")
           & "  lastError, called at libraries/base/GHC/List.hs:151:29 in "
           & "base:GHC.List" & LF;
      elsif Fn = "cycle" then
         return Empty ("845:27");
      elsif Fn = "maximum" then
         return Empty ("717:28")
           & "  maximum, called at libraries/base/Data/Foldable.hs:745:15 in "
           & "base:Data.Foldable" & LF;
      elsif Fn = "minimum" then
         return Empty ("741:28")
           & "  minimum, called at libraries/base/Data/Foldable.hs:746:15 in "
           & "base:Data.Foldable" & LF;
      elsif Fn = "foldr1" then
         return Empty ("611:30")
           & "  foldr1, called at libraries/base/Data/Foldable.hs:741:15 in "
           & "base:Data.Foldable" & LF;
      elsif Fn = "foldl1" then
         return Empty ("391:28")
           & "  foldl1, called at libraries/base/Data/Foldable.hs:738:15 in "
           & "base:Data.Foldable" & LF;
      elsif Fn = "!!/large" then
         return "  error, called at libraries/base/GHC/List.hs:1368:14 in "
           & "base:GHC.List" & LF
           & "  tooLarge, called at libraries/base/GHC/List.hs:1378:50 in "
           & "base:GHC.List" & LF;
      elsif Fn = "!!/negative" then
         return "  error, called at libraries/base/GHC/List.hs:1371:12 in "
           & "base:GHC.List" & LF
           & "  negIndex, called at libraries/base/GHC/List.hs:1375:17 in "
           & "base:GHC.List" & LF;
      elsif Fn = "fromJust" then
         return "  error, called at libraries/base/Data/Maybe.hs:150:21 in "
           & "base:Data.Maybe" & LF;
      end if;
      return "";
   end Base_Frames;

   function Stack_Is_Base_Only (Fn : String) return Boolean is
     (Fn = "maximum" or else Fn = "minimum" or else Fn = "foldr1"
      or else Fn = "foldl1");

   ----------------
   -- Call_Stack --
   ----------------

   function Call_Stack
     (Ctx : Site_Context; Fn : String; Span : Diagnostics.Source_Span;
      Shown : String := "") return String
   is
      Frames : constant String := Base_Frames (Fn);
      --  "!!/large" and "!!/negative" share the user frame "!!".
      Name : constant String :=
        (if Shown /= "" then Shown
         elsif Fn'Length > 2 and then Fn (Fn'First .. Fn'First + 1) = "!!"
         then "!!" else Fn);
   begin
      if Fn = "" then
         return "";   --  GHC prints no call stack for this function
      elsif Stack_Is_Base_Only (Fn) then
         --  Drop the last frame's line feed: the block ends there.
         return "CallStack (from HasCallStack):" & LF
           & Frames (Frames'First .. Frames'Last - 1);
      end if;
      return "CallStack (from HasCallStack):" & LF & Frames
        & "  " & Name & ", called at " & Ghc_Point (Ctx, Span)
        & " in main:" & To_String (Ctx.Module);
   end Call_Stack;

   function Located_Plain (I : Located_Index) return String is
     (case I is
         when 1 => "error",
         when 2 => "undefined",
         when 3 => "errorWithoutStackTrace",
         when 4 => "head",
         when 5 => "tail",
         when 6 => "init",
         when 7 => "last",
         when 8 => "cycle",
         when 9 => "!!",
         when 10 => "fromJust",
         when 11 => "read",
         when 12 => "chr");

   function Located_Name (I : Located_Index) return String is
     (case I is
         when 1 => "error_at_",
         when 2 => "undefined_at_",
         when 3 => "errorWithoutStackTrace_at_",
         when 4 => "head_at_",
         when 5 => "tail_at_",
         when 6 => "init_at_",
         when 7 => "last_at_",
         when 8 => "cycle_at_",
         when 9 => "index_at_",
         when 10 => "fromJust_at_",
         when 11 => "read_at_",
         when 12 => "chr_at_");

   function Located_Stack_Key (I : Located_Index) return String is
     (case I is
         when 1 => "error",
         when 2 => "undefined",
         when 3 => "",
         when 4 => "head",
         when 5 => "tail",
         when 6 => "init",
         when 7 => "last",
         when 8 => "cycle",
         when 9 => "!!/large",
         when 10 => "fromJust",
         when 11 => "",
         when 12 => "");

   function Located_Headline (I : Located_Index) return String is
     (case I is
         when 1 => "error called",
         when 2 => "undefined",
         when 3 => "error called",
         when 4 => "empty list",
         when 5 => "empty list",
         when 6 => "empty list",
         when 7 => "empty list",
         when 8 => "empty list",
         when 9 => "index out of range",
         when 10 => "fromJust Nothing",
         when 11 => "no parse",
         when 12 => "bad argument");

end AHC.Sites;
