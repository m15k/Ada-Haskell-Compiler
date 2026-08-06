with Ada.Containers.Hashed_Maps;

with AHC.Names;
with AHC.Rename;

package body AHC.Optimizer is

   use AHC.Core;
   use type AHC.Names.Name_Id;

   package Env_Maps is new Ada.Containers.Hashed_Maps
     (Real_Var_Id, Expr_Node,
      Hash => Rename.Var_Hash, Equivalent_Keys => "=");

   procedure Optimize
     (M : in out Core.Core_Module; Rounds : out Natural)
   is
      Changes : Natural := 0;

      --  Occurrences of V in the (already rebuilt) expression E.
      function Count (V : Real_Var_Id; E : Real_Expr_Id) return Natural
      is
         N : constant Expr_Node := M.Node (E);
      begin
         case N.Kind is
            when Var_C =>
               return (if N.V = V then 1 else 0);
            when Lit_C | Con_C =>
               return 0;
            when App_C =>
               return Count (V, N.Fun) + Count (V, N.Arg);
            when Lam_C =>
               return (if N.Binder = V then 0
                       else Count (V, N.Lam_Body));
            when Let_C =>
               declare
                  T : Natural := 0;
               begin
                  for B of N.Binds loop
                     if B.Binder = V then
                        return 0;   --  shadowed
                     end if;
                  end loop;
                  for B of N.Binds loop
                     T := T + Count (V, B.Rhs);
                  end loop;
                  return T + Count (V, N.Let_Body);
               end;
            when Case_C =>
               declare
                  T : Natural := Count (V, N.Scrutinee);
               begin
                  for A of N.Alts loop
                     declare
                        Alt : constant Alt_Node := M.Node (A);
                        Shadowed : Boolean := False;
                     begin
                        if Alt.Kind = Con_Alt then
                           for B of Alt.Binders loop
                              if B = V then
                                 Shadowed := True;
                              end if;
                           end loop;
                        end if;
                        if not Shadowed then
                           T := T + Count (V, Alt.Alt_Body);
                        end if;
                     end;
                  end loop;
                  return T;
               end;
         end case;
      end Count;

      --  Any free occurrence of V under a lambda within E: inlining
      --  there could turn one evaluation into many, so it is barred.
      function Under_Lam
        (V : Real_Var_Id; E : Real_Expr_Id; In_Lam : Boolean)
         return Boolean
      is
         N : constant Expr_Node := M.Node (E);
      begin
         case N.Kind is
            when Var_C =>
               return N.V = V and then In_Lam;
            when Lit_C | Con_C =>
               return False;
            when App_C =>
               return Under_Lam (V, N.Fun, In_Lam)
                 or else Under_Lam (V, N.Arg, In_Lam);
            when Lam_C =>
               return N.Binder /= V
                 and then Under_Lam (V, N.Lam_Body, True);
            when Let_C =>
               for B of N.Binds loop
                  if B.Binder = V then
                     return False;   --  shadowed
                  end if;
               end loop;
               for B of N.Binds loop
                  if Under_Lam (V, B.Rhs, In_Lam) then
                     return True;
                  end if;
               end loop;
               return Under_Lam (V, N.Let_Body, In_Lam);
            when Case_C =>
               if Under_Lam (V, N.Scrutinee, In_Lam) then
                  return True;
               end if;
               for A of N.Alts loop
                  declare
                     Alt : constant Alt_Node := M.Node (A);
                     Shadowed : Boolean := False;
                  begin
                     if Alt.Kind = Con_Alt then
                        for B of Alt.Binders loop
                           if B = V then
                              Shadowed := True;
                           end if;
                        end loop;
                     end if;
                     if not Shadowed
                       and then Under_Lam (V, Alt.Alt_Body, In_Lam)
                     then
                        return True;
                     end if;
                  end;
               end loop;
               return False;
         end case;
      end Under_Lam;

      --  Replace the single free occurrence of V in E with R (which
      --  MOVES - the caller guarantees exactly one occurrence, so
      --  the tree invariant is preserved). Untouched subtrees are
      --  reused; the path to the occurrence is rebuilt.
      function Subst_One
        (V : Real_Var_Id; R : Real_Expr_Id; E : Real_Expr_Id)
         return Real_Expr_Id
      is
         N : constant Expr_Node := M.Node (E);
      begin
         case N.Kind is
            when Var_C =>
               return (if N.V = V then R else E);
            when Lit_C | Con_C =>
               return E;
            when App_C =>
               if Count (V, N.Fun) > 0 then
                  return M.Add (Expr_Node'
                    (Kind => App_C, Span => N.Span,
                     Fun => Subst_One (V, R, N.Fun),
                     Arg => N.Arg));
               end if;
               return M.Add (Expr_Node'
                 (Kind => App_C, Span => N.Span, Fun => N.Fun,
                  Arg => Subst_One (V, R, N.Arg)));
            when Lam_C =>
               if N.Binder = V then
                  return E;
               end if;
               return M.Add (Expr_Node'
                 (Kind => Lam_C, Span => N.Span, Binder => N.Binder,
                  Lam_Body => Subst_One (V, R, N.Lam_Body)));
            when Let_C =>
               for B of N.Binds loop
                  if B.Binder = V then
                     return E;   --  shadowed
                  end if;
               end loop;
               declare
                  Binds : Bind_Vectors.Vector;
                  Done : Boolean := False;
               begin
                  for B of N.Binds loop
                     if not Done and then Count (V, B.Rhs) > 0 then
                        Binds.Append (Bind_Pair'
                          (Binder => B.Binder,
                           Rhs => Subst_One (V, R, B.Rhs)));
                        Done := True;
                     else
                        Binds.Append (B);
                     end if;
                  end loop;
                  return M.Add (Expr_Node'
                    (Kind => Let_C, Span => N.Span,
                     Is_Rec => N.Is_Rec, Binds => Binds,
                     Let_Body =>
                       (if Done then N.Let_Body
                        else Subst_One (V, R, N.Let_Body))));
               end;
            when Case_C =>
               if Count (V, N.Scrutinee) > 0 then
                  return M.Add (Expr_Node'
                    (Kind => Case_C, Span => N.Span,
                     Scrutinee => Subst_One (V, R, N.Scrutinee),
                     Alts => N.Alts));
               end if;
               declare
                  Alts : Alt_Id_Vectors.Vector;
                  Done : Boolean := False;
               begin
                  for A of N.Alts loop
                     declare
                        Alt : constant Alt_Node := M.Node (A);
                        Shadowed : Boolean := False;
                     begin
                        if Alt.Kind = Con_Alt then
                           for B of Alt.Binders loop
                              if B = V then
                                 Shadowed := True;
                              end if;
                           end loop;
                        end if;
                        if not Done and then not Shadowed
                          and then Count (V, Alt.Alt_Body) > 0
                        then
                           case Alt.Kind is
                              when Con_Alt =>
                                 Alts.Append (M.Add (Alt_Node'
                                   (Kind => Con_Alt,
                                    Span => Alt.Span,
                                    A_Con => Alt.A_Con,
                                    Binders => Alt.Binders,
                                    Alt_Body => Subst_One
                                      (V, R, Alt.Alt_Body))));
                              when Lit_Alt =>
                                 Alts.Append (M.Add (Alt_Node'
                                   (Kind => Lit_Alt,
                                    Span => Alt.Span,
                                    A_Lit => Alt.A_Lit,
                                    Alt_Body => Subst_One
                                      (V, R, Alt.Alt_Body))));
                              when Default_Alt =>
                                 Alts.Append (M.Add (Alt_Node'
                                   (Kind => Default_Alt,
                                    Span => Alt.Span,
                                    Alt_Body => Subst_One
                                      (V, R, Alt.Alt_Body))));
                           end case;
                           Done := True;
                        else
                           Alts.Append (A);
                        end if;
                     end;
                  end loop;
                  return M.Add (Expr_Node'
                    (Kind => Case_C, Span => N.Span,
                     Scrutinee => N.Scrutinee, Alts => Alts));
               end;
         end case;
      end Subst_One;

      --  Constructor spine of a rebuilt expression: Con applied to
      --  zero or more arguments. Returns the DataCon (0 if not a
      --  spine) and fills Args.
      procedure Con_Spine
        (E : Real_Expr_Id;
         DC : out DataCon_Id;
         Args : in out Expr_Id_Vectors.Vector)
      is
         N : constant Expr_Node := M.Node (E);
      begin
         case N.Kind is
            when Con_C =>
               DC := DataCon_Id (N.Con);
            when App_C =>
               Con_Spine (N.Fun, DC, Args);
               if DC /= 0 then
                  Args.Append (N.Arg);
               end if;
            when others =>
               DC := 0;
         end case;
      end Con_Spine;

      function Simp
        (E : Real_Expr_Id; Env : Env_Maps.Map) return Real_Expr_Id
      is
         N : constant Expr_Node := M.Node (E);
      begin
         case N.Kind is
            when Var_C =>
               declare
                  C : constant Env_Maps.Cursor := Env.Find (N.V);
               begin
                  if Env_Maps.Has_Element (C) then
                     declare
                        A : Expr_Node := Env_Maps.Element (C);
                     begin
                        A.Span := N.Span;
                        return M.Add (A);   --  fresh clone per use
                     end;
                  end if;
                  return M.Add (N);
               end;

            when Lit_C | Con_C =>
               return M.Add (N);

            when App_C =>
               declare
                  SF : constant Real_Expr_Id := Simp (N.Fun, Env);
                  SA : constant Real_Expr_Id := Simp (N.Arg, Env);
                  FN : constant Expr_Node := M.Node (SF);
               begin
                  if FN.Kind = Lam_C then
                     --  beta-to-let: sharing-exact.
                     declare
                        Binds : Bind_Vectors.Vector;
                     begin
                        Changes := Changes + 1;
                        Binds.Append (Bind_Pair'
                          (Binder => FN.Binder, Rhs => SA));
                        return M.Add (Expr_Node'
                          (Kind => Let_C, Span => N.Span,
                           Is_Rec => False, Binds => Binds,
                           Let_Body => FN.Lam_Body));
                     end;
                  end if;
                  return M.Add (Expr_Node'
                    (Kind => App_C, Span => N.Span,
                     Fun => SF, Arg => SA));
               end;

            when Lam_C =>
               return M.Add (Expr_Node'
                 (Kind => Lam_C, Span => N.Span, Binder => N.Binder,
                  Lam_Body => Simp (N.Lam_Body, Env)));

            when Let_C =>
               declare
                  Env2 : Env_Maps.Map := Env;
                  Kept : Bind_Vectors.Vector;
               begin
                  --  Simplify right-hand sides; atoms go into the
                  --  environment instead of surviving as bindings.
                  for B of N.Binds loop
                     declare
                        SR : constant Real_Expr_Id :=
                          Simp (B.Rhs, Env);
                        RN : constant Expr_Node := M.Node (SR);
                     begin
                        --  Duplicating a Lit_C string here is free:
                        --  codegen dedups literals into per-unit
                        --  statics, so every copy names the same
                        --  ls_<n>. Revisit if that hoisting is ever
                        --  reverted.
                        if not N.Is_Rec
                          and then RN.Kind in Var_C | Lit_C | Con_C
                        then
                           Changes := Changes + 1;
                           Env2.Include (B.Binder, RN);
                        else
                           Kept.Append (Bind_Pair'
                             (Binder => B.Binder, Rhs => SR));
                        end if;
                     end;
                  end loop;
                  declare
                     SB : Real_Expr_Id :=
                       Simp (N.Let_Body, Env2);
                     Live : Bind_Vectors.Vector;
                  begin
                     --  Dead non-recursive bindings are unforced
                     --  thunks: drop them; a binding used exactly
                     --  ONCE outside any lambda inlines at its use
                     --  site (still evaluated at most once, but the
                     --  let thunk vanishes - and a use in scrutinee
                     --  position evaluates directly). (Recursive
                     --  groups are kept whole.)
                     if N.Is_Rec then
                        Live := Kept;
                     else
                        for B of Kept loop
                           declare
                              Uses : constant Natural :=
                                Count (B.Binder, SB);
                           begin
                              if Uses = 0 then
                                 Changes := Changes + 1;
                              elsif Uses = 1
                                and then not Under_Lam
                                  (B.Binder, SB, False)
                              then
                                 SB := Subst_One
                                   (B.Binder, B.Rhs, SB);
                                 Changes := Changes + 1;
                              else
                                 Live.Append (B);
                              end if;
                           end;
                        end loop;
                     end if;
                     if Live.Is_Empty then
                        return SB;
                     end if;
                     return M.Add (Expr_Node'
                       (Kind => Let_C, Span => N.Span,
                        Is_Rec => N.Is_Rec, Binds => Live,
                        Let_Body => SB));
                  end;
               end;

            when Case_C =>
               declare
                  SS : constant Real_Expr_Id :=
                    Simp (N.Scrutinee, Env);
                  SN : constant Expr_Node := M.Node (SS);
               begin
                  --  Default-only case: the wildcard does not force.
                  if Natural (N.Alts.Length) = 1
                    and then M.Node (N.Alts (1)).Kind = Default_Alt
                  then
                     Changes := Changes + 1;
                     return Simp (M.Node (N.Alts (1)).Alt_Body, Env);
                  end if;

                  --  Case of known literal.
                  if SN.Kind = Lit_C and then SN.Lit.Kind = L_Int then
                     for A of N.Alts loop
                        declare
                           Alt : constant Alt_Node := M.Node (A);
                        begin
                           if Alt.Kind = Lit_Alt
                             and then Alt.A_Lit.Kind = L_Int
                             and then Alt.A_Lit.Text = SN.Lit.Text
                           then
                              Changes := Changes + 1;
                              return Simp (Alt.Alt_Body, Env);
                           end if;
                        end;
                     end loop;
                  end if;

                  --  Case of known constructor: bind the field
                  --  thunks and take the matching branch.
                  declare
                     DC : DataCon_Id;
                     Args : Expr_Id_Vectors.Vector;
                  begin
                     Con_Spine (SS, DC, Args);
                     if DC /= 0 then
                        for A of N.Alts loop
                           declare
                              Alt : constant Alt_Node := M.Node (A);
                           begin
                              if Alt.Kind = Con_Alt
                                and then DataCon_Id (Alt.A_Con) = DC
                                and then Natural (Alt.Binders.Length)
                                         = Natural (Args.Length)
                              then
                                 Changes := Changes + 1;
                                 declare
                                    Body_S : constant Real_Expr_Id :=
                                      Simp (Alt.Alt_Body, Env);
                                    Binds : Bind_Vectors.Vector;
                                 begin
                                    for I in 1 .. Args.Last_Index loop
                                       Binds.Append (Bind_Pair'
                                         (Binder => Alt.Binders (I),
                                          Rhs => Args (I)));
                                    end loop;
                                    if Binds.Is_Empty then
                                       return Body_S;
                                    end if;
                                    return M.Add (Expr_Node'
                                      (Kind => Let_C, Span => N.Span,
                                       Is_Rec => False,
                                       Binds => Binds,
                                       Let_Body => Body_S));
                                 end;
                              end if;
                           end;
                        end loop;
                        --  No constructor alt matched: the default.
                        for A of N.Alts loop
                           if M.Node (A).Kind = Default_Alt then
                              Changes := Changes + 1;
                              return Simp (M.Node (A).Alt_Body, Env);
                           end if;
                        end loop;
                     end if;
                  end;

                  --  Rebuild.
                  declare
                     Alts : Alt_Id_Vectors.Vector;
                  begin
                     for A of N.Alts loop
                        declare
                           Alt : constant Alt_Node := M.Node (A);
                           B2 : constant Real_Expr_Id :=
                             Simp (Alt.Alt_Body, Env);
                        begin
                           case Alt.Kind is
                              when Con_Alt =>
                                 Alts.Append (M.Add (Alt_Node'
                                   (Kind => Con_Alt,
                                    Span => Alt.Span,
                                    A_Con => Alt.A_Con,
                                    Binders => Alt.Binders,
                                    Alt_Body => B2)));
                              when Lit_Alt =>
                                 Alts.Append (M.Add (Alt_Node'
                                   (Kind => Lit_Alt,
                                    Span => Alt.Span,
                                    A_Lit => Alt.A_Lit,
                                    Alt_Body => B2)));
                              when Default_Alt =>
                                 Alts.Append (M.Add (Alt_Node'
                                   (Kind => Default_Alt,
                                    Span => Alt.Span,
                                    Alt_Body => B2)));
                           end case;
                        end;
                     end loop;
                     return M.Add (Expr_Node'
                       (Kind => Case_C, Span => N.Span,
                        Scrutinee => SS, Alts => Alts));
                  end;
               end;
         end case;
      end Simp;

   begin
      Rounds := 0;
      loop
         Changes := 0;
         for GI in 1 .. M.Top_Binds.Last_Index loop
            declare
               G : Top_Bind := M.Top_Binds (GI);
               Empty : constant Env_Maps.Map := Env_Maps.Empty_Map;
            begin
               for BI in 1 .. G.Binds.Last_Index loop
                  G.Binds.Replace_Element
                    (BI, Bind_Pair'
                       (Binder => G.Binds (BI).Binder,
                        Rhs => Simp (G.Binds (BI).Rhs, Empty)));
               end loop;
               M.Top_Binds.Replace_Element (GI, G);
            end;
         end loop;
         Rounds := Rounds + 1;
         exit when Changes = 0 or else Rounds >= Max_Rounds;
      end loop;
   end Optimize;

end AHC.Optimizer;
