--  Command-line driver for AHC.
--
--  Usage:
--    ahc --version
--    ahc lex [--layout] FILE.hs    (Milestone 2+)
--    ahc parse FILE.hs             (Milestone 5+)
--
--  Exit status: 0 on success, 1 on compilation errors, 2 on usage errors.

with Ada.Command_Line;
with Ada.Text_IO;

with AHC;

procedure AHC_Main is
   use Ada.Command_Line;
   use Ada.Text_IO;

   procedure Print_Usage (Target : File_Type) is
   begin
      Put_Line (Target, "usage: ahc --version");
      Put_Line (Target, "       ahc lex [--layout] FILE.hs");
      Put_Line (Target, "       ahc parse FILE.hs");
   end Print_Usage;
begin
   if Argument_Count = 0 then
      Print_Usage (Standard_Error);
      Set_Exit_Status (2);
      return;
   end if;

   declare
      Command : constant String := Argument (1);
   begin
      if Command = "--version" then
         Put_Line ("ahc " & AHC.Version);
      elsif Command = "lex" or else Command = "parse" then
         Put_Line (Standard_Error,
                   "ahc: '" & Command & "' is not implemented yet");
         Set_Exit_Status (2);
      else
         Put_Line (Standard_Error, "ahc: unknown command '" & Command & "'");
         Print_Usage (Standard_Error);
         Set_Exit_Status (2);
      end if;
   end;
end AHC_Main;
