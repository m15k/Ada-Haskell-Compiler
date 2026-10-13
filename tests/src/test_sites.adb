with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AHC.Sites; use AHC.Sites;
with AHC.Source_Text; use AHC.Source_Text;

with Test_Harness; use Test_Harness;

package body Test_Sites is

   LF : constant Character := ASCII.LF;

   procedure Run is
      Src : constant Source :=
        Load_String ("E.hs",
                     "area (Circle r) = r" & LF          --  line 1
                     & "area (Square s) = s" & LF        --  line 2
                     & "x = case v of" & LF              --  line 3
                     & ASCII.HT & "y = h" & LF           --  line 4: tab
                     & "z = " & Character'Val (16#CE#)   --  line 5: UTF-8
                     & Character'Val (16#BB#) & " q");
      Ctx : constant Site_Context :=
        (File => To_Unbounded_String ("E.hs"),
         Module => To_Unbounded_String ("Main"), Src => Src);
   begin
      Start_Suite ("Sites");

      --  Offsets: line 1 is bytes 1..19, LF at 20; line 2 starts at 21.
      Check_Equal (Ghc_Span (Ctx, (Start => 1, Stop => 40)),
                   "E.hs:(1,1)-(2,19)", "multi-line span is GHC's (L,C)-(L,C)");
      Check_Equal (Ghc_Span (Ctx, (Start => 6, Stop => 16)),
                   "E.hs:1:6-15", "one-line span is GHC's L:C1-C2");
      Check_Equal (Ghc_Span (Ctx, (Start => 1, Stop => 2)),
                   "E.hs:1:1", "one-character span is GHC's L:C");

      --  Line 4 starts at byte 55 with a tab: "y" is GHC column 9.
      Check_Equal (Ghc_Point (Ctx, (Start => 56, Stop => 57)),
                   "E.hs:4:9", "a tab advances to the next multiple of 8");
      --  Line 5: "z = " then a two-byte letter, " q": q is column 7.
      Check_Equal (Ghc_Point (Ctx, (Start => 69, Stop => 70)),
                   "E.hs:5:7", "a UTF-8 character is one column");

      declare
         S : Site;
         Lit : Unbounded_String;
      begin
         S.Ghc_Text := To_Unbounded_String ("msg");
         S.Span := (Start => 1, Stop => 40);
         Lit := To_Unbounded_String (Encode (Ctx, S));
         Check_Equal (Ada.Strings.Fixed.Count (To_String (Lit), "" & ASCII.US),
                      9, "a site literal has ten fields");
         Check (Ada.Strings.Fixed.Index
                  (To_String (Lit), "1|area (Circle r) = r" & ASCII.RS
                   & "2|area (Square s) = s") > 0,
                "the snippet holds the spanned lines");
      end;

      Check_Equal
        (Call_Stack (Ctx, "head", (Start => 1, Stop => 5)),
         "CallStack (from HasCallStack):" & LF
         & "  error, called at libraries/base/GHC/List.hs:1646:3 in base:GHC.List" & LF
         & "  errorEmptyList, called at libraries/base/GHC/List.hs:85:11 in base:GHC.List" & LF
         & "  badHead, called at libraries/base/GHC/List.hs:81:28 in base:GHC.List" & LF
         & "  head, called at E.hs:1:1 in main:Main",
         "head's call stack is GHC's");
      Check_Equal
        (Call_Stack (Ctx, "maximum", (Start => 1, Stop => 5)),
         "CallStack (from HasCallStack):" & LF
         & "  error, called at libraries/base/GHC/List.hs:1646:3 in base:GHC.List" & LF
         & "  errorEmptyList, called at libraries/base/GHC/List.hs:717:28 in base:GHC.List" & LF
         & "  maximum, called at libraries/base/Data/Foldable.hs:745:15 in base:Data.Foldable",
         "maximum's stack is base-only, as GHC's");
      Check_Equal
        (Call_Stack (Ctx, "!!/large", (Start => 6, Stop => 7)),
         "CallStack (from HasCallStack):" & LF
         & "  error, called at libraries/base/GHC/List.hs:1368:14 in base:GHC.List" & LF
         & "  tooLarge, called at libraries/base/GHC/List.hs:1378:50 in base:GHC.List" & LF
         & "  !!, called at E.hs:1:6 in main:Main",
         "(!!)'s user frame is named !!");
      Check_Equal
        (Call_Stack (Ctx, "error", (Start => 21, Stop => 25)),
         "CallStack (from HasCallStack):" & LF
         & "  error, called at E.hs:2:1 in main:Main",
         "error's stack is its call site alone");
   end Run;

end Test_Sites;
