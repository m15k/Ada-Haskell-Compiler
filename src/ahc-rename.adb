package body AHC.Rename is

   use AHC.Syntax;
   use type Core.TyCon_Id;
   use type Core.Class_Id;

   ---------------------------------------------------------------------
   --  Equation grouping (Report 4.4.3)
   ---------------------------------------------------------------------

   function Group
     (Arena : Syntax.Module_Arena;
      Decls : Syntax.Decl_Id_Vectors.Vector;
      Bag   : in out Diagnostics.Diagnostic_Bag)
      return Unit_Vectors.Vector
   is
      Units : Unit_Vectors.Vector;
      Seen  : Builtins.Var_Maps.Map;  --  name -> unit index (as Var_Id)
   begin
      for D of Decls loop
         declare
            N : constant Decl_Node := Arena.Node (D);
         begin
            case N.Kind is
               when Fun_D =>
                  if not Units.Is_Empty
                    and then Units.Last_Element.Kind = Fun_Unit
                    and then Units.Last_Element.Name = N.Fun_Name
                  then
                     --  Continue the current run of equations.
                     if Natural (N.Fun_Pats.Length) /=
                        Units.Last_Element.Arity
                     then
                        Bag.Add (Diagnostics.Error,
                                 Diagnostics.Rename_Bad_Equations,
                                 N.Span,
                                 "equations have different arities");
                     end if;
                     Units (Units.Last_Index).Equations.Append (D);
                  else
                     if Seen.Contains (N.Fun_Name) then
                        Bag.Add (Diagnostics.Error,
                                 Diagnostics.Rename_Bad_Equations,
                                 N.Span,
                                 "equations are not contiguous");
                     end if;
                     Seen.Include (N.Fun_Name, 1);
                     declare
                        U : Binding_Unit;
                     begin
                        U.Kind := Fun_Unit;
                        U.Name := N.Fun_Name;
                        U.Arity := Natural (N.Fun_Pats.Length);
                        U.Span := N.Span;
                        U.Equations.Append (D);
                        Units.Append (U);
                     end;
                  end if;
               when Pat_D =>
                  declare
                     U : Binding_Unit;
                  begin
                     U.Kind := Pat_Unit;
                     U.Span := N.Span;
                     U.Equations.Append (D);
                     Units.Append (U);
                  end;
               when others =>
                  null;
            end case;
         end;
      end loop;
      return Units;
   end Group;

   ---------------------------------------------------------------------
   --  Resolve_Module
   ---------------------------------------------------------------------

   procedure Resolve_Module
     (Arena : Syntax.Module_Arena;
      Table : in out Names.Name_Table;
      Bag   : in out Diagnostics.Diagnostic_Bag;
      M     : in out Core.Core_Module;
      Env   : in out Builtins.Global_Env;
      Res   : in out Resolutions;
      Reg   : access Modules.Registry := null;
      Fixities : Fixity.Fixity_Maps.Map :=
        Fixity.Fixity_Maps.Empty_Map)
   is
      Prelude_Name : constant Names.Real_Name_Id :=
        Table.Intern ("Prelude");

      --  This module's complete top-level tables (private names
      --  included) - what pass B resolves against before imports.
      Own : Modules.Iface;

      --  One processed import: its exports filtered by the spec.
      type Imp_View is record
         Module    : Names.Name_Id := Names.No_Name;
         Alias     : Names.Name_Id := Names.No_Name;
         Qualified : Boolean := False;
         Visible   : Modules.Iface;
      end record;

      function IV_Never_Eq (A, B : Imp_View) return Boolean is
         pragma Unreferenced (A, B);
      begin
         return False;
      end IV_Never_Eq;
      package Imp_Vectors is new Ada.Containers.Vectors
        (Positive, Imp_View, "=" => IV_Never_Eq);
      Imp_Views : Imp_Vectors.Vector;

      package Scope_Maps renames Builtins.Var_Maps;
      package Scope_Vectors is new Ada.Containers.Vectors
        (Positive, Scope_Maps.Map, Scope_Maps."=");

      Scopes : Scope_Vectors.Vector;

      --  Names defined by this module at top level (for duplicate
      --  detection distinct from builtin shadowing, which is legal).
      Top_Names : Scope_Maps.Map;

      ------------------------------------------------------------------
      --  Small helpers
      ------------------------------------------------------------------

      procedure Set_Expr (Id : Real_Expr_Id; R : Resolution) is
      begin
         Res.Expr_Res.Replace_Element (Positive (Id), R);
      end Set_Expr;

      procedure Set_Pat (Id : Real_Pat_Id; R : Resolution) is
      begin
         Res.Pat_Res.Replace_Element (Positive (Id), R);
      end Set_Pat;

      function Text (N : Names.Name_Id) return String
      is (if N = Names.No_Name then "?" else Table.Text (N));

      Modular : constant Boolean := Reg /= null;

      --  The import view matching qualifier Q (alias first), 0 if
      --  none.
      function Find_View (Q : Names.Name_Id) return Natural is
      begin
         for I in 1 .. Imp_Views.Last_Index loop
            if Imp_Views (I).Alias = Q
              or else Imp_Views (I).Module = Q
            then
               return I;
            end if;
         end loop;
         return 0;
      end Find_View;

      --  Strip a legal qualifier (Prelude, the module's own name, or
      --  an import's name/alias). Returns False with a diagnostic
      --  for anything else.
      function Check_Qualifier
        (Q : QName; Span : Diagnostics.Source_Span) return Boolean is
      begin
         if Q.Qualifier = Names.No_Name
           or else Q.Qualifier = Names.Name_Id (Prelude_Name)
           or else Q.Qualifier = Arena.Module_Name
           or else (Modular and then Find_View (Q.Qualifier) /= 0)
         then
            return True;
         end if;
         Bag.Add (Diagnostics.Error, Diagnostics.Rename_Out_Of_Scope,
                  Span,
                  "unknown module qualifier '"
                  & Text (Q.Qualifier) & "'");
         return False;
      end Check_Qualifier;


      --  Import-aware resolution for type-level and constructor
      --  names (own module, then unqualified imports first-hit, then
      --  Base). Falls back to the flat environment when no registry
      --  is in play.
      function Mod_Find_TyCon
        (Name : Names.Name_Id) return Core.TyCon_Id is
      begin
         if not Modular then
            declare
               C : constant Builtins.TyCon_Maps.Cursor :=
                 Env.TyCons.Find (Name);
            begin
               return (if Builtins.TyCon_Maps.Has_Element (C)
                       then Core.TyCon_Id
                              (Builtins.TyCon_Maps.Element (C))
                       else Core.No_TyCon);
            end;
         end if;
         declare
            C : Builtins.TyCon_Maps.Cursor := Own.TyCons.Find (Name);
         begin
            if Builtins.TyCon_Maps.Has_Element (C) then
               return Core.TyCon_Id (Builtins.TyCon_Maps.Element (C));
            end if;
            for V of Imp_Views loop
               if not V.Qualified then
                  C := V.Visible.TyCons.Find (Name);
                  if Builtins.TyCon_Maps.Has_Element (C) then
                     return Core.TyCon_Id
                       (Builtins.TyCon_Maps.Element (C));
                  end if;
               end if;
            end loop;
            C := Reg.Base.TyCons.Find (Name);
            if Builtins.TyCon_Maps.Has_Element (C) then
               return Core.TyCon_Id (Builtins.TyCon_Maps.Element (C));
            end if;
            return Core.No_TyCon;
         end;
      end Mod_Find_TyCon;

      function Mod_Find_DataCon
        (Name : Names.Name_Id) return Core.DataCon_Id is
      begin
         if not Modular then
            declare
               C : constant Builtins.DataCon_Maps.Cursor :=
                 Env.DataCons.Find (Name);
            begin
               return (if Builtins.DataCon_Maps.Has_Element (C)
                       then Core.DataCon_Id
                              (Builtins.DataCon_Maps.Element (C))
                       else 0);
            end;
         end if;
         declare
            C : Builtins.DataCon_Maps.Cursor :=
              Own.DataCons.Find (Name);
         begin
            if Builtins.DataCon_Maps.Has_Element (C) then
               return Core.DataCon_Id
                 (Builtins.DataCon_Maps.Element (C));
            end if;
            for V of Imp_Views loop
               if not V.Qualified then
                  C := V.Visible.DataCons.Find (Name);
                  if Builtins.DataCon_Maps.Has_Element (C) then
                     return Core.DataCon_Id
                       (Builtins.DataCon_Maps.Element (C));
                  end if;
               end if;
            end loop;
            C := Reg.Base.DataCons.Find (Name);
            if Builtins.DataCon_Maps.Has_Element (C) then
               return Core.DataCon_Id
                 (Builtins.DataCon_Maps.Element (C));
            end if;
            return 0;
         end;
      end Mod_Find_DataCon;

      function Mod_Find_Class
        (Name : Names.Name_Id) return Core.Class_Id is
      begin
         if not Modular then
            declare
               C : constant Builtins.Class_Maps.Cursor :=
                 Env.Classes.Find (Name);
            begin
               return (if Builtins.Class_Maps.Has_Element (C)
                       then Core.Class_Id
                              (Builtins.Class_Maps.Element (C))
                       else Core.No_Class);
            end;
         end if;
         declare
            C : Builtins.Class_Maps.Cursor := Own.Classes.Find (Name);
         begin
            if Builtins.Class_Maps.Has_Element (C) then
               return Core.Class_Id (Builtins.Class_Maps.Element (C));
            end if;
            for V of Imp_Views loop
               if not V.Qualified then
                  C := V.Visible.Classes.Find (Name);
                  if Builtins.Class_Maps.Has_Element (C) then
                     return Core.Class_Id
                       (Builtins.Class_Maps.Element (C));
                  end if;
               end if;
            end loop;
            C := Reg.Base.Classes.Find (Name);
            if Builtins.Class_Maps.Has_Element (C) then
               return Core.Class_Id (Builtins.Class_Maps.Element (C));
            end if;
            return Core.No_Class;
         end;
      end Mod_Find_Class;

      function Mod_Syn_Visible
        (Name : Names.Name_Id) return Boolean is
      begin
         if not Modular then
            return Env.Synonyms.Contains (Name);
         end if;
         if Own.Synonyms.Contains (Name)
           or else Reg.Base.Synonyms.Contains (Name)
         then
            return True;
         end if;
         for V of Imp_Views loop
            if not V.Qualified
              and then V.Visible.Synonyms.Contains (Name)
            then
               return True;
            end if;
         end loop;
         return False;
      end Mod_Syn_Visible;

      function Mint_Local
        (Name : Names.Name_Id; Span : Diagnostics.Source_Span)
         return Core.Real_Var_Id
      is (M.Mint_Var ((Name => Name, Span => Span, Is_Global => False,
                       others => <>)));

      --  Bring a binder into the innermost scope; duplicate names in
      --  the same scope are an error (shadowing outer scopes is fine).
      procedure Bind_In_Scope
        (Name : Names.Name_Id; V : Core.Real_Var_Id;
         Span : Diagnostics.Source_Span) is
      begin
         if Scopes (Scopes.Last_Index).Contains (Name) then
            Bag.Add (Diagnostics.Error, Diagnostics.Rename_Duplicate,
                     Span,
                     "'" & Text (Name) & "' is bound more than once");
         end if;
         Scopes (Scopes.Last_Index).Include (Name, V);
      end Bind_In_Scope;

      function Lookup_Value
        (Q : QName; Span : Diagnostics.Source_Span) return Resolution
      is
      begin
         if not Check_Qualifier (Q, Span) then
            return (Kind => Unresolved);
         end if;
         if Q.Qualifier = Names.No_Name then
            for I in reverse 1 .. Scopes.Last_Index loop
               declare
                  C : constant Scope_Maps.Cursor :=
                    Scopes (I).Find (Q.Name);
               begin
                  if Scope_Maps.Has_Element (C) then
                     return (Kind => Var_Res,
                             Var => Scope_Maps.Element (C));
                  end if;
               end;
            end loop;
         end if;
         if Modular then
            --  Qualified through an import name or alias.
            if Q.Qualifier /= Names.No_Name
              and then Q.Qualifier /= Names.Name_Id (Prelude_Name)
              and then Q.Qualifier /= Arena.Module_Name
            then
               declare
                  VI : constant Natural := Find_View (Q.Qualifier);
                  C : Builtins.Var_Maps.Cursor;
               begin
                  C := Imp_Views (VI).Visible.Values.Find (Q.Name);
                  if Builtins.Var_Maps.Has_Element (C) then
                     return (Kind => Var_Res,
                             Var => Builtins.Var_Maps.Element (C));
                  end if;
                  Bag.Add (Diagnostics.Error,
                           Diagnostics.Rename_Out_Of_Scope, Span,
                           "module '" & Text (Q.Qualifier)
                           & "' does not export '"
                           & Text (Q.Name) & "'");
                  return (Kind => Unresolved);
               end;
            end if;
            --  Own module first.
            declare
               C : constant Builtins.Var_Maps.Cursor :=
                 Own.Values.Find (Q.Name);
            begin
               if Builtins.Var_Maps.Has_Element (C) then
                  return (Kind => Var_Res,
                          Var => Builtins.Var_Maps.Element (C));
               end if;
            end;
            --  Unqualified imports; two distinct hits = ambiguous
            --  (Report 5.5.2, at the use site).
            if Q.Qualifier = Names.No_Name then
               declare
                  Found : Core.Var_Id := Core.No_Var;
                  Amb : Boolean := False;
               begin
                  for V of Imp_Views loop
                     if not V.Qualified then
                        declare
                           C : constant Builtins.Var_Maps.Cursor :=
                             V.Visible.Values.Find (Q.Name);
                        begin
                           if Builtins.Var_Maps.Has_Element (C) then
                              if Found /= Core.No_Var
                                and then Found /= Core.Var_Id
                                  (Builtins.Var_Maps.Element (C))
                              then
                                 Amb := True;
                              end if;
                              Found := Core.Var_Id
                                (Builtins.Var_Maps.Element (C));
                           end if;
                        end;
                     end if;
                  end loop;
                  if Amb then
                     Bag.Add (Diagnostics.Error,
                              Diagnostics.Rename_Out_Of_Scope, Span,
                              "ambiguous name '" & Text (Q.Name)
                              & "' (imported from several modules)");
                     return (Kind => Unresolved);
                  end if;
                  if Found /= Core.No_Var then
                     return (Kind => Var_Res,
                             Var => Core.Real_Var_Id (Found));
                  end if;
               end;
            end if;
            --  Base: builtins + Prelude.
            declare
               C : constant Builtins.Var_Maps.Cursor :=
                 Reg.Base.Values.Find (Q.Name);
            begin
               if Builtins.Var_Maps.Has_Element (C) then
                  return (Kind => Var_Res,
                          Var => Builtins.Var_Maps.Element (C));
               end if;
            end;
            Bag.Add (Diagnostics.Error,
                     Diagnostics.Rename_Out_Of_Scope,
                     Span,
                     "variable not in scope: " & Text (Q.Name));
            return (Kind => Unresolved);
         end if;
         declare
            C : constant Builtins.Var_Maps.Cursor :=
              Env.Values.Find (Q.Name);
         begin
            if Builtins.Var_Maps.Has_Element (C) then
               return (Kind => Var_Res,
                       Var => Builtins.Var_Maps.Element (C));
            end if;
         end;
         Bag.Add (Diagnostics.Error, Diagnostics.Rename_Out_Of_Scope,
                  Span, "variable not in scope: " & Text (Q.Name));
         return (Kind => Unresolved);
      end Lookup_Value;

      function Lookup_Con
        (Q : QName; Span : Diagnostics.Source_Span) return Resolution is
      begin
         if not Check_Qualifier (Q, Span) then
            return (Kind => Unresolved);
         end if;
         declare
            use type Core.DataCon_Id;
            DC : constant Core.DataCon_Id := Mod_Find_DataCon (Q.Name);
         begin
            if DC /= 0 then
               return (Kind => Data_Res,
                       Con => Core.Real_DataCon_Id (DC));
            end if;
         end;
         Bag.Add (Diagnostics.Error, Diagnostics.Rename_Out_Of_Scope,
                  Span,
                  "data constructor not in scope: " & Text (Q.Name));
         return (Kind => Unresolved);
      end Lookup_Con;

      ------------------------------------------------------------------
      --  Types (pass B)
      ------------------------------------------------------------------

      procedure Rename_Type (Id : Real_Type_Id);

      --  Forward (bodies below): predicate refinements embed an
      --  expression inside a type.
      procedure Rename_Expr (Id : Real_Expr_Id);

      --  A context entry: resolve its head as a class.
      procedure Rename_Assertion (Id : Real_Type_Id) is
         N : constant Type_Node := Arena.Node (Id);
      begin
         case N.Kind is
            when Con_T =>
               declare
                  Cl : constant Core.Class_Id :=
                    Mod_Find_Class (N.Con.Name);
               begin
                  if Cl /= Core.No_Class then
                     Res.Class_Res.Replace_Element
                       (Positive (Id), Cl);
                  else
                     Bag.Add (Diagnostics.Error,
                              Diagnostics.Rename_Out_Of_Scope, N.Span,
                              "class not in scope: " & Text (N.Con.Name));
                  end if;
               end;
            when App_T =>
               Rename_Assertion (N.Fun);
               Rename_Type (N.Arg);
            when others =>
               Bag.Add (Diagnostics.Error, Diagnostics.Kind_Error,
                        N.Span, "malformed class assertion");
         end case;
      end Rename_Assertion;

      procedure Rename_Type (Id : Real_Type_Id) is
         N : constant Type_Node := Arena.Node (Id);
      begin
         case N.Kind is
            when Var_T =>
               null;   --  implicitly bound; kinds handled in AHC.Kinds
            when Con_T =>
               declare
                  TC : constant Core.TyCon_Id :=
                    Mod_Find_TyCon (N.Con.Name);
               begin
                  if TC /= Core.No_TyCon then
                     Res.Ty_Res.Replace_Element
                       (Positive (Id), TC);
                  elsif Mod_Syn_Visible (N.Con.Name) then
                     null;   --  expanded during conversion, by name
                  else
                     Bag.Add (Diagnostics.Error,
                              Diagnostics.Rename_Out_Of_Scope, N.Span,
                              "type not in scope: " & Text (N.Con.Name));
                  end if;
               end;
            when App_T =>
               Rename_Type (N.Fun);
               Rename_Type (N.Arg);
            when Fun_T =>
               Rename_Type (N.From);
               Rename_Type (N.To);
            when List_T =>
               Rename_Type (N.Elem);
            when Tuple_T =>
               for T of N.Items loop
                  Rename_Type (T);
               end loop;
            when Qual_T =>
               for A of N.Context loop
                  Rename_Assertion (A);
               end loop;
               Rename_Type (N.Q_Body);
            when Refined_T =>
               Rename_Type (N.R_Base);
            when Pred_T =>
               Rename_Type (N.P_Base);
               Rename_Expr (N.P_Expr);
            when Mod_T =>
               Rename_Type (N.M_Base);
         end case;
      end Rename_Type;

      ------------------------------------------------------------------
      --  Patterns (pass B); binders go into the innermost scope
      ------------------------------------------------------------------

      procedure Rename_Pat
        (Id : Real_Pat_Id; Global_Binders : Boolean := False)
      is
         N : constant Pat_Node := Arena.Node (Id);

         procedure Bind_Pattern_Var
           (Name : Names.Name_Id; Span : Diagnostics.Source_Span) is
         begin
            if Global_Binders then
               declare
                  V : constant Core.Real_Var_Id :=
                    M.Mint_Var ((Name => Name, Span => Span,
                                 Is_Global => True, others => <>));
               begin
                  if Top_Names.Contains (Name) then
                     Bag.Add (Diagnostics.Error,
                              Diagnostics.Rename_Duplicate, Span,
                              "'" & Text (Name)
                              & "' is defined more than once");
                  end if;
                  Top_Names.Include (Name, V);
                  Env.Values.Include (Name, V);
                  Own.Values.Include (Name, V);
                  Set_Pat (Id, (Kind => Var_Res, Var => V));
               end;
            else
               declare
                  V : constant Core.Real_Var_Id :=
                    Mint_Local (Name, Span);
               begin
                  Bind_In_Scope (Name, V, Span);
                  Set_Pat (Id, (Kind => Var_Res, Var => V));
               end;
            end if;
         end Bind_Pattern_Var;
      begin
         case N.Kind is
            when Var_P =>
               Bind_Pattern_Var (N.Var, N.Span);
            when Wild_P | Lit_Int_P | Lit_Float_P | Lit_Char_P
               | Lit_String_P | Neg_Int_P | Neg_Float_P =>
               null;
            when Con_P =>
               declare
                  R : constant Resolution := Lookup_Con (N.Con, N.Span);
               begin
                  Set_Pat (Id, R);
                  if R.Kind = Data_Res
                    and then Natural (N.Con_Args.Length) /=
                               M.Info (R.Con).Arity
                  then
                     Bag.Add (Diagnostics.Error,
                              Diagnostics.Arity_Mismatch, N.Span,
                              "constructor '" & Text (N.Con.Name)
                              & "' expects"
                              & M.Info (R.Con).Arity'Image
                              & " arguments in a pattern");
                  end if;
               end;
               for P of N.Con_Args loop
                  Rename_Pat (P, Global_Binders);
               end loop;
            when Con_Chain_P =>
               --  Fixity resolution removed these.
               null;
            when Tuple_P | List_P =>
               for P of N.Items loop
                  Rename_Pat (P, Global_Binders);
               end loop;
            when As_P =>
               Bind_Pattern_Var (N.As_Var, N.Span);
               Rename_Pat (N.As_Pat, Global_Binders);
            when Lazy_P =>
               Rename_Pat (N.Lazy_Pat, Global_Binders);
            when Rec_P =>
               declare
                  R : constant Resolution :=
                    Lookup_Con (N.Rec_Con, N.Span);
               begin
                  Set_Pat (Id, R);
                  for F of N.Rec_Fields loop
                     if R.Kind = Data_Res then
                        declare
                           Fields : constant Core.Name_Id_Vectors.Vector
                             := M.Info (R.Con).Field_Names;
                           Found : Boolean := False;
                        begin
                           for FN of Fields loop
                              if FN = F.Field.Name then
                                 Found := True;
                              end if;
                           end loop;
                           if not Found then
                              Bag.Add
                                (Diagnostics.Error,
                                 Diagnostics.Rename_Field_Error, N.Span,
                                 "'" & Text (F.Field.Name)
                                 & "' is not a field of '"
                                 & Text (N.Rec_Con.Name) & "'");
                           end if;
                        end;
                     end if;
                     Rename_Pat (F.Value, Global_Binders);
                  end loop;
               end;
            when Sig_P =>
               Rename_Pat (N.Sig_Pat, Global_Binders);
               Rename_Type (N.Sig_Type);
         end case;
      end Rename_Pat;

      ------------------------------------------------------------------
      --  Expressions and declaration groups (pass B)
      ------------------------------------------------------------------

      procedure Declare_Group
        (Decls : Syntax.Decl_Id_Vectors.Vector; Global : Boolean);
      procedure Rename_Group_Bodies
        (Decls : Syntax.Decl_Id_Vectors.Vector);

      procedure Push_Scope is
      begin
         Scopes.Append (Scope_Maps.Empty_Map);
      end Push_Scope;

      procedure Pop_Scope is
      begin
         Scopes.Delete_Last;
      end Pop_Scope;

      procedure Rename_Stmt (Id : Real_Stmt_Id);

      procedure Rename_Rhs (R : Rhs) is
      begin
         if R.Guarded then
            --  Pattern-guard binders scope over the later qualifiers
            --  and the alternative's body (Report 3.13).
            for G of R.Guards loop
               Push_Scope;
               for Q of G.Quals loop
                  Rename_Stmt (Q);
               end loop;
               Rename_Expr (G.G_Body);
               Pop_Scope;
            end loop;
         else
            Rename_Expr (R.Plain);
         end if;
      end Rename_Rhs;

      procedure Rename_Stmt (Id : Real_Stmt_Id) is
         N : constant Stmt_Node := Arena.Node (Id);
      begin
         case N.Kind is
            when Bind_S =>
               --  The expression cannot see the pattern's binders.
               Rename_Expr (N.Bind_Expr);
               Rename_Pat (N.Bind_Pat);
            when Let_S =>
               Declare_Group (N.Let_Binds, Global => False);
               Rename_Group_Bodies (N.Let_Binds);
            when Syntax.Expr_S =>
               Rename_Expr (N.Expr);
         end case;
      end Rename_Stmt;

      procedure Rename_Expr (Id : Real_Expr_Id) is
         N : constant Expr_Node := Arena.Node (Id);
      begin
         case N.Kind is
            when Var_E =>
               Set_Expr (Id, Lookup_Value (N.Name, N.Span));
            when Con_E =>
               Set_Expr (Id, Lookup_Con (N.Name, N.Span));
            when Lit_Int_E | Lit_Float_E | Lit_Char_E | Lit_String_E =>
               null;
            when App_E =>
               Rename_Expr (N.Fun);
               Rename_Expr (N.Arg);
            when Op_Chain_E =>
               null;   --  removed by fixity resolution
            when Neg_E =>
               Rename_Expr (N.Negated);
            when Lambda_E =>
               Push_Scope;
               for P of N.L_Pats loop
                  Rename_Pat (P);
               end loop;
               Rename_Expr (N.L_Body);
               Pop_Scope;
            when Let_E =>
               Push_Scope;
               Declare_Group (N.Binds, Global => False);
               Rename_Group_Bodies (N.Binds);
               Rename_Expr (N.Let_Body);
               Pop_Scope;
            when If_E =>
               Rename_Expr (N.Cond);
               Rename_Expr (N.Then_E);
               Rename_Expr (N.Else_E);
            when Case_E =>
               Rename_Expr (N.Scrutinee);
               for A of N.Alts loop
                  declare
                     Alt : constant Alt_Node := Arena.Node (A);
                  begin
                     Push_Scope;
                     Rename_Pat (Alt.Pat);
                     Declare_Group (Alt.Where_Ds, Global => False);
                     Rename_Rhs (Alt.Alt_Rhs);
                     Rename_Group_Bodies (Alt.Where_Ds);
                     Pop_Scope;
                  end;
               end loop;
            when Do_E =>
               Push_Scope;
               for S of N.Stmts loop
                  Rename_Stmt (S);
               end loop;
               Pop_Scope;
            when Tuple_E | List_E =>
               for E of N.Items loop
                  Rename_Expr (E);
               end loop;
            when Arith_Seq_E =>
               Rename_Expr (N.Seq_From);
               if N.Seq_Then /= No_Expr then
                  Rename_Expr (N.Seq_Then);
               end if;
               if N.Seq_To /= No_Expr then
                  Rename_Expr (N.Seq_To);
               end if;
            when List_Comp_E =>
               Push_Scope;
               for S of N.Comp_Quals loop
                  Rename_Stmt (S);
               end loop;
               Rename_Expr (N.Comp_Expr);
               Pop_Scope;
            when Left_Section_E | Right_Section_E =>
               --  The section's own resolution slot carries its
               --  operator (the node has no other use for it).
               if N.Sec_Op.Is_Con then
                  Set_Expr (Id, Lookup_Con (N.Sec_Op.Op, N.Span));
               else
                  Set_Expr (Id, Lookup_Value (N.Sec_Op.Op, N.Span));
               end if;
               Rename_Expr (N.Sec_Expr);
            when Sig_E =>
               Rename_Expr (N.Sig_Expr);
               Rename_Type (N.Sig_Type);
            when Rec_Con_E | Rec_Update_E =>
               Rename_Expr (N.Rec_Base);
               for F of N.Rec_Fields loop
                  if not Env.Values.Contains (F.Field.Name) then
                     Bag.Add (Diagnostics.Error,
                              Diagnostics.Rename_Field_Error, N.Span,
                              "unknown field '" & Text (F.Field.Name)
                              & "'");
                  end if;
                  Rename_Expr (F.Value);
               end loop;
         end case;
      end Rename_Expr;

      ------------------------------------------------------------------
      --  Value declaration groups
      ------------------------------------------------------------------

      procedure Declare_Group
        (Decls : Syntax.Decl_Id_Vectors.Vector; Global : Boolean)
      is
         Units : constant Unit_Vectors.Vector :=
           Group (Arena, Decls, Bag);
      begin
         --  Binders first (letrec semantics), then signatures.
         for U of Units loop
            case U.Kind is
               when Fun_Unit =>
                  declare
                     Span : constant Diagnostics.Source_Span := U.Span;
                     V : Core.Real_Var_Id;
                  begin
                     if Global then
                        V := M.Mint_Var
                          ((Name => U.Name, Span => Span,
                            Is_Global => True, others => <>));
                        if Top_Names.Contains (U.Name) then
                           Bag.Add (Diagnostics.Error,
                                    Diagnostics.Rename_Duplicate, Span,
                                    "'" & Text (U.Name)
                                    & "' is defined more than once");
                        end if;
                        Top_Names.Include (U.Name, V);
                        Env.Values.Include (U.Name, V);
                        Own.Values.Include (U.Name, V);
                     else
                        V := Mint_Local (U.Name, Span);
                        Bind_In_Scope (U.Name, V, Span);
                     end if;
                     for D of U.Equations loop
                        Res.Decl_Var.Replace_Element
                          (Positive (D), Core.Var_Id (V));
                     end loop;
                  end;
               when Pat_Unit =>
                  declare
                     D : constant Real_Decl_Id := U.Equations (1);
                     N : constant Decl_Node := Arena.Node (D);
                  begin
                     Rename_Pat (N.Pat, Global_Binders => Global);
                  end;
            end case;
         end loop;

         --  Signatures attach to just-declared binders.
         for D of Decls loop
            declare
               N : constant Decl_Node := Arena.Node (D);
            begin
               if N.Kind = Sig_D then
                  Rename_Type (N.Sig_Type);
                  for Q of N.Sig_Names loop
                     declare
                        R : Resolution := (Kind => Unresolved);
                     begin
                        if Global then
                           declare
                              C : constant Scope_Maps.Cursor :=
                                Top_Names.Find (Q.Name);
                           begin
                              if Scope_Maps.Has_Element (C) then
                                 R := (Kind => Var_Res,
                                       Var => Scope_Maps.Element (C));
                              end if;
                           end;
                        else
                           declare
                              C : constant Scope_Maps.Cursor :=
                                Scopes (Scopes.Last_Index).Find (Q.Name);
                           begin
                              if Scope_Maps.Has_Element (C) then
                                 R := (Kind => Var_Res,
                                       Var => Scope_Maps.Element (C));
                              end if;
                           end;
                        end if;
                        if R.Kind = Var_Res then
                           Res.Var_Sig.Include (R.Var, N.Sig_Type);
                        else
                           Bag.Add
                             (Diagnostics.Error,
                              Diagnostics.Rename_Bad_Equations, N.Span,
                              "signature for '" & Text (Q.Name)
                              & "' lacks a binding");
                        end if;
                     end;
                  end loop;
               end if;
            end;
         end loop;
      end Declare_Group;

      procedure Rename_Value_Decl (D : Real_Decl_Id) is
         N : constant Decl_Node := Arena.Node (D);
      begin
         case N.Kind is
            when Fun_D =>
               Push_Scope;
               for P of N.Fun_Pats loop
                  Rename_Pat (P);
               end loop;
               Declare_Group (N.Fun_Where, Global => False);
               Rename_Rhs (N.Fun_Rhs);
               Rename_Group_Bodies (N.Fun_Where);
               Pop_Scope;
            when Pat_D =>
               --  Pattern already renamed by Declare_Group.
               Push_Scope;
               Declare_Group (N.Pat_Where, Global => False);
               Rename_Rhs (N.Pat_Rhs);
               Rename_Group_Bodies (N.Pat_Where);
               Pop_Scope;
            when others =>
               null;
         end case;
      end Rename_Value_Decl;

      procedure Rename_Group_Bodies
        (Decls : Syntax.Decl_Id_Vectors.Vector) is
      begin
         for D of Decls loop
            Rename_Value_Decl (D);
         end loop;
      end Rename_Group_Bodies;

      ------------------------------------------------------------------
      --  Pass A: declare module-level entities
      ------------------------------------------------------------------

      procedure Declare_Data (D : Real_Decl_Id; N : Decl_Node) is
         Is_NT : constant Boolean := N.Kind = Newtype_D;
         TC : Core.Real_TyCon_Id;
      begin
         if Env.TyCons.Contains (N.D_Name)
           or else Env.Synonyms.Contains (N.D_Name)
         then
            Bag.Add (Diagnostics.Error, Diagnostics.Rename_Duplicate,
                     N.Span,
                     "type '" & Text (N.D_Name)
                     & "' is defined more than once");
         end if;
         TC := M.Mint_TyCon
           ((Name => N.D_Name, Arity => Natural (N.D_Vars.Length),
             Is_Newtype => Is_NT, others => <>));
         Env.TyCons.Include (N.D_Name, TC);
         Own.TyCons.Include (N.D_Name, TC);

         for CI in 1 .. N.D_Cons.Last_Index loop
            declare
               CN : constant Con_Node := Arena.Node (N.D_Cons (CI));
               Info : Core.DataCon_Info;
            begin
               Info.Name := CN.Name.Name;
               Info.TyCon := Core.TyCon_Id (TC);
               Info.Tag := CI;
               case CN.Shape is
                  when Prefix_Con | Infix_Con =>
                     Info.Arity := Natural (CN.Args.Length);
                     for S of CN.Stricts loop
                        Info.Stricts.Append (S);
                     end loop;
                  when Record_Con =>
                     for F of CN.Fields loop
                        for FQ of F.Names_List loop
                           Info.Arity := Info.Arity + 1;
                           Info.Field_Names.Append (FQ.Name);
                           Info.Stricts.Append (F.Strict);
                        end loop;
                     end loop;
               end case;
               if Env.DataCons.Contains (Info.Name) then
                  Bag.Add (Diagnostics.Error,
                           Diagnostics.Rename_Duplicate, CN.Span,
                           "constructor '" & Text (Info.Name)
                           & "' is defined more than once");
               end if;
               declare
                  DC : constant Core.Real_DataCon_Id :=
                    M.Mint_DataCon (Info);
               begin
                  Env.DataCons.Include (Info.Name, DC);
                  Own.DataCons.Include (Info.Name, DC);
                  --  Field selector globals (schemes come from
                  --  AHC.Kinds; bodies from the desugarer).
                  for FN of Info.Field_Names loop
                     if not Env.Values.Contains (FN) then
                        declare
                           Sel : constant Core.Real_Var_Id :=
                             M.Mint_Var ((Name => FN, Span => CN.Span,
                                          Is_Global => True,
                                          others => <>));
                        begin
                           Env.Values.Include (FN, Sel);
                           Own.Values.Include (FN, Sel);
                        end;
                     end if;
                  end loop;
               end;
            end;
         end loop;

         --  deriving (C1, ...): register signature-only instances so
         --  derived classes participate in context reduction.
         for DC of N.D_Deriving loop
            declare
               C : constant Builtins.Class_Maps.Cursor :=
                 Env.Classes.Find (DC.Name);
            begin
               if Builtins.Class_Maps.Has_Element (C) then
                  declare
                     Cl : constant Core.Real_Class_Id :=
                       Builtins.Class_Maps.Element (C);
                     Ctx : Core.Constraint_Vectors.Vector;
                     Vars : Core.TyVar_Id_Vectors.Vector;
                     Dict : Core.Real_Var_Id;
                     Ignore : Core.Real_Instance_Id;
                  begin
                     for VQ of N.D_Vars loop
                        declare
                           Tv : constant Core.Real_TyVar_Id :=
                             M.Mint_TyVar ((Name => VQ.Name,
                                            Tv_Kind => Core.Kind_Id
                                              (M.Star)));
                           TvT : constant Core.Real_Type_Id :=
                             M.Add (Core.Type_Node'
                               (Kind => Core.TVar_T, Tv => Tv));
                        begin
                           Vars.Append (Tv);
                           Ctx.Append
                             (Core.Constraint'
                                (Class => Cl, Arg => TvT,
                                 Span => N.Span));
                        end;
                     end loop;
                     Dict := M.Mint_Var
                       ((Name => Table.Intern
                           ("$d" & Text (DC.Name) & Text (N.D_Name)),
                         Span => N.Span, Is_Global => True,
                         others => <>));
                     Ignore := M.Mint_Instance
                       ((Of_Class => Core.Class_Id (Cl),
                         Head => Core.TyCon_Id (TC),
                         Head_Vars => Vars,
                         Context => Ctx,
                         Dict_Global => Core.Var_Id (Dict),
                         Method_Binds =>
                           Core.Bind_Vectors.Empty_Vector,
                         Param_Vars =>
                           Core.Var_Id_Vectors.Empty_Vector,
                         Span => N.Span));
                     pragma Unreferenced (Ignore);
                  end;
               else
                  Bag.Add (Diagnostics.Error,
                           Diagnostics.Rename_Out_Of_Scope, N.Span,
                           "cannot derive unknown class '"
                           & Text (DC.Name) & "'");
               end if;
            end;
         end loop;
         pragma Unreferenced (D);
      end Declare_Data;

      procedure Declare_Class (D : Real_Decl_Id; N : Decl_Node) is
         Star_K : constant Core.Real_Kind_Id := M.Star;
         Dict_TC : Core.Real_TyCon_Id;
         Cl : Core.Real_Class_Id;
      begin
         if Env.Classes.Contains (N.C_Name) then
            Bag.Add (Diagnostics.Error, Diagnostics.Rename_Duplicate,
                     N.Span,
                     "class '" & Text (N.C_Name)
                     & "' is defined more than once");
         end if;
         Dict_TC := M.Mint_TyCon
           ((Name => Table.Intern ("Dict$" & Text (N.C_Name)),
             Arity => 1, others => <>));
         Cl := M.Mint_Class
           ((Name => N.C_Name, Var_Kind => Core.Kind_Id (Star_K),
             Dict_TyCon => Core.TyCon_Id (Dict_TC), others => <>));
         M.Classes (Cl).Dict_Con := Core.DataCon_Id
           (M.Mint_DataCon
              ((Name => Table.Intern ("MkDict$" & Text (N.C_Name)),
                TyCon => Core.TyCon_Id (Dict_TC), Tag => 1,
                others => <>)));
         Env.Classes.Include (N.C_Name, Cl);
         Own.Classes.Include (N.C_Name, Cl);
         Res.Decl_Class.Replace_Element
           (Positive (D), Core.Class_Id (Cl));

         --  Superclasses from the context.
         for A of N.C_Context loop
            declare
               AN : constant Type_Node := Arena.Node (A);
            begin
               if AN.Kind = App_T
                 and then Arena.Node (AN.Fun).Kind = Con_T
               then
                  declare
                     SC : constant Core.Class_Id :=
                       Mod_Find_Class
                         (Arena.Node (AN.Fun).Con.Name);
                  begin
                     if SC /= Core.No_Class then
                        M.Classes (Cl).Supers.Append
                          (Core.Real_Class_Id (SC));
                     end if;
                  end;
               end if;
            end;
         end loop;

         --  Methods: every Sig_D inside the class body.
         for CD of N.C_Decls loop
            declare
               CN : constant Decl_Node := Arena.Node (CD);
            begin
               if CN.Kind = Sig_D then
                  Rename_Type (CN.Sig_Type);
                  for Q of CN.Sig_Names loop
                     declare
                        Has_Default : Boolean := False;
                        Sel : Core.Real_Var_Id;
                     begin
                        for CD2 of N.C_Decls loop
                           declare
                              C2 : constant Decl_Node :=
                                Arena.Node (CD2);
                           begin
                              if C2.Kind = Fun_D
                                and then C2.Fun_Name = Q.Name
                              then
                                 Has_Default := True;
                              end if;
                           end;
                        end loop;
                        Sel := M.Mint_Var
                          ((Name => Q.Name, Span => CN.Span,
                            Is_Global => True, others => <>));
                        Env.Values.Include (Q.Name, Sel);
                        Own.Values.Include (Q.Name, Sel);
                        M.Classes (Cl).Methods.Append
                          (Core.Method_Info'
                             (Name => Q.Name,
                              Selector => Core.Var_Id (Sel),
                              Has_Default => Has_Default,
                              others => <>));
                        Res.Var_Sig.Include (Sel, CN.Sig_Type);
                     end;
                  end loop;
               end if;
            end;
         end loop;
         M.DataCons
           (Core.Real_DataCon_Id (M.Classes (Cl).Dict_Con)).Arity :=
           Natural (M.Classes (Cl).Supers.Length)
           + Natural (M.Classes (Cl).Methods.Length);
         for I in 1 .. M.Classes (Cl).Supers.Last_Index loop
            declare
               Img : constant String := I'Image;
               Sel : constant Core.Real_Var_Id :=
                 M.Mint_Var
                   ((Name => Table.Intern
                       ("sup$" & Text (N.C_Name)
                        & "$" & Img (2 .. Img'Last)),
                     Span => N.Span, Is_Global => True,
                     others => <>));
            begin
               M.Classes (Cl).Super_Sels.Append (Sel);
            end;
         end loop;
      end Declare_Class;

      --  Head TyCon of an instance type.
      function Instance_Head
        (T : Real_Type_Id; Span : Diagnostics.Source_Span)
         return Core.TyCon_Id
      is
         N : constant Type_Node := Arena.Node (T);
      begin
         case N.Kind is
            when Con_T =>
               declare
                  TC2 : constant Core.TyCon_Id :=
                    Mod_Find_TyCon (N.Con.Name);
               begin
                  if TC2 /= Core.No_TyCon then
                     return TC2;
                  end if;
               end;
               Bag.Add (Diagnostics.Error,
                        Diagnostics.Rename_Out_Of_Scope, Span,
                        "type not in scope: " & Text (N.Con.Name));
               return Core.No_TyCon;
            when App_T =>
               return Instance_Head (N.Fun, Span);
            when List_T =>
               return Env.List_TC;
            when Tuple_T =>
               if Natural (N.Items.Length) in 2 .. Builtins.Max_Tuple
               then
                  return Env.Tuple_TCs (Natural (N.Items.Length));
               end if;
               return Core.No_TyCon;
            when Fun_T =>
               return Env.Arrow_TC;
            when others =>
               Bag.Add (Diagnostics.Error, Diagnostics.Rename_Unsupported,
                        Span, "unsupported instance head");
               return Core.No_TyCon;
         end case;
      end Instance_Head;

      procedure Declare_Instance (D : Real_Decl_Id; N : Decl_Node) is
         ClC : constant Builtins.Class_Maps.Cursor :=
           Env.Classes.Find (N.I_Class.Name);
         Head : Core.TyCon_Id;
      begin
         if not Builtins.Class_Maps.Has_Element (ClC) then
            Bag.Add (Diagnostics.Error, Diagnostics.Rename_Out_Of_Scope,
                     N.Span,
                     "class not in scope: " & Text (N.I_Class.Name));
            return;
         end if;
         Head := Instance_Head (N.I_Type, N.Span);
         if Head = Core.No_TyCon then
            return;
         end if;
         declare
            Cl : constant Core.Real_Class_Id :=
              Builtins.Class_Maps.Element (ClC);
         begin
            Res.Decl_Class.Replace_Element
              (Positive (D), Core.Class_Id (Cl));
            for I of M.Classes (Cl).Instances loop
               if M.Info (I).Head = Head then
                  Bag.Add (Diagnostics.Error,
                           Diagnostics.Class_Duplicate_Instance, N.Span,
                           "duplicate instance");
               end if;
            end loop;
            declare
               Dict : constant Core.Real_Var_Id :=
                 M.Mint_Var
                   ((Name => Table.Intern
                       ("$d" & Text (N.I_Class.Name)
                        & Text (M.Info (Core.Real_TyCon_Id (Head)).Name)),
                     Span => N.Span, Is_Global => True, others => <>));
               Ignore : Core.Real_Instance_Id;
            begin
               --  Head_Vars and Context are filled by AHC.Kinds once
               --  the instance type is converted.
               Ignore := M.Mint_Instance
                 ((Of_Class => Core.Class_Id (Cl), Head => Head,
                   Head_Vars => Core.TyVar_Id_Vectors.Empty_Vector,
                   Context => Core.Constraint_Vectors.Empty_Vector,
                   Dict_Global => Core.Var_Id (Dict),
                   Method_Binds => Core.Bind_Vectors.Empty_Vector,
                   Param_Vars => Core.Var_Id_Vectors.Empty_Vector,
                   Span => N.Span));
               pragma Unreferenced (Ignore);
            end;
         end;
      end Declare_Instance;

      ------------------------------------------------------------------
      --  Class/instance bodies (pass B)
      ------------------------------------------------------------------

      procedure Rename_Method_Bodies
        (Decls : Syntax.Decl_Id_Vectors.Vector;
         Of_Class : Core.Class_Id)
      is
      begin
         for D of Decls loop
            declare
               N : constant Decl_Node := Arena.Node (D);
            begin
               case N.Kind is
                  when Fun_D | Pat_D =>
                     --  Method implementations bind fresh local vars
                     --  (they become dictionary fields, not globals).
                     if N.Kind = Fun_D then
                        declare
                           V : constant Core.Real_Var_Id :=
                             Mint_Local (N.Fun_Name, N.Span);
                           Known : Boolean := False;
                        begin
                           Res.Decl_Var.Replace_Element
                             (Positive (D), Core.Var_Id (V));
                           if Of_Class in 1 .. M.Last_Class then
                              for Mth of M.Classes
                                (Core.Real_Class_Id (Of_Class)).Methods
                              loop
                                 if Mth.Name = N.Fun_Name then
                                    Known := True;
                                 end if;
                              end loop;
                              if not Known then
                                 Bag.Add
                                   (Diagnostics.Error,
                                    Diagnostics.Class_Missing_Method,
                                    N.Span,
                                    "'" & Text (N.Fun_Name)
                                    & "' is not a method of the class");
                              end if;
                           end if;
                        end;
                     end if;
                     Rename_Value_Decl (D);
                  when others =>
                     null;
               end case;
            end;
         end loop;
      end Rename_Method_Bodies;

   begin
      --  Size the side vectors.
      for I in 1 .. Natural (Arena.Last_Expr) loop
         Res.Expr_Res.Append (Resolution'(Kind => Unresolved));
      end loop;
      for I in 1 .. Natural (Arena.Last_Pat) loop
         Res.Pat_Res.Append (Resolution'(Kind => Unresolved));
      end loop;
      for I in 1 .. Natural (Arena.Last_Type) loop
         Res.Ty_Res.Append (Core.No_TyCon);
         Res.Class_Res.Append (Core.No_Class);
      end loop;
      for I in 1 .. Natural (Arena.Last_Decl) loop
         Res.Decl_Var.Append (Core.No_Var);
         Res.Decl_Class.Append (Core.No_Class);
      end loop;

      Push_Scope;   --  a scratch scope so Scopes is never empty

      --  Process imports: each becomes a view of the exporting
      --  module's iface, filtered by the import spec.
      if Modular then
         for Imp of Arena.Imports loop
            declare
               MI : constant Natural :=
                 (if Imp.Module = Names.Name_Id (Prelude_Name) then 0
                  else Modules.Find (Reg.all, Imp.Module));
               View : Imp_View;

               procedure Filter (Source : Modules.Iface) is
               begin
                  if not Imp.Has_Spec then
                     View.Visible := Source;
                     return;
                  end if;
                  if Imp.Hiding then
                     View.Visible := Source;
                     for E of Imp.Spec loop
                        View.Visible.Values.Exclude (E.Name.Name);
                        View.Visible.TyCons.Exclude (E.Name.Name);
                        View.Visible.DataCons.Exclude (E.Name.Name);
                        View.Visible.Classes.Exclude (E.Name.Name);
                        View.Visible.Synonyms.Exclude (E.Name.Name);
                     end loop;
                     return;
                  end if;
                  --  Only-list: copy the named entities across.
                  for E of Imp.Spec loop
                     declare
                        Hit : Boolean := False;
                        C : Builtins.Var_Maps.Cursor :=
                          Source.Values.Find (E.Name.Name);
                     begin
                        if Builtins.Var_Maps.Has_Element (C) then
                           View.Visible.Values.Include
                             (E.Name.Name,
                              Builtins.Var_Maps.Element (C));
                           Hit := True;
                        end if;
                        declare
                           TCC : constant Builtins.TyCon_Maps.Cursor
                             := Source.TyCons.Find (E.Name.Name);
                        begin
                           if Builtins.TyCon_Maps.Has_Element (TCC)
                           then
                              View.Visible.TyCons.Include
                                (E.Name.Name,
                                 Builtins.TyCon_Maps.Element (TCC));
                              Hit := True;
                              if E.Sub_All or else E.Has_Subs then
                                 --  T(..) / T(A, f): constructors
                                 --  and selectors travel with T.
                                 declare
                                    TC : constant
                                      Core.Real_TyCon_Id :=
                                        Builtins.TyCon_Maps.Element
                                          (TCC);
                                 begin
                                    for DCI of M.Info (TC).Cons loop
                                       declare
                                          DI : constant
                                            Core.DataCon_Info :=
                                              M.Info
                                                (Core.Real_DataCon_Id
                                                   (DCI));
                                          DCC : constant Builtins
                                            .DataCon_Maps.Cursor :=
                                              Source.DataCons.Find
                                                (DI.Name);
                                       begin
                                          if Builtins.DataCon_Maps
                                            .Has_Element (DCC)
                                          then
                                             View.Visible.DataCons
                                               .Include (DI.Name,
                                                 Builtins.DataCon_Maps
                                                   .Element (DCC));
                                          end if;
                                          for FN of DI.Field_Names
                                          loop
                                             declare
                                                FC : constant Builtins
                                                  .Var_Maps.Cursor :=
                                                    Source.Values.Find
                                                      (FN);
                                             begin
                                                if Builtins.Var_Maps
                                                  .Has_Element (FC)
                                                then
                                                   View.Visible.Values
                                                     .Include (FN,
                                                       Builtins
                                                         .Var_Maps
                                                         .Element
                                                           (FC));
                                                end if;
                                             end;
                                          end loop;
                                       end;
                                    end loop;
                                 end;
                              end if;
                           end if;
                        end;
                        declare
                           CLC : constant Builtins.Class_Maps.Cursor
                             := Source.Classes.Find (E.Name.Name);
                        begin
                           if Builtins.Class_Maps.Has_Element (CLC)
                           then
                              View.Visible.Classes.Include
                                (E.Name.Name,
                                 Builtins.Class_Maps.Element (CLC));
                              Hit := True;
                              if E.Sub_All then
                                 --  C(..): method selectors.
                                 for Mth of M.Info
                                   (Builtins.Class_Maps.Element
                                      (CLC)).Methods
                                 loop
                                    C := Source.Values.Find
                                      (Mth.Name);
                                    if Builtins.Var_Maps.Has_Element
                                      (C)
                                    then
                                       View.Visible.Values.Include
                                         (Mth.Name,
                                          Builtins.Var_Maps.Element
                                            (C));
                                    end if;
                                 end loop;
                              end if;
                           end if;
                        end;
                        if Source.Synonyms.Contains (E.Name.Name)
                        then
                           View.Visible.Synonyms.Include
                             (E.Name.Name,
                              Fixity.Fixity_Info'(others => <>));
                           Hit := True;
                        end if;
                        if not Hit then
                           Bag.Add (Diagnostics.Error,
                                    Diagnostics.Rename_Out_Of_Scope,
                                    Imp.Span,
                                    "module '" & Text (Imp.Module)
                                    & "' does not export '"
                                    & Text (E.Name.Name) & "'");
                        end if;
                     end;
                  end loop;
               end Filter;
            begin
               View.Module := Imp.Module;
               View.Alias := Imp.Alias;
               View.Qualified := Imp.Qualified;
               if Imp.Module = Names.Name_Id (Prelude_Name) then
                  Filter (Reg.Base);
               elsif MI = 0 then
                  Bag.Add (Diagnostics.Error,
                           Diagnostics.Rename_Out_Of_Scope, Imp.Span,
                           "module '" & Text (Imp.Module)
                           & "' has not been compiled");
               else
                  Filter (Reg.Mods (MI).Exports);
               end if;
               Imp_Views.Append (View);
            end;
         end loop;
      end if;

      --  Pass A: types, classes, instances, synonyms first...
      for D of Arena.Top_Decls loop
         declare
            N : constant Decl_Node := Arena.Node (D);
         begin
            case N.Kind is
               when Data_D | Newtype_D =>
                  Declare_Data (D, N);
               when Type_Syn_D =>
                  if Env.Synonyms.Contains (N.S_Name)
                    or else Env.TyCons.Contains (N.S_Name)
                  then
                     Bag.Add (Diagnostics.Error,
                              Diagnostics.Rename_Duplicate, N.Span,
                              "type '" & Text (N.S_Name)
                              & "' is defined more than once");
                  end if;
                  Own.Synonyms.Include
                    (N.S_Name, Fixity.Fixity_Info'(others => <>));
                  Env.Synonyms.Include
                    (N.S_Name,
                     (Arity => Natural (N.S_Vars.Length),
                      Vars => N.S_Vars,
                      Syntax_Rhs => Syntax.Type_Id (N.S_Rhs),
                      Core_Rhs => Core.No_Type));
               when Class_D =>
                  Declare_Class (D, N);
               when others =>
                  null;
            end case;
         end;
      end loop;

      for D of Arena.Top_Decls loop
         declare
            N : constant Decl_Node := Arena.Node (D);
         begin
            if N.Kind = Instance_D then
               Declare_Instance (D, N);
            end if;
         end;
      end loop;

      --  ... then top-level value binders and signatures.
      Declare_Group (Arena.Top_Decls, Global => True);

      --  Pass B: resolve all bodies and types.
      for D of Arena.Top_Decls loop
         declare
            N : constant Decl_Node := Arena.Node (D);
         begin
            case N.Kind is
               when Fun_D | Pat_D =>
                  Rename_Value_Decl (D);
               when Class_D =>
                  Rename_Method_Bodies
                    (N.C_Decls, Res.Decl_Class (Positive (D)));
               when Instance_D =>
                  for A of N.I_Context loop
                     Rename_Assertion (A);
                  end loop;
                  Rename_Type (N.I_Type);
                  Rename_Method_Bodies
                    (N.I_Decls, Res.Decl_Class (Positive (D)));
               when Data_D | Newtype_D =>
                  for C of N.D_Cons loop
                     declare
                        CN : constant Con_Node := Arena.Node (C);
                     begin
                        case CN.Shape is
                           when Prefix_Con | Infix_Con =>
                              for T of CN.Args loop
                                 Rename_Type (T);
                              end loop;
                           when Record_Con =>
                              for F of CN.Fields loop
                                 Rename_Type (F.Field_Type);
                              end loop;
                        end case;
                     end;
                  end loop;
                  for A of N.D_Context loop
                     Rename_Assertion (A);
                  end loop;
               when Type_Syn_D =>
                  Rename_Type (N.S_Rhs);
               when Sig_D =>
                  null;   --  handled in Declare_Group
               when Default_D =>
                  for T of N.Def_Types loop
                     Rename_Type (T);
                  end loop;
               when Fixity_D =>
                  null;
            end case;
         end;
      end loop;

      Pop_Scope;

      --  Register this module's exports: everything top-level, or
      --  the export list's subset (Report 5.2). Re-exports resolve
      --  through imports and Base.
      if Modular then
         declare
            Ent : Modules.Module_Entry;

            procedure Export_All is
            begin
               Ent.Exports := Own;
            end Export_All;

            procedure Export_Listed is
            begin
               for E of Arena.Exports loop
                  case E.Kind is
                     when Module_Ent =>
                        Bag.Add (Diagnostics.Error,
                                 Diagnostics.Rename_Unsupported,
                                 (Start => 1, Stop => 1),
                                 "'module M' re-exports are not"
                                 & " supported");
                     when Var_Ent =>
                        declare
                           R : constant Resolution :=
                             Lookup_Value (E.Name, (1, 1));
                        begin
                           if R.Kind = Var_Res then
                              Ent.Exports.Values.Include
                                (E.Name.Name, R.Var);
                           end if;
                        end;
                     when Type_Ent =>
                        declare
                           TC : constant Core.TyCon_Id :=
                             Mod_Find_TyCon (E.Name.Name);
                           Cl : constant Core.Class_Id :=
                             Mod_Find_Class (E.Name.Name);
                        begin
                           if TC /= Core.No_TyCon then
                              Ent.Exports.TyCons.Include
                                (E.Name.Name,
                                 Core.Real_TyCon_Id (TC));
                              if E.Sub_All or else E.Has_Subs then
                                 for DCI of M.Info
                                   (Core.Real_TyCon_Id (TC)).Cons
                                 loop
                                    declare
                                       DI : constant
                                         Core.DataCon_Info :=
                                           M.Info
                                             (Core.Real_DataCon_Id
                                                (DCI));
                                    begin
                                       Ent.Exports.DataCons.Include
                                         (DI.Name,
                                          Core.Real_DataCon_Id
                                            (DCI));
                                       for FN of DI.Field_Names loop
                                          declare
                                             C : constant Builtins
                                               .Var_Maps.Cursor :=
                                                 Own.Values.Find
                                                   (FN);
                                          begin
                                             if Builtins.Var_Maps
                                               .Has_Element (C)
                                             then
                                                Ent.Exports.Values
                                                  .Include (FN,
                                                    Builtins.Var_Maps
                                                      .Element (C));
                                             end if;
                                          end;
                                       end loop;
                                    end;
                                 end loop;
                              end if;
                           elsif Cl /= Core.No_Class then
                              Ent.Exports.Classes.Include
                                (E.Name.Name,
                                 Core.Real_Class_Id (Cl));
                              if E.Sub_All then
                                 for Mth of M.Info
                                   (Core.Real_Class_Id (Cl)).Methods
                                 loop
                                    declare
                                       C : constant Builtins
                                         .Var_Maps.Cursor :=
                                           Own.Values.Find
                                             (Mth.Name);
                                    begin
                                       if Builtins.Var_Maps
                                         .Has_Element (C)
                                       then
                                          Ent.Exports.Values.Include
                                            (Mth.Name,
                                             Builtins.Var_Maps
                                               .Element (C));
                                       end if;
                                    end;
                                 end loop;
                              end if;
                           elsif Own.Synonyms.Contains (E.Name.Name)
                           then
                              Ent.Exports.Synonyms.Include
                                (E.Name.Name,
                                 Fixity.Fixity_Info'(others => <>));
                           else
                              Bag.Add
                                (Diagnostics.Error,
                                 Diagnostics.Rename_Out_Of_Scope,
                                 (Start => 1, Stop => 1),
                                 "exported type '"
                                 & Text (E.Name.Name)
                                 & "' is not defined");
                           end if;
                        end;
                  end case;
               end loop;
            end Export_Listed;
         begin
            Ent.Name :=
              (if Arena.Module_Name = Names.No_Name
               then Names.Name_Id (Table.Intern ("Main"))
               else Arena.Module_Name);
            if Arena.Has_Export_List then
               Export_Listed;
            else
               Export_All;
            end if;
            --  Synonyms always ride along unless an export list is
            --  present (they are name-only visibility).
            if not Arena.Has_Export_List then
               Ent.Exports.Synonyms := Own.Synonyms;
            end if;
            Ent.Exports.Fixities := Fixities;
            Reg.Mods.Append (Ent);
         end;
      end if;
   end Resolve_Module;

end AHC.Rename;
