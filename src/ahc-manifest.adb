with Ada.Strings.Fixed;
with Ada.Text_IO;

package body AHC.Manifest is

   function Load (Path : String; P : out Project;
                  Require_Main : Boolean := True) return Boolean is
      use Ada.Text_IO;

      F       : File_Type;
      Line_No : Natural := 0;

      procedure Fail (Msg : String) is
      begin
         Put_Line (Standard_Error,
                   "ahc: " & Path & ":" & Line_No'Image & ": "
                   & Msg);
      end Fail;

      --  One construct per line: "key = value" or a "[section]"
      --  header; # starts a comment; blank lines skipped. Values:
      --  "quoted string", true/false, or a natural number.
      --  Sections: [package], and [dependencies.NAME] once per
      --  dependency. Keys before any header keep their original
      --  flat meaning.

      function Trim (S : String) return String is
        (Ada.Strings.Fixed.Trim (S, Ada.Strings.Both));

      function Is_Word (S : String) return Boolean is
        (S'Length > 0
         and then (for all C of S =>
                     C in 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9'
                       | '_' | '-'));

      Ok : Boolean := True;

      type Section is (Top, Pkg, Dep);
      Cur     : Section := Top;
      Cur_Dep : Natural := 0;   --  index into P.Deps when Cur = Dep

      procedure Parse_Header (L : String) is
      begin
         if L (L'Last) /= ']' then
            Fail ("expected ']' to close the section header");
            Ok := False;
            return;
         end if;
         declare
            Inner : constant String :=
              Trim (L (L'First + 1 .. L'Last - 1));
            Dot   : constant Natural :=
              Ada.Strings.Fixed.Index (Inner, ".");
         begin
            if Inner = "package" then
               Cur := Pkg;
            elsif Dot > 0
              and then Inner (Inner'First .. Dot - 1) = "dependencies"
            then
               declare
                  Name : constant String :=
                    Inner (Dot + 1 .. Inner'Last);
               begin
                  if not Is_Word (Name) then
                     Fail ("dependency name '" & Name
                           & "' wants letters, digits, _ or -");
                     Ok := False;
                     return;
                  end if;
                  for D of P.Deps loop
                     if To_String (D.Name) = Name then
                        Fail ("duplicate dependency '" & Name & "'");
                        Ok := False;
                        return;
                     end if;
                  end loop;
                  P.Deps.Append
                    (Dependency'
                       (Name   => To_Unbounded_String (Name),
                        others => <>));
                  Cur_Dep := Natural (P.Deps.Length);
                  Cur := Dep;
               end;
            else
               Fail ("unknown section '[" & Inner & "]'");
               Ok := False;
            end if;
         end;
      end Parse_Header;

      procedure Parse_Line (Raw : String) is
         Hash : constant Natural :=
           Ada.Strings.Fixed.Index (Raw, "#");
         L : constant String :=
           Trim (if Hash > 0
                 then Raw (Raw'First .. Hash - 1)
                 else Raw);
         Eq : Natural;
      begin
         if L'Length = 0 then
            return;
         end if;
         if L (L'First) = '[' then
            Parse_Header (L);
            return;
         end if;
         Eq := Ada.Strings.Fixed.Index (L, "=");
         if Eq = 0 then
            Fail ("expected key = value");
            Ok := False;
            return;
         end if;
         declare
            Key : constant String := Trim (L (L'First .. Eq - 1));
            Val : constant String := Trim (L (Eq + 1 .. L'Last));

            function Str return String is
            begin
               if Val'Length >= 2
                 and then Val (Val'First) = '"'
                 and then Val (Val'Last) = '"'
               then
                  return Val (Val'First + 1 .. Val'Last - 1);
               end if;
               Fail ("key '" & Key & "' wants a quoted string");
               Ok := False;
               return "";
            end Str;

            function Bool return Boolean is
            begin
               if Val = "true" then
                  return True;
               elsif Val = "false" then
                  return False;
               end if;
               Fail ("key '" & Key & "' wants true or false");
               Ok := False;
               return False;
            end Bool;

            function Nat return Natural is
            begin
               if Val'Length > 0
                 and then (for all C of Val => C in '0' .. '9')
               then
                  return Natural'Value (Val);
               end if;
               Fail ("key '" & Key & "' wants a number");
               Ok := False;
               return 0;
            end Nat;

            procedure Top_Key is
            begin
               if Key = "main" then
                  P.Main := To_Unbounded_String (Str);
               elsif Key = "output" then
                  P.Output := To_Unbounded_String (Str);
               elsif Key = "cflags" then
                  P.Cflags := To_Unbounded_String (Str);
               elsif Key = "ldflags" then
                  P.Ldflags := To_Unbounded_String (Str);
               elsif Key = "gc" then
                  declare
                     G : constant String := Str;
                  begin
                     if G in "boehm" | "own" | "none" then
                        P.GC := To_Unbounded_String (G);
                     elsif Ok then
                        Fail ("gc must be boehm, own, or none");
                        Ok := False;
                     end if;
                  end;
               elsif Key = "unchecked" then
                  P.Unchecked := Bool;
               elsif Key = "no-opt" then
                  P.No_Opt := Bool;
               elsif Key = "lib" then
                  P.Lib := Bool;
               elsif Key = "jobs" then
                  P.Jobs := Nat;
               else
                  Fail ("unknown key '" & Key & "'");
                  Ok := False;
               end if;
            end Top_Key;

            procedure Pkg_Key is
            begin
               if Key = "name" then
                  declare
                     N : constant String := Str;
                  begin
                     if Is_Word (N) then
                        P.Pkg_Name := To_Unbounded_String (N);
                     elsif Ok then
                        Fail ("package name '" & N
                              & "' wants letters, digits, _ or -");
                        Ok := False;
                     end if;
                  end;
               elsif Key = "version" then
                  P.Pkg_Version := To_Unbounded_String (Str);
               else
                  Fail ("unknown key '" & Key & "' in [package]");
                  Ok := False;
               end if;
            end Pkg_Key;

            procedure Dep_Key is
               D : Dependency := P.Deps (Cur_Dep);
            begin
               if Key = "path" then
                  D.Path := To_Unbounded_String (Str);
               elsif Key in "git" | "version" | "pin" then
                  Fail ("key '" & Key
                        & "': git dependencies arrive in a later "
                        & "milestone");
                  Ok := False;
               else
                  Fail ("unknown key '" & Key & "' in [dependencies."
                        & To_String (D.Name) & "]");
                  Ok := False;
               end if;
               P.Deps (Cur_Dep) := D;
            end Dep_Key;

         begin
            case Cur is
               when Top => Top_Key;
               when Pkg => Pkg_Key;
               when Dep => Dep_Key;
            end case;
         end;
      end Parse_Line;

   begin
      P := (others => <>);
      begin
         Open (F, In_File, Path);
      exception
         when others =>
            Put_Line (Standard_Error,
                      "ahc: cannot open " & Path);
            return False;
      end;
      while not End_Of_File (F) loop
         Line_No := Line_No + 1;
         Parse_Line (Get_Line (F));
      end loop;
      Close (F);
      Line_No := 0;
      for D of P.Deps loop
         if Ok and then D.Path = "" then
            Fail ("dependency '" & To_String (D.Name)
                  & "' needs path = ""...""");
            Ok := False;
         end if;
      end loop;
      if Ok and then Require_Main and then P.Main = "" then
         Fail ("missing required key 'main'");
         Ok := False;
      end if;
      return Ok;
   end Load;

end AHC.Manifest;
