with Ada.Containers.Hashed_Maps;
with Ada.Strings.Unbounded.Hash;

with AHC.Rename;

package body AHC.CodeGen is

   use AHC.Core;
   use Ada.Strings.Unbounded;
   use type Names.Name_Id;

   procedure Emit_Units
     (Table    : in out Names.Name_Table;
      M        : Core.Core_Module;
      Env      : Builtins.Global_Env;
      Prims    : Prelude_Core.Prim_Maps.Map;
      Owners   : UStr_Vectors.Vector;
      F_Owners : UStr_Vectors.Vector;
      Units    : UStr_Vectors.Vector;
      Lib_Mode : Boolean;
      Header   : out Ada.Strings.Unbounded.Unbounded_String;
      Exports_H : out Ada.Strings.Unbounded.Unbounded_String;
      Files    : out Unit_File_Vectors.Vector)
   is
      Fns  : Unbounded_String;   --  lifted function bodies
      Decl : Unbounded_String;   --  forward decls + CAF globals
      Init : Unbounded_String;   --  CAF initialization statements
      Fn_Counter : Natural := 0;

      package Var_Str_Maps is new Ada.Containers.Hashed_Maps
        (Real_Var_Id, Unbounded_String,
         Hash => Rename.Var_Hash, Equivalent_Keys => "=");

      package Var_Nat_Maps is new Ada.Containers.Hashed_Maps
        (Real_Var_Id, Natural,
         Hash => Rename.Var_Hash, Equivalent_Keys => "=");

      package Str_Nat_Maps is new Ada.Containers.Hashed_Maps
        (Unbounded_String, Natural,
         Hash => Ada.Strings.Unbounded.Hash, Equivalent_Keys => "=");

      --  Special globals: prims, selectors, missing.
      Special : Var_Str_Maps.Map;

      --  Globals that have top-level bindings.
      Has_Body : Var_Str_Maps.Map;

      --  Stable C symbol per bodied global: g_<unit>_<name>, with a
      --  deterministic counter on (rare) mangling collisions. A
      --  unit's generated text then never mentions an arena id.
      Sym : Var_Str_Maps.Map;

      --  Per-unit local numbering (reset for every unit): let-bound
      --  locals come out as l_0, l_1, ... in first-use order.
      L_Map : Var_Nat_Maps.Map;
      L_Next : Natural := 0;

      function Img (N : Natural) return String is
         S : constant String := N'Image;
      begin
         return S (2 .. S'Last);
      end Img;

      --  C-identifier mangling: letters/digits kept, '.' becomes
      --  '_', everything else escapes to _xHH.
      function Mangle (S : String) return String is
         R : Unbounded_String;
         Hex : constant String := "0123456789ABCDEF";
      begin
         for C of S loop
            if C in 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' then
               Append (R, C);
            elsif C = '.' then
               Append (R, '_');
            else
               Append (R, "_x"
                       & Hex (Character'Pos (C) / 16 + 1)
                       & Hex (Character'Pos (C) mod 16 + 1));
            end if;
         end loop;
         return To_String (R);
      end Mangle;

      function Sym_Of (V : Real_Var_Id) return String
      is (To_String (Sym (V)));

      function Lid (V : Real_Var_Id) return String is
         C : constant Var_Nat_Maps.Cursor := L_Map.Find (V);
      begin
         if Var_Nat_Maps.Has_Element (C) then
            return "l_" & Img (Var_Nat_Maps.Element (C));
         end if;
         L_Map.Include (V, L_Next);
         L_Next := L_Next + 1;
         return "l_" & Img (L_Next - 1);
      end Lid;

      function C_Escape (S : String) return String is
         R : Unbounded_String;
      begin
         for C of S loop
            case C is
               when '"' => Append (R, "\""");
               when '\' => Append (R, "\\");
               when ASCII.LF => Append (R, "\n");
               when ASCII.HT => Append (R, "\t");
               when ASCII.CR => Append (R, "\r");
               when others =>
                  if Character'Pos (C) in 32 .. 126 then
                     Append (R, C);
                  else
                     declare
                        P : Natural := Character'Pos (C);
                        O : String (1 .. 3);
                     begin
                        for I in reverse 1 .. 3 loop
                           O (I) := Character'Val (48 + P mod 8);
                           P := P / 8;
                        end loop;
                        Append (R, "\" & O);
                     end;
                  end if;
            end case;
         end loop;
         return To_String (R);
      end C_Escape;

      --  Parse an integer lexeme (dec/hex/oct, optional leading '-'
      --  on generated literals such as refinement bounds) to decimal
      --  text.
      function Int_Text (T : Names.Name_Id) return String is
         S : constant String := Table.Text (Names.Real_Name_Id (T));
         V : Long_Long_Integer := 0;
         Base : Long_Long_Integer := 10;
         First : Positive := S'First;
         Neg : Boolean := False;
      begin
         if S'Length > 1 and then S (S'First) = '-' then
            Neg := True;
            First := S'First + 1;
         end if;
         if S'Last - First > 1 and then S (First) = '0'
           and then (S (First + 1) in 'x' | 'X')
         then
            Base := 16;
            First := First + 2;
         elsif S'Last - First > 1 and then S (First) = '0'
           and then (S (First + 1) in 'o' | 'O')
         then
            Base := 8;
            First := First + 2;
         end if;
         for I in First .. S'Last loop
            declare
               C : constant Character := S (I);
               D : constant Long_Long_Integer :=
                 (if C in '0' .. '9'
                  then Character'Pos (C) - 48
                  elsif C in 'a' .. 'f'
                  then Character'Pos (C) - 87
                  else Character'Pos (C) - 55);
            begin
               V := V * Base + D;
            end;
         end loop;
         if Neg then
            V := -V;
         end if;
         declare
            R : constant String := V'Image;
         begin
            return (if R (R'First) = ' ' then R (R'First + 1 .. R'Last)
                    else R);
         end;
      end Int_Text;

      --  Exact rational literals: the :% constructor's tag when
      --  Data.Ratio is in the program, -1 otherwise (float literals
      --  then fall back to plain double nodes - the pre-Ratio
      --  world, byte-identical because both paths round correctly).
      Ratio_Tag : Integer := -1;

      --  Split a float lexeme ddd[.ddd][e[+|-]ddd] into exact
      --  decimal numerator/denominator text (den = a power of 10).
      procedure Rat_Parts
        (T : Names.Name_Id; Num, Den : out Unbounded_String)
      is
         S : constant String := Table.Text (Names.Real_Name_Id (T));
         Digits_S : Unbounded_String;
         Frac : Natural := 0;
         E10 : Integer := 0;
         I : Positive := S'First;
         In_Frac : Boolean := False;
      begin
         while I <= S'Last and then S (I) not in 'e' | 'E' loop
            if S (I) = '.' then
               In_Frac := True;
            else
               Append (Digits_S, S (I));
               if In_Frac then
                  Frac := Frac + 1;
               end if;
            end if;
            I := I + 1;
         end loop;
         if I <= S'Last then          --  exponent part
            declare
               J : Positive := I + 1;
               Neg : Boolean := False;
               V : Integer := 0;
            begin
               if J <= S'Last and then S (J) in '+' | '-' then
                  Neg := S (J) = '-';
                  J := J + 1;
               end if;
               while J <= S'Last loop
                  V := V * 10 + (Character'Pos (S (J)) - 48);
                  J := J + 1;
               end loop;
               E10 := (if Neg then -V else V);
            end;
         end if;
         E10 := E10 - Frac;
         declare
            DS : constant String := To_String (Digits_S);
            F : Positive := DS'First;
         begin
            while F < DS'Last and then DS (F) = '0' loop
               F := F + 1;
            end loop;
            Num := To_Unbounded_String (DS (F .. DS'Last));
         end;
         Den := To_Unbounded_String ("1");
         if E10 >= 0 then
            Append (Num, [1 .. E10 => '0']);
         else
            Append (Den, [1 .. -E10 => '0']);
         end if;
      end Rat_Parts;

      ------------------------------------------------------------------
      --  Free local variables (bound-set threading)
      ------------------------------------------------------------------

      package Var_Vectors renames Var_Id_Vectors;

      procedure Add_Unique
        (V : Real_Var_Id; Into : in out Var_Vectors.Vector) is
      begin
         for X of Into loop
            if X = V then
               return;
            end if;
         end loop;
         Into.Append (V);
      end Add_Unique;

      procedure Free_Vars
        (E : Real_Expr_Id;
         Bound : in out Var_Vectors.Vector;
         Into : in out Var_Vectors.Vector)
      is
         N : constant Expr_Node := M.Node (E);

         function Is_Bound (V : Real_Var_Id) return Boolean is
         begin
            for X of Bound loop
               if X = V then
                  return True;
               end if;
            end loop;
            return False;
         end Is_Bound;
      begin
         case N.Kind is
            when Var_C =>
               if not M.Info (N.V).Is_Global
                 and then not Is_Bound (N.V)
               then
                  Add_Unique (N.V, Into);
               end if;
            when Lit_C | Con_C =>
               null;
            when App_C =>
               Free_Vars (N.Fun, Bound, Into);
               Free_Vars (N.Arg, Bound, Into);
            when Lam_C =>
               declare
                  Mark : constant Natural := Bound.Last_Index;
               begin
                  Bound.Append (N.Binder);
                  Free_Vars (N.Lam_Body, Bound, Into);
                  while Bound.Last_Index > Mark loop
                     Bound.Delete_Last;
                  end loop;
               end;
            when Let_C =>
               declare
                  Mark : constant Natural := Bound.Last_Index;
               begin
                  for B of N.Binds loop
                     Bound.Append (B.Binder);
                  end loop;
                  for B of N.Binds loop
                     Free_Vars (B.Rhs, Bound, Into);
                  end loop;
                  Free_Vars (N.Let_Body, Bound, Into);
                  while Bound.Last_Index > Mark loop
                     Bound.Delete_Last;
                  end loop;
               end;
            when Case_C =>
               Free_Vars (N.Scrutinee, Bound, Into);
               for A of N.Alts loop
                  declare
                     Alt : constant Alt_Node := M.Node (A);
                     Mark : constant Natural := Bound.Last_Index;
                  begin
                     if Alt.Kind = Con_Alt then
                        for B of Alt.Binders loop
                           Bound.Append (B);
                        end loop;
                     end if;
                     Free_Vars (Alt.Alt_Body, Bound, Into);
                     while Bound.Last_Index > Mark loop
                        Bound.Delete_Last;
                     end loop;
                  end;
               end loop;
         end case;
      end Free_Vars;

      ------------------------------------------------------------------
      --  Scopes: local var -> C expression
      ------------------------------------------------------------------

      package Scope_Maps renames Var_Str_Maps;

      function Var_Ref
        (V : Real_Var_Id; Scope : Scope_Maps.Map) return String
      is
         C : constant Scope_Maps.Cursor := Scope.Find (V);
      begin
         if Scope_Maps.Has_Element (C) then
            return To_String (Scope_Maps.Element (C));
         end if;
         if Special.Contains (V) then
            return To_String (Special (V));
         end if;
         if Has_Body.Contains (V) then
            return Sym_Of (V);
         end if;
         --  Opaque global: fail loudly if ever forced.
         return "ahc_mk_missing(""" &
           C_Escape (Table.Text
             (Names.Real_Name_Id (M.Info (V).Name))) & """)";
      end Var_Ref;

      ------------------------------------------------------------------
      --  Expression generation
      ------------------------------------------------------------------

      function Gen_Force
        (E : Real_Expr_Id; Scope : Scope_Maps.Map) return String;

      --  Lift E into a function over its free variables; returns the
      --  creation expression (thunk or fun).
      function Lift
        (E : Real_Expr_Id; Scope : Scope_Maps.Map;
         Param : Var_Id;                     --  No_Var for thunks
         Kind : Character)                   --  't' or 'f'
         return String
      is
         Bound : Var_Vectors.Vector;
         FVs : Var_Vectors.Vector;
         Inner : Scope_Maps.Map;
         Fn : constant String :=
           "fn_" & Img (Fn_Counter + 1);
         Creation : Unbounded_String;
      begin
         Fn_Counter := Fn_Counter + 1;
         if Param /= No_Var then
            Bound.Append (Real_Var_Id (Param));
         end if;
         Free_Vars (E, Bound, FVs);

         for I in 1 .. FVs.Last_Index loop
            Inner.Include
              (FVs (I),
               To_Unbounded_String ("env[" & Img (I - 1) & "]"));
         end loop;
         if Param /= No_Var then
            Inner.Include (Real_Var_Id (Param),
                           To_Unbounded_String ("arg"));
         end if;

         if Kind = 't' then
            Append (Decl, "static AhcNode *" & Fn
                    & "(AhcNode **env);" & ASCII.LF);
            Append (Fns, "static AhcNode *" & Fn
                    & "(AhcNode **env) {" & ASCII.LF
                    & "  (void)env;" & ASCII.LF
                    & "  return " & Gen_Force (E, Inner) & ";"
                    & ASCII.LF & "}" & ASCII.LF & ASCII.LF);
         else
            Append (Decl, "static AhcNode *" & Fn
                    & "(AhcNode **env, AhcNode *arg);" & ASCII.LF);
            Append (Fns, "static AhcNode *" & Fn
                    & "(AhcNode **env, AhcNode *arg) {" & ASCII.LF
                    & "  (void)env; (void)arg;" & ASCII.LF
                    & "  return " & Gen_Force (E, Inner) & ";"
                    & ASCII.LF & "}" & ASCII.LF & ASCII.LF);
         end if;

         --  Creation with captured environment.
         if FVs.Is_Empty then
            Append (Creation,
                    (if Kind = 't' then "ahc_mk_thunk("
                     else "ahc_mk_fun(") & Fn & ", NULL)");
         else
            Append (Creation, "({ AhcNode **e = ahc_env("
                    & Img (Natural (FVs.Length)) & "); ");
            for I in 1 .. FVs.Last_Index loop
               Append (Creation, "e[" & Img (I - 1) & "] = "
                       & Var_Ref (FVs (I), Scope) & "; ");
            end loop;
            Append (Creation,
                    (if Kind = 't' then "ahc_mk_thunk("
                     else "ahc_mk_fun(") & Fn & ", e); })");
         end if;
         return To_String (Creation);
      end Lift;

      --  A node expression usable in a lazy position.
      function Gen_Lazy
        (E : Real_Expr_Id; Scope : Scope_Maps.Map) return String
      is
         N : constant Expr_Node := M.Node (E);
      begin
         case N.Kind is
            when Var_C =>
               return Var_Ref (N.V, Scope);
            when Lit_C | Con_C =>
               return Gen_Force (E, Scope);
            when Lam_C =>
               return Lift (N.Lam_Body, Scope, Var_Id (N.Binder), 'f');
            when others =>
               return Lift (E, Scope, No_Var, 't');
         end case;
      end Gen_Lazy;

      function Gen_Force
        (E : Real_Expr_Id; Scope : Scope_Maps.Map) return String
      is
         N : constant Expr_Node := M.Node (E);
      begin
         case N.Kind is
            when Var_C =>
               return Var_Ref (N.V, Scope);
            when Lit_C =>
               case N.Lit.Kind is
                  when L_Int =>
                     --  Literals beyond a C long go through the
                     --  runtime bignum parser (which canonicalizes
                     --  small values back to plain ints, so an
                     --  over-conservative digit-count test is safe).
                     declare
                        Raw : constant String :=
                          Table.Text (Names.Real_Name_Id (N.Lit.Text));
                        First : Natural := Raw'First;
                        Limit : Natural := 18;
                     begin
                        if Raw'Length > 0
                          and then Raw (Raw'First) = '-'
                        then
                           First := First + 1;
                        end if;
                        if Raw'Last - First >= 1
                          and then Raw (First) = '0'
                          and then Raw (First + 1) in 'x' | 'X'
                        then
                           First := First + 2;
                           Limit := 15;
                        elsif Raw'Last - First >= 1
                          and then Raw (First) = '0'
                          and then Raw (First + 1) in 'o' | 'O'
                        then
                           First := First + 2;
                           Limit := 20;
                        end if;
                        if Raw'Last - First + 1 > Limit then
                           return "ahc_mk_big_str("""
                             & Raw & """)";
                        end if;
                        return "ahc_mk_int(" & Int_Text (N.Lit.Text)
                          & "L)";
                     end;
                  when L_Float =>
                     if Ratio_Tag >= 0 then
                        declare
                           Num, Den : Unbounded_String;
                        begin
                           Rat_Parts (N.Lit.Text, Num, Den);
                           return "ahc_mk_ratlit("
                             & Img (Ratio_Tag) & ", """
                             & To_String (Num) & """, """
                             & To_String (Den) & """)";
                        end;
                     end if;
                     return "ahc_mk_double("
                       & Table.Text (Names.Real_Name_Id (N.Lit.Text))
                       & ")";
                  when L_Char =>
                     return "ahc_mk_char(" & Img (N.Lit.Code) & "L)";
                  when L_String =>
                     if N.Lit.Text = Names.No_Name then
                        return "ahc_mk_string("""")";
                     end if;
                     return "ahc_mk_string("""
                       & C_Escape (Table.Text
                           (Names.Real_Name_Id (N.Lit.Text)))
                       & """)";
               end case;
            when Con_C =>
               declare
                  Info : constant DataCon_Info := M.Info (N.Con);
               begin
                  return "ahc_mk_confun(" & Img (Info.Tag) & ", "
                    & Img (Info.Arity) & ")";
               end;
            when App_C =>
               return "ahc_apply(" & Gen_Lazy (N.Fun, Scope) & ", "
                 & Gen_Lazy (N.Arg, Scope) & ")";
            when Lam_C =>
               return Lift (N.Lam_Body, Scope, Var_Id (N.Binder), 'f');
            when Let_C =>
               declare
                  R : Unbounded_String;
                  Inner : Scope_Maps.Map := Scope;
               begin
                  Append (R, "({ ");
                  --  Declare nodes first (letrec-friendly), envs
                  --  patched after creation.
                  declare
                     type Bind_Gen is record
                        Fn : Unbounded_String;
                        FVs : Var_Vectors.Vector;
                        Is_Fun : Boolean;
                     end record;
                     package BG_Vectors is new Ada.Containers.Vectors
                       (Positive, Bind_Gen);
                     Gens : BG_Vectors.Vector;
                  begin
                     --  Bring binders into scope before lifting.
                     for B of N.Binds loop
                        Inner.Include
                          (B.Binder,
                           To_Unbounded_String (Lid (B.Binder)));
                     end loop;

                     for B of N.Binds loop
                        declare
                           BN : constant Expr_Node := M.Node (B.Rhs);
                           G : Bind_Gen;
                           Bound : Var_Vectors.Vector;
                           Body_E : Real_Expr_Id := B.Rhs;
                        begin
                           G.Is_Fun := BN.Kind = Lam_C;
                           if G.Is_Fun then
                              Bound.Append (BN.Binder);
                              Body_E := BN.Lam_Body;
                           end if;
                           Free_Vars (Body_E, Bound, G.FVs);
                           Fn_Counter := Fn_Counter + 1;
                           G.Fn := To_Unbounded_String
                             ("fn_" & Img (Fn_Counter));
                           declare
                              FScope : Scope_Maps.Map;
                           begin
                              for I in 1 .. G.FVs.Last_Index loop
                                 FScope.Include
                                   (G.FVs (I),
                                    To_Unbounded_String
                                      ("env[" & Img (I - 1) & "]"));
                              end loop;
                              if G.Is_Fun then
                                 FScope.Include
                                   (BN.Binder,
                                    To_Unbounded_String ("arg"));
                                 Append (Decl, "static AhcNode *"
                                   & To_String (G.Fn)
                                   & "(AhcNode **env, AhcNode *arg);"
                                   & ASCII.LF);
                                 Append (Fns, "static AhcNode *"
                                   & To_String (G.Fn)
                                   & "(AhcNode **env, AhcNode *arg) {"
                                   & ASCII.LF
                                   & "  (void)env; (void)arg;"
                                   & ASCII.LF & "  return "
                                   & Gen_Force (Body_E, FScope) & ";"
                                   & ASCII.LF & "}" & ASCII.LF
                                   & ASCII.LF);
                              else
                                 Append (Decl, "static AhcNode *"
                                   & To_String (G.Fn)
                                   & "(AhcNode **env);" & ASCII.LF);
                                 Append (Fns, "static AhcNode *"
                                   & To_String (G.Fn)
                                   & "(AhcNode **env) {" & ASCII.LF
                                   & "  (void)env;" & ASCII.LF
                                   & "  return "
                                   & Gen_Force (Body_E, FScope) & ";"
                                   & ASCII.LF & "}" & ASCII.LF
                                   & ASCII.LF);
                              end if;
                           end;
                           Gens.Append (G);
                        end;
                     end loop;

                     --  Create nodes with fresh envs.
                     for I in 1 .. N.Binds.Last_Index loop
                        declare
                           B : constant Bind_Pair := N.Binds (I);
                           G : constant Bind_Gen := Gens (I);
                           EN : constant String :=
                             "e_" & Lid (B.Binder);
                        begin
                           if G.FVs.Is_Empty then
                              Append (R, "AhcNode *" & Lid (B.Binder)
                                & " = "
                                & (if G.Is_Fun then "ahc_mk_fun("
                                   else "ahc_mk_thunk(")
                                & To_String (G.Fn) & ", NULL); ");
                           else
                              Append (R, "AhcNode **" & EN
                                & " = ahc_env("
                                & Img (Natural (G.FVs.Length))
                                & "); AhcNode *" & Lid (B.Binder)
                                & " = "
                                & (if G.Is_Fun then "ahc_mk_fun("
                                   else "ahc_mk_thunk(")
                                & To_String (G.Fn) & ", " & EN
                                & "); ");
                           end if;
                        end;
                     end loop;

                     --  Patch environments (siblings now in scope).
                     for I in 1 .. N.Binds.Last_Index loop
                        declare
                           B : constant Bind_Pair := N.Binds (I);
                           G : constant Bind_Gen := Gens (I);
                           EN : constant String :=
                             "e_" & Lid (B.Binder);
                        begin
                           for K in 1 .. G.FVs.Last_Index loop
                              Append (R, EN & "[" & Img (K - 1)
                                & "] = "
                                & Var_Ref (G.FVs (K), Inner) & "; ");
                           end loop;
                        end;
                     end loop;
                  end;
                  Append (R, Gen_Force (N.Let_Body, Inner) & "; })");
                  return To_String (R);
               end;
            when Case_C =>
               declare
                  R : Unbounded_String;
                  First : Boolean := True;
                  Has_Default : Boolean := False;
               begin
                  Append (R, "({ AhcNode *s = ahc_eval("
                    & Gen_Lazy (N.Scrutinee, Scope)
                    & "); AhcNode *r; ");
                  for A of N.Alts loop
                     declare
                        Alt : constant Alt_Node := M.Node (A);
                     begin
                        case Alt.Kind is
                           when Con_Alt =>
                              Append (R,
                                (if First then "if" else "else if")
                                & " (s->tag == AHC_CON && "
                                & "s->u.con.contag == "
                                & Img (M.Info (Alt.A_Con).Tag)
                                & ") { ");
                              declare
                                 Inner : Scope_Maps.Map := Scope;
                              begin
                                 for BI in 1 ..
                                   Alt.Binders.Last_Index
                                 loop
                                    Append (R, "AhcNode *"
                                      & Lid (Alt.Binders (BI))
                                      & " = s->u.con.fields["
                                      & Img (BI - 1) & "]; ");
                                    Inner.Include
                                      (Alt.Binders (BI),
                                       To_Unbounded_String
                                         (Lid (Alt.Binders (BI))));
                                 end loop;
                                 Append (R, "r = "
                                   & Gen_Force (Alt.Alt_Body, Inner)
                                   & "; } ");
                              end;
                              First := False;
                           when Lit_Alt =>
                              declare
                                 Test : constant String :=
                                   (case Alt.A_Lit.Kind is
                                      when L_Int =>
                                        "s->u.i == "
                                        & Int_Text (Alt.A_Lit.Text)
                                        & "L",
                                      when L_Char =>
                                        "s->u.c == "
                                        & Img (Alt.A_Lit.Code) & "L",
                                      when others => "0");
                              begin
                                 Append (R,
                                   (if First then "if"
                                    else "else if")
                                   & " (" & Test & ") { r = "
                                   & Gen_Force (Alt.Alt_Body, Scope)
                                   & "; } ");
                                 First := False;
                              end;
                           when Default_Alt =>
                              Has_Default := True;
                              if First then
                                 Append (R, "r = "
                                   & Gen_Force (Alt.Alt_Body, Scope)
                                   & "; ");
                              else
                                 Append (R, "else { r = "
                                   & Gen_Force (Alt.Alt_Body, Scope)
                                   & "; } ");
                              end if;
                        end case;
                     end;
                  end loop;
                  if not Has_Default and then not First then
                     Append
                       (R, "else { ahc_die(""non-exhaustive case"");"
                           & " } ");
                  end if;
                  Append (R, "r; })");
                  return To_String (R);
               end;
         end case;
      end Gen_Force;

      ------------------------------------------------------------------
      --  Foreign imports: one C wrapper (plus node global) per import,
      --  emitted into the owning unit. The node symbol is stable -
      --  derived from (unit, source name) only.
      ------------------------------------------------------------------

      function F_Owner (FI : Positive) return String
      is (if FI <= F_Owners.Last_Index
          then To_String (F_Owners (FI)) else "Prelude");

      function FFI_Base (FI : Positive) return String
      is (Mangle (F_Owner (FI)) & "_"
          & Mangle (Table.Text
              (Names.Real_Name_Id
                 (M.Info (M.Foreigns (FI).Binder).Name))));

      function C_Type (K : Marshal_Kind) return String
      is (case K is
            when M_Int    => "long",
            when M_Double => "double",
            when M_Char   => "long",
            when M_Bool   => "int",
            when M_Unit   => "void",
            when M_String => "const char *",
            when M_Ptr    => "void *");

      procedure Emit_Foreign (FI : Positive) is
         F : Foreign_Import renames M.Foreigns (FI);
         Base : constant String := FFI_Base (FI);
         NArgs : constant Natural := Natural (F.Args.Length);
         CName : constant String :=
           Table.Text (Names.Real_Name_Id (F.C_Name));
         LF : Character renames ASCII.LF;

         function Proto return String is
            R : Unbounded_String;
         begin
            Append (R, "extern " & C_Type (F.Res) & " " & CName
                    & "(");
            if NArgs = 0 then
               Append (R, "void");
            else
               for I in 1 .. NArgs loop
                  if I > 1 then
                     Append (R, ", ");
                  end if;
                  Append (R, C_Type (F.Args (I)));
               end loop;
            end if;
            Append (R, ");");
            return To_String (R);
         end Proto;

         --  Marshal every argument out of Src[i], call, free any
         --  temporary strings, box the result.
         function Call_Text (Src : String) return String is
            R : Unbounded_String;
            Call : Unbounded_String;
         begin
            for I in 1 .. NArgs loop
               declare
                  Ix : constant String := Img (I - 1);
                  S : constant String := Src & "[" & Ix & "]";
               begin
                  case F.Args (I) is
                     when M_Int =>
                        Append (R, "  AhcNode *e" & Ix
                                & " = ahc_eval(" & S & ");" & LF
                                & "  if (e" & Ix
                                & "->tag != AHC_INT) ahc_die(""FFI: "
                                & "Int argument out of range"");" & LF
                                & "  long x" & Ix & " = e" & Ix
                                & "->u.i;" & LF);
                     when M_Double =>
                        Append (R, "  double x" & Ix
                                & " = ahc_eval(" & S & ")->u.d;"
                                & LF);
                     when M_Char =>
                        Append (R, "  long x" & Ix
                                & " = ahc_eval(" & S & ")->u.c;"
                                & LF);
                     when M_Bool =>
                        Append (R, "  int x" & Ix
                                & " = (ahc_eval(" & S
                                & ")->u.con.contag == 2);" & LF);
                     when M_String =>
                        Append (R, "  char *x" & Ix
                                & " = ahc_marshal_cstring(" & S
                                & ");" & LF);
                     when M_Ptr =>
                        Append (R, "  void *x" & Ix
                                & " = ahc_eval(" & S & ")->u.p;"
                                & LF);
                     when M_Unit =>
                        null;   --  rejected during desugaring
                  end case;
               end;
            end loop;

            Append (Call, CName & "(");
            for I in 1 .. NArgs loop
               if I > 1 then
                  Append (Call, ", ");
               end if;
               Append (Call, "x" & Img (I - 1));
            end loop;
            Append (Call, ")");

            case F.Res is
               when M_Unit =>
                  Append (R, "  " & Call & ";" & LF);
               when M_Int =>
                  Append (R, "  long rv = " & Call & ";" & LF);
               when M_Double =>
                  Append (R, "  double rv = " & Call & ";" & LF);
               when M_Char =>
                  Append (R, "  long rv = " & Call & ";" & LF);
               when M_Bool =>
                  Append (R, "  int rv = " & Call & ";" & LF);
               when M_String =>
                  Append (R, "  const char *rv = " & Call & ";"
                          & LF);
               when M_Ptr =>
                  Append (R, "  void *rv = " & Call & ";" & LF);
            end case;

            for I in 1 .. NArgs loop
               if F.Args (I) = M_String then
                  Append (R, "  ahc_free_cstring(x" & Img (I - 1)
                          & ");" & LF);
               end if;
            end loop;

            case F.Res is
               when M_Unit =>
                  Append (R, "  return ahc_mk_con(1, 0);" & LF);
               when M_Int =>
                  Append (R, "  return ahc_mk_int(rv);" & LF);
               when M_Double =>
                  Append (R, "  return ahc_mk_double(rv);" & LF);
               when M_Char =>
                  Append (R, "  return ahc_mk_char(rv);" & LF);
               when M_Bool =>
                  Append (R, "  return ahc_mk_con(rv ? 2 : 1, 0);"
                          & LF);
               when M_String =>
                  Append (R, "  if (!rv) ahc_die(""FFI: NULL string "
                          & "result"");" & LF
                          & "  return ahc_mk_string(rv);" & LF);
               when M_Ptr =>
                  Append (R, "  return ahc_mk_ptr(rv);" & LF);
            end case;
            return To_String (R);
         end Call_Text;

         --  "wrapper" import: a 32-slot pool of statically typed
         --  trampolines; each forwards to cbrun, which applies the
         --  slot's closure to the marshalled C arguments.
         procedure Emit_Wrapper is
            Pool : constant := 32;
            NCB : constant Natural := Natural (F.CB_Args.Length);
            RT : constant String :=
              (if F.CB_Res = M_String then "char *"
               else C_Type (F.CB_Res));

            function Args_Decl return String is
               R : Unbounded_String;
            begin
               for I in 1 .. NCB loop
                  Append (R, ", " & C_Type (F.CB_Args (I))
                          & " a" & Img (I - 1));
               end loop;
               return To_String (R);
            end Args_Decl;

            function Args_Pass return String is
               R : Unbounded_String;
            begin
               for I in 1 .. NCB loop
                  Append (R, ", a" & Img (I - 1));
               end loop;
               return To_String (R);
            end Args_Pass;
         begin
            Append (Decl, "AhcNode *ffi_" & Base & ";" & LF);
            Append (Fns, "static AhcNode *cbclos_" & Base & "["
                    & Img (Pool) & "];" & LF);
            Append (Fns, "static " & RT & " cbrun_" & Base
                    & "(int i" & Args_Decl & ") {" & LF
                    & "  AhcNode *r = cbclos_" & Base & "[i];" & LF
                    & "  if (!r) ahc_die(""FFI: callback used after "
                    & "freeHaskellFunPtr"");" & LF);
            for I in 1 .. NCB loop
               declare
                  A : constant String := "a" & Img (I - 1);
               begin
                  Append (Fns, "  r = ahc_apply(r, "
                          & (case F.CB_Args (I) is
                               when M_Int    =>
                                 "ahc_mk_int(" & A & ")",
                               when M_Double =>
                                 "ahc_mk_double(" & A & ")",
                               when M_Char   =>
                                 "ahc_mk_char(" & A & ")",
                               when M_Bool   =>
                                 "ahc_mk_con(" & A & " ? 2 : 1, 0)",
                               when M_String =>
                                 "ahc_mk_string(" & A & ")",
                               when M_Ptr    =>
                                 "ahc_mk_ptr(" & A & ")",
                               when M_Unit   => "ahc_mk_con(1, 0)")
                          & ");" & LF);
               end;
            end loop;
            if F.CB_Res_IO then
               Append (Fns, "  r = ahc_run_io(r);" & LF);
            else
               Append (Fns, "  r = ahc_eval(r);" & LF);
            end if;
            case F.CB_Res is
               when M_Unit =>
                  Append (Fns, "  (void)r;" & LF);
               when M_Int =>
                  Append (Fns, "  if (r->tag != AHC_INT) ahc_die("
                          & """FFI: Int result out of range"");" & LF
                          & "  return r->u.i;" & LF);
               when M_Double =>
                  Append (Fns, "  return r->u.d;" & LF);
               when M_Char =>
                  Append (Fns, "  return r->u.c;" & LF);
               when M_Bool =>
                  Append (Fns, "  return r->u.con.contag == 2;"
                          & LF);
               when M_String =>
                  Append (Fns, "  return ahc_marshal_cstring(r);"
                          & LF);
               when M_Ptr =>
                  Append (Fns, "  return r->u.p;" & LF);
            end case;
            Append (Fns, "}" & LF);
            declare
               AD : constant String := Args_Decl;
               Plain : constant String :=
                 (if NCB = 0 then "void"
                  else AD (AD'First + 2 .. AD'Last));
            begin
               for I in 0 .. Pool - 1 loop
                  Append (Fns, "static " & RT & " tramp_" & Base
                          & "_" & Img (I) & "(" & Plain & ") { "
                          & (if F.CB_Res = M_Unit then ""
                             else "return ")
                          & "cbrun_" & Base & "(" & Img (I)
                          & Args_Pass & "); }" & LF);
               end loop;
            end;
            Append (Fns, "static void *tramps_" & Base & "["
                    & Img (Pool) & "] = {" & LF);
            for I in 0 .. Pool - 1 loop
               Append (Fns, "  (void *)tramp_" & Base & "_"
                       & Img (I) & "," & LF);
            end loop;
            Append (Fns, "};" & LF);
            Append (Fns, "static AhcNode *ffiio_" & Base
                    & "(AhcNode **env, AhcNode *w) {" & LF
                    & "  (void)w;" & LF
                    & "  return ahc_wrap_fun(env[0], cbclos_" & Base
                    & ", tramps_" & Base & ", " & Img (Pool) & ");"
                    & LF & "}" & LF);
            Append (Fns, "static AhcNode *ffiw_" & Base
                    & "(AhcNode **a) {" & LF
                    & "  AhcNode **e = ahc_env(1);" & LF
                    & "  e[0] = a[0];" & LF
                    & "  return ahc_mk_fun(ffiio_" & Base & ", e);"
                    & LF & "}" & LF & LF);
            Append (Init, "  ffi_" & Base & " = ahc_mk_primn(1, ffiw_"
                    & Base & ");" & LF);
         end Emit_Wrapper;

      begin
         if F.Is_Wrapper then
            Emit_Wrapper;
            return;
         end if;
         Append (Decl, Proto & LF);
         Append (Decl, "AhcNode *ffi_" & Base & ";" & LF);
         if F.Res_IO then
            --  World-passing shape: the effect runs only when the IO
            --  action meets the world (the p_readfile pattern).
            Append (Fns, "static AhcNode *ffiio_" & Base
                    & "(AhcNode **env, AhcNode *w) {" & LF
                    & "  (void)w;"
                    & (if NArgs = 0 then " (void)env;" else "") & LF
                    & Call_Text ("env") & "}" & LF & LF);
            if NArgs > 0 then
               Append (Fns, "static AhcNode *ffiw_" & Base
                       & "(AhcNode **a) {" & LF
                       & "  AhcNode **e = ahc_env(" & Img (NArgs)
                       & ");" & LF);
               for I in 1 .. NArgs loop
                  Append (Fns, "  e[" & Img (I - 1) & "] = a["
                          & Img (I - 1) & "];" & LF);
               end loop;
               Append (Fns, "  return ahc_mk_fun(ffiio_" & Base
                       & ", e);" & LF & "}" & LF & LF);
               Append (Init, "  ffi_" & Base & " = ahc_mk_primn("
                       & Img (NArgs) & ", ffiw_" & Base & ");" & LF);
            else
               Append (Init, "  ffi_" & Base & " = ahc_mk_fun(ffiio_"
                       & Base & ", NULL);" & LF);
            end if;
         elsif NArgs > 0 then
            Append (Fns, "static AhcNode *ffiw_" & Base
                    & "(AhcNode **a) {" & LF
                    & Call_Text ("a") & "}" & LF & LF);
            Append (Init, "  ffi_" & Base & " = ahc_mk_primn("
                    & Img (NArgs) & ", ffiw_" & Base & ");" & LF);
         else
            --  Nullary pure import: a CAF thunk, evaluated once.
            Append (Fns, "static AhcNode *ffit_" & Base
                    & "(AhcNode **env) {" & LF
                    & "  (void)env;" & LF
                    & Call_Text ("a") & "}" & LF & LF);
            Append (Init, "  ffi_" & Base & " = ahc_mk_thunk(ffit_"
                    & Base & ", NULL);" & LF);
         end if;
      end Emit_Foreign;

      ------------------------------------------------------------------
      --  Foreign exports: a real C-ABI entry function per export,
      --  emitted into the root unit (its file already sees every
      --  global through ahc_prog.h). Marshal C args to nodes, build
      --  the application spine, eval (or run the IO action), unbox.
      ------------------------------------------------------------------

      --  Result type as seen by the C caller: an exported String
      --  comes back as a malloc'd char* the caller frees.
      function C_Ret_Type (K : Marshal_Kind) return String
      is (if K = M_String then "char *" else C_Type (K));

      function Export_Proto (F : Foreign_Import) return String is
         R : Unbounded_String;
         NArgs : constant Natural := Natural (F.Args.Length);
      begin
         Append (R, C_Ret_Type (F.Res) & " "
                 & Table.Text (Names.Real_Name_Id (F.C_Name)) & "(");
         if NArgs = 0 then
            Append (R, "void");
         else
            for I in 1 .. NArgs loop
               if I > 1 then
                  Append (R, ", ");
               end if;
               Append (R, C_Type (F.Args (I)) & " a" & Img (I - 1));
            end loop;
         end if;
         Append (R, ")");
         return To_String (R);
      end Export_Proto;

      procedure Emit_Export (F : Foreign_Import) is
         NArgs : constant Natural := Natural (F.Args.Length);
         LF : Character renames ASCII.LF;
      begin
         Append (Fns, Export_Proto (F) & " {" & LF);
         Append (Fns, "  AhcNode *r = "
                 & Var_Ref (F.Binder, Scope_Maps.Empty_Map) & ";"
                 & LF);
         for I in 1 .. NArgs loop
            declare
               A : constant String := "a" & Img (I - 1);
            begin
               Append (Fns, "  r = ahc_apply(r, "
                       & (case F.Args (I) is
                            when M_Int    => "ahc_mk_int(" & A & ")",
                            when M_Double =>
                              "ahc_mk_double(" & A & ")",
                            when M_Char   => "ahc_mk_char(" & A & ")",
                            when M_Bool   =>
                              "ahc_mk_con(" & A & " ? 2 : 1, 0)",
                            when M_String =>
                              "ahc_mk_string(" & A & ")",
                            when M_Ptr    => "ahc_mk_ptr(" & A & ")",
                            when M_Unit   => "ahc_mk_con(1, 0)")
                       & ");" & LF);
            end;
         end loop;
         if F.Res_IO then
            Append (Fns, "  r = ahc_run_io(r);" & LF);
         else
            Append (Fns, "  r = ahc_eval(r);" & LF);
         end if;
         case F.Res is
            when M_Unit =>
               Append (Fns, "  (void)r;" & LF);
            when M_Int =>
               Append (Fns, "  if (r->tag != AHC_INT) ahc_die(""FFI: "
                       & "Int result out of range"");" & LF
                       & "  return r->u.i;" & LF);
            when M_Double =>
               Append (Fns, "  return r->u.d;" & LF);
            when M_Char =>
               Append (Fns, "  return r->u.c;" & LF);
            when M_Bool =>
               Append (Fns, "  return r->u.con.contag == 2;" & LF);
            when M_String =>
               Append (Fns, "  return ahc_marshal_cstring(r);" & LF);
            when M_Ptr =>
               Append (Fns, "  return r->u.p;" & LF);
         end case;
         Append (Fns, "}" & LF & LF);
      end Emit_Export;

      Main_Var : Var_Id := No_Var;

   begin
      --  Special globals: prims and selectors.
      declare
         C : Prelude_Core.Prim_Maps.Cursor := Prims.First;
      begin
         while Prelude_Core.Prim_Maps.Has_Element (C) loop
            Special.Include
              (Prelude_Core.Prim_Maps.Key (C),
               To_Unbounded_String
                 (Table.Text (Names.Real_Name_Id
                    (Prelude_Core.Prim_Maps.Element (C)))));
            Prelude_Core.Prim_Maps.Next (C);
         end loop;
      end;
      for CI in 1 .. M.Last_Class loop
         declare
            Cl : constant Class_Info := M.Info (Real_Class_Id (CI));
            NS : constant Natural := Natural (Cl.Supers.Length);
         begin
            for I in 1 .. Cl.Super_Sels.Last_Index loop
               Special.Include
                 (Cl.Super_Sels (I),
                  To_Unbounded_String
                    ("ahc_mk_selector(" & Img (I - 1) & ")"));
            end loop;
            for I in 1 .. Cl.Methods.Last_Index loop
               if Cl.Methods (I).Selector /= No_Var then
                  Special.Include
                    (Real_Var_Id (Cl.Methods (I).Selector),
                     To_Unbounded_String
                       ("ahc_mk_selector(" & Img (NS + I - 1)
                        & ")"));
               end if;
            end loop;
         end;
      end loop;

      --  Foreign-import binders substitute as their stable node
      --  symbols at every occurrence.
      for FI in 1 .. M.Foreigns.Last_Index loop
         Special.Include
           (M.Foreigns (FI).Binder,
            To_Unbounded_String ("ffi_" & FFI_Base (FI)));
      end loop;

      --  Register bodied globals and mint their stable symbols.
      declare
         Taken : Str_Nat_Maps.Map;
      begin
         for GI in 1 .. M.Top_Binds.Last_Index loop
            declare
               Owner : constant String :=
                 (if GI <= Owners.Last_Index
                  then To_String (Owners (GI))
                  else "Prelude");
            begin
               for B of M.Top_Binds (GI).Binds loop
                  Has_Body.Include
                    (B.Binder, To_Unbounded_String (""));
                  --  Prims/selectors that also got Core bodies keep
                  --  their body (drop the special mapping).
                  if Special.Contains (B.Binder) then
                     Special.Delete (B.Binder);
                  end if;
                  declare
                     Base : constant Unbounded_String :=
                       To_Unbounded_String
                         ("g_" & Mangle (Owner) & "_"
                          & Mangle (Table.Text
                              (Names.Real_Name_Id
                                 (M.Info (B.Binder).Name))));
                     C : constant Str_Nat_Maps.Cursor :=
                       Taken.Find (Base);
                  begin
                     if Str_Nat_Maps.Has_Element (C) then
                        declare
                           N : constant Natural :=
                             Str_Nat_Maps.Element (C) + 1;
                        begin
                           Taken.Replace_Element (C, N);
                           Sym.Include
                             (B.Binder, Base & "_" & Img (N));
                        end;
                     else
                        Taken.Include (Base, 1);
                        Sym.Include (B.Binder, Base);
                     end if;
                  end;
               end loop;
            end;
         end loop;
      end;

      declare
         C : constant Builtins.Var_Maps.Cursor :=
           Env.Values.Find (Table.Intern ("main"));
      begin
         if Builtins.Var_Maps.Has_Element (C) then
            Main_Var := Var_Id (Builtins.Var_Maps.Element (C));
         end if;
      end;

      --  Exact rational literals need :%'s runtime tag; absent
      --  Data.Ratio, Ratio_Tag stays -1 and float literals emit
      --  plain double nodes as before.
      declare
         Colon_Pct : constant Names.Name_Id :=
           Names.Name_Id (Table.Intern (":%"));
      begin
         for DI in 1 .. M.Last_DataCon loop
            if M.Info (Core.Real_DataCon_Id (DI)).Name = Colon_Pct
            then
               Ratio_Tag :=
                 Integer (M.Info (Core.Real_DataCon_Id (DI)).Tag);
            end if;
         end loop;
      end;

      --  Shared header: extern CAF globals + unit init prototypes.
      Header := To_Unbounded_String
        ("#include ""ahc_rts.h""" & ASCII.LF & ASCII.LF);
      for G of M.Top_Binds loop
         for B of G.Binds loop
            Append (Header, "extern AhcNode *" & Sym_Of (B.Binder)
                    & ";" & ASCII.LF);
         end loop;
      end loop;
      for FI in 1 .. M.Foreigns.Last_Index loop
         Append (Header, "extern AhcNode *ffi_" & FFI_Base (FI)
                 & ";" & ASCII.LF);
      end loop;
      Append (Header, ASCII.LF);
      for U of Units loop
         Append (Header, "void ahc_init_" & Mangle (To_String (U))
                 & "(void);" & ASCII.LF);
      end loop;

      --  One C file per unit, in Units (dependency) order; the last
      --  unit is the root and carries main().
      for UI in 1 .. Units.Last_Index loop
         declare
            U : constant String := To_String (Units (UI));
            F : Unit_File;
         begin
            Decl := Null_Unbounded_String;
            Fns := Null_Unbounded_String;
            Init := Null_Unbounded_String;
            Fn_Counter := 0;
            L_Map.Clear;
            L_Next := 0;

            for GI in 1 .. M.Top_Binds.Last_Index loop
               if (if GI <= Owners.Last_Index
                   then To_String (Owners (GI)) = U
                   else U = "Prelude")
               then
                  for B of M.Top_Binds (GI).Binds loop
                     Append (Decl, "AhcNode *" & Sym_Of (B.Binder)
                             & ";" & ASCII.LF);
                     Append (Init, "  " & Sym_Of (B.Binder) & " = "
                             & Gen_Lazy (B.Rhs, Scope_Maps.Empty_Map)
                             & ";" & ASCII.LF);
                  end loop;
               end if;
            end loop;

            for FI in 1 .. M.Foreigns.Last_Index loop
               if F_Owner (FI) = U then
                  Emit_Foreign (FI);
               end if;
            end loop;

            if UI = Units.Last_Index then
               for F of M.Foreign_Exports loop
                  Emit_Export (F);
               end loop;
            end if;

            F.Name := Units (UI);
            F.Text := To_Unbounded_String
              ("#include ""ahc_prog.h""" & ASCII.LF & ASCII.LF);
            Append (F.Text, Decl);
            Append (F.Text, ASCII.LF);
            Append (F.Text, Fns);
            Append (F.Text, "void ahc_init_" & Mangle (U)
                    & "(void) {" & ASCII.LF);
            Append (F.Text, Init);
            Append (F.Text, "}" & ASCII.LF);

            if UI = Units.Last_Index then
               if Lib_Mode then
                  Append (F.Text, ASCII.LF
                          & "void ahc_lib_init(void) {" & ASCII.LF
                          & "  ahc_rts_init();" & ASCII.LF);
                  for U2 of Units loop
                     Append (F.Text, "  ahc_init_"
                             & Mangle (To_String (U2)) & "();"
                             & ASCII.LF);
                  end loop;
                  Append (F.Text, "}" & ASCII.LF);
               else
                  Append (F.Text, ASCII.LF
                          & "int main(int argc, char **argv) {"
                          & ASCII.LF
                          & "  ahc_set_args(argc, argv);" & ASCII.LF
                          & "  ahc_rts_init();" & ASCII.LF);
                  for U2 of Units loop
                     Append (F.Text, "  ahc_init_"
                             & Mangle (To_String (U2)) & "();"
                             & ASCII.LF);
                  end loop;
                  if Main_Var /= No_Var
                    and then Has_Body.Contains
                               (Real_Var_Id (Main_Var))
                  then
                     Append (F.Text, "  ahc_run_main("
                             & Sym_Of (Real_Var_Id (Main_Var))
                             & ");" & ASCII.LF);
                  else
                     Append (F.Text,
                             "  ahc_die(""no main function"");"
                             & ASCII.LF);
                  end if;
                  Append (F.Text, "  return 0;" & ASCII.LF & "}"
                          & ASCII.LF);
               end if;
            end if;

            Files.Append (F);
         end;
      end loop;

      --  ahc_exports.h: the C-visible surface of this program.
      Exports_H := To_Unbounded_String
        ("/* Generated by ahc emit: C entry points for foreign"
         & " exports. */" & ASCII.LF
         & "#ifndef AHC_EXPORTS_H" & ASCII.LF
         & "#define AHC_EXPORTS_H" & ASCII.LF
         & "#ifdef __cplusplus" & ASCII.LF
         & "extern ""C"" {" & ASCII.LF
         & "#endif" & ASCII.LF & ASCII.LF);
      if Lib_Mode then
         Append (Exports_H,
                 "/* Call once, from the one thread that will use"
                 & " the library. */" & ASCII.LF
                 & "void ahc_lib_init(void);" & ASCII.LF
                 & ASCII.LF);
      end if;
      for F of M.Foreign_Exports loop
         Append (Exports_H, Export_Proto (F) & ";" & ASCII.LF);
      end loop;
      Append (Exports_H, ASCII.LF
              & "#ifdef __cplusplus" & ASCII.LF
              & "}" & ASCII.LF
              & "#endif" & ASCII.LF
              & "#endif" & ASCII.LF);
   end Emit_Units;

end AHC.CodeGen;
