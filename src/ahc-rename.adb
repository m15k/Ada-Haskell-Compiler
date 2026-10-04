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

      --  Whose declarations are program-global: only a pass without a
      --  registry - the Prelude (and single-module unit tests), whose
      --  types, constructors, classes and synonyms join the builtins
      --  in Env and reach every module through the Base snapshot. A
      --  user module's declarations live in its own Iface only, so
      --  two modules may declare the same name (M75).
      Global_Scope : constant Boolean := not Modular;

      --  The implicit Prelude this module sees (M144b): a library
      --  module (compiled from lib/ or $AHC_LIB) is base's
      --  internals and sees the whole snapshot; a user module sees
      --  only the Prelude's export list. Pub is always the public
      --  view: own-vs-Prelude ambiguity is judged against what GHC's
      --  Prelude exports, even inside the library.
      --  GHCi scoping (the REPL's generated modules): own declarations
      --  shadow imports and the Prelude, no ambiguity (M144 off).
      Shadow : constant Boolean := Modular and then Arena.Own_Shadows;

      Pre : constant access constant Modules.Iface :=
        (if not Modular then null
         elsif Arena.Is_Library then Reg.Base'Unchecked_Access
         else Reg.Public_Base'Unchecked_Access);
      Pub : constant access constant Modules.Iface :=
        (if not Modular then null
         else Reg.Public_Base'Unchecked_Access);

      --  An explicit `import Prelude ...` suppresses the implicit
      --  whole-Prelude fallback (Report 5.6.1): resolution then goes
      --  through the import's filtered view like any other module.
      Prelude_Explicit : Boolean := False;

      --  Builtin SYNTAX - the unit type/constructor, the list
      --  constructors, tuples - is always in scope (GHC cannot hide
      --  it either: it is grammar, not a Prelude export), so those
      --  names keep the Base fallback even under an explicit
      --  Prelude import. Lists and tuples mostly resolve through
      --  dedicated paths; these are the names that reach the maps.
      Main_Name : constant Names.Real_Name_Id := Table.Intern ("Main");
      --  What this module calls itself in a qualifier: a headerless
      --  root is `Main` (Report 5.1), so `Main.f` must resolve.
      Self_Qual : constant Names.Name_Id :=
        (if Arena.Module_Name = Names.No_Name
         then Names.Name_Id (Main_Name) else Arena.Module_Name);
      Unit_Name : constant Names.Real_Name_Id := Table.Intern ("()");
      Nil_Name  : constant Names.Real_Name_Id := Table.Intern ("[]");
      Cons_Name : constant Names.Real_Name_Id := Table.Intern (":");

      function Is_Builtin_Syntax (N : Names.Name_Id) return Boolean
      is (N = Names.Name_Id (Unit_Name)
          or else N = Names.Name_Id (Nil_Name)
          or else N = Names.Name_Id (Cons_Name));

      --  Does view I answer to qualifier Q? A module may be imported
      --  more than once - Report 5.3.1, and `import Prelude hiding
      --  (String)` beside `import qualified Prelude (String)` in the
      --  wild - and a qualified name is in scope if ANY of those
      --  imports brings it, so every matching view must be asked.
      function View_Matches
        (I : Positive; Q : Names.Name_Id) return Boolean
      is (Imp_Views (I).Alias = Q or else Imp_Views (I).Module = Q);

      --  The FIRST import view matching qualifier Q, 0 if none: for
      --  "is this a legal qualifier at all", never for lookup.
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
           or else Q.Qualifier = Self_Qual
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


      --  How a qualifier scopes a type-level or constructor name
      --  (Report 5.3, 5.5.1): through import names/aliases; the
      --  implicitly imported Prelude (only its own entities); this
      --  module's own name (only its own top level); or none.
      type Qual_Scope is
        (Unqualified, Through_Import, Implicit_Prelude, This_Module);

      function Qual_Kind (Q : Names.Name_Id) return Qual_Scope is
        (if Q = Names.No_Name then Unqualified
         elsif Q = Self_Qual
         then This_Module
         elsif Q = Names.Name_Id (Prelude_Name)
           and then not Prelude_Explicit then Implicit_Prelude
         else Through_Import);

      --  Import-aware resolution for type constructors, data
      --  constructors and classes - one shape for all three (M75).
      --  Qualified through an import name or alias: only those
      --  imports' exports (Report 5.3). Unqualified: this module's
      --  own declarations, then every unqualified import, then Base.
      --  Two DIFFERENT entities reached through imports are an
      --  ambiguity, reported here at the use site (Report 5.5.2);
      --  one entity re-exported along two paths is not. Amb tells
      --  the caller not to add a "not in scope" error on top. Without
      --  a registry (the Prelude pass) the flat Env is the scope.
      generic
         type Id is range <>;
         None : Id;
         with function In_Iface
           (I : Modules.Iface; N : Names.Name_Id) return Id;
         with function In_Env (N : Names.Name_Id) return Id;
         --  A wired placeholder a module may shadow (the builtin
         --  Rational, Text, ...): an import beats it, no ambiguity.
         with function Shadowable (X : Id) return Boolean;
         What : String;
      function Mod_Find_G
        (Q : Syntax.QName; Span : Diagnostics.Source_Span;
         Amb : out Boolean) return Id
        with Post => (if Amb then Mod_Find_G'Result = None);

      function Mod_Find_G
        (Q : Syntax.QName; Span : Diagnostics.Source_Span;
         Amb : out Boolean) return Id
      is
         Found : Id := None;

         procedure Take (X : Id) is
         begin
            if X = None then
               return;
            elsif Found = None then
               Found := X;
            elsif X /= Found then
               Amb := True;
            end if;
         end Take;
      begin
         Amb := False;
         if not Modular then
            return In_Env (Q.Name);
         end if;
         case Qual_Kind (Q.Qualifier) is
            when Through_Import =>
               for I in 1 .. Imp_Views.Last_Index loop
                  if View_Matches (I, Q.Qualifier) then
                     Take (In_Iface (Imp_Views (I).Visible, Q.Name));
                  end if;
               end loop;
            when Implicit_Prelude =>
               --  Prelude.T: only the Prelude, never this module's
               --  or an import's T (mirrors Lookup_Value).
               Found := In_Iface (Pre.all, Q.Name);
            when This_Module =>
               --  M.T inside M: only M's own declarations.
               Found := In_Iface (Own, Q.Name);
            when Unqualified =>
               --  An own declaration counts as one entity among the
               --  unqualified imports and the implicit Prelude: a
               --  different entity under the same name is ambiguous
               --  at this use (M144, Report 5.5.2). Wired
               --  placeholders the module defines are exempt.
               Found := In_Iface (Own, Q.Name);
               if Found /= None and then Shadow then
                  return Found;
               end if;
               if Found /= None then
                  for V of Imp_Views loop
                     if not V.Qualified then
                        declare
                           X : constant Id := In_Iface (V.Visible, Q.Name);
                        begin
                           if X /= None and then X /= Found
                             and then not (Arena.Is_Library
                                           and then Shadowable (X))
                           then
                              Amb := True;
                           end if;
                        end;
                     end if;
                  end loop;
                  if not Prelude_Explicit then
                     declare
                        B : constant Id := In_Iface (Pub.all, Q.Name);
                     begin
                        if B /= None and then B /= Found
                          and then not (Arena.Is_Library
                                        and then Shadowable (B))
                        then
                           Amb := True;
                        end if;
                     end;
                  end if;
                  if Amb then
                     Bag.Add (Diagnostics.Error,
                              Diagnostics.Rename_Out_Of_Scope, Span,
                              "ambiguous " & What & " '" & Text (Q.Name)
                              & "' (declared in this module and"
                              & " imported)");
                     return None;
                  end if;
                  return Found;
               end if;
               for V of Imp_Views loop
                  if not V.Qualified then
                     Take (In_Iface (V.Visible, Q.Name));
                  end if;
               end loop;
               if not Prelude_Explicit
                 or else Is_Builtin_Syntax (Q.Name)
               then
                  declare
                     B : constant Id := In_Iface (Pre.all, Q.Name);
                  begin
                     --  An import and the implicit Prelude naming two
                     --  different entities are ambiguous (Report
                     --  5.5.2) - unless the Prelude's is a wired
                     --  placeholder the import defines.
                     if Found = None then
                        Found := B;
                     elsif B /= None and then not Shadowable (B) then
                        Take (B);
                     end if;
                  end;
               end if;
         end case;
         if Amb then
            Bag.Add (Diagnostics.Error, Diagnostics.Rename_Out_Of_Scope,
                     Span,
                     "ambiguous " & What & " '" & Text (Q.Name)
                     & "' (imported from several modules)");
            return None;
         end if;
         return Found;
      end Mod_Find_G;

      function TyCon_In
        (I : Modules.Iface; N : Names.Name_Id) return Core.TyCon_Id
      is (if I.TyCons.Contains (N)
          then Core.TyCon_Id (I.TyCons.Element (N)) else Core.No_TyCon);
      function TyCon_Env (N : Names.Name_Id) return Core.TyCon_Id
      is (if Env.TyCons.Contains (N)
          then Core.TyCon_Id (Env.TyCons.Element (N)) else Core.No_TyCon);
      function DataCon_In
        (I : Modules.Iface; N : Names.Name_Id) return Core.DataCon_Id
      is (if I.DataCons.Contains (N)
          then Core.DataCon_Id (I.DataCons.Element (N)) else 0);
      function DataCon_Env (N : Names.Name_Id) return Core.DataCon_Id
      is (if Env.DataCons.Contains (N)
          then Core.DataCon_Id (Env.DataCons.Element (N)) else 0);
      function Class_In
        (I : Modules.Iface; N : Names.Name_Id) return Core.Class_Id
      is (if I.Classes.Contains (N)
          then Core.Class_Id (I.Classes.Element (N)) else Core.No_Class);
      function Class_Env (N : Names.Name_Id) return Core.Class_Id
      is (if Env.Classes.Contains (N)
          then Core.Class_Id (Env.Classes.Element (N)) else Core.No_Class);

      --  A wired PLACEHOLDER: a builtin TyCon with no constructors
      --  (the abstract Rational, Text, IORef, ...) that a library may
      --  define or re-export. Wired types with constructors - Maybe,
      --  Bool, Ordering - are real Prelude types, and an import of a
      --  different Maybe is ambiguous with them (Report 5.5.2).
      function TyCon_Wired (X : Core.TyCon_Id) return Boolean
      is (M.Info (Core.Real_TyCon_Id (X)).Is_Builtin
          and then M.Info (Core.Real_TyCon_Id (X)).Cons.Is_Empty);
      function DataCon_Wired (X : Core.DataCon_Id) return Boolean is
         pragma Unreferenced (X);
      begin
         return False;   --  a constructor's type is never a placeholder
      end DataCon_Wired;
      function Class_Wired (X : Core.Class_Id) return Boolean is
         pragma Unreferenced (X);
      begin
         return False;   --  every Prelude class is a source class
      end Class_Wired;

      function Mod_Find_TyCon is new Mod_Find_G
        (Core.TyCon_Id, Core.No_TyCon, TyCon_In, TyCon_Env,
         TyCon_Wired, "type");
      function Mod_Find_DataCon is new Mod_Find_G
        (Core.DataCon_Id, 0, DataCon_In, DataCon_Env,
         DataCon_Wired, "constructor");
      function Mod_Find_Class is new Mod_Find_G
        (Core.Class_Id, Core.No_Class, Class_In, Class_Env,
         Class_Wired, "class");

      --  The synonym a type-constructor name resolves to, scoped
      --  exactly as Mod_Find_G scopes a TyCon. Found is False when no
      --  synonym of that name is in scope. The record, not the name,
      --  is what Kinds expands (M75); its Owner is its identity, so
      --  two DIFFERENT imported synonyms are ambiguous (reported here,
      --  Amb set) while one re-exported along two paths is not.
      procedure Mod_Find_Syn
        (Q     : Syntax.QName;
         Span  : Diagnostics.Source_Span;
         Found : out Boolean;
         Ref   : out Syn_Ref;
         Amb   : out Boolean)
      is
         procedure Take (Syns : Builtins.Syn_Maps.Map) is
         begin
            if not Syns.Contains (Q.Name) then
               return;
            end if;
            declare
               S : constant Builtins.Syn_Rec := Syns (Q.Name);
            begin
               if not Found then
                  Found := True;
                  Ref := (Is_Own => False, Name => Q.Name, Rec => S);
               elsif Ref.Rec.Owner /= S.Owner then
                  Amb := True;
               end if;
            end;
         end Take;
      begin
         Found := False;
         Amb := False;
         Ref := (Is_Own => True, Name => Q.Name, others => <>);
         if not Modular then
            if Own.Synonyms.Contains (Q.Name) then
               Found := True;
            else
               Take (Env.Synonyms);
            end if;
            return;
         end if;
         case Qual_Kind (Q.Qualifier) is
            when Through_Import =>
               for I in 1 .. Imp_Views.Last_Index loop
                  if View_Matches (I, Q.Qualifier) then
                     Take (Imp_Views (I).Visible.Synonyms);
                  end if;
               end loop;
            when Implicit_Prelude =>
               Take (Pre.Synonyms);
            when This_Module =>
               Found := Own.Synonyms.Contains (Q.Name);
               return;
            when Unqualified =>
               if Own.Synonyms.Contains (Q.Name) and then Shadow then
                  Found := True;
                  return;
               end if;
               if Own.Synonyms.Contains (Q.Name) then
                  Found := True;
                  --  M144: ambiguous with an unqualified import's or
                  --  the Prelude's synonym of that name.
                  for V of Imp_Views loop
                     if not V.Qualified
                       and then V.Visible.Synonyms.Contains (Q.Name)
                     then
                        Amb := True;
                     end if;
                  end loop;
                  if not Prelude_Explicit
                    and then Pub.Synonyms.Contains (Q.Name)
                  then
                     Amb := True;
                  end if;
                  if Amb then
                     Found := False;
                     Bag.Add (Diagnostics.Error,
                              Diagnostics.Rename_Out_Of_Scope, Span,
                              "ambiguous type '" & Text (Q.Name)
                              & "' (declared in this module and"
                              & " imported)");
                  end if;
                  return;
               end if;
               for V of Imp_Views loop
                  if not V.Qualified then
                     Take (V.Visible.Synonyms);
                  end if;
               end loop;
               if not Prelude_Explicit then
                  Take (Pre.Synonyms);
               end if;
         end case;
         if Amb then
            Found := False;
            Bag.Add (Diagnostics.Error, Diagnostics.Rename_Out_Of_Scope,
                     Span,
                     "ambiguous type '" & Text (Q.Name)
                     & "' (imported from several modules)");
         end if;
      end Mod_Find_Syn;

      --  A type-level name may be visible as a TyCon AND as a synonym
      --  (M75). A synonym beats a wired placeholder it shadows (`type
      --  Rational = Ratio Integer`); otherwise this module's own
      --  declaration beats an imported one (the documented own-wins
      --  policy), and two imported entities are ambiguous (Report
      --  5.5.2). Ambiguity is reported here; Neither is not.
      type Ty_Choice is (Neither, Take_TyCon, Take_Syn, Ambiguous);

      procedure Resolve_Ty
        (Q      : Syntax.QName;
         Span   : Diagnostics.Source_Span;
         TC     : out Core.TyCon_Id;
         Syn    : out Syn_Ref;
         Choice : out Ty_Choice)
      is
         Amb_T, Amb_S, SF : Boolean;
      begin
         TC := Mod_Find_TyCon (Q, Span, Amb_T);
         Mod_Find_Syn (Q, Span, SF, Syn, Amb_S);
         if Amb_T or else Amb_S then
            Choice := Ambiguous;
         elsif TC = Core.No_TyCon then
            Choice := (if SF then Take_Syn else Neither);
         elsif not SF then
            Choice := Take_TyCon;
            --  The wired placeholder a library DEFINES: the Prelude's
            --  Rational means Data.Ratio's `Ratio Integer` once that
            --  module is in the program, whether or not this import
            --  list names its synonym (GHC: Rational is a Prelude
            --  export). Env.Synonyms holds that one library synonym
            --  and the Prelude's own, nothing else (M75).
            if TyCon_Wired (TC) then
               declare
                  PN : constant Names.Name_Id :=
                    M.Info (Core.Real_TyCon_Id (TC)).Name;
               begin
                  if Env.Synonyms.Contains (PN) then
                     Syn := (Is_Own => False, Name => PN,
                             Rec => Env.Synonyms.Element (PN));
                     Choice := Take_Syn;
                  end if;
               end;
            end if;
         elsif Shadow
           and then (Syn.Is_Own or else Own.TyCons.Contains (Q.Name))
         then
            Choice := (if Syn.Is_Own then Take_Syn else Take_TyCon);
         elsif M.Info (Core.Real_TyCon_Id (TC)).Is_Builtin then
            --  A synonym beats a wired placeholder it shadows. A
            --  Prelude type proper (Maybe, Either, ...) and a synonym
            --  of the same name are ambiguous when GHC's Prelude
            --  exports that name (M144); a builtin it does not export
            --  (Int8, ...) is shadowed as before.
            if Modular and then Q.Qualifier = Names.No_Name
              and then Pub.TyCons.Contains (Q.Name)
              and then (not TyCon_Wired (TC)
                        or else (Syn.Is_Own
                                 and then not Arena.Is_Library))
            then
               Choice := Ambiguous;
               Bag.Add (Diagnostics.Error,
                        Diagnostics.Rename_Out_Of_Scope, Span,
                        "ambiguous type '" & Text (Q.Name)
                        & "' (declared in this module and imported)");
            else
               Choice := Take_Syn;
            end if;
         else
            Choice := Ambiguous;
            Bag.Add (Diagnostics.Error,
                     Diagnostics.Rename_Out_Of_Scope, Span,
                     "ambiguous type '" & Text (Q.Name)
                     & "' (imported from several modules)");
         end if;
      end Resolve_Ty;

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

      --  Set when Lookup_Value reported an ambiguity (even Quiet): a
      --  caller about to add "unknown field" says the ambiguity instead.
      Value_Amb_Reported : Boolean := False;

      --  Quiet: answer "is this name in scope" without reporting.
      --  The export list's C(..) asks that of every method of a class
      --  it may only have imported; a method that is not in scope is
      --  simply not re-exported, not an error at the class.
      function Lookup_Value
        (Q : QName; Span : Diagnostics.Source_Span;
         Quiet : Boolean := False) return Resolution
      is
         procedure Not_In_Scope is
         begin
            if not Quiet then
               Bag.Add (Diagnostics.Error,
                        Diagnostics.Rename_Out_Of_Scope, Span,
                        "variable not in scope: " & Text (Q.Name));
            end if;
         end Not_In_Scope;
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
              and then (Q.Qualifier /= Names.Name_Id (Prelude_Name)
                        or else Prelude_Explicit)
              and then Q.Qualifier /= Self_Qual
            then
               declare
                  C : Builtins.Var_Maps.Cursor;
               begin
                  for I in 1 .. Imp_Views.Last_Index loop
                     if View_Matches (I, Q.Qualifier) then
                        C := Imp_Views (I).Visible.Values.Find
                               (Q.Name);
                        if Builtins.Var_Maps.Has_Element (C) then
                           return (Kind => Var_Res,
                                   Var => Builtins.Var_Maps.Element
                                            (C));
                        end if;
                     end if;
                  end loop;
                  Bag.Add (Diagnostics.Error,
                           Diagnostics.Rename_Out_Of_Scope, Span,
                           "module '" & Text (Q.Qualifier)
                           & "' does not export '"
                           & Text (Q.Name) & "'");
                  return (Kind => Unresolved);
               end;
            end if;
            --  Prelude-qualified through the IMPLICIT import: only
            --  the Prelude itself - never the module's own binding
            --  of the same bare name (Prelude.filter must not find
            --  a local filter).
            if Q.Qualifier = Names.Name_Id (Prelude_Name)
              and then Q.Qualifier /= Self_Qual
            then
               declare
                  C : constant Builtins.Var_Maps.Cursor :=
                    Pre.Values.Find (Q.Name);
               begin
                  if Builtins.Var_Maps.Has_Element (C) then
                     return (Kind => Var_Res,
                             Var => Builtins.Var_Maps.Element (C));
                  end if;
                  Bag.Add (Diagnostics.Error,
                           Diagnostics.Rename_Out_Of_Scope, Span,
                           "'Prelude' does not export '"
                           & Text (Q.Name) & "'");
                  return (Kind => Unresolved);
               end;
            end if;
            --  Own module: at an UNQUALIFIED use the own binding is
            --  one entity among the unqualified imports' and the
            --  implicit Prelude's - a different one under the same
            --  name is ambiguous (M144, Report 5.5.2).
            declare
               C : constant Builtins.Var_Maps.Cursor :=
                 Own.Values.Find (Q.Name);
            begin
               if Builtins.Var_Maps.Has_Element (C) then
                  if Q.Qualifier = Names.No_Name and then not Shadow then
                     declare
                        Mine : constant Core.Var_Id := Core.Var_Id
                          (Builtins.Var_Maps.Element (C));
                        Amb  : Boolean := False;
                     begin
                        for V of Imp_Views loop
                           if not V.Qualified then
                              declare
                                 IC : constant Builtins.Var_Maps.Cursor :=
                                   V.Visible.Values.Find (Q.Name);
                              begin
                                 if Builtins.Var_Maps.Has_Element (IC)
                                   and then Core.Var_Id
                                     (Builtins.Var_Maps.Element (IC))
                                     /= Mine
                                 then
                                    Amb := True;
                                 end if;
                              end;
                           end if;
                        end loop;
                        if not Prelude_Explicit then
                           declare
                              BC : constant Builtins.Var_Maps.Cursor :=
                                Pub.Values.Find (Q.Name);
                           begin
                              if Builtins.Var_Maps.Has_Element (BC)
                                and then Core.Var_Id
                                  (Builtins.Var_Maps.Element (BC)) /= Mine
                              then
                                 Amb := True;
                              end if;
                           end;
                        end if;
                        if Amb then
                           Value_Amb_Reported := True;
                           Bag.Add
                             (Diagnostics.Error,
                              Diagnostics.Rename_Out_Of_Scope, Span,
                              "ambiguous name '" & Text (Q.Name)
                              & "' (declared in this module and"
                              & " imported)");
                           return (Kind => Unresolved);
                        end if;
                     end;
                  end if;
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
                     Value_Amb_Reported := True;
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
            --  Base: builtins + Prelude (implicit import only).
            if not Prelude_Explicit then
               declare
                  C : constant Builtins.Var_Maps.Cursor :=
                    Pre.Values.Find (Q.Name);
               begin
                  if Builtins.Var_Maps.Has_Element (C) then
                     return (Kind => Var_Res,
                             Var => Builtins.Var_Maps.Element (C));
                  end if;
               end;
            end if;
            Not_In_Scope;
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
         Not_In_Scope;
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
            Amb : Boolean;
            DC : constant Core.DataCon_Id :=
              Mod_Find_DataCon (Q, Span, Amb);
         begin
            if DC /= 0 then
               return (Kind => Data_Res,
                       Con => Core.Real_DataCon_Id (DC));
            elsif Amb then
               return (Kind => Unresolved);
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
                  Amb : Boolean;
                  Cl : constant Core.Class_Id :=
                    Mod_Find_Class (N.Con, N.Span, Amb);
               begin
                  if Cl /= Core.No_Class then
                     Res.Class_Res.Replace_Element
                       (Positive (Id), Cl);
                  elsif not Amb then
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
                  TC : Core.TyCon_Id;
                  Syn : Syn_Ref;
                  Choice : Ty_Choice;
               begin
                  Resolve_Ty (N.Con, N.Span, TC, Syn, Choice);
                  case Choice is
                     when Take_TyCon =>
                        Res.Ty_Res.Replace_Element (Positive (Id), TC);
                     when Take_Syn =>
                        --  Expanded during conversion, through the
                        --  record resolved here.
                        Res.Syn_Res.Include (Positive (Id), Syn);
                     when Neither =>
                        Bag.Add (Diagnostics.Error,
                                 Diagnostics.Rename_Out_Of_Scope, N.Span,
                                 "type not in scope: "
                                 & Text (N.Con.Name));
                     when Ambiguous =>
                        null;   --  reported by Resolve_Ty
                  end case;
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
                  if Global_Scope then
                     Env.Values.Include (Name, V);
                  end if;
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
                     --  A field label is a name in scope: ambiguous
                     --  with an import's or the Prelude's (M144).
                     declare
                        Ignore : constant Resolution :=
                          Lookup_Value (F.Field, N.Span, Quiet => True);
                     begin
                        null;
                     end;
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

      --  Each binding statement of a do block, comprehension or
      --  pattern guard opens a NEW scope over the statements after it
      --  (Report 3.14: `do {p <- e; stmts}` = `e >>= \p -> do {stmts}`),
      --  so `x <- a; x <- b` shadows rather than clashing (M142
      --  review); only a name bound twice by ONE pattern or let group
      --  is an error. The caller pops the scopes this pushed, after
      --  renaming whatever the binders scope over.
      Stmt_Scopes : Natural := 0;

      --  Pop the statement scopes pushed since Mark.
      procedure Pop_Stmt_Scopes (Mark : Natural) is
      begin
         while Stmt_Scopes > Mark loop
            Pop_Scope;
            Stmt_Scopes := Stmt_Scopes - 1;
         end loop;
      end Pop_Stmt_Scopes;

      procedure Rename_Stmt (Id : Real_Stmt_Id);

      procedure Rename_Rhs (R : Rhs) is
      begin
         if R.Guarded then
            --  Pattern-guard binders scope over the later qualifiers
            --  and the alternative's body (Report 3.13).
            for G of R.Guards loop
               declare
                  Mark : constant Natural := Stmt_Scopes;
               begin
                  Push_Scope;
                  for Q of G.Quals loop
                     Rename_Stmt (Q);
                  end loop;
                  Rename_Expr (G.G_Body);
                  Pop_Stmt_Scopes (Mark);
                  Pop_Scope;
               end;
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
               Push_Scope;
               Stmt_Scopes := Stmt_Scopes + 1;
               Rename_Pat (N.Bind_Pat);
            when Let_S =>
               Push_Scope;
               Stmt_Scopes := Stmt_Scopes + 1;
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
               declare
                  Mark : constant Natural := Stmt_Scopes;
               begin
                  Push_Scope;
                  for S of N.Stmts loop
                     Rename_Stmt (S);
                  end loop;
                  Pop_Stmt_Scopes (Mark);
                  Pop_Scope;
               end;
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
               declare
                  Mark : constant Natural := Stmt_Scopes;
               begin
                  Push_Scope;
                  for S of N.Comp_Quals loop
                     Rename_Stmt (S);
                  end loop;
                  Rename_Expr (N.Comp_Expr);
                  Pop_Stmt_Scopes (Mark);
                  Pop_Scope;
               end;
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
               --  Each field resolves through scope like any value
               --  (its qualifier honoured) and must be a selector.
               --  Construction then matches by name WITHIN its one
               --  constructor; an update keeps the selectors, which
               --  identify the fields program-wide (M75).
               Rename_Expr (N.Rec_Base);
               declare
                  Sels : Core.Var_Id_Vectors.Vector;
               begin
                  for F of N.Rec_Fields loop
                     Value_Amb_Reported := False;
                     declare
                        R : constant Resolution :=
                          Lookup_Value (F.Field, N.Span, Quiet => True);
                     begin
                        if R.Kind = Var_Res and then M.Info (R.Var).Is_Field
                        then
                           Sels.Append (R.Var);
                        elsif Value_Amb_Reported then
                           null;   --  the ambiguity was reported
                        else
                           Bag.Add (Diagnostics.Error,
                                    Diagnostics.Rename_Field_Error,
                                    N.Span,
                                    "unknown field '"
                                    & Text (F.Field.Name) & "'");
                        end if;
                     end;
                     Rename_Expr (F.Value);
                  end loop;
                  if N.Kind = Rec_Update_E then
                     Res.Field_Res.Include (Positive (Id), Sels);
                  end if;
               end;
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
         if not Global then
            for D of Decls loop
               if Arena.Node (D).Kind = Foreign_D then
                  Bag.Add (Diagnostics.Error,
                           Diagnostics.Rename_Unsupported,
                           Arena.Node (D).Span,
                           "foreign declarations are only allowed at "
                           & "the top level");
               end if;
            end loop;
         end if;
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
                        if Global_Scope then
                           Env.Values.Include (U.Name, V);
                        end if;
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

      --  A derivable class (Report 4.3.3, 10): the Prelude's Eq, Ord,
      --  Enum, Bounded, Show or Read - Env holds only builtin and
      --  Prelude classes - or Data.Ix's Ix, by identity.
      function Stock_Derivable
        (C : Core.Class_Id; Name : Names.Name_Id) return Boolean
      is
         T : constant String := Text (Name);
      begin
         if T in "Eq" | "Ord" | "Enum" | "Bounded" | "Show" | "Read" then
            return Env.Classes.Contains (Name)
              and then Core.Class_Id (Env.Classes.Element (Name)) = C;
         elsif T = "Ix" and then Modular then
            declare
               MI : constant Natural :=
                 Modules.Find (Reg.all, Table.Intern ("Data.Ix"));
            begin
               return MI /= 0
                 and then Reg.Mods (MI).Exports.Classes.Contains (Name)
                 and then Core.Class_Id
                   (Reg.Mods (MI).Exports.Classes.Element (Name)) = C;
            end;
         end if;
         return False;
      end Stock_Derivable;

      procedure Declare_Data (D : Real_Decl_Id; N : Decl_Node) is
         Is_NT : constant Boolean := N.Kind = Newtype_D;
         TC : Core.Real_TyCon_Id;
         Type_Fields : Scope_Maps.Map;   --  field -> this type's selector
      begin
         --  Report 4.2.1: one module may not declare a type name
         --  twice. ACROSS modules it is legal and qualified imports
         --  disambiguate, so this asks Own, not Env (M75); a builtin
         --  is never in Own, so shadowing one stays legal
         --  (Data.Ratio's Rational shadows the wired-in abstract one).
         declare
            Clash : constant Boolean :=
              Own.TyCons.Contains (N.D_Name)
                or else Own.Synonyms.Contains (N.D_Name);
         begin
            if Clash then
               Bag.Add (Diagnostics.Error,
                        Diagnostics.Rename_Duplicate,
                        N.Span,
                        "type '" & Text (N.D_Name)
                        & "' is defined more than once");
            end if;
         end;
         TC := M.Mint_TyCon
           ((Name => N.D_Name, Arity => Natural (N.D_Vars.Length),
             Is_Newtype => Is_NT, Owner => Arena.Module_Name,
             others => <>));
         if Global_Scope then
            Env.TyCons.Include (N.D_Name, TC);
         end if;
         Own.TyCons.Include (N.D_Name, TC);
         Res.Decl_TyCon.Replace_Element (Positive (D), Core.TyCon_Id (TC));

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
               --  Field selector globals (schemes come from
               --  AHC.Kinds; bodies from the desugarer), minted per
               --  module: constructors of THIS type share one
               --  selector per field; any other top-level binding of
               --  the name in this module is a duplicate (Report
               --  3.15.1), and another module's is unrelated (M75).
               for FN of Info.Field_Names loop
                  if Type_Fields.Contains (FN) then
                     Info.Field_Sels.Append (Type_Fields (FN));
                  else
                     declare
                        Sel : constant Core.Real_Var_Id :=
                          M.Mint_Var ((Name => FN, Span => CN.Span,
                                       Is_Global => True,
                                       Is_Field => True,
                                       others => <>));
                     begin
                        if Top_Names.Contains (FN) then
                           Bag.Add (Diagnostics.Error,
                                    Diagnostics.Rename_Duplicate,
                                    CN.Span,
                                    "'" & Text (FN)
                                    & "' is defined more than once");
                        end if;
                        Top_Names.Include (FN, Sel);
                        Type_Fields.Include (FN, Sel);
                        if Global_Scope then
                           Env.Values.Include (FN, Sel);
                        end if;
                        Own.Values.Include (FN, Sel);
                        Info.Field_Sels.Append (Sel);
                     end;
                  end if;
               end loop;
               if Own.DataCons.Contains (Info.Name) then
                  Bag.Add (Diagnostics.Error,
                           Diagnostics.Rename_Duplicate, CN.Span,
                           "constructor '" & Text (Info.Name)
                           & "' is defined more than once");
               end if;
               declare
                  DC : constant Core.Real_DataCon_Id :=
                    M.Mint_DataCon (Info);
               begin
                  if Global_Scope then
                     Env.DataCons.Include (Info.Name, DC);
                  end if;
                  Own.DataCons.Include (Info.Name, DC);
                  Res.Decl_Con.Replace_Element
                    (Positive (N.D_Cons.Element (CI)), Core.DataCon_Id (DC));
               end;
            end;
         end loop;

         --  deriving (C1, ...): register signature-only instances so
         --  derived classes participate in context reduction.
         for DC of N.D_Deriving loop
            declare
               Amb : Boolean;
               C : constant Core.Class_Id :=
                 Mod_Find_Class (DC, N.Span, Amb);
            begin
               if C /= Core.No_Class
                 and then not Stock_Derivable (C, DC.Name)
               then
                  --  Report 4.3.3: only the standard classes derive.
                  --  A same-named user class must not reach the
                  --  deriving machinery, which dispatches on the
                  --  class's name (M75 review: a user `class Read`
                  --  crashed it).
                  Bag.Add (Diagnostics.Error,
                           Diagnostics.Rename_Unsupported, N.Span,
                           "cannot derive '" & Text (DC.Name)
                           & "': not a stock derivable class");
               elsif C /= Core.No_Class then
                  --  Enum/Bounded/Ix derive only for ENUMERATIONS
                  --  here; a non-nullary constructor is a
                  --  compile-time rejection (GHC rejects most of
                  --  these shapes too; the ones it accepts -
                  --  single-constructor Bounded/Ix - are honestly
                  --  unimplemented, and a loud error beats the
                  --  runtime stub it used to be). Read is NOT in
                  --  that list since M141: it derives for every
                  --  shape, as the inverse of derived Show.
                  declare
                     DN : constant String := Text (DC.Name);
                  begin
                     if DN in "Enum" | "Bounded" | "Ix" then
                        for CI of N.D_Cons loop
                           declare
                              CN : constant Con_Node :=
                                Arena.Node (CI);
                              Nullary : Boolean := True;
                           begin
                              case CN.Shape is
                                 when Prefix_Con | Infix_Con =>
                                    Nullary := CN.Args.Is_Empty;
                                 when Record_Con =>
                                    Nullary := CN.Fields.Is_Empty;
                              end case;
                              if not Nullary then
                                 Bag.Add
                                   (Diagnostics.Error,
                                    Diagnostics.Rename_Unsupported,
                                    N.Span,
                                    "cannot derive " & DN & " for '"
                                    & Text (N.D_Name)
                                    & "': all constructors must "
                                    & "be nullary");
                                 goto Next_Derive;
                              end if;
                           end;
                        end loop;
                     end if;
                  end;
                  declare
                     Cl : constant Core.Real_Class_Id :=
                       Core.Real_Class_Id (C);
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
                         From_Source => False,   --  deriving clause
                         Method_Binds =>
                           Core.Bind_Vectors.Empty_Vector,
                         Param_Vars =>
                           Core.Var_Id_Vectors.Empty_Vector,
                         Span => N.Span));
                     pragma Unreferenced (Ignore);
                  end;
               elsif not Amb then
                  Bag.Add (Diagnostics.Error,
                           Diagnostics.Rename_Out_Of_Scope, N.Span,
                           "cannot derive unknown class '"
                           & Text (DC.Name) & "'");
               end if;
            end;
            <<Next_Derive>>
         end loop;
      end Declare_Data;

      procedure Declare_Class (D : Real_Decl_Id; N : Decl_Node) is
         Star_K : constant Core.Real_Kind_Id := M.Star;
         Dict_TC : Core.Real_TyCon_Id;
         Cl : Core.Real_Class_Id;
      begin
         if Own.Classes.Contains (N.C_Name) then
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
         if Global_Scope then
            Env.Classes.Include (N.C_Name, Cl);
         end if;
         Own.Classes.Include (N.C_Name, Cl);
         Res.Decl_Class.Replace_Element
           (Positive (D), Core.Class_Id (Cl));
      end Declare_Class;

      --  A class's superclasses and methods, resolved only after
      --  every type, synonym and class NAME of the module is declared:
      --  a method signature or a superclass may name a declaration
      --  further down the file (M75 review: they were "not in scope",
      --  or silently bound to a same-named import).
      procedure Fill_Class (D : Real_Decl_Id; N : Decl_Node) is
         Cl : constant Core.Real_Class_Id :=
           Core.Real_Class_Id (Res.Decl_Class.Element (Positive (D)));
      begin
         --  Superclasses from the context.
         for A of N.C_Context loop
            declare
               AN : constant Type_Node := Arena.Node (A);
            begin
               if AN.Kind = App_T
                 and then Arena.Node (AN.Fun).Kind = Con_T
               then
                  declare
                     FN : constant Type_Node := Arena.Node (AN.Fun);
                     Amb : Boolean;
                     SC : constant Core.Class_Id :=
                       Mod_Find_Class (FN.Con, FN.Span, Amb);
                  begin
                     if SC /= Core.No_Class then
                        M.Classes (Cl).Supers.Append
                          (Core.Real_Class_Id (SC));
                     elsif not Amb then
                        Bag.Add (Diagnostics.Error,
                                 Diagnostics.Rename_Out_Of_Scope,
                                 FN.Span,
                                 "class not in scope: "
                                 & Text (FN.Con.Name));
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
                        if Global_Scope then
                           Env.Values.Include (Q.Name, Sel);
                        end if;
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
      end Fill_Class;

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
                  Amb : Boolean;
                  TC2 : constant Core.TyCon_Id :=
                    Mod_Find_TyCon (N.Con, Span, Amb);
               begin
                  if TC2 /= Core.No_TyCon or else Amb then
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
         Amb : Boolean;
         ClC : constant Core.Class_Id :=
           Mod_Find_Class (N.I_Class, N.Span, Amb);
         Head : Core.TyCon_Id;
      begin
         if Amb then
            return;
         elsif ClC = Core.No_Class then
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
              Core.Real_Class_Id (ClC);
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
               Inst : Core.Real_Instance_Id;
            begin
               --  Head_Vars and Context are filled by AHC.Kinds once
               --  the instance type is converted.
               Inst := M.Mint_Instance
                 ((Of_Class => Core.Class_Id (Cl), Head => Head,
                   Head_Vars => Core.TyVar_Id_Vectors.Empty_Vector,
                   Context => Core.Constraint_Vectors.Empty_Vector,
                   Dict_Global => Core.Var_Id (Dict),
                   From_Source => True,
                   Method_Binds => Core.Bind_Vectors.Empty_Vector,
                   Param_Vars => Core.Var_Id_Vectors.Empty_Vector,
                   Span => N.Span));
               Res.Decl_Inst.Replace_Element
                 (Positive (D), Core.Instance_Id (Inst));
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
                     declare
                        procedure Check_Method
                          (Name : Names.Name_Id;
                           Span : Diagnostics.Source_Span)
                        is
                           Known : Boolean := False;
                        begin
                           if Of_Class in 1 .. M.Last_Class then
                              for Mth of M.Classes
                                (Core.Real_Class_Id (Of_Class)).Methods
                              loop
                                 if Mth.Name = Name then
                                    Known := True;
                                 end if;
                              end loop;
                              if not Known then
                                 Bag.Add
                                   (Diagnostics.Error,
                                    Diagnostics.Class_Missing_Method,
                                    Span,
                                    "'" & Text (Name)
                                    & "' is not a method of the class");
                              end if;
                           end if;
                        end Check_Method;
                     begin
                        if N.Kind = Fun_D then
                           declare
                              V : constant Core.Real_Var_Id :=
                                Mint_Local (N.Fun_Name, N.Span);
                           begin
                              Res.Decl_Var.Replace_Element
                                (Positive (D), Core.Var_Id (V));
                              Check_Method (N.Fun_Name, N.Span);
                           end;
                        elsif Arena.Node (N.Pat).Kind = Var_P then
                           --  A nullary method body (mempty = ...):
                           --  the pattern var IS the method name.
                           --  Top-level Pat_Ds get their pattern
                           --  renamed by Declare_Group; here we mint
                           --  the dictionary-field local directly,
                           --  so desugar's Ds_Group sees a plain
                           --  Var_Res bind instead of falling into
                           --  the $pb selector translation.
                           declare
                              PN : constant Pat_Node :=
                                Arena.Node (N.Pat);
                              V : constant Core.Real_Var_Id :=
                                Mint_Local (PN.Var, PN.Span);
                           begin
                              Set_Pat (N.Pat,
                                       (Kind => Var_Res, Var => V));
                              Check_Method (PN.Var, PN.Span);
                           end;
                        end if;
                     end;
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
         Res.Decl_TyCon.Append (Core.No_TyCon);
         Res.Decl_Inst.Append (0);
         Res.Decl_Class.Append (Core.No_Class);
      end loop;
      for I in 1 .. Natural (Arena.Last_Con) loop
         Res.Decl_Con.Append (0);
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
                        --  Report 5.3.1: T(..) / C(..) hide the
                        --  constructors and fields / methods too, and
                        --  T(a, B) the ones listed (M75 review).
                        if E.Kind = Type_Ent
                          and then (E.Sub_All or else E.Has_Subs)
                        then
                           declare
                              function Listed
                                (N : Names.Name_Id) return Boolean is
                              begin
                                 if E.Sub_All then
                                    return True;
                                 end if;
                                 for Q of E.Subs loop
                                    if Q.Name = N then
                                       return True;
                                    end if;
                                 end loop;
                                 return False;
                              end Listed;

                              --  Hide N only where it names THIS
                              --  entity, not a same-named other one.
                              procedure Hide_Value
                                (N : Names.Name_Id; V : Core.Var_Id) is
                              begin
                                 if Listed (N)
                                   and then View.Visible.Values.Contains (N)
                                   and then Core.Var_Id
                                     (View.Visible.Values.Element (N)) = V
                                 then
                                    View.Visible.Values.Exclude (N);
                                 end if;
                              end Hide_Value;
                           begin
                              if Source.TyCons.Contains (E.Name.Name) then
                                 for DCI of M.Info
                                   (Source.TyCons.Element (E.Name.Name)).Cons
                                 loop
                                    declare
                                       DI : constant Core.DataCon_Info :=
                                         M.Info (DCI);
                                    begin
                                       if Listed (DI.Name) then
                                          View.Visible.DataCons.Exclude
                                            (DI.Name);
                                       end if;
                                       for FI in 1 .. DI.Field_Sels.Last_Index
                                       loop
                                          Hide_Value
                                            (DI.Field_Names (FI),
                                             Core.Var_Id (DI.Field_Sels.Element (FI)));
                                       end loop;
                                    end;
                                 end loop;
                              end if;
                              if Source.Classes.Contains (E.Name.Name) then
                                 for Mth of M.Info
                                   (Source.Classes.Element (E.Name.Name))
                                   .Methods
                                 loop
                                    Hide_Value (Mth.Name, Mth.Selector);
                                 end loop;
                              end if;
                           end;
                        end if;
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
                                          for FI in
                                            1 .. DI.Field_Sels.Last_Index
                                          loop
                                             declare
                                                FN : constant Names
                                                  .Name_Id :=
                                                    DI.Field_Names (FI);
                                                FC : constant Builtins
                                                  .Var_Maps.Cursor :=
                                                    Source.Values.Find
                                                      (FN);
                                             begin
                                                --  This type's own
                                                --  selector, by
                                                --  identity (M75).
                                                if Builtins.Var_Maps
                                                  .Has_Element (FC)
                                                  and then Builtins
                                                    .Var_Maps.Element
                                                      (FC)
                                                    = DI.Field_Sels (FI)
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
                              Source.Synonyms (E.Name.Name));
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
                  Prelude_Explicit := True;
                  Filter (Pre.all);
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
                  --  Like data declarations: a duplicate only within
                  --  this module (Report 4.2.1), so a builtin TyCon
                  --  may be shadowed (`type Rational = Ratio
                  --  Integer`) and another module's name is legal.
                  declare
                     Clash : constant Boolean :=
                       Own.TyCons.Contains (N.S_Name)
                         or else Own.Synonyms.Contains (N.S_Name);
                  begin
                     if Clash then
                        Bag.Add (Diagnostics.Error,
                                 Diagnostics.Rename_Duplicate, N.Span,
                                 "type '" & Text (N.S_Name)
                                 & "' is defined more than once");
                     end if;
                  end;
                  declare
                     Syn : constant Builtins.Syn_Rec :=
                       (Arity => Natural (N.S_Vars.Length),
                        Vars => N.S_Vars,
                        Syntax_Rhs => Syntax.Type_Id (N.S_Rhs),
                        Core_Rhs => Core.No_Type,
                        Owner => Arena.Module_Name,
                        others => <>);
                  begin
                     Own.Synonyms.Include (N.S_Name, Syn);
                     if Global_Scope then
                        Env.Synonyms.Include (N.S_Name, Syn);
                     end if;
                  end;
               when Class_D =>
                  Declare_Class (D, N);
               when others =>
                  null;
            end case;
         end;
      end loop;

      --  Class bodies once every type-level name is declared.
      for D of Arena.Top_Decls loop
         declare
            N : constant Decl_Node := Arena.Node (D);
         begin
            if N.Kind = Class_D then
               Fill_Class (D, N);
            end if;
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

      --  Foreign imports: bodiless globals whose signature is the
      --  declaration's type (the same channel Sig_D uses, so kinds
      --  and the typechecker need no special cases). Exports are
      --  handled after Declare_Group - they reference bindings.
      for D of Arena.Top_Decls loop
         declare
            N : constant Decl_Node := Arena.Node (D);
         begin
            if N.Kind = Foreign_D and then not N.F_Export then
               declare
                  V : constant Core.Real_Var_Id :=
                    M.Mint_Var ((Name => N.F_Name, Span => N.Span,
                                 Is_Global => True, others => <>));
               begin
                  if Top_Names.Contains (N.F_Name) then
                     Bag.Add (Diagnostics.Error,
                              Diagnostics.Rename_Duplicate, N.Span,
                              "'" & Text (N.F_Name)
                              & "' is defined more than once");
                  end if;
                  Top_Names.Include (N.F_Name, V);
                  if Global_Scope then
                     Env.Values.Include (N.F_Name, V);
                  end if;
                  Own.Values.Include (N.F_Name, V);
                  Res.Decl_Var.Replace_Element
                    (Positive (D), Core.Var_Id (V));
                  Rename_Type (N.F_Type);
                  Res.Var_Sig.Include (V, N.F_Type);
               end;
            end if;
         end;
      end loop;

      --  ... then top-level value binders and signatures.
      Declare_Group (Arena.Top_Decls, Global => True);

      --  Foreign exports: resolve to this module's own top-level
      --  binding. When the binding carries no signature, the export
      --  type becomes its signature (so the body is checked against
      --  it); when it does, the binding's own signature wins and the
      --  marshal spec is derived from it during desugaring.
      for D of Arena.Top_Decls loop
         declare
            N : constant Decl_Node := Arena.Node (D);
         begin
            if N.Kind = Foreign_D and then N.F_Export then
               declare
                  C : constant Scope_Maps.Cursor :=
                    Top_Names.Find (N.F_Name);
               begin
                  if Scope_Maps.Has_Element (C) then
                     declare
                        V : constant Core.Real_Var_Id :=
                          Scope_Maps.Element (C);
                     begin
                        Res.Decl_Var.Replace_Element
                          (Positive (D), Core.Var_Id (V));
                        Rename_Type (N.F_Type);
                        if not Res.Var_Sig.Contains (V) then
                           Res.Var_Sig.Include (V, N.F_Type);
                        end if;
                     end;
                  else
                     Bag.Add (Diagnostics.Error,
                              Diagnostics.Rename_Out_Of_Scope,
                              N.Span,
                              "foreign export of '"
                              & Text (N.F_Name)
                              & "', which this module does not "
                              & "define");
                  end if;
               end;
            end if;
         end;
      end loop;

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
               when Foreign_D =>
                  null;   --  handled before Declare_Group
            end case;
         end;
      end loop;

      Pop_Scope;

      --  Register this module's exports: everything top-level, or
      --  the export list's subset (Report 5.2). Re-exports resolve
      --  through imports and Base. The Prelude pass has no registry
      --  but does have an export list (M144b): the same machinery
      --  resolves it against the flat environment into Res.Public.
      if Modular or else Arena.Has_Export_List then
         declare
            Ent : Modules.Module_Entry;

            procedure Export_All is
            begin
               Ent.Exports := Own;
            end Export_All;

            procedure Export_Listed is
               Cur_Span : Diagnostics.Source_Span;

               --  Report 5.2: an export list may not name two
               --  DIFFERENT entities by one unqualified name - reachable
               --  since two modules may declare the same name (M75).
               procedure Conflict (N : Names.Name_Id) is
               begin
                  Bag.Add (Diagnostics.Error,
                           Diagnostics.Rename_Duplicate, Cur_Span,
                           "conflicting exports for '" & Text (N) & "'");
               end Conflict;

               procedure Exp_Value
                 (N : Names.Name_Id; X : Core.Real_Var_Id) is
               begin
                  if Ent.Exports.Values.Contains (N)
                    and then Ent.Exports.Values.Element (N) /= X
                  then
                     Conflict (N);
                  end if;
                  Ent.Exports.Values.Include (N, X);
               end Exp_Value;

               procedure Exp_TyCon
                 (N : Names.Name_Id; X : Core.Real_TyCon_Id) is
               begin
                  if (Ent.Exports.TyCons.Contains (N)
                      and then Core."/=" (Ent.Exports.TyCons.Element (N), X))
                    or else Ent.Exports.Synonyms.Contains (N)
                  then
                     Conflict (N);
                  end if;
                  Ent.Exports.TyCons.Include (N, X);
               end Exp_TyCon;

               procedure Exp_DataCon
                 (N : Names.Name_Id; X : Core.Real_DataCon_Id) is
               begin
                  if Ent.Exports.DataCons.Contains (N)
                    and then Core."/=" (Ent.Exports.DataCons.Element (N), X)
                  then
                     Conflict (N);
                  end if;
                  Ent.Exports.DataCons.Include (N, X);
               end Exp_DataCon;

               procedure Exp_Class
                 (N : Names.Name_Id; X : Core.Real_Class_Id) is
               begin
                  if Ent.Exports.Classes.Contains (N)
                    and then Core."/=" (Ent.Exports.Classes.Element (N), X)
                  then
                     Conflict (N);
                  end if;
                  Ent.Exports.Classes.Include (N, X);
               end Exp_Class;

               procedure Exp_Syn
                 (N : Names.Name_Id; X : Builtins.Syn_Rec) is
               begin
                  if (Ent.Exports.Synonyms.Contains (N)
                      and then Ent.Exports.Synonyms.Element (N).Owner
                               /= X.Owner)
                    or else Ent.Exports.TyCons.Contains (N)
                  then
                     Conflict (N);
                  end if;
                  Ent.Exports.Synonyms.Include (N, X);
               end Exp_Syn;
            begin
               for E of Arena.Exports loop
                  Cur_Span := E.Span;
                  case E.Kind is
                     when Module_Ent =>
                        --  Report 5.2: `module M` exports what is in
                        --  scope both unqualified and qualified as M:
                        --  the whole module for M = self, an
                        --  unqualified import's visible view, or the
                        --  Base snapshot for `module Prelude`.
                        --  Qualified-only imports contribute nothing.
                        declare
                           procedure Merge (Src : Modules.Iface) is
                              procedure MV
                                (C : Builtins.Var_Maps.Cursor) is
                              begin
                                 Exp_Value
                                   (Builtins.Var_Maps.Key (C),
                                    Builtins.Var_Maps.Element (C));
                              end MV;
                              procedure MT
                                (C : Builtins.TyCon_Maps.Cursor) is
                              begin
                                 Exp_TyCon
                                   (Builtins.TyCon_Maps.Key (C),
                                    Builtins.TyCon_Maps.Element
                                      (C));
                              end MT;
                              procedure MD
                                (C : Builtins.DataCon_Maps.Cursor)
                              is
                              begin
                                 Exp_DataCon
                                   (Builtins.DataCon_Maps.Key (C),
                                    Builtins.DataCon_Maps.Element
                                      (C));
                              end MD;
                              procedure MC
                                (C : Builtins.Class_Maps.Cursor) is
                              begin
                                 Exp_Class
                                   (Builtins.Class_Maps.Key (C),
                                    Builtins.Class_Maps.Element
                                      (C));
                              end MC;
                              procedure MS
                                (C : Builtins.Syn_Maps.Cursor) is
                              begin
                                 Exp_Syn
                                   (Builtins.Syn_Maps.Key (C),
                                    Builtins.Syn_Maps.Element (C));
                              end MS;
                           begin
                              Src.Values.Iterate (MV'Access);
                              Src.TyCons.Iterate (MT'Access);
                              Src.DataCons.Iterate (MD'Access);
                              Src.Classes.Iterate (MC'Access);
                              Src.Synonyms.Iterate (MS'Access);
                           end Merge;
                           Found : Boolean := False;
                        begin
                           if E.Name.Name = Arena.Module_Name
                             or else (Arena.Module_Name =
                                        Names.No_Name
                                      and then E.Name.Name =
                                        Names.Name_Id
                                          (Table.Intern ("Main")))
                           then
                              Merge (Own);
                              Found := True;
                           elsif E.Name.Name =
                             Names.Name_Id (Prelude_Name)
                             and then Pub /= null
                           then
                              Merge (Pub.all);
                              Found := True;
                           else
                              for V of Imp_Views loop
                                 if (V.Alias = E.Name.Name
                                     or else V.Module = E.Name.Name)
                                   and then not V.Qualified
                                 then
                                    Merge (V.Visible);
                                    Found := True;
                                 end if;
                              end loop;
                           end if;
                           if not Found then
                              Bag.Add
                                (Diagnostics.Error,
                                 Diagnostics.Rename_Out_Of_Scope,
                                 E.Span,
                                 "'module "
                                 & Text (E.Name.Name)
                                 & "' export: no such unqualified"
                                 & " import");
                           end if;
                        end;
                     when Var_Ent =>
                        declare
                           R : constant Resolution :=
                             Lookup_Value (E.Name, E.Span);
                        begin
                           if R.Kind = Var_Res then
                              Exp_Value
                                (E.Name.Name, R.Var);
                           end if;
                        end;
                     when Type_Ent =>
                        declare
                           Amb_C : Boolean := False;
                           TC : Core.TyCon_Id;
                           Cl : Core.Class_Id := Core.No_Class;
                           Exported_Syn : Syn_Ref;
                           Ty_Ch : Ty_Choice;
                        begin
                           --  Exactly as at a use site (M75): a
                           --  synonym wins over the wired placeholder
                           --  it shadows, or Data.Ratio would export
                           --  the abstract Rational, not its `Ratio
                           --  Integer`; own beats imported; two
                           --  imported entities are ambiguous.
                           Resolve_Ty (E.Name, E.Span, TC, Exported_Syn,
                                       Ty_Ch);
                           if Ty_Ch = Neither then
                              Cl := Mod_Find_Class (E.Name, E.Span, Amb_C);
                           end if;
                           if Ty_Ch = Take_Syn and then Exported_Syn.Is_Own
                           then
                              Exported_Syn.Rec :=
                                Own.Synonyms (E.Name.Name);
                           end if;
                           if Ty_Ch = Take_TyCon then
                              Exp_TyCon
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
                                       Exp_DataCon
                                         (DI.Name,
                                          Core.Real_DataCon_Id
                                            (DCI));
                                       --  The type's own field
                                       --  selectors - not whatever
                                       --  this module calls by that
                                       --  name (M75).
                                       for FI in
                                         1 .. DI.Field_Sels.Last_Index
                                       loop
                                          Exp_Value
                                            (DI.Field_Names (FI),
                                             DI.Field_Sels (FI));
                                       end loop;
                                    end;
                                 end loop;
                              end if;
                           elsif Cl /= Core.No_Class then
                              Exp_Class
                                (E.Name.Name,
                                 Core.Real_Class_Id (Cl));
                              if E.Sub_All then
                                 --  Through Lookup_Value, not
                                 --  Own.Values: C(..) may RE-export a
                                 --  class this module only imported,
                                 --  whose selectors are not its own.
                                 --  Control.Applicative exports
                                 --  Applicative(..) for the Prelude's
                                 --  class, and `import
                                 --  Control.Applicative ((<*>))` was
                                 --  refused because no selector ever
                                 --  reached the iface.
                                 --  The class's own selectors, by
                                 --  identity: an unqualified lookup
                                 --  missed L.C(..)'s methods and could
                                 --  export an unrelated same-named
                                 --  value instead (M75).
                                 for Mth of M.Info
                                   (Core.Real_Class_Id (Cl)).Methods
                                 loop
                                    if Core."/=" (Mth.Selector, Core.No_Var)
                                    then
                                       Exp_Value
                                         (Mth.Name,
                                          Core.Real_Var_Id (Mth.Selector));
                                    end if;
                                 end loop;
                              end if;
                           elsif Ty_Ch = Take_Syn then
                              --  A synonym in scope may be RE-exported
                              --  (Report 5.2): System.IO.Error exports
                              --  the Prelude's IOError. The record
                              --  travels, Own first (M75); this
                              --  module's own is cached into it by
                              --  AHC.Kinds after renaming.
                              Exp_Syn
                                (E.Name.Name, Exported_Syn.Rec);
                           elsif Ty_Ch = Neither and then not Amb_C then
                              Bag.Add
                                (Diagnostics.Error,
                                 Diagnostics.Rename_Out_Of_Scope,
                                 E.Span,
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
            --  present.
            if not Arena.Has_Export_List then
               Ent.Exports.Synonyms := Own.Synonyms;
            end if;
            Ent.Exports.Fixities := Fixities;
            if Modular then
               Reg.Mods.Append (Ent);
            else
               Res.Public := Ent.Exports;
            end if;
         end;
      end if;
      --  Kinds caches these and publishes the cached records into
      --  the export entry just appended (M75).
      Res.Own_Syns := Own.Synonyms;
      Res.Own_Values := Own.Values;
   end Resolve_Module;

end AHC.Rename;
