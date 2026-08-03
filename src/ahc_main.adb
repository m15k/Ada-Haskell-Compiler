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
with Ada.Environment_Variables;

with AHC.Bindgen;
with AHC.Build;
with AHC.Builtins;
with AHC.CodeGen;
with AHC.Contracts;
with AHC.Core.Printer;
with AHC.Desugar;
with AHC.Diagnostics;
with AHC.Elaborate;
with AHC.Fixity;
with AHC.Kinds;
with AHC.Layout;
with AHC.Manifest;
with AHC.Paths;
with AHC.Modules;
with AHC.Optimizer;
with AHC.Lexer;
with AHC.Names;
with AHC.Repl;
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
      Put_Line (Target, "       ahc build [--lib] FILE.hs [OUT]"
                & " [--unchecked] [--no-opt] [-o OUT] [-j N] [-v]");
      Put_Line (Target, "       ahc emit FILE.hs OUT"
                & " [--unchecked|--no-opt|--lib]"
                        & "   (writes OUT.c)");
      Put_Line (Target, "       ahc bindgen cpp|rust|go|ghc"
                & " FILE.hs OUT");
      Put_Line (Target, "       ahc repl");
   end Print_Usage;

   --  Set by every failure path that precedes or aborts emit
   --  (Usage_Error included - a root file that fails to open goes
   --  through it), so the build command can tell whether emit
   --  succeeded: Ada.Command_Line's exit status is write-only.
   Middle_Failed : Boolean := False;

   procedure Usage_Error (Message : String) is
   begin
      Put_Line (Standard_Error, "ahc: " & Message);
      Print_Usage (Standard_Error);
      Set_Exit_Status (2);
      Middle_Failed := True;
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
      Refined  : Boolean := True; Optimize : Boolean := True;
      Lib      : Boolean := False;
      Bindgen_Lang : String := "";
      Quiet    : Boolean := False) is
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

      --  Separate code generation: which top-level bind groups (and
      --  which instances) each module contributed, so codegen can
      --  partition the program into per-unit C files with stable
      --  symbols.
      type Unit_Span is record
         Name : Ada.Strings.Unbounded.Unbounded_String;
         From_Group, To_Group : Natural := 0;
         From_Inst, To_Inst   : Natural := 0;
         From_Foreign, To_Foreign : Natural := 0;
         Tag : Natural := 0;   --  diagnostic origin (Diag_Texts idx)
      end record;
      package Unit_Span_Vectors is new Ada.Containers.Vectors
        (Positive, Unit_Span);
      Unit_Spans : Unit_Span_Vectors.Vector;

      --  Diagnostic origin table: tag -> that module's source text,
      --  so cross-module diagnostics print against the RIGHT file.
      package Text_Vectors is new Ada.Containers.Vectors
        (Positive, AHC.Source_Text.Source,
         "=" => AHC.Source_Text."=");
      Diag_Texts : Text_Vectors.Vector;
      Prelude_Tag : Natural := 0;
      Group_Origins, Inst_Origins :
        AHC.Diagnostics.Origin_Vectors.Vector;

      --  {-# OPTIONS_AHC_LINK <flags> #-} pragmas accumulate here;
      --  `ahc emit` writes them to OUT.build/link_flags so the build
      --  script can pass them to the linker. GHC only warns on the
      --  unknown pragma, so FFI source stays oracle-portable.
      Link_Flags : Ada.Strings.Unbounded.Unbounded_String;

      procedure Collect_Link_Flags
        (Src   : AHC.Source_Text.Source;
         Spans : AHC.Lexer.Span_Vectors.Vector)
      is
         Key : constant String := "OPTIONS_AHC_LINK";

         function Is_Space (C : Character) return Boolean
         is (C in ' ' | ASCII.HT | ASCII.LF | ASCII.CR);
      begin
         for Sp of Spans loop
            declare
               From : constant Positive := Positive (Sp.Start) + 3;
               To   : constant Natural  := Natural (Sp.Stop) - 4;
            begin
               if To >= From then
                  declare
                     Inner : constant String := AHC.Source_Text.Slice
                       (Src,
                        AHC.Source_Text.Byte_Offset (From),
                        AHC.Source_Text.Byte_Offset (To));
                     I : Positive := Inner'First;
                     J : Natural := Inner'Last;
                  begin
                     while I <= J and then Is_Space (Inner (I)) loop
                        I := I + 1;
                     end loop;
                     while J >= I and then Is_Space (Inner (J)) loop
                        J := J - 1;
                     end loop;
                     if J - I + 1 > Key'Length
                       and then Inner (I .. I + Key'Length - 1) = Key
                       and then Is_Space (Inner (I + Key'Length))
                     then
                        Ada.Strings.Unbounded.Append
                          (Link_Flags,
                           " " & Inner (I + Key'Length + 1 .. J));
                     end if;
                  end;
               end if;
            end;
         end loop;
      end Collect_Link_Flags;

      --  Function contracts (PRE/POST pragmas): collected per
      --  module, signatures injected after the frontend, wrapping
      --  done by AHC.Refine.
      All_Contracts : AHC.Contracts.Contract_Vectors.Vector;
      Contract_Map  : AHC.Contracts.Contract_Maps.Map;

      procedure Print_Diags is
      begin
         for I in 1 .. Bag.Count loop
            declare
               Tag : constant Natural := Bag.Origin_Of (I);
            begin
               if Tag in 1 .. Diag_Texts.Last_Index then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     Bag.Render (Diag_Texts (Tag), I));
               else
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     Bag.Render (Text, I));
               end if;
            end;
         end loop;
      end Print_Diags;

      Root_Dir : constant String :=
        Ada.Directories.Containing_Directory (Path);

      --  Resolve a module name to a file: beside the root file
      --  first, then the stdlib cascade ($AHC_LIB, the CWD's lib/,
      --  the installation's lib/ - AHC.Paths). Returns the first
      --  existing candidate, or the root-relative path for the
      --  error message.
      function Module_Path (Name : String) return String is
         P : String := Name;
      begin
         for I in P'Range loop
            if P (I) = '.' then
               P (I) := '/';
            end if;
         end loop;
         declare
            Local : constant String := Root_Dir & "/" & P & ".hs";
         begin
            if Ada.Directories.Exists (Local) then
               return Local;
            end if;
            declare
               Std : constant String :=
                 AHC.Paths.Stdlib_File (P & ".hs");
            begin
               if Std /= "" then
                  return Std;
               end if;
            end;
            return Local;
         end;
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
         declare
            L_Pragmas : AHC.Lexer.Span_Vectors.Vector;
         begin
            AHC.Lexer.Scan (L.Text, Table, Bag, L_Stream, L_Pragmas);
            AHC.Parser.Parse_Module (L_Stream, Table, Bag, L.Ref.all);
            Collect_Link_Flags (L.Text, L_Pragmas);
            if not Bag.Has_Errors then
               --  PRE/POST contract pragmas become hidden top-level
               --  bindings in this module's arena.
               AHC.Contracts.Collect
                 (L.Text, L_Pragmas, Table, Bag, L.Ref.all,
                  All_Contracts);
            end if;
         end;
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
         declare
            R_Pragmas : AHC.Lexer.Span_Vectors.Vector;
         begin
            AHC.Lexer.Scan (Text, Table, Bag, Root_Stream, R_Pragmas);
            AHC.Parser.Parse_Module (Root_Stream, Table, Bag,
                                     Root.Ref.all);
            Collect_Link_Flags (Text, R_Pragmas);
            if not Bag.Has_Errors then
               AHC.Contracts.Collect
                 (Text, R_Pragmas, Table, Bag, Root.Ref.all,
                  All_Contracts);
            end if;
         end;
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
            Middle_Failed := True;
            Set_Exit_Status (1);
            return;
         end if;
      end;

      if not Bag.Has_Errors then
         AHC.Builtins.Install (M, Table, Env);

         --  Compile prelude/Prelude.hs into the same module first, so
         --  its definitions are in scope for the user module.
         declare
            P_Path : constant String := AHC.Paths.Prelude_File;
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
               Diag_Texts.Append (P_Text);
               Prelude_Tag := Diag_Texts.Last_Index;
               Bag.Set_Origin (Prelude_Tag);
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
                  Middle_Failed := True;
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
         --  The root module (appended last) additionally gets
         --  exhaustiveness/redundancy warnings.
         for LI in 1 .. Order.Last_Index loop
            exit when Bag.Has_Errors;
            declare
               L : Loaded renames Order (LI);
               Is_Root : constant Boolean :=
                 LI = Order.Last_Index;
               G0 : constant Natural :=
                 Natural (M.Top_Binds.Length);
               I0 : constant Natural :=
                 Natural (M.Last_Instance);
               F0 : constant Natural :=
                 Natural (M.Foreigns.Length);
               L_Tag : Natural;
               L_Res   : AHC.Rename.Resolutions;
               L_Annos : AHC.Kinds.Anno_Maps.Map;
               L_Preds : AHC.Kinds.Pred_Vectors.Vector;
               Tops     : aliased AHC.Fixity.Fixity_Maps.Map;
               Base_Fix : AHC.Fixity.Fixity_Maps.Map;
            begin
               Diag_Texts.Append (L.Text);
               L_Tag := Diag_Texts.Last_Index;
               Bag.Set_Origin (L_Tag);
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
                     L_Annos, L_Preds,
                     Warn_Matches => Is_Root);
               end if;
               Unit_Spans.Append
                 (Unit_Span'
                    (Name => Ada.Strings.Unbounded.
                       To_Unbounded_String
                         (Table.Text
                            (AHC.Names.Real_Name_Id (L.Name))),
                     From_Group => G0 + 1,
                     To_Group => Natural (M.Top_Binds.Length),
                     From_Inst => I0 + 1,
                     To_Inst => Natural (M.Last_Instance),
                     From_Foreign => F0 + 1,
                     To_Foreign => Natural (M.Foreigns.Length),
                     Tag => L_Tag));
               if Bag.Has_Errors then
                  Bag.Print_All (L.Text);
                  Middle_Failed := True;
                  Set_Exit_Status (1);
                  return;
               end if;
            end;
         end loop;
      end if;

      --  Per-group and per-instance diagnostic origins for the
      --  whole-program phases; fallback = the root module's text.
      declare
         Root_Tag : constant Natural := Diag_Texts.Last_Index;
      begin
         Bag.Set_Origin (Root_Tag);
         for GI in 1 .. Natural (M.Top_Binds.Length) loop
            declare
               Tag : Natural := Prelude_Tag;
            begin
               for Sp of Unit_Spans loop
                  if GI in Sp.From_Group .. Sp.To_Group then
                     Tag := Sp.Tag;
                  end if;
               end loop;
               Group_Origins.Append (Tag);
            end;
         end loop;
         for II in 1 .. Natural (M.Last_Instance) loop
            declare
               Tag : Natural := Prelude_Tag;
            begin
               for Sp of Unit_Spans loop
                  if II in Sp.From_Inst .. Sp.To_Inst then
                     Tag := Sp.Tag;
                  end if;
               end loop;
               Inst_Origins.Append (Tag);
            end;
         end loop;
      end;

      --  Contracts: each contract binding's signature is DERIVED
      --  from the contracted function's own - its tyvars and
      --  context, its argument spine, then Bool (POST inserts the
      --  result type). The typechecker then checks the parsed
      --  contract lambda against it like any signatured binding.
      if not Bag.Has_Errors then
         for C of All_Contracts loop
            declare
               use type AHC.Core.Scheme_Id;
               use type AHC.Core.Type_Kind;
               use AHC.Contracts;
               Fn_C : constant AHC.Builtins.Var_Maps.Cursor :=
                 Env.Values.Find (C.Fn_Name);
               Bd_C : constant AHC.Builtins.Var_Maps.Cursor :=
                 Env.Values.Find (C.Bind_Name);
               Fn_Text : constant String :=
                 Table.Text (AHC.Names.Real_Name_Id (C.Fn_Name));
            begin
               if not AHC.Builtins.Var_Maps.Has_Element (Fn_C) then
                  Bag.Add (AHC.Diagnostics.Error,
                           AHC.Diagnostics.Rename_Out_Of_Scope,
                           C.Span,
                           "contract for unknown function '"
                           & Fn_Text & "'");
               elsif AHC.Builtins.Var_Maps.Has_Element (Bd_C) then
                  declare
                     FnV : constant AHC.Core.Real_Var_Id :=
                       AHC.Builtins.Var_Maps.Element (Fn_C);
                     BdV : constant AHC.Core.Real_Var_Id :=
                       AHC.Builtins.Var_Maps.Element (Bd_C);
                     Sig_C : constant AHC.Kinds.Sig_Maps.Cursor :=
                       Sigs.Find (FnV);
                  begin
                     if not AHC.Kinds.Sig_Maps.Has_Element (Sig_C)
                       or else AHC.Kinds.Sig_Maps.Element (Sig_C) =
                                 AHC.Core.No_Scheme
                     then
                        Bag.Add
                          (AHC.Diagnostics.Error,
                           AHC.Diagnostics.Type_Signature_Too_General,
                           C.Span,
                           "contract requires a type signature for '"
                           & Fn_Text & "'");
                     else
                        declare
                           Sch : constant AHC.Core.Scheme :=
                             M.Node (AHC.Core.Real_Scheme_Id
                               (AHC.Kinds.Sig_Maps.Element (Sig_C)));
                           Args : AHC.Core.Type_Id_Vectors.Vector;
                           R : AHC.Core.Real_Type_Id :=
                             AHC.Core.Real_Type_Id (Sch.S_Body);
                           Body_T : AHC.Core.Real_Type_Id;
                        begin
                           while M.Node (R).Kind = AHC.Core.TFun_T
                           loop
                              Args.Append
                                (AHC.Core.Type_Id
                                   (M.Node (R).From));
                              R := M.Node (R).To;
                           end loop;
                           if C.Kind = Pre_C
                             and then Args.Is_Empty
                           then
                              Bag.Add
                                (AHC.Diagnostics.Error,
                                 AHC.Diagnostics.Parse_Error,
                                 C.Span,
                                 "PRE contract on a value binding"
                                 & " ('" & Fn_Text
                                 & "' takes no arguments)");
                           else
                              Body_T := M.Add
                                (AHC.Core.Type_Node'
                                   (Kind => AHC.Core.TCon_T,
                                    Con => AHC.Core.Real_TyCon_Id
                                      (Env.Bool_TC),
                                    Refine =>
                                      AHC.Core.No_Refinement));
                              if C.Kind = Post_C then
                                 Body_T := M.Add
                                   (AHC.Core.Type_Node'
                                      (Kind => AHC.Core.TFun_T,
                                       From => R,
                                       To => Body_T));
                              end if;
                              for I in reverse 1 .. Args.Last_Index
                              loop
                                 Body_T := M.Add
                                   (AHC.Core.Type_Node'
                                      (Kind => AHC.Core.TFun_T,
                                       From =>
                                         AHC.Core.Real_Type_Id
                                           (Args.Element (I)),
                                       To => Body_T));
                              end loop;
                              Sigs.Include
                                (BdV,
                                 AHC.Core.Scheme_Id
                                   (M.Add (AHC.Core.Scheme'
                                      (Tvs => Sch.Tvs,
                                       Context => Sch.Context,
                                       S_Body =>
                                         AHC.Core.Type_Id
                                           (Body_T)))));
                              declare
                                 CB : Contract_Binds;
                                 Cur : constant
                                   Contract_Maps.Cursor :=
                                     Contract_Map.Find (FnV);
                              begin
                                 if Contract_Maps.Has_Element (Cur)
                                 then
                                    CB := Contract_Maps.Element
                                      (Cur);
                                 end if;
                                 if C.Kind = Pre_C then
                                    CB.Pre_V :=
                                      AHC.Core.Var_Id (BdV);
                                 else
                                    CB.Post_V :=
                                      AHC.Core.Var_Id (BdV);
                                 end if;
                                 Contract_Map.Include (FnV, CB);
                              end;
                           end if;
                        end;
                     end if;
                  end;
               end if;
            end;
         end loop;
      end if;

      if not Bag.Has_Errors then
         if Mode = 't' then
            AHC.Typechecker.Check_Module
              (Table, Bag, M, Env, Sigs, Group_Origins, Inst_Origins);
            if not Bag.Has_Errors then
               AHC.Elaborate.Elaborate_Dictionaries
                 (Table, Bag, M, Env, Inst_Origins);
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
            AHC.Typechecker.Check_Module
              (Table, Bag, M, Env, Sigs, Group_Origins, Inst_Origins);
            if not Bag.Has_Errors then
               AHC.Elaborate.Elaborate_Dictionaries
                 (Table, Bag, M, Env, Inst_Origins);
               declare
                  use Ada.Strings.Unbounded;
                  Prims : AHC.Prelude_Core.Prim_Maps.Map;
                  Build_Dir : constant String := Out_Path & ".build";

                  --  Elaboration binds instance dictionaries as new
                  --  top-level groups; attribute each dict global to
                  --  the module that declared its instance.
                  package Var_UStr_Maps is new
                    Ada.Containers.Hashed_Maps
                      (AHC.Core.Real_Var_Id, Unbounded_String,
                       Hash => AHC.Rename.Var_Hash,
                       Equivalent_Keys => AHC.Core."=");
                  Dict_Owner : Var_UStr_Maps.Map;

                  Owners   : AHC.CodeGen.UStr_Vectors.Vector;
                  F_Owners : AHC.CodeGen.UStr_Vectors.Vector;
                  Units  : AHC.CodeGen.UStr_Vectors.Vector;
                  Header : Unbounded_String;
                  Exports_H : Unbounded_String;
                  Files  : AHC.CodeGen.Unit_File_Vectors.Vector;

                  function Sanitize (S : String) return String is
                     R : String := S;
                  begin
                     for C of R loop
                        if C not in 'A' .. 'Z' | 'a' .. 'z'
                                    | '0' .. '9'
                        then
                           C := '_';
                        end if;
                     end loop;
                     return R;
                  end Sanitize;

                  function Img2 (N : Natural) return String is
                     S : constant String := N'Image;
                     T : constant String := S (2 .. S'Last);
                  begin
                     return (if T'Length = 1 then "0" & T else T);
                  end Img2;
               begin
                  --  Wired bodies first: contract discharge (inside
                  --  Insert_Checks) evaluates through the wired
                  --  dictionaries, so they must exist by then.
                  AHC.Prelude_Core.Install_Bodies
                    (Table, M, Env, Prims, Base => Reg.Base.Values);
                  AHC.Refine.Insert_Checks
                    (Table, M, Sigs, Prims, Bag,
                     Checks_Enabled => Refined,
                     Contracts => Contract_Map);
                  if Optimize then
                     declare
                        Rounds : Natural;
                     begin
                        AHC.Optimizer.Optimize (M, Rounds);
                     end;
                  end if;

                  for Sp of Unit_Spans loop
                     for II in Sp.From_Inst .. Sp.To_Inst loop
                        declare
                           use type AHC.Core.Var_Id;
                           DG : constant AHC.Core.Var_Id :=
                             M.Info
                               (AHC.Core.Real_Instance_Id (II))
                               .Dict_Global;
                        begin
                           if DG /= AHC.Core.No_Var then
                              Dict_Owner.Include
                                (AHC.Core.Real_Var_Id (DG),
                                 Sp.Name);
                           end if;
                        end;
                     end loop;
                  end loop;

                  --  One owner entry per group: Prelude by default
                  --  (wired prelude, prim bodies), the declaring
                  --  module for its frontend groups, and the
                  --  instance's module for elaborated dictionaries.
                  for GI in 1 .. Natural (M.Top_Binds.Length) loop
                     declare
                        Name : Unbounded_String :=
                          To_Unbounded_String ("Prelude");
                     begin
                        for Sp of Unit_Spans loop
                           if GI in Sp.From_Group .. Sp.To_Group then
                              Name := Sp.Name;
                           end if;
                        end loop;
                        if not M.Top_Binds (GI).Binds.Is_Empty then
                           declare
                              B0 : constant AHC.Core.Real_Var_Id :=
                                M.Top_Binds (GI).Binds (1).Binder;
                              C : constant Var_UStr_Maps.Cursor :=
                                Dict_Owner.Find (B0);
                           begin
                              if Var_UStr_Maps.Has_Element (C) then
                                 Name := Var_UStr_Maps.Element (C);
                              end if;
                           end;
                        end if;
                        Owners.Append (Name);
                     end;
                  end loop;

                  --  One owner entry per foreign import, from the
                  --  same spans.
                  for FI in 1 .. Natural (M.Foreigns.Length) loop
                     declare
                        Name : Unbounded_String :=
                          To_Unbounded_String ("Prelude");
                     begin
                        for Sp of Unit_Spans loop
                           if FI in Sp.From_Foreign .. Sp.To_Foreign
                           then
                              Name := Sp.Name;
                           end if;
                        end loop;
                        F_Owners.Append (Name);
                     end;
                  end loop;

                  Units.Append (To_Unbounded_String ("Prelude"));
                  for Sp of Unit_Spans loop
                     if To_String (Sp.Name) /= "Prelude" then
                        Units.Append (Sp.Name);
                     end if;
                  end loop;

                  AHC.CodeGen.Emit_Units
                    (Table, M, Env, Prims, Owners, F_Owners, Units,
                     Lib_Mode => Lib,
                     Header => Header, Exports_H => Exports_H,
                     Files => Files);

                  Ada.Directories.Create_Path (Build_Dir);
                  declare
                     Search : Ada.Directories.Search_Type;
                     Ent : Ada.Directories.Directory_Entry_Type;
                  begin
                     Ada.Directories.Start_Search
                       (Search, Build_Dir, "*.c");
                     while Ada.Directories.More_Entries (Search) loop
                        Ada.Directories.Get_Next_Entry (Search, Ent);
                        Ada.Directories.Delete_File
                          (Ada.Directories.Full_Name (Ent));
                     end loop;
                     Ada.Directories.End_Search (Search);
                  end;
                  declare
                     F : Ada.Text_IO.File_Type;
                  begin
                     Create (F, Out_File,
                             Build_Dir & "/ahc_prog.h");
                     Put (F, To_String (Header));
                     Close (F);
                     for I in 1 .. Files.Last_Index loop
                        Create (F, Out_File,
                                Build_Dir & "/u" & Img2 (I) & "_"
                                & Sanitize
                                    (To_String (Files (I).Name))
                                & ".c");
                        Put (F, To_String (Files (I).Text));
                        Close (F);
                     end loop;
                     Create (F, Out_File,
                             Build_Dir & "/link_flags");
                     Put (F, To_String (Link_Flags));
                     Close (F);
                     Create (F, Out_File,
                             Build_Dir & "/ahc_exports.h");
                     Put (F, To_String (Exports_H));
                     Close (F);
                     if Bindgen_Lang /= "" then
                        Create (F, Out_File,
                                Build_Dir & "/"
                                & AHC.Bindgen.File_Name
                                    (Bindgen_Lang));
                        Put (F, To_String
                               (AHC.Bindgen.Generate
                                  (Bindgen_Lang,
                                   Ada.Directories.Simple_Name
                                     (Out_Path),
                                   M.Foreign_Exports, Table)));
                        Close (F);
                        Put_Line
                          ("wrote " & Build_Dir & "/"
                           & AHC.Bindgen.File_Name (Bindgen_Lang));
                     end if;
                  end;
                  if not Quiet then
                     Put_Line ("wrote " & Build_Dir);
                  end if;
               end;
            end if;
         else
            AHC.Typechecker.Check_Module
              (Table, Bag, M, Env, Sigs, Group_Origins, Inst_Origins);
            if not Bag.Has_Errors then
               AHC.Elaborate.Elaborate_Dictionaries
                 (Table, Bag, M, Env, Inst_Origins);
               declare
                  Prims : AHC.Prelude_Core.Prim_Maps.Map;
               begin
                  AHC.Refine.Insert_Checks
                    (Table, M, Sigs, Prims, Bag,
                     Contracts => Contract_Map);
               end;
            end if;
            Put (AHC.Core.Printer.Dump
                   (M, Table, From_Group => Prelude_Groups + 1));
         end if;
      end if;

      Print_Diags;
      if Bag.Has_Errors then
         Middle_Failed := True;
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
      elsif Command = "repl" then
         if Argument_Count = 1 then
            AHC.Repl.Run;
         else
            Usage_Error ("expected: ahc repl");
         end if;
      elsif Command = "check" then
         if Argument_Count = 2 then
            Run_Middle (Argument (2), 't');
         else
            Usage_Error ("expected: ahc check FILE.hs");
         end if;
      elsif Command = "bindgen" then
         if Argument_Count = 4
           and then AHC.Bindgen.Supported (Argument (2))
         then
            Run_Middle (Argument (3), 'b', Argument (4),
                        Lib => True,
                        Bindgen_Lang => Argument (2));
         else
            Usage_Error
              ("expected: ahc bindgen cpp|rust|go|ghc FILE.hs OUT");
         end if;
      elsif Command = "build" then
         --  emit + compile + link, the script's job done natively:
         --  works from any directory (AHC.Paths) and prints only
         --  "built OUT" on success.
         declare
            use Ada.Strings.Unbounded;
            Src, Dest  : Unbounded_String;
            Refined    : Boolean := True;
            Optimize   : Boolean := True;
            Lib        : Boolean := False;
            Verbose    : Boolean := False;
            Bad         : Boolean := False;
            Expect_Out  : Boolean := False;
            Expect_Jobs : Boolean := False;
            Jobs        : Natural := 0;
            Positional  : Natural := 0;

            function All_Digits (S : String) return Boolean is
              (S'Length > 0
               and then (for all C of S => C in '0' .. '9'));
         begin
            for I in 2 .. Argument_Count loop
               declare
                  A : constant String := Argument (I);
               begin
                  if Expect_Out then
                     Dest := To_Unbounded_String (A);
                     Expect_Out := False;
                  elsif Expect_Jobs then
                     if All_Digits (A) then
                        Jobs := Natural'Value (A);
                     else
                        Bad := True;
                     end if;
                     Expect_Jobs := False;
                  elsif A = "-j" then
                     Expect_Jobs := True;
                  elsif A'Length > 2
                    and then A (A'First .. A'First + 1) = "-j"
                    and then All_Digits (A (A'First + 2 .. A'Last))
                  then
                     Jobs := Natural'Value (A (A'First + 2 .. A'Last));
                  elsif A = "--lib" then
                     Lib := True;
                  elsif A = "--unchecked" then
                     Refined := False;
                  elsif A = "--no-opt" then
                     Optimize := False;
                  elsif A = "-o" then
                     Expect_Out := True;
                  elsif A = "-v" then
                     Verbose := True;
                  elsif A'Length > 0 and then A (A'First) = '-' then
                     Bad := True;
                  else
                     Positional := Positional + 1;
                     case Positional is
                        when 1      => Src := To_Unbounded_String (A);
                        when 2      => Dest := To_Unbounded_String (A);
                        when others => Bad := True;
                     end case;
                  end if;
               end;
            end loop;
            --  No source argument: a project directory names its
            --  root in ahc.toml (M129). CLI flags and environment
            --  variables override manifest values.
            if not Bad and then not Expect_Out
              and then not Expect_Jobs and then Src = ""
              and then Ada.Directories.Exists ("ahc.toml")
            then
               declare
                  Proj : AHC.Manifest.Project;

                  procedure Append_Env (Name, Extra : String) is
                     Cur : constant String :=
                       (if Ada.Environment_Variables.Exists (Name)
                        then Ada.Environment_Variables.Value (Name)
                        else "");
                  begin
                     if Extra /= "" then
                        Ada.Environment_Variables.Set
                          (Name,
                           (if Cur = "" then Extra
                            else Cur & " " & Extra));
                     end if;
                  end Append_Env;
               begin
                  if not AHC.Manifest.Load ("ahc.toml", Proj) then
                     Set_Exit_Status (2);
                     return;
                  end if;
                  Src := Proj.Main;
                  if Dest = "" then
                     Dest := Proj.Output;
                  end if;
                  Refined  := Refined and not Proj.Unchecked;
                  Optimize := Optimize and not Proj.No_Opt;
                  Lib      := Lib or Proj.Lib;
                  if Jobs = 0 then
                     Jobs := Proj.Jobs;
                  end if;
                  Append_Env ("AHC_CFLAGS",
                              To_String (Proj.Cflags));
                  Append_Env ("AHC_LDFLAGS",
                              To_String (Proj.Ldflags));
                  if Proj.GC /= ""
                    and then not Ada.Environment_Variables.Exists
                      ("AHC_GC")
                  then
                     Ada.Environment_Variables.Set
                       ("AHC_GC", To_String (Proj.GC));
                  end if;
               end;
            end if;
            if Bad or else Expect_Out or else Expect_Jobs
              or else Src = ""
            then
               Usage_Error
                 ("expected: ahc build [--lib] FILE.hs [OUT]"
                  & " [--unchecked] [--no-opt] [-o OUT] [-j N] [-v]"
                  & " (or an ahc.toml in the current directory)");
            else
               if Dest = "" then
                  declare
                     S : constant String := To_String (Src);
                  begin
                     if S'Length > 3
                       and then S (S'Last - 2 .. S'Last) = ".hs"
                     then
                        Dest := To_Unbounded_String
                          (S (S'First .. S'Last - 3));
                     else
                        Usage_Error
                          ("cannot infer output name from '" & S
                           & "'; pass OUT or -o OUT");
                        return;
                     end if;
                  end;
               end if;
               Run_Middle (To_String (Src), 'b', To_String (Dest),
                           Refined  => Refined,
                           Optimize => Optimize,
                           Lib      => Lib,
                           Quiet    => True);
               if not Middle_Failed
                 and then not AHC.Build.Compile_And_Link
                   (To_String (Dest),
                    (Lib => Lib, Verbose => Verbose, Jobs => Jobs))
               then
                  Set_Exit_Status (1);
               end if;
            end if;
         end;
      elsif Command = "emit" then
         if Argument_Count >= 3 then
            declare
               Refined  : Boolean := True;
               Optimize : Boolean := True;
               Lib      : Boolean := False;
               Bad      : Boolean := False;
            begin
               for I in 4 .. Argument_Count loop
                  if Argument (I) = "--unchecked" then
                     Refined := False;
                  elsif Argument (I) = "--no-opt" then
                     Optimize := False;
                  elsif Argument (I) = "--lib" then
                     Lib := True;
                  else
                     Bad := True;
                  end if;
               end loop;
               if Bad then
                  Usage_Error
                    ("expected: ahc emit FILE.hs OUT"
                     & " [--unchecked|--no-opt|--lib]");
               else
                  Run_Middle (Argument (2), 'b', Argument (3),
                              Refined => Refined,
                              Optimize => Optimize,
                              Lib => Lib);
               end if;
            end;
         else
            Usage_Error
              ("expected: ahc emit FILE.hs OUT"
               & " [--unchecked|--no-opt|--lib]");
         end if;
      else
         Usage_Error ("unknown command '" & Command & "'");
      end if;
   end;
end AHC_Main;
