with Ada.Containers.Hashed_Maps;
with Ada.Containers.Vectors;

package body AHC.Fixity is

   use AHC.Syntax;
   use type Names.Name_Id;

   function Chain_Free (Arena : Syntax.Module_Arena) return Boolean
   is ((for all N of Arena.Exprs => N.Kind /= Op_Chain_E)
       and then (for all N of Arena.Pats => N.Kind /= Con_Chain_P));

   type Fixity_Info is record
      Assoc : Assoc_Kind := Assoc_Left;
      Prec  : Natural := 9;
   end record;

   function Name_Hash (N : Names.Name_Id) return Ada.Containers.Hash_Type
   is (Ada.Containers.Hash_Type (N));

   package Fixity_Maps is new Ada.Containers.Hashed_Maps
     (Key_Type        => Names.Name_Id,
      Element_Type    => Fixity_Info,
      Hash            => Name_Hash,
      Equivalent_Keys => "=");

   package Scope_Vectors is new Ada.Containers.Vectors
     (Positive, Fixity_Maps.Map, Fixity_Maps."=");

   procedure Resolve_Module
     (Arena : in out Syntax.Module_Arena;
      Table : in out Names.Name_Table;
      Bag   : in out Diagnostics.Diagnostic_Bag)
   is
      Scopes : Scope_Vectors.Vector;

      Default_Fixity : constant Fixity_Info := (Assoc_Left, 9);
      Minus_Prec     : constant := 6;

      function Fixity_Of (Op : QName) return Fixity_Info is
      begin
         for I in reverse 1 .. Scopes.Last_Index loop
            declare
               C : constant Fixity_Maps.Cursor :=
                 Scopes (I).Find (Op.Name);
            begin
               if Fixity_Maps.Has_Element (C) then
                  return Fixity_Maps.Element (C);
               end if;
            end;
         end loop;
         return Default_Fixity;
      end Fixity_Of;

      --  Prelude fixities (Report 4.4.2 table) as the base scope.
      procedure Push_Prelude_Scope is
         M : Fixity_Maps.Map;
         procedure Def (S : String; A : Assoc_Kind; P : Natural) is
         begin
            M.Include (Names.Name_Id (Table.Intern (S)), (A, P));
         end Def;
      begin
         Def (".", Assoc_Right, 9);
         Def ("!!", Assoc_Left, 9);
         Def ("^", Assoc_Right, 8);
         Def ("^^", Assoc_Right, 8);
         Def ("**", Assoc_Right, 8);
         Def ("*", Assoc_Left, 7);
         Def ("/", Assoc_Left, 7);
         Def ("quot", Assoc_Left, 7);
         Def ("rem", Assoc_Left, 7);
         Def ("div", Assoc_Left, 7);
         Def ("mod", Assoc_Left, 7);
         Def ("+", Assoc_Left, 6);
         Def ("-", Assoc_Left, 6);
         Def (":", Assoc_Right, 5);
         Def ("++", Assoc_Right, 5);
         Def ("==", Assoc_None, 4);
         Def ("/=", Assoc_None, 4);
         Def ("<", Assoc_None, 4);
         Def ("<=", Assoc_None, 4);
         Def (">", Assoc_None, 4);
         Def (">=", Assoc_None, 4);
         Def ("elem", Assoc_None, 4);
         Def ("notElem", Assoc_None, 4);
         Def ("&&", Assoc_Right, 3);
         Def ("||", Assoc_Right, 2);
         Def (">>", Assoc_Left, 1);
         Def (">>=", Assoc_Left, 1);
         Def ("=<<", Assoc_Right, 1);
         Def ("$", Assoc_Right, 0);
         Def ("$!", Assoc_Right, 0);
         Def ("seq", Assoc_Right, 0);
         Scopes.Append (M);
      end Push_Prelude_Scope;

      procedure Push_Scope (Decls : Decl_Id_Vectors.Vector) is
         M : Fixity_Maps.Map;
      begin
         for D of Decls loop
            declare
               N : constant Decl_Node := Arena.Node (D);
            begin
               if N.Kind = Fixity_D then
                  for Op of N.Ops loop
                     M.Include (Op.Name, (N.Assoc, N.Prec));
                  end loop;
               end if;
            end;
         end loop;
         Scopes.Append (M);
      end Push_Scope;

      procedure Pop_Scope is
      begin
         Scopes.Delete_Last;
      end Pop_Scope;

      ------------------------------------------------------------------
      --  Walkers
      ------------------------------------------------------------------

      procedure Resolve_Expr (Id : Real_Expr_Id);
      procedure Resolve_Pat (Id : Real_Pat_Id);
      procedure Resolve_Group (Decls : Decl_Id_Vectors.Vector);

      procedure Resolve_Rhs (R : Rhs) is
      begin
         if R.Guarded then
            for G of R.Guards loop
               Resolve_Expr (G.Guard);
               Resolve_Expr (G.G_Body);
            end loop;
         else
            Resolve_Expr (R.Plain);
         end if;
      end Resolve_Rhs;

      --  Build the application node for 'Lhs op Rhs'.
      function Combine
        (Op : Op_Occ; Lhs, Rhs_E : Real_Expr_Id) return Real_Expr_Id
      is
         Op_Ref : Real_Expr_Id;
      begin
         if Op.Is_Con then
            Op_Ref := Arena.Add
              (Expr_Node'(Kind => Con_E, Span => Op.Span, Name => Op.Op));
         else
            Op_Ref := Arena.Add
              (Expr_Node'(Kind => Var_E, Span => Op.Span, Name => Op.Op));
         end if;
         return Arena.Add
           (Expr_Node'(Kind => App_E, Span => Op.Span,
                       Fun => Arena.Add
                         (Expr_Node'(Kind => App_E, Span => Op.Span,
                                     Fun => Op_Ref, Arg => Lhs)),
                       Arg => Rhs_E));
      end Combine;

      --  Report 10.6 resolution by precedence climbing over the flat
      --  chain. Consumed counts operands taken; op K follows operand K.
      procedure Resolve_Chain (Id : Real_Expr_Id) is
         N        : constant Expr_Node := Arena.Node (Id);
         Consumed : Natural := 0;
         Failed   : Boolean := False;

         function Operand_Negated return Boolean
         is (if Consumed = 0 then N.Neg_First
             else N.Operators (Consumed).Neg_After);

         --  Caller_Prec/Caller_Assoc describe the operator whose right
         --  operand we are parsing (-1 at top level): an operator of
         --  equal precedence is only legal when both are right-
         --  associative ("a <+> b * c" with equal precedence is
         --  ambiguous even though climbing would consume it).
         function Parse
           (Min_Prec     : Natural;
            Caller_Prec  : Integer := -1;
            Caller_Assoc : Assoc_Kind := Assoc_Left) return Real_Expr_Id
         is
            Left   : Real_Expr_Id;
            Last_P : Integer := -1;
            Last_A : Assoc_Kind := Assoc_Left;
         begin
            --  Operand, possibly under prefix minus.
            if Operand_Negated then
               if Min_Prec > Minus_Prec then
                  Bag.Add
                    (Diagnostics.Error, Diagnostics.Fixity_Error, N.Span,
                     "cannot mix prefix '-' with an operator of higher"
                     & " precedence");
                  Failed := True;
               end if;
               Consumed := Consumed + 1;
               declare
                  Seg : Real_Expr_Id := N.Operands (Consumed);
               begin
                  --  The negated segment binds everything above 6.
                  while Consumed <= N.Operators.Last_Index
                    and then Fixity_Of
                               (N.Operators (Consumed).Op).Prec
                             > Minus_Prec
                  loop
                     declare
                        Op : constant Op_Occ := N.Operators (Consumed);
                        F  : constant Fixity_Info := Fixity_Of (Op.Op);
                     begin
                        Seg := Combine
                          (Op, Seg,
                           Parse ((if F.Assoc = Assoc_Right
                                   then F.Prec else F.Prec + 1),
                                  Integer (F.Prec), F.Assoc));
                     end;
                  end loop;
                  Left := Arena.Add
                    (Expr_Node'(Kind => Neg_E, Span => N.Span,
                                Negated => Seg));
               end;
            else
               Consumed := Consumed + 1;
               Left := N.Operands (Consumed);
            end if;

            while Consumed <= N.Operators.Last_Index loop
               declare
                  Op : constant Op_Occ := N.Operators (Consumed);
                  F  : constant Fixity_Info := Fixity_Of (Op.Op);
               begin
                  exit when F.Prec < Min_Prec;
                  if (Integer (F.Prec) = Last_P
                      and then not (F.Assoc = Assoc_Left
                                    and then Last_A = Assoc_Left))
                    or else
                     (Integer (F.Prec) = Caller_Prec
                      and then not (F.Assoc = Assoc_Right
                                    and then Caller_Assoc = Assoc_Right))
                  then
                     Bag.Add
                       (Diagnostics.Error, Diagnostics.Fixity_Error,
                        Op.Span,
                        "ambiguous use of operators with equal"
                        & " precedence; add parentheses");
                     Failed := True;
                  end if;
                  Left := Combine
                    (Op, Left,
                     Parse ((if F.Assoc = Assoc_Right
                             then F.Prec else F.Prec + 1),
                            Integer (F.Prec), F.Assoc));
                  Last_P := Integer (F.Prec);
                  Last_A := F.Assoc;
               end;
            end loop;
            return Left;
         end Parse;

         Top : Real_Expr_Id;
      begin
         --  Children first (they may themselves contain chains).
         for Operand of N.Operands loop
            Resolve_Expr (Operand);
         end loop;

         Top := Parse (0);
         pragma Unreferenced (Failed);
         Arena.Exprs.Replace_Element (Id, Arena.Node (Top));
      end Resolve_Chain;

      procedure Resolve_Pat_Chain (Id : Real_Pat_Id) is
         N        : constant Pat_Node := Arena.Node (Id);
         Consumed : Natural := 0;

         function Combine_P
           (Op : Op_Occ; Lhs, Rhs_P : Real_Pat_Id) return Real_Pat_Id
         is
            Args : Pat_Id_Vectors.Vector;
         begin
            Args.Append (Lhs);
            Args.Append (Rhs_P);
            return Arena.Add
              (Pat_Node'(Kind => Con_P, Span => Op.Span,
                         Con => Op.Op, Con_Args => Args));
         end Combine_P;

         function Parse
           (Min_Prec     : Natural;
            Caller_Prec  : Integer := -1;
            Caller_Assoc : Assoc_Kind := Assoc_Left) return Real_Pat_Id
         is
            Left   : Real_Pat_Id;
            Last_P : Integer := -1;
            Last_A : Assoc_Kind := Assoc_Left;
         begin
            Consumed := Consumed + 1;
            Left := N.Operands (Consumed);
            while Consumed <= N.Operators.Last_Index loop
               declare
                  Op : constant Op_Occ := N.Operators (Consumed);
                  F  : constant Fixity_Info := Fixity_Of (Op.Op);
               begin
                  exit when F.Prec < Min_Prec;
                  if (Integer (F.Prec) = Last_P
                      and then not (F.Assoc = Assoc_Left
                                    and then Last_A = Assoc_Left))
                    or else
                     (Integer (F.Prec) = Caller_Prec
                      and then not (F.Assoc = Assoc_Right
                                    and then Caller_Assoc = Assoc_Right))
                  then
                     Bag.Add
                       (Diagnostics.Error, Diagnostics.Fixity_Error,
                        Op.Span,
                        "ambiguous use of pattern operators with equal"
                        & " precedence; add parentheses");
                  end if;
                  Left := Combine_P
                    (Op, Left,
                     Parse ((if F.Assoc = Assoc_Right
                             then F.Prec else F.Prec + 1),
                            Integer (F.Prec), F.Assoc));
                  Last_P := Integer (F.Prec);
                  Last_A := F.Assoc;
               end;
            end loop;
            return Left;
         end Parse;

         Top : Real_Pat_Id;
      begin
         for Operand of N.Operands loop
            Resolve_Pat (Operand);
         end loop;
         Top := Parse (0);
         Arena.Pats.Replace_Element (Id, Arena.Node (Top));
      end Resolve_Pat_Chain;

      procedure Resolve_Pat (Id : Real_Pat_Id) is
         N : constant Pat_Node := Arena.Node (Id);
      begin
         case N.Kind is
            when Con_Chain_P =>
               Resolve_Pat_Chain (Id);
            when Con_P =>
               for P of N.Con_Args loop
                  Resolve_Pat (P);
               end loop;
            when Tuple_P | List_P =>
               for P of N.Items loop
                  Resolve_Pat (P);
               end loop;
            when As_P =>
               Resolve_Pat (N.As_Pat);
            when Lazy_P =>
               Resolve_Pat (N.Lazy_Pat);
            when Rec_P =>
               for F of N.Rec_Fields loop
                  Resolve_Pat (F.Value);
               end loop;
            when Sig_P =>
               Resolve_Pat (N.Sig_Pat);
            when others =>
               null;
         end case;
      end Resolve_Pat;

      procedure Resolve_Alt (Id : Real_Alt_Id) is
         N : constant Alt_Node := Arena.Node (Id);
      begin
         Resolve_Pat (N.Pat);
         Push_Scope (N.Where_Ds);
         Resolve_Rhs (N.Alt_Rhs);
         Resolve_Group (N.Where_Ds);
         Pop_Scope;
      end Resolve_Alt;

      procedure Resolve_Stmt (Id : Real_Stmt_Id) is
         N : constant Stmt_Node := Arena.Node (Id);
      begin
         case N.Kind is
            when Bind_S =>
               Resolve_Pat (N.Bind_Pat);
               Resolve_Expr (N.Bind_Expr);
            when Let_S =>
               --  A let scope covers the following statements too, but
               --  chains only need the fixities, which are block-local.
               Push_Scope (N.Let_Binds);
               Resolve_Group (N.Let_Binds);
               Pop_Scope;
            when Syntax.Expr_S =>
               Resolve_Expr (N.Expr);
         end case;
      end Resolve_Stmt;

      procedure Resolve_Expr (Id : Real_Expr_Id) is
         N : constant Expr_Node := Arena.Node (Id);
      begin
         case N.Kind is
            when Op_Chain_E =>
               Resolve_Chain (Id);
            when App_E =>
               Resolve_Expr (N.Fun);
               Resolve_Expr (N.Arg);
            when Neg_E =>
               Resolve_Expr (N.Negated);
            when Lambda_E =>
               for P of N.L_Pats loop
                  Resolve_Pat (P);
               end loop;
               Resolve_Expr (N.L_Body);
            when Let_E =>
               Push_Scope (N.Binds);
               Resolve_Group (N.Binds);
               Resolve_Expr (N.Let_Body);
               Pop_Scope;
            when If_E =>
               Resolve_Expr (N.Cond);
               Resolve_Expr (N.Then_E);
               Resolve_Expr (N.Else_E);
            when Case_E =>
               Resolve_Expr (N.Scrutinee);
               for A of N.Alts loop
                  Resolve_Alt (A);
               end loop;
            when Do_E =>
               for S of N.Stmts loop
                  Resolve_Stmt (S);
               end loop;
            when Tuple_E | List_E =>
               for E of N.Items loop
                  Resolve_Expr (E);
               end loop;
            when Arith_Seq_E =>
               Resolve_Expr (N.Seq_From);
               if N.Seq_Then /= No_Expr then
                  Resolve_Expr (N.Seq_Then);
               end if;
               if N.Seq_To /= No_Expr then
                  Resolve_Expr (N.Seq_To);
               end if;
            when List_Comp_E =>
               for S of N.Comp_Quals loop
                  Resolve_Stmt (S);
               end loop;
               Resolve_Expr (N.Comp_Expr);
            when Left_Section_E | Right_Section_E =>
               Resolve_Expr (N.Sec_Expr);
            when Sig_E =>
               Resolve_Expr (N.Sig_Expr);
            when Rec_Con_E | Rec_Update_E =>
               Resolve_Expr (N.Rec_Base);
               for F of N.Rec_Fields loop
                  Resolve_Expr (F.Value);
               end loop;
            when others =>
               null;
         end case;
      end Resolve_Expr;

      procedure Resolve_Decl (Id : Real_Decl_Id) is
         N : constant Decl_Node := Arena.Node (Id);
      begin
         case N.Kind is
            when Fun_D =>
               for P of N.Fun_Pats loop
                  Resolve_Pat (P);
               end loop;
               Push_Scope (N.Fun_Where);
               Resolve_Rhs (N.Fun_Rhs);
               Resolve_Group (N.Fun_Where);
               Pop_Scope;
            when Pat_D =>
               Resolve_Pat (N.Pat);
               Push_Scope (N.Pat_Where);
               Resolve_Rhs (N.Pat_Rhs);
               Resolve_Group (N.Pat_Where);
               Pop_Scope;
            when Class_D =>
               Push_Scope (N.C_Decls);
               Resolve_Group (N.C_Decls);
               Pop_Scope;
            when Instance_D =>
               Push_Scope (N.I_Decls);
               Resolve_Group (N.I_Decls);
               Pop_Scope;
            when others =>
               null;
         end case;
      end Resolve_Decl;

      procedure Resolve_Group (Decls : Decl_Id_Vectors.Vector) is
      begin
         for D of Decls loop
            Resolve_Decl (D);
         end loop;
      end Resolve_Group;

   begin
      Push_Prelude_Scope;
      Push_Scope (Arena.Top_Decls);
      Resolve_Group (Arena.Top_Decls);

      --  Predicate refinements embed expressions inside types, which
      --  the declaration walk above never reaches; resolve their
      --  operator chains at top-level fixity scope.
      for T in 1 .. Arena.Last_Type loop
         declare
            N : constant Type_Node := Arena.Node (Real_Type_Id (T));
         begin
            if N.Kind = Pred_T then
               Resolve_Expr (N.P_Expr);
            end if;
         end;
      end loop;

      Pop_Scope;
      Pop_Scope;
   end Resolve_Module;

end AHC.Fixity;
