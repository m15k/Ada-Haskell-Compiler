with Ada.Strings.Fixed;

package body AHC.Semver is

   function Parse (S : String; V : out Version) return Boolean is

      function Component (Part : String; N : out Natural)
        return Boolean is
      begin
         N := 0;
         --  Digits only, no leading zero (semver forbids "01"),
         --  and short enough that Natural'Value cannot overflow -
         --  the digit check alone would let "9999999999" raise
         --  Constraint_Error out of a Boolean function.
         if Part'Length = 0
           or else Part'Length > 9
           or else (for some C of Part => C not in '0' .. '9')
           or else (Part'Length > 1 and then Part (Part'First) = '0')
         then
            return False;
         end if;
         N := Natural'Value (Part);
         return True;
      end Component;

      First_Dot  : constant Natural :=
        Ada.Strings.Fixed.Index (S, ".");
      Second_Dot : constant Natural :=
        (if First_Dot > 0
         then Ada.Strings.Fixed.Index (S, ".", First_Dot + 1)
         else 0);
   begin
      V := (others => 0);
      return First_Dot > 0 and then Second_Dot > 0
        and then Component (S (S'First .. First_Dot - 1), V.Major)
        and then Component
          (S (First_Dot + 1 .. Second_Dot - 1), V.Minor)
        and then Component (S (Second_Dot + 1 .. S'Last), V.Patch);
   end Parse;

   function "<" (L, R : Version) return Boolean is
     (L.Major < R.Major
      or else (L.Major = R.Major
               and then (L.Minor < R.Minor
                         or else (L.Minor = R.Minor
                                  and then L.Patch < R.Patch))));

   function Image (V : Version) return String is
      function Img (N : Natural) return String is
         S : constant String := N'Image;
      begin
         return S (S'First + 1 .. S'Last);
      end Img;
   begin
      return Img (V.Major) & "." & Img (V.Minor) & "." & Img (V.Patch);
   end Image;

end AHC.Semver;
