package body AHC.Exhaustive is

   use AHC.Syntax;
   use type AHC.Rename.Res_Kind;
   use type AHC.Core.TyCon_Id;
   use type AHC.Core.DataCon_Id;
   use type AHC.Names.Name_Id;

   procedure Check_Match
     (Arena : Syntax.Module_Arena;
      Res   : Rename.Resolutions;
      Table : in out Names.Name_Table;
      Bag   : in out Diagnostics.Diagnostic_Bag;
      M     : Core.Core_Module;
      Env   : Builtins.Global_Env;
      Rows  : Row_Vectors.Vector;
      What  : String;
      Span  : Diagnostics.Source_Span)
   is
      --  Abstract patterns: everything irrefutable collapses to
      --  Wild_A; constructors (including tuples, lists, records)
      --  to Con_A; literals to interned opaque keys (two literals
      --  are "equal" iff their keys are - textual, which is exact
      --  for chars and conservative for numbers).
      type APat_Kind is (Wild_A, Con_A, Lit_A);

      package Nat_Vectors is new Ada.Containers.Vectors
        (Positive, Positive);

      type APat_Node (Kind : APat_Kind := Wild_A) is record
         case Kind is
            when Wild_A =>
               null;
            when Con_A =>
               Con  : Core.Real_DataCon_Id;
               Args : Nat_Vectors.Vector;
            when Lit_A =>
               Key : Names.Name_Id;
         end case;
      end record;

      package APat_Vectors is new Ada.Containers.Vectors
        (Positive, APat_Node);

      Pool : APat_Vectors.Vector;

      function Add (N : APat_Node) return Positive is
      begin
         Pool.Append (N);
         return Pool.Last_Index;
      end Add;

      Wild : constant Positive := Add ((Kind => Wild_A));

      function Lit_Key (S : String) return Names.Name_Id
      is (Names.Name_Id (Table.Intern (S)));

      --  ---------------------------------------------------------
      --  Syntax pattern -> abstract pattern

      function Norm (P : Syntax.Pat_Id) return Positive;

      function Norm_Vec
        (Ps : Syntax.Pat_Id_Vectors.Vector) return Nat_Vectors.Vector
      is
         R : Nat_Vectors.Vector;
      begin
         for P of Ps loop
            R.Append (Norm (Syntax.Pat_Id (P)));
         end loop;
         return R;
      end Norm_Vec;

      --  [p1, p2] normalizes to p1 : (p2 : []).
      function Norm_List
        (Items : Syntax.Pat_Id_Vectors.Vector; From : Positive)
         return Positive
      is
      begin
         if From > Items.Last_Index then
            return Add ((Kind => Con_A,
                         Con => Core.Real_DataCon_Id (Env.Nil_DC),
                         Args => Nat_Vectors.Empty_Vector));
         end if;
         declare
            Args : Nat_Vectors.Vector;
         begin
            Args.Append (Norm (Syntax.Pat_Id (Items (From))));
            Args.Append (Norm_List (Items, From + 1));
            return Add ((Kind => Con_A,
                         Con => Core.Real_DataCon_Id (Env.Cons_DC),
                         Args => Args));
         end;
      end Norm_List;

      function Norm (P : Syntax.Pat_Id) return Positive is
         N : constant Pat_Node := Arena.Node (Real_Pat_Id (P));
      begin
         case N.Kind is
            when Var_P | Wild_P | Con_Chain_P =>
               return Wild;
            when Lazy_P =>
               return Wild;   --  irrefutable by definition
            when As_P =>
               return Norm (Syntax.Pat_Id (N.As_Pat));
            when Sig_P =>
               return Norm (Syntax.Pat_Id (N.Sig_Pat));
            when Lit_Int_P =>
               return Add ((Kind => Lit_A,
                            Key => Lit_Key
                              ("i" & Table.Text
                                 (Names.Real_Name_Id (N.Text)))));
            when Neg_Int_P =>
               return Add ((Kind => Lit_A,
                            Key => Lit_Key
                              ("i-" & Table.Text
                                 (Names.Real_Name_Id (N.Text)))));
            when Lit_Float_P =>
               return Add ((Kind => Lit_A,
                            Key => Lit_Key
                              ("f" & Table.Text
                                 (Names.Real_Name_Id (N.Text)))));
            when Neg_Float_P =>
               return Add ((Kind => Lit_A,
                            Key => Lit_Key
                              ("f-" & Table.Text
                                 (Names.Real_Name_Id (N.Text)))));
            when Lit_Char_P =>
               return Add ((Kind => Lit_A,
                            Key => Lit_Key
                              ("c" & N.Char_Value'Image)));
            when Lit_String_P =>
               --  Empty string literals carry No_Name (AHC.Tokens).
               return Add ((Kind => Lit_A,
                            Key => Lit_Key
                              ("s" & (if N.Text = Names.No_Name then ""
                                      else Table.Text
                                        (Names.Real_Name_Id (N.Text))))));
            when Con_P =>
               declare
                  R : constant Rename.Resolution :=
                    Res.Pat_Res (Positive (P));
               begin
                  if R.Kind /= Rename.Data_Res then
                     return Wild;
                  end if;
                  return Add ((Kind => Con_A, Con => R.Con,
                               Args => Norm_Vec (N.Con_Args)));
               end;
            when Tuple_P =>
               declare
                  Count : constant Natural :=
                    Natural (N.Items.Length);
               begin
                  if Count in Builtins.Tuple_DC_Array'Range
                    and then Env.Tuple_DCs (Count) /= 0
                  then
                     return Add
                       ((Kind => Con_A,
                         Con => Core.Real_DataCon_Id
                                  (Env.Tuple_DCs (Count)),
                         Args => Norm_Vec (N.Items)));
                  end if;
                  return Wild;
               end;
            when List_P =>
               return Norm_List (N.Items, 1);
            when Rec_P =>
               declare
                  R : constant Rename.Resolution :=
                    Res.Pat_Res (Positive (P));
               begin
                  if R.Kind /= Rename.Data_Res then
                     return Wild;
                  end if;
                  declare
                     Info : constant Core.DataCon_Info :=
                       M.Info (R.Con);
                     Args : Nat_Vectors.Vector;
                  begin
                     for FI in 1 .. Info.Field_Names.Last_Index loop
                        declare
                           A : Positive := Wild;
                        begin
                           for F of N.Rec_Fields loop
                              if F.Field.Name = Info.Field_Names (FI)
                              then
                                 A := Norm (Syntax.Pat_Id (F.Value));
                              end if;
                           end loop;
                           Args.Append (A);
                        end;
                     end loop;
                     return Add ((Kind => Con_A, Con => R.Con,
                                  Args => Args));
                  end;
               end;
         end case;
      end Norm;

      --  ---------------------------------------------------------
      --  Usefulness (Maranget). A row is a vector of pool ids; the
      --  matrix a vector of rows. Bounded by a step budget - on
      --  overrun no warning is reported in either direction.

      package Mx_Vectors is new Ada.Containers.Vectors
        (Positive, Nat_Vectors.Vector, Nat_Vectors."=");

      Budget  : Natural := 0;
      Overrun : Boolean := False;

      function Wilds
        (Count : Natural; Tail : Nat_Vectors.Vector)
         return Nat_Vectors.Vector
      is
         R : Nat_Vectors.Vector;
      begin
         for I in 1 .. Count loop
            R.Append (Wild);
         end loop;
         for T of Tail loop
            R.Append (T);
         end loop;
         return R;
      end Wilds;

      function Tail_Of (V : Nat_Vectors.Vector)
        return Nat_Vectors.Vector
      is
         R : Nat_Vectors.Vector;
      begin
         for I in 2 .. V.Last_Index loop
            R.Append (V (I));
         end loop;
         return R;
      end Tail_Of;

      function Prepend
        (Args : Nat_Vectors.Vector; Tail : Nat_Vectors.Vector)
         return Nat_Vectors.Vector
      is
         R : Nat_Vectors.Vector := Args;
      begin
         for T of Tail loop
            R.Append (T);
         end loop;
         return R;
      end Prepend;

      --  Rows that can match constructor C, first column expanded.
      function Spec_Con
        (Rows : Mx_Vectors.Vector; C : Core.Real_DataCon_Id;
         Arity : Natural) return Mx_Vectors.Vector
      is
         R : Mx_Vectors.Vector;
      begin
         for Row of Rows loop
            declare
               H : constant APat_Node := Pool (Row (1));
            begin
               case H.Kind is
                  when Wild_A =>
                     R.Append (Wilds (Arity, Tail_Of (Row)));
                  when Con_A =>
                     if H.Con = C then
                        R.Append (Prepend (H.Args, Tail_Of (Row)));
                     end if;
                  when Lit_A =>
                     null;
               end case;
            end;
         end loop;
         return R;
      end Spec_Con;

      function Spec_Lit
        (Rows : Mx_Vectors.Vector; Key : Names.Name_Id)
         return Mx_Vectors.Vector
      is
         R : Mx_Vectors.Vector;
      begin
         for Row of Rows loop
            declare
               H : constant APat_Node := Pool (Row (1));
            begin
               case H.Kind is
                  when Wild_A =>
                     R.Append (Tail_Of (Row));
                  when Con_A =>
                     null;
                  when Lit_A =>
                     if H.Key = Key then
                        R.Append (Tail_Of (Row));
                     end if;
               end case;
            end;
         end loop;
         return R;
      end Spec_Lit;

      --  Rows whose first column is irrefutable.
      function Default_Mx
        (Rows : Mx_Vectors.Vector) return Mx_Vectors.Vector
      is
         R : Mx_Vectors.Vector;
      begin
         for Row of Rows loop
            if Pool (Row (1)).Kind = Wild_A then
               R.Append (Tail_Of (Row));
            end if;
         end loop;
         return R;
      end Default_Mx;

      function Useful
        (Rows : Mx_Vectors.Vector; Q : Nat_Vectors.Vector)
         return Boolean
      is
      begin
         if Budget = 0 then
            Overrun := True;
            return False;
         end if;
         Budget := Budget - 1;

         if Q.Is_Empty then
            return Rows.Is_Empty;
         end if;

         declare
            H : constant APat_Node := Pool (Q (1));
         begin
            case H.Kind is
               when Con_A =>
                  return Useful
                    (Spec_Con (Rows, H.Con,
                               Natural (H.Args.Length)),
                     Prepend (H.Args, Tail_Of (Q)));
               when Lit_A =>
                  return Useful (Spec_Lit (Rows, H.Key),
                                 Tail_Of (Q));
               when Wild_A =>
                  --  Collect the constructor signature of column 1.
                  declare
                     TC       : Core.TyCon_Id := Core.No_TyCon;
                     Mixed    : Boolean := False;
                     Has_Lit  : Boolean := False;
                     Seen     : Nat_Vectors.Vector;
                  begin
                     for Row of Rows loop
                        declare
                           RH : constant APat_Node :=
                             Pool (Row (1));
                        begin
                           case RH.Kind is
                              when Con_A =>
                                 declare
                                    RT : constant Core.TyCon_Id :=
                                      M.Info (RH.Con).TyCon;
                                    New_C : Boolean := True;
                                 begin
                                    if TC = Core.No_TyCon then
                                       TC := RT;
                                    elsif TC /= RT then
                                       Mixed := True;
                                    end if;
                                    for S of Seen loop
                                       if Core.Real_DataCon_Id (S) =
                                         RH.Con
                                       then
                                          New_C := False;
                                       end if;
                                    end loop;
                                    if New_C then
                                       Seen.Append
                                         (Positive (RH.Con));
                                    end if;
                                 end;
                              when Lit_A =>
                                 Has_Lit := True;
                              when Wild_A =>
                                 null;
                           end case;
                        end;
                     end loop;

                     if TC /= Core.No_TyCon
                       and then not Mixed
                       and then not Has_Lit
                       and then Natural (Seen.Length) =
                                Natural
                                  (M.Info
                                     (Core.Real_TyCon_Id (TC))
                                   .Cons.Length)
                     then
                        --  Complete signature: try every con.
                        for DC of
                          M.Info (Core.Real_TyCon_Id (TC)).Cons
                        loop
                           declare
                              RDC : constant Core.Real_DataCon_Id :=
                                Core.Real_DataCon_Id (DC);
                              Ar : constant Natural :=
                                M.Info (RDC).Arity;
                           begin
                              if Useful
                                (Spec_Con (Rows, RDC, Ar),
                                 Wilds (Ar, Tail_Of (Q)))
                              then
                                 return True;
                              end if;
                           end;
                        end loop;
                        return False;
                     end if;
                     return Useful (Default_Mx (Rows), Tail_Of (Q));
                  end;
            end case;
         end;
      end Useful;

      Arity : Natural := 0;

      Norm_Rows : Mx_Vectors.Vector;   --  one per input row, in order

   begin
      if Rows.Is_Empty then
         return;
      end if;
      Arity := Natural (Rows (1).Pats.Length);
      if Arity = 0 then
         return;
      end if;
      for R of Rows loop
         if Natural (R.Pats.Length) /= Arity then
            return;   --  malformed; renamer already complained
         end if;
      end loop;

      for R of Rows loop
         Norm_Rows.Append (Norm_Vec (R.Pats));
      end loop;

      --  Redundancy: row I is redundant when it is not useful after
      --  the preceding TOTAL rows (guarded predecessors might fall
      --  through, so they cannot shadow anything).
      for I in 2 .. Rows.Last_Index loop
         declare
            Prev : Mx_Vectors.Vector;
         begin
            for J in 1 .. I - 1 loop
               if Rows (J).Total then
                  Prev.Append (Norm_Rows (J));
               end if;
            end loop;
            if not Prev.Is_Empty then
               Budget := 20_000;
               Overrun := False;
               if not Useful (Prev, Norm_Rows (I))
                 and then not Overrun
               then
                  Bag.Add (Diagnostics.Warning,
                           Diagnostics.Match_Warning,
                           Rows (I).Span,
                           "redundant pattern in " & What);
               end if;
            end if;
         end;
      end loop;

      --  Exhaustiveness: a wildcard row still useful after all the
      --  total rows means some value falls through every clause.
      declare
         Totals : Mx_Vectors.Vector;
      begin
         for I in 1 .. Rows.Last_Index loop
            if Rows (I).Total then
               Totals.Append (Norm_Rows (I));
            end if;
         end loop;
         Budget := 20_000;
         Overrun := False;
         if Useful (Totals, Wilds (Arity, Nat_Vectors.Empty_Vector))
           and then not Overrun
         then
            Bag.Add (Diagnostics.Warning, Diagnostics.Match_Warning,
                     Span, "non-exhaustive patterns in " & What);
         end if;
      end;
   end Check_Match;

end AHC.Exhaustive;
