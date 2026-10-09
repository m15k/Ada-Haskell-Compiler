with Ada.Containers.Hashed_Maps;

package body AHC.Inst_Match is

   function Hash (T : Real_TyVar_Id) return Ada.Containers.Hash_Type
   is (Ada.Containers.Hash_Type (T));

   package Bind_Maps is new Ada.Containers.Hashed_Maps
     (Real_TyVar_Id, Real_Type_Id, Hash, "=");

   package Ren_Maps is new Ada.Containers.Hashed_Maps
     (Real_TyVar_Id, Real_TyVar_Id, Hash, "=");

   function Combine (A, B : Match_Result) return Match_Result
   is (if A = No_Match or else B = No_Match then No_Match
       elsif A = Undecided or else B = Undecided then Undecided
       else Matched);

   ----------------
   -- Match_Head --
   ----------------

   function Match_Head
     (M      : Core_Module;
      Env    : Builtins.Global_Env;
      Pat    : Real_Type_Id;
      Vars   : TyVar_Id_Vectors.Vector;
      Target : Real_Type_Id;
      Args   : out Type_Id_Vectors.Vector) return Match_Result
   is
      B : Bind_Maps.Map;

      --  Structural equality, for a head variable that occurs twice
      --  (`instance C (Either a a)`). A metavariable makes it
      --  undecided unless both sides are that same metavariable.
      function Same (X, Y : Real_Type_Id) return Match_Result is
         NX : constant Type_Node := M.Node (Norm (X));
         NY : constant Type_Node := M.Node (Norm (Y));
      begin
         if NX.Kind = TMeta_T or else NY.Kind = TMeta_T then
            return (if NX.Kind = TMeta_T and then NY.Kind = TMeta_T
                      and then NX.Meta = NY.Meta
                    then Matched else Undecided);
         elsif NX.Kind /= NY.Kind then
            return No_Match;
         end if;
         case NX.Kind is
            when TVar_T =>
               return (if NX.Tv = NY.Tv then Matched else No_Match);
            when TCon_T =>
               return (if NX.Con = NY.Con then Matched else No_Match);
            when TApp_T =>
               declare
                  R1 : constant Match_Result := Same (NX.T_Fun, NY.T_Fun);
               begin
                  return Combine (R1, Same (NX.T_Arg, NY.T_Arg));
               end;
            when TFun_T =>
               declare
                  R1 : constant Match_Result := Same (NX.From, NY.From);
               begin
                  return Combine (R1, Same (NX.To, NY.To));
               end;
            when TMeta_T =>
               return Undecided;
         end case;
      end Same;

      --  P is the instance head (TVar/TCon/TApp/TFun only), T0 the
      --  wanted type. Every compound case binds its first result to a
      --  constant before computing the second: both mutate B, and Ada
      --  leaves the order of a call's actuals unspecified.
      function Go (P, T0 : Real_Type_Id) return Match_Result is
         PN : constant Type_Node := M.Node (P);
         T  : constant Real_Type_Id := Norm (T0);
         TN : constant Type_Node := M.Node (T);
      begin
         if PN.Kind = TVar_T then
            if B.Contains (PN.Tv) then
               return Same (B.Element (PN.Tv), T);
            end if;
            B.Include (PN.Tv, T);
            return Matched;
         elsif TN.Kind = TMeta_T then
            return Undecided;
         end if;
         case PN.Kind is
            when TCon_T =>
               return (if TN.Kind = TCon_T and then TN.Con = PN.Con
                       then Matched else No_Match);
            when TApp_T =>
               if TN.Kind = TApp_T then
                  declare
                     R1 : constant Match_Result := Go (PN.T_Fun, TN.T_Fun);
                  begin
                     return Combine (R1, Go (PN.T_Arg, TN.T_Arg));
                  end;
               elsif TN.Kind = TFun_T then
                  --  A head spelled `(->) a b` against `x -> y` (M142:
                  --  a function type unifies with (->) applied).
                  declare
                     PF : constant Type_Node := M.Node (PN.T_Fun);
                  begin
                     if PF.Kind = TApp_T then
                        declare
                           PH : constant Type_Node := M.Node (PF.T_Fun);
                        begin
                           if PH.Kind = TCon_T
                             and then TyCon_Id (PH.Con) = Env.Arrow_TC
                           then
                              declare
                                 R1 : constant Match_Result :=
                                   Go (PF.T_Arg, TN.From);
                              begin
                                 return Combine (R1, Go (PN.T_Arg, TN.To));
                              end;
                           end if;
                        end;
                     end if;
                  end;
               end if;
               return No_Match;
            when TFun_T =>
               if TN.Kind = TFun_T then
                  declare
                     R1 : constant Match_Result := Go (PN.From, TN.From);
                  begin
                     return Combine (R1, Go (PN.To, TN.To));
                  end;
               end if;
               return No_Match;
            when TVar_T | TMeta_T =>
               return No_Match;   --  TVar handled above; heads hold no metas
         end case;
      end Go;

      R : constant Match_Result := Go (Pat, Target);
   begin
      Args := Type_Id_Vectors.Empty_Vector;
      for V of Vars loop
         --  Every variable of a well-formed head occurs in it, so it is
         --  bound after any Matched; the Target fallback only keeps the
         --  vector positional on No_Match/Undecided, where callers
         --  ignore Args.
         Args.Append (if B.Contains (V) then B.Element (V) else Target);
      end loop;
      return R;
   end Match_Head;

   --------------------
   -- Match_Instance --
   --------------------

   function Match_Instance
     (M      : Core_Module;
      Env    : Builtins.Global_Env;
      Inst   : Instance_Info;
      Target : Real_Type_Id;
      Args   : out Type_Id_Vectors.Vector) return Match_Result
   is
      function Full is new Match_Head (Norm);
      Spine : Type_Id_Vectors.Vector;   --  reversed spine arguments
      T : Real_Type_Id := Norm (Target);
   begin
      if Inst.Head_Type /= No_Type then
         return Full (M, Env, Real_Type_Id (Inst.Head_Type),
                      Inst.Head_Vars, Target, Args);
      end if;
      Args := Type_Id_Vectors.Empty_Vector;
      loop
         declare
            N : constant Type_Node := M.Node (T);
         begin
            case N.Kind is
               when TApp_T =>
                  Spine.Append (N.T_Arg);
                  T := Norm (N.T_Fun);
               when TFun_T =>
                  if Inst.Head /= Env.Arrow_TC then
                     return No_Match;
                  end if;
                  Args.Append (N.From);
                  Args.Append (N.To);
                  for I in reverse 1 .. Spine.Last_Index loop
                     Args.Append (Spine (I));
                  end loop;
                  return Matched;
               when TCon_T =>
                  if TyCon_Id (N.Con) /= Inst.Head then
                     return No_Match;
                  end if;
                  for I in reverse 1 .. Spine.Last_Index loop
                     Args.Append (Spine (I));
                  end loop;
                  return Matched;
               when TMeta_T =>
                  return Undecided;
               when TVar_T =>
                  return No_Match;
            end case;
         end;
      end loop;
   end Match_Instance;

   -------------------
   -- Instance_Type --
   -------------------

   function Instance_Type
     (M : in out Core_Module; Env : Builtins.Global_Env;
      I : Instance_Info) return Real_Type_Id
   is
   begin
      if I.Head_Type /= No_Type then
         return Real_Type_Id (I.Head_Type);
      end if;
      declare
         H : Real_Type_Id :=
           M.Add (Type_Node'(Kind => TCon_T,
                             Con => Real_TyCon_Id (I.Head),
                             Refine => No_Refinement));
      begin
         for HV of I.Head_Vars loop
            declare
               A : constant Real_Type_Id :=
                 M.Add (Type_Node'(Kind => TVar_T,
                                   Tv => Real_TyVar_Id (HV)));
            begin
               H := Builtins.Make_App (M, Env, H, A);
            end;
         end loop;
         return H;
      end;
   end Instance_Type;

   -----------------
   -- Heads_Equal --
   -----------------

   function Heads_Equal
     (M : Core_Module; A, B : Real_Type_Id) return Boolean
   is
      AB : Ren_Maps.Map;   --  A's variables -> B's
      BA : Ren_Maps.Map;   --  and back: the renaming is a bijection

      function Go (X, Y : Real_Type_Id) return Boolean is
         NX : constant Type_Node := M.Node (X);
         NY : constant Type_Node := M.Node (Y);
      begin
         if NX.Kind /= NY.Kind then
            return False;
         end if;
         case NX.Kind is
            when TVar_T =>
               if AB.Contains (NX.Tv) or else BA.Contains (NY.Tv) then
                  return AB.Contains (NX.Tv)
                    and then BA.Contains (NY.Tv)
                    and then AB.Element (NX.Tv) = NY.Tv
                    and then BA.Element (NY.Tv) = NX.Tv;
               end if;
               AB.Include (NX.Tv, NY.Tv);
               BA.Include (NY.Tv, NX.Tv);
               return True;
            when TCon_T =>
               return NX.Con = NY.Con;
            when TApp_T =>
               return Go (NX.T_Fun, NY.T_Fun)
                 and then Go (NX.T_Arg, NY.T_Arg);
            when TFun_T =>
               return Go (NX.From, NY.From) and then Go (NX.To, NY.To);
            when TMeta_T =>
               return NX.Meta = NY.Meta;
         end case;
      end Go;
   begin
      return Go (A, B);
   end Heads_Equal;

end AHC.Inst_Match;
