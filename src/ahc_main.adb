--  Command-line driver for AHC.
--
--  Usage:
--    ahc --version
--    ahc lex [--layout] FILE.hs
--    ahc parse FILE.hs             (Milestone 5+)
--
--  Exit status: 0 on success, 1 on compilation errors, 2 on usage errors.

with Ada.Command_Line;
with Ada.IO_Exceptions;
with Ada.Text_IO;

with AHC.Builtins;
with AHC.Core.Printer;
with AHC.Desugar;
with AHC.Diagnostics;
with AHC.Fixity;
with AHC.Kinds;
with AHC.Layout;
with AHC.Lexer;
with AHC.Names;
with AHC.Parser;
with AHC.Rename;
with AHC.Source_Text;
with AHC.Syntax.Printer;
with AHC.Tokens;
with AHC.Typechecker;

procedure AHC_Main is
   use Ada.Command_Line;
   use Ada.Text_IO;

   procedure Print_Usage (Target : File_Type) is
   begin
      Put_Line (Target, "usage: ahc --version");
      Put_Line (Target, "       ahc lex [--layout] FILE.hs");
      Put_Line (Target, "       ahc parse FILE.hs");
      Put_Line (Target, "       ahc core FILE.hs");
      Put_Line (Target, "       ahc check FILE.hs");
   end Print_Usage;

   procedure Usage_Error (Message : String) is
   begin
      Put_Line (Standard_Error, "ahc: " & Message);
      Print_Usage (Standard_Error);
      Set_Exit_Status (2);
   end Usage_Error;

   --  Dump one token per line as "line:col[*] image"; '*' marks the
   --  first token of a source line (layout-relevant). Golden-test format.
   procedure Run_Lex (Path : String; Apply_Layout : Boolean) is
      Text   : AHC.Source_Text.Source;
      Table  : AHC.Names.Name_Table;
      Bag    : AHC.Diagnostics.Diagnostic_Bag;
      Stream : AHC.Tokens.Token_Vectors.Vector;

      procedure Print (T : AHC.Tokens.Token) is
         Line : constant String := T.Line'Image;
         Col  : constant String := T.Column'Image;
      begin
         Put_Line
           (Line (2 .. Line'Last) & ":" & Col (2 .. Col'Last)
            & (if T.First_On_Line then "* " else "  ")
            & AHC.Tokens.Image (T, Table));
      end Print;
   begin
      begin
         Text := AHC.Source_Text.Load_File (Path);
      exception
         when Ada.IO_Exceptions.Name_Error =>
            Usage_Error ("cannot open '" & Path & "'");
            return;
      end;

      AHC.Lexer.Scan (Text, Table, Bag, Stream);

      if Apply_Layout then
         declare
            use type AHC.Tokens.Token_Kind;
            Laid : AHC.Layout.Layout_Stream;
            T    : AHC.Tokens.Token;
         begin
            Laid.Start (Stream);
            loop
               Laid.Next (Bag, T);
               Print (T);
               exit when T.Kind = AHC.Tokens.End_Of_File;
            end loop;
         end;
      else
         for T of Stream loop
            Print (T);
         end loop;
      end if;

      Bag.Print_All (Text);
      if Bag.Has_Errors then
         Set_Exit_Status (1);
      end if;
   end Run_Lex;

   --  Pipeline through desugaring (+ typechecking for `check`).
   --  Mode: 'c' = print Core dump, 't' = print top-level types.
   procedure Run_Middle (Path : String; Mode : Character) is
      Text   : AHC.Source_Text.Source;
      Table  : AHC.Names.Name_Table;
      Bag    : AHC.Diagnostics.Diagnostic_Bag;
      Stream : AHC.Tokens.Token_Vectors.Vector;
      Arena  : AHC.Syntax.Module_Arena;
      M      : AHC.Core.Core_Module;
      Env    : AHC.Builtins.Global_Env;
      Res    : AHC.Rename.Resolutions;
      Sigs   : AHC.Kinds.Sig_Maps.Map;
      Annos  : AHC.Kinds.Anno_Maps.Map;
   begin
      begin
         Text := AHC.Source_Text.Load_File (Path);
      exception
         when Ada.IO_Exceptions.Name_Error =>
            Usage_Error ("cannot open '" & Path & "'");
            return;
      end;

      AHC.Lexer.Scan (Text, Table, Bag, Stream);
      AHC.Parser.Parse_Module (Stream, Table, Bag, Arena);
      AHC.Fixity.Resolve_Module (Arena, Table, Bag);
      if not Bag.Has_Errors then
         AHC.Builtins.Install (M, Table, Env);
         AHC.Rename.Resolve_Module (Arena, Table, Bag, M, Env, Res);
         AHC.Kinds.Check_Module
           (Arena, Res, Table, Bag, M, Env, Sigs, Annos);
      end if;
      if not Bag.Has_Errors then
         AHC.Desugar.Desugar_Module
           (Arena, Res, Table, Bag, M, Env, Sigs, Annos);
         if Mode = 't' then
            AHC.Typechecker.Check_Module (Table, Bag, M, Env, Sigs);
            if not Bag.Has_Errors then
               for G of M.Top_Binds loop
                  for B of G.Binds loop
                     declare
                        use type AHC.Core.Scheme_Id;
                        Info : constant AHC.Core.Var_Info :=
                          M.Info (B.Binder);
                        Name : constant String :=
                          Table.Text (Info.Name);
                     begin
                        if Info.Var_Scheme /= AHC.Core.No_Scheme
                          and then (Name'Length = 0
                                    or else Name (Name'First) /= '$')
                        then
                           Put_Line
                             (Name & " :: "
                              & AHC.Core.Printer.Pretty_Scheme
                                  (M, Table,
                                   AHC.Core.Real_Scheme_Id
                                     (Info.Var_Scheme)));
                        end if;
                     end;
                  end loop;
               end loop;
            end if;
         else
            Put (AHC.Core.Printer.Dump (M, Table));
         end if;
      end if;

      Bag.Print_All (Text);
      if Bag.Has_Errors then
         Set_Exit_Status (1);
      end if;
   end Run_Middle;

   procedure Run_Parse (Path : String) is
      Text   : AHC.Source_Text.Source;
      Table  : AHC.Names.Name_Table;
      Bag    : AHC.Diagnostics.Diagnostic_Bag;
      Stream : AHC.Tokens.Token_Vectors.Vector;
      Arena  : AHC.Syntax.Module_Arena;
   begin
      begin
         Text := AHC.Source_Text.Load_File (Path);
      exception
         when Ada.IO_Exceptions.Name_Error =>
            Usage_Error ("cannot open '" & Path & "'");
            return;
      end;

      AHC.Lexer.Scan (Text, Table, Bag, Stream);
      AHC.Parser.Parse_Module (Stream, Table, Bag, Arena);
      AHC.Fixity.Resolve_Module (Arena, Table, Bag);

      Put (AHC.Syntax.Printer.Dump (Arena, Table));

      Bag.Print_All (Text);
      if Bag.Has_Errors then
         Set_Exit_Status (1);
      end if;
   end Run_Parse;

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
      elsif Command = "lex" then
         if Argument_Count = 2 then
            Run_Lex (Argument (2), Apply_Layout => False);
         elsif Argument_Count = 3 and then Argument (2) = "--layout" then
            Run_Lex (Argument (3), Apply_Layout => True);
         else
            Usage_Error ("expected: ahc lex [--layout] FILE.hs");
         end if;
      elsif Command = "parse" then
         if Argument_Count = 2 then
            Run_Parse (Argument (2));
         else
            Usage_Error ("expected: ahc parse FILE.hs");
         end if;
      elsif Command = "core" then
         if Argument_Count = 2 then
            Run_Middle (Argument (2), 'c');
         else
            Usage_Error ("expected: ahc core FILE.hs");
         end if;
      elsif Command = "check" then
         if Argument_Count = 2 then
            Run_Middle (Argument (2), 't');
         else
            Usage_Error ("expected: ahc check FILE.hs");
         end if;
      else
         Usage_Error ("unknown command '" & Command & "'");
      end if;
   end;
end AHC_Main;
