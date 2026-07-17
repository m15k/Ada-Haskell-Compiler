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
                     SB : constant Real_Expr_Id :=
                       Simp (N.Let_Body, Env2);
                     Live : Bind_Vectors.Vector;
                  begin
                     --  Dead non-recursive bindings are unforced
                     --  thunks: drop them. (Recursive groups are
                     --  kept whole.)
                     if N.Is_Rec then
                        Live := Kept;
                     else
                        for B of Kept loop
                           if Count (B.Binder, SB) > 0 then
                              Live.Append (B);
                           else
                              Changes := Changes + 1;
                           end if;
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
