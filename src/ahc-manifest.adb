with Ada.Strings.Fixed;
with Ada.Text_IO;

package body AHC.Manifest is

   function Load (Path : String; P : out Project) return Boolean is
      use Ada.Text_IO;

      F       : File_Type;
      Line_No : Natural := 0;

      procedure Fail (Msg : String) is
      begin
         Put_Line (Standard_Error,
                   "ahc: " & Path & ":" & Line_No'Image & ": "
                   & Msg);
      end Fail;

      --  "key = value" with optional whitespace; # starts a
      --  comment; blank lines skipped. Values: "quoted string",
      --  true/false, or a natural number.

      function Trim (S : String) return String is
        (Ada.Strings.Fixed.Trim (S, Ada.Strings.Both));

      Ok : Boolean := True;

      procedure Parse_Line (Raw : String) is
         Hash : constant Natural :=
           Ada.Strings.Fixed.Index (Raw, "#");
         L : constant String :=
           Trim (if Hash > 0
                 then Raw (Raw'First .. Hash - 1)
                 else Raw);
         Eq : constant Natural := Ada.Strings.Fixed.Index (L, "=");
      begin
         if L'Length = 0 then
            return;
         end if;
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
      if Ok and then P.Main = "" then
         Line_No := 0;
         Fail ("missing required key 'main'");
         Ok := False;
      end if;
      return Ok;
   end Load;

end AHC.Manifest;
