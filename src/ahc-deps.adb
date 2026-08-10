with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Directories;
with Ada.Strings.Hash;
with Ada.Text_IO;

with GNAT.OS_Lib;

with AHC.Manifest;

package body AHC.Deps is

   package String_Sets is new Ada.Containers.Indefinite_Hashed_Sets
     (Element_Type        => String,
      Hash                => Ada.Strings.Hash,
      Equivalent_Elements => "=");

   package String_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => String,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   function Collect_Roots
     (Manifest_Dir : String;
      Roots        : out Root_Vectors.Vector) return Boolean
   is
      use Ada.Text_IO;

      Seen     : String_Sets.Set;   --  every directory ever taken
      On_Stack : String_Sets.Set;   --  the walk's current spine
      By_Name  : String_Maps.Map;   --  name -> directory it means

      Ok : Boolean := True;

      procedure Err (Msg : String) is
      begin
         Put_Line (Standard_Error, "ahc: " & Msg);
         Ok := False;
      end Err;

      procedure Walk (Dir : String) is
         Manifest_Path : constant String := Dir & "/ahc.toml";
         P             : AHC.Manifest.Project;
      begin
         if not Ada.Directories.Exists (Manifest_Path) then
            return;   --  a bare module tree: nothing more to walk
         end if;
         if not AHC.Manifest.Load
           (Manifest_Path, P, Require_Main => False)
         then
            Ok := False;
            return;
         end if;
         On_Stack.Include (Dir);
         for D of P.Deps loop
            exit when not Ok;
            declare
               Name : constant String := To_String (D.Name);
               Full : constant String := GNAT.OS_Lib.Normalize_Pathname
                 (Dir & "/" & To_String (D.Path));
            begin
               if not Ada.Directories.Exists (Full) then
                  Err ("dependency '" & Name
                       & "': no such directory " & Full
                       & " (from " & Manifest_Path & ")");
               elsif On_Stack.Contains (Full) then
                  Err ("dependency cycle through '" & Full & "'");
               elsif By_Name.Contains (Name)
                 and then By_Name (Name) /= Full
               then
                  Err ("dependency '" & Name & "' means both "
                       & By_Name (Name) & " and " & Full);
               elsif not Seen.Contains (Full) then
                  Seen.Include (Full);
                  By_Name.Include (Name, Full);
                  Roots.Append
                    (Dep_Root'(Name => To_Unbounded_String (Name),
                               Dir  => To_Unbounded_String (Full)));
                  Walk (Full);
               end if;
            end;
         end loop;
         On_Stack.Exclude (Dir);
      end Walk;

      Start : constant String :=
        GNAT.OS_Lib.Normalize_Pathname (Manifest_Dir);

   begin
      Roots.Clear;
      Walk (Start);
      return Ok;
   end Collect_Roots;

end AHC.Deps;
