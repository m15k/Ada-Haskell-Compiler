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
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Ada.Containers.Hashed_Maps;
with Ada.Containers.Vectors;
with Ada.Directories;

with AHC.Builtins;
with AHC.CodeGen;
with AHC.Core.Printer;
with AHC.Desugar;
with AHC.Diagnostics;
with AHC.Elaborate;
with AHC.Fixity;
with AHC.Kinds;
with AHC.Layout;
with AHC.Modules;
with AHC.Lexer;
with AHC.Names;
with AHC.Parser;
with AHC.Prelude_Core;
with AHC.Refine;
with AHC.Rename;
with AHC.Source_Text;
with AHC.Syntax.Printer;
with AHC.Tokens;
with AHC.Typechecker;

procedure AHC_Main is
   use Ada.Command_Line;
   use Ada.Text_IO;
   use type AHC.Names.Name_Id;

   procedure Print_Usage (Target : File_Type) is
   begin
      Put_Line (Target, "usage: ahc --version");
      Put_Line (Target, "       ahc lex [--layout] FILE.hs");
      Put_Line (Target, "       ahc parse FILE.hs");
      Put_Line (Target, "       ahc core FILE.hs");
      Put_Line (Target, "       ahc check FILE.hs");
      Put_Line (Target, "       ahc emit FILE.hs OUT [--unchecked]"
                        & "   (writes OUT.c)");
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
   --  Mode: 'c' = Core dump, 't' = types, 'b' = build executable.
   procedure Run_Middle
     (Path     : String; Mode : Character; Out_Path : String := "";
      Refined  : Boolean := True) is
      Text   : AHC.Source_Text.Source;
      Table  : AHC.Names.Name_Table;
      Bag    : AHC.Diagnostics.Diagnostic_Bag;
      M      : AHC.Core.Core_Module;
      Env    : AHC.Builtins.Global_Env;
      Sigs   : AHC.Kinds.Sig_Maps.Map;
      Annos  : AHC.Kinds.Anno_Maps.Map;
      Prelude_Groups : Natural := 0;

      Reg : aliased AHC.Modules.Registry;

      --  The module graph, discovered from the root file's imports
      --  (Report ch. 5): A.B.C lives in A/B/C.hs beside the root.
      type Arena_Ref is access AHC.Syntax.Module_Arena;
      type Loaded is record
         Name  : AHC.Names.Name_Id := AHC.Names.No_Name;
         Path  : Ada.Strings.Unbounded.Unbounded_String;
         Text  : AHC.Source_Text.Source;
         Ref   : Arena_Ref;
      end record;
      package Loaded_Vectors is new Ada.Containers.Vectors
        (Positive, Loaded);
      Order : Loaded_Vectors.Vector;   --  dependencies first
      Failed : Boolean := False;

      Root_Dir : constant String :=
        Ada.Directories.Containing_Directory (Path);

      function Module_Path (Name : String) return String is
         P : String := Name;
      begin
         for I in P'Range loop
            if P (I) = '.' then
               P (I) := '/';
            end if;
         end loop;
         return Root_Dir & "/" & P & ".hs";
      end Module_Path;

      Prelude_N : AHC.Names.Real_Name_Id;

      --  DFS with an on-stack set: postorder is dependency order,
      --  a back edge is an import cycle.
      type St is (Unseen, Loading, Done);
      package State_Maps is new Ada.Containers.Hashed_Maps
        (AHC.Names.Name_Id, St, AHC.Fixity.Name_Hash, AHC.Names."=");
      States : State_Maps.Map;

      procedure Load (File : String; Mod_Name : AHC.Names.Name_Id);

      procedure Load (File : String; Mod_Name : AHC.Names.Name_Id) is
         L : Loaded;
         L_Stream : AHC.Tokens.Token_Vectors.Vector;
      begin
         if Failed then
            return;
         end if;
         States.Include (Mod_Name, Loading);
         begin
            L.Text := AHC.Source_Text.Load_File (File);
         exception
            when Ada.IO_Exceptions.Name_Error =>
               Put_Line (Standard_Error,
                         "ahc: cannot find module '"
                         & Table.Text
                             (AHC.Names.Real_Name_Id (Mod_Name))
                         & "' (looked for " & File & ")");
               Failed := True;
               return;
         end;
         L.Name := Mod_Name;
         L.Path := Ada.Strings.Unbounded.To_Unbounded_String (File);
         L.Ref := new AHC.Syntax.Module_Arena;
         AHC.Lexer.Scan (L.Text, Table, Bag, L_Stream);
         AHC.Parser.Parse_Module (L_Stream, Table, Bag, L.Ref.all);
         if Bag.Has_Errors then
            Bag.Print_All (L.Text);
            Failed := True;
            return;
         end if;
         for Imp of L.Ref.Imports loop
            if Imp.Module /= AHC.Names.Name_Id (Prelude_N) then
               declare
                  C : constant State_Maps.Cursor :=
                    States.Find (Imp.Module);
               begin
                  if State_Maps.Has_Element (C) then
                     if State_Maps.Element (C) = Loading then
                        Put_Line (Standard_Error,
                                  "ahc: import cycle through '"
                                  & Table.Text
                                      (AHC.Names.Real_Name_Id
                                         (Imp.Module)) & "'");
                        Failed := True;
                        return;
                     end if;
                  else
                     Load (Module_Path
                             (Table.Text (AHC.Names.Real_Name_Id
                                            (Imp.Module))),
                           Imp.Module);
                     if Failed then
                        return;
                     end if;
                  end if;
               end;
            end if;
         end loop;
         States.Include (Mod_Name, Done);
         Order.Append (L);
      end Load;

      --  Snapshot the flat environment as the registry Base.
      procedure Snapshot_Base is
      begin
         Reg.Base.Values := Env.Values;
         Reg.Base.TyCons := Env.TyCons;
         Reg.Base.DataCons := Env.DataCons;
         Reg.Base.Classes := Env.Classes;
         Reg.Base.Synonyms.Clear;
         declare
            C : AHC.Builtins.Syn_Maps.Cursor := Env.Synonyms.First;
         begin
            while AHC.Builtins.Syn_Maps.Has_Element (C) loop
               Reg.Base.Synonyms.Include
                 (AHC.Builtins.Syn_Maps.Key (C),
                  AHC.Fixity.Fixity_Info'(others => <>));
               AHC.Builtins.Syn_Maps.Next (C);
            end loop;
         end;
      end Snapshot_Base;
   begin
      Prelude_N := Table.Intern ("Prelude");
      begin
         Text := AHC.Source_Text.Load_File (Path);
      exception
         when Ada.IO_Exceptions.Name_Error =>
            Usage_Error ("cannot open '" & Path & "'");
            return;
      end;

      --  Discover and parse the module graph rooted at Path.
      declare
         Root_Stream : AHC.Tokens.Token_Vectors.Vector;
         Root : Loaded;
      begin
         Root.Text := Text;
         Root.Path := Ada.Strings.Unbounded.To_Unbounded_String (Path);
         Root.Ref := new AHC.Syntax.Module_Arena;
         AHC.Lexer.Scan (Text, Table, Bag, Root_Stream);
         AHC.Parser.Parse_Module (Root_Stream, Table, Bag,
                                  Root.Ref.all);
         Root.Name :=
           (if Root.Ref.Module_Name = AHC.Names.No_Name
            then AHC.Names.Name_Id (Table.Intern ("Main"))
            else Root.Ref.Module_Name);
         if not Bag.Has_Errors then
            States.Include (Root.Name, Loading);
            for Imp of Root.Ref.Imports loop
               if Imp.Module /= AHC.Names.Name_Id (Prelude_N)
                 and then not States.Contains (Imp.Module)
               then
                  Load (Module_Path
                          (Table.Text (AHC.Names.Real_Name_Id
                                         (Imp.Module))),
                        Imp.Module);
               end if;
            end loop;
            Order.Append (Root);
         end if;
         if Failed then
            Set_Exit_Status (1);
            return;
         end if;
      end;

      if not Bag.Has_Errors then
         AHC.Builtins.Install (M, Table, Env);

         --  Compile prelude/Prelude.hs into the same module first, so
         --  its definitions are in scope for the user module.
         declare
            P_Path : constant String := "prelude/Prelude.hs";
            P_Text : AHC.Source_Text.Source;
            P_Stream : AHC.Tokens.Token_Vectors.Vector;
            P_Arena : AHC.Syntax.Module_Arena;
            P_Res : AHC.Rename.Resolutions;
            P_Preds : AHC.Kinds.Pred_Vectors.Vector;
            Loaded : Boolean := True;
         begin
            begin
               P_Text := AHC.Source_Text.Load_File (P_Path);
            exception
               when Ada.IO_Exceptions.Name_Error =>
                  Loaded := False;
            end;
            if Loaded then
               AHC.Lexer.Scan (P_Text, Table, Bag, P_Stream);
               AHC.Parser.Parse_Module (P_Stream, Table, Bag, P_Arena);
               AHC.Fixity.Resolve_Module (P_Arena, Table, Bag);
               if not Bag.Has_Errors then
                  AHC.Rename.Resolve_Module
                    (P_Arena, Table, Bag, M, Env, P_Res);
                  AHC.Kinds.Check_Module
                    (P_Arena, P_Res, Table, Bag, M, Env, Sigs, Annos,
                     P_Preds);
               end if;
               if not Bag.Has_Errors then
                  AHC.Desugar.Desugar_Module
                    (P_Arena, P_Res, Table, Bag, M, Env, Sigs, Annos,
                     P_Preds);
               end if;
               if Bag.Has_Errors then
                  Put_Line (Standard_Error,
                            "ahc: internal: the Prelude failed to"
                            & " compile");
                  Bag.Print_All (P_Text);
                  Set_Exit_Status (1);
                  return;
               end if;
            end if;
         end;
         Prelude_Groups := Natural (M.Top_Binds.Length);
         Snapshot_Base;

         --  Frontend for every module, dependencies first, into the
         --  shared Core module. Each gets fresh resolutions,
         --  annotation and predicate tables (their keys are
         --  per-arena); signatures are Core-var keyed and shared.
         for L of Order loop
            exit when Bag.Has_Errors;
            declare
               L_Res   : AHC.Rename.Resolutions;
               L_Annos : AHC.Kinds.Anno_Maps.Map;
               L_Preds : AHC.Kinds.Pred_Vectors.Vector;
               Tops     : aliased AHC.Fixity.Fixity_Maps.Map;
               Base_Fix : AHC.Fixity.Fixity_Maps.Map;
            begin
               for Imp of L.Ref.Imports loop
                  declare
                     MI : constant Natural :=
                       AHC.Modules.Find (Reg, Imp.Module);
                  begin
                     if MI /= 0 then
                        declare
                           C : AHC.Fixity.Fixity_Maps.Cursor :=
                             Reg.Mods (MI).Exports.Fixities.First;
                        begin
                           while AHC.Fixity.Fixity_Maps.Has_Element
                             (C)
                           loop
                              Base_Fix.Include
                                (AHC.Fixity.Fixity_Maps.Key (C),
                                 AHC.Fixity.Fixity_Maps.Element (C));
                              AHC.Fixity.Fixity_Maps.Next (C);
                           end loop;
                        end;
                     end if;
                  end;
               end loop;
               AHC.Fixity.Resolve_Module
                 (L.Ref.all, Table, Bag, Base_Fix,
                  Tops'Unchecked_Access);
               if not Bag.Has_Errors then
                  AHC.Rename.Resolve_Module
                    (L.Ref.all, Table, Bag, M, Env, L_Res,
                     Reg'Unchecked_Access, Tops);
               end if;
               if not Bag.Has_Errors then
                  AHC.Kinds.Check_Module
                    (L.Ref.all, L_Res, Table, Bag, M, Env, Sigs,
                     L_Annos, L_Preds);
               end if;
               if not Bag.Has_Errors then
                  AHC.Desugar.Desugar_Module
                    (L.Ref.all, L_Res, Table, Bag, M, Env, Sigs,
                     L_Annos, L_Preds);
               end if;
               if Bag.Has_Errors then
                  Bag.Print_All (L.Text);
                  Set_Exit_Status (1);
                  return;
               end if;
            end;
         end loop;
      end if;
      if not Bag.Has_Errors then
         if Mode = 't' then
            AHC.Typechecker.Check_Module (Table, Bag, M, Env, Sigs);
            if not Bag.Has_Errors then
               AHC.Elaborate.Elaborate_Dictionaries (Table, Bag, M, Env);
            end if;
            if not Bag.Has_Errors then
               for GI in Prelude_Groups + 1 ..
                         M.Top_Binds.Last_Index
               loop
                  for B of M.Top_Binds (GI).Binds loop
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
         elsif Mode = 'b' then
            AHC.Typechecker.Check_Module (Table, Bag, M, Env, Sigs);
            if not Bag.Has_Errors then
               AHC.Elaborate.Elaborate_Dictionaries (Table, Bag, M, Env);
               declare
                  Prims : AHC.Prelude_Core.Prim_Maps.Map;
                  C_Src : Ada.Text_IO.File_Type;
                  C_Path : constant String := Out_Path & ".c";
               begin
                  AHC.Refine.Insert_Checks
                    (Table, M, Sigs, Prims, Checks_Enabled => Refined);
                  AHC.Prelude_Core.Install_Bodies (Table, M, Env, Prims);
                  Create (C_Src, Out_File, C_Path);
                  Put (C_Src,
                       Ada.Strings.Unbounded.To_String
                         (AHC.CodeGen.Emit (Table, M, Env, Prims)));
                  Close (C_Src);
                  Put_Line ("wrote " & C_Path);
               end;
            end if;
         else
            AHC.Typechecker.Check_Module (Table, Bag, M, Env, Sigs);
            if not Bag.Has_Errors then
               AHC.Elaborate.Elaborate_Dictionaries (Table, Bag, M, Env);
               declare
                  Prims : AHC.Prelude_Core.Prim_Maps.Map;
               begin
                  AHC.Refine.Insert_Checks (Table, M, Sigs, Prims);
               end;
            end if;
            Put (AHC.Core.Printer.Dump
                   (M, Table, From_Group => Prelude_Groups + 1));
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
      elsif Command = "emit" then
         if Argument_Count = 3 then
            Run_Middle (Argument (2), 'b', Argument (3));
         elsif Argument_Count = 4
           and then Argument (4) = "--unchecked"
         then
            Run_Middle (Argument (2), 'b', Argument (3),
                        Refined => False);
         else
            Usage_Error
              ("expected: ahc emit FILE.hs OUT [--unchecked]");
         end if;
      else
         Usage_Error ("unknown command '" & Command & "'");
      end if;
   end;
end AHC_Main;
