with Ada.Strings.Unbounded;

package body AHC.Core.Printer is

   function Img (N : Natural) return String is
      S : constant String := N'Image;
   begin
      return S (2 .. S'Last);
   end Img;

   function NM
     (Table : Names.Name_Table; N : Names.Name_Id) return String
   is (if N = Names.No_Name then "?" else Table.Text (N));

   function Var_Image
     (M : Core_Module; Table : Names.Name_Table; V : Real_Var_Id)
      return String
   is (NM (Table, M.Info (V).Name) & "_" & Img (Natural (V)));

   function Lit_Image
     (Table : Names.Name_Table; L : Literal) return String
   is (case L.Kind is
         when L_Int    => "(int """ & NM (Table, L.Text) & """)",
         when L_Float  => "(float """ & NM (Table, L.Text) & """)",
         when L_Char   => "(char " & Img (L.Code) & ")",
         when L_String =>
           "(str """
           & (if L.Text = Names.No_Name then "" else Table.Text (L.Text))
           & """)");

   ---------------------------------------------------------------------
   --  Types and schemes
   ---------------------------------------------------------------------

   function Type_Image
     (M : Core_Module; Table : Names.Name_Table; T : Real_Type_Id)
      return String
   is
      N : constant Type_Node := M.Node (T);
   begin
      case N.Kind is
         when TVar_T =>
            return "(tv " & NM (Table, M.Info (N.Tv).Name)
              & "_" & Img (Natural (N.Tv)) & ")";
         when TMeta_T =>
            return "(meta ?" & Img (Natural (N.Meta)) & ")";
         when TCon_T =>
            return "(tcon " & NM (Table, M.Info (N.Con).Name) & ")";
         when TApp_T =>
            return "(tap " & Type_Image (M, Table, N.T_Fun) & " "
              & Type_Image (M, Table, N.T_Arg) & ")";
         when TFun_T =>
            return "(-> " & Type_Image (M, Table, N.From) & " "
              & Type_Image (M, Table, N.To) & ")";
      end case;
   end Type_Image;

   function Scheme_Image
     (M : Core_Module; Table : Names.Name_Table; S : Real_Scheme_Id)
      return String
   is
      use Ada.Strings.Unbounded;
      Sch : constant Scheme := M.Node (S);
      R   : Unbounded_String;
   begin
      Append (R, "(forall (");
      for I in 1 .. Sch.Tvs.Last_Index loop
         if I > 1 then
            Append (R, " ");
         end if;
         Append (R, NM (Table, M.Info (Sch.Tvs (I)).Name)
                    & "_" & Img (Natural (Sch.Tvs (I))));
      end loop;
      Append (R, ")");
      if not Sch.Context.Is_Empty then
         Append (R, " (ctx");
         for C of Sch.Context loop
            Append (R, " (" & NM (Table, M.Info (C.Class).Name) & " "
                       & Type_Image (M, Table, C.Arg) & ")");
         end loop;
         Append (R, ")");
      end if;
      Append (R, " " & Type_Image (M, Table, Sch.S_Body) & ")");
      return To_String (R);
   end Scheme_Image;

   ---------------------------------------------------------------------
   --  Pretty types (ahc check output)
   ---------------------------------------------------------------------

   function Pretty_Scheme
     (M : Core_Module; Table : Names.Name_Table; S : Real_Scheme_Id)
      return String
   is
      use Ada.Strings.Unbounded;
      Sch : constant Scheme := M.Node (S);

      --  Rename tyvars a, b, .., z, t1, t2, .. by first occurrence.
      Seen  : TyVar_Id_Vectors.Vector;

      function TV_Name (Tv : Real_TyVar_Id) return String is
         Idx : Natural := 0;
      begin
         for I in 1 .. Seen.Last_Index loop
            if Core."=" (Seen (I), Tv) then
               Idx := I;
            end if;
         end loop;
         if Idx = 0 then
            Seen.Append (Tv);
            Idx := Seen.Last_Index;
         end if;
         if Idx <= 26 then
            return [Character'Val (Character'Pos ('a') + Idx - 1)];
         end if;
         return "t" & Img (Idx);
      end TV_Name;

      --  Precedence: 0 = top (fun), 1 = app arg, 2 = atomic.
      function Ty (T : Real_Type_Id; Prec : Natural) return String is
         N : constant Type_Node := M.Node (T);
      begin
         case N.Kind is
            when TVar_T =>
               return TV_Name (N.Tv);
            when TMeta_T =>
               return "?" & Img (Natural (N.Meta));
            when TCon_T =>
               return NM (Table, M.Info (N.Con).Name);
            when TFun_T =>
               declare
                  Inner : constant String :=
                    Ty (N.From, 1) & " -> " & Ty (N.To, 0);
               begin
                  return (if Prec > 0 then "(" & Inner & ")"
                          else Inner);
               end;
            when TApp_T =>
               --  Detect list and tuple spines for standard notation.
               declare
                  Head : Real_Type_Id := T;
                  Args : Type_Id_Vectors.Vector;
               begin
                  while M.Node (Head).Kind = TApp_T loop
                     Args.Prepend (M.Node (Head).T_Arg);
                     Head := M.Node (Head).T_Fun;
                  end loop;
                  if M.Node (Head).Kind = TCon_T then
                     declare
                        Name : constant String :=
                          NM (Table, M.Info (M.Node (Head).Con).Name);
                     begin
                        if Name = "[]"
                          and then Natural (Args.Length) = 1
                        then
                           return "[" & Ty (Args (1), 0) & "]";
                        end if;
                        if Name'Length >= 3
                          and then Name (Name'First) = '('
                          and then Name (Name'First + 1) = ','
                          and then Natural (Args.Length) =
                                     Name'Length - 1
                        then
                           declare
                              R : Unbounded_String;
                           begin
                              Append (R, "(");
                              for I in 1 .. Args.Last_Index loop
                                 if I > 1 then
                                    Append (R, ", ");
                                 end if;
                                 Append (R, Ty (Args (I), 0));
                              end loop;
                              Append (R, ")");
                              return To_String (R);
                           end;
                        end if;
                     end;
                  end if;
                  declare
                     R : Unbounded_String;
                  begin
                     Append (R, Ty (Head, 2));
                     for A of Args loop
                        Append (R, " " & Ty (A, 2));
                     end loop;
                     if Prec > 1 then
                        return "(" & To_String (R) & ")";
                     end if;
                     return To_String (R);
                  end;
               end;
         end case;
      end Ty;

      Result : Unbounded_String;
   begin
      --  Walk the body first so tyvar letters follow their appearance
      --  in the printed type, then prepend the (sorted-as-written)
      --  context.
      declare
         Body_S : constant String := Ty (Sch.S_Body, 0);
      begin
         if not Sch.Context.Is_Empty then
            declare
               Ctx : Unbounded_String;
               First : Boolean := True;
            begin
               for C of Sch.Context loop
                  if not First then
                     Append (Ctx, ", ");
                  end if;
                  First := False;
                  Append (Ctx, NM (Table, M.Info (C.Class).Name) & " "
                             & Ty (C.Arg, 2));
               end loop;
               if Natural (Sch.Context.Length) = 1 then
                  Append (Result, To_String (Ctx) & " => ");
               else
                  Append (Result,
                          "(" & To_String (Ctx) & ") => ");
               end if;
            end;
         end if;
         Append (Result, Body_S);
      end;
      return To_String (Result);
   end Pretty_Scheme;

   ---------------------------------------------------------------------
   --  Expressions
   ---------------------------------------------------------------------

   function Dump
     (M : Core_Module; Table : Names.Name_Table) return String
   is
      use Ada.Strings.Unbounded;

      Out_Buf : Unbounded_String;

      function Expr_S (Id : Real_Expr_Id) return String;

      function Alt_S (Id : Real_Alt_Id) return String is
         N : constant Alt_Node := M.Node (Id);
         R : Unbounded_String;
      begin
         case N.Kind is
            when Con_Alt =>
               Append (R, "(alt (con "
                          & NM (Table, M.Info (N.A_Con).Name));
               for B of N.Binders loop
                  Append (R, " " & Var_Image (M, Table, B));
               end loop;
               Append (R, ")");
            when Lit_Alt =>
               Append (R, "(alt " & Lit_Image (Table, N.A_Lit));
            when Default_Alt =>
               Append (R, "(alt _");
         end case;
         Append (R, " " & Expr_S (N.Alt_Body) & ")");
         return To_String (R);
      end Alt_S;

      function Binds_S (Binds : Bind_Vectors.Vector) return String is
         R : Unbounded_String;
      begin
         for B of Binds loop
            Append (R, " (" & Var_Image (M, Table, B.Binder) & " "
                       & Expr_S (B.Rhs) & ")");
         end loop;
         return To_String (R);
      end Binds_S;

      function Expr_S (Id : Real_Expr_Id) return String is
         N : constant Expr_Node := M.Node (Id);
      begin
         case N.Kind is
            when Var_C =>
               return "(var " & Var_Image (M, Table, N.V) & ")";
            when Lit_C =>
               return Lit_Image (Table, N.Lit);
            when Con_C =>
               return "(con " & NM (Table, M.Info (N.Con).Name) & ")";
            when App_C =>
               return "(app " & Expr_S (N.Fun) & " "
                 & Expr_S (N.Arg) & ")";
            when Lam_C =>
               return "(lam " & Var_Image (M, Table, N.Binder) & " "
                 & Expr_S (N.Lam_Body) & ")";
            when Let_C =>
               declare
                  B : constant String := Binds_S (N.Binds);
               begin
                  return (if N.Is_Rec then "(letrec (" else "(let (")
                    & B (B'First + 1 .. B'Last)
                    & ") " & Expr_S (N.Let_Body) & ")";
               end;
            when Case_C =>
               declare
                  R : Unbounded_String;
               begin
                  Append (R, "(case " & Expr_S (N.Scrutinee));
                  for A of N.Alts loop
                     Append (R, " " & Alt_S (A));
                  end loop;
                  Append (R, ")");
                  return To_String (R);
               end;
         end case;
      end Expr_S;

   begin
      for Group of M.Top_Binds loop
         Append (Out_Buf, (if Group.Is_Rec then "(bindrec" else "(bind"));
         for B of Group.Binds loop
            declare
               V : constant Var_Info := M.Info (B.Binder);
            begin
               Append (Out_Buf, " (" & Var_Image (M, Table, B.Binder));
               if V.Var_Scheme /= No_Scheme then
                  Append (Out_Buf, " :: "
                             & Scheme_Image (M, Table, V.Var_Scheme));
               end if;
               Append (Out_Buf, " " & Expr_S (B.Rhs) & ")");
            end;
         end loop;
         Append (Out_Buf, ")" & ASCII.LF);
      end loop;
      return Ada.Strings.Unbounded.To_String (Out_Buf);
   end Dump;

end AHC.Core.Printer;
