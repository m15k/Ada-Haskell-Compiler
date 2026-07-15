package body AHC.Core is

   use type Ada.Containers.Count_Type;

   ---------------------------------------------------------------------
   --  Well_Formed
   ---------------------------------------------------------------------

   function Well_Formed (M : Core_Module; N : Kind_Node) return Boolean is
   begin
      case N.Kind is
         when Star_K | KMeta_K =>
            return True;
         when KFun_K =>
            return N.KFrom <= M.Last_Kind and then N.KTo <= M.Last_Kind;
      end case;
   end Well_Formed;

   function Well_Formed (M : Core_Module; N : Type_Node) return Boolean is
   begin
      case N.Kind is
         when TVar_T =>
            return N.Tv <= M.Last_TyVar;
         when TMeta_T =>
            return True;   --  meta cells live in the typechecker state
         when TCon_T =>
            --  Design rule 1: Phase 2 never constructs refinements.
            return N.Con <= M.Last_TyCon
              and then N.Refine = No_Refinement;
         when TApp_T =>
            return N.T_Fun <= M.Last_Type and then N.T_Arg <= M.Last_Type;
         when TFun_T =>
            return N.From <= M.Last_Type and then N.To <= M.Last_Type;
      end case;
   end Well_Formed;

   function Well_Formed (M : Core_Module; S : Scheme) return Boolean
   is (S.S_Body in Real_Type_Id
       and then S.S_Body <= M.Last_Type
       and then (for all Tv of S.Tvs => Tv <= M.Last_TyVar)
       and then (for all C of S.Context =>
                   C.Class <= M.Last_Class
                   and then C.Arg <= M.Last_Type));

   function Well_Formed (M : Core_Module; N : Expr_Node) return Boolean is
   begin
      case N.Kind is
         when Var_C =>
            return N.V <= M.Last_Var;
         when Lit_C =>
            return True;
         when Con_C =>
            return N.Con <= M.Last_DataCon;
         when App_C =>
            return N.Fun <= M.Last_Expr and then N.Arg <= M.Last_Expr;
         when Lam_C =>
            return N.Binder <= M.Last_Var
              and then N.Lam_Body <= M.Last_Expr;
         when Let_C =>
            --  PRD 4.2 carried into Core: a Let binds something.
            return N.Binds.Length >= 1
              and then N.Let_Body <= M.Last_Expr
              and then (for all B of N.Binds =>
                          B.Binder <= M.Last_Var
                          and then B.Rhs <= M.Last_Expr);
         when Case_C =>
            if N.Alts.Length < 1
              or else N.Scrutinee > M.Last_Expr
            then
               return False;
            end if;
            --  Alt ids in range; at most one Default_Alt, and last.
            for I in 1 .. N.Alts.Last_Index loop
               if N.Alts (I) > M.Last_Alt then
                  return False;
               end if;
               if M.Alts (N.Alts (I)).Kind = Default_Alt
                 and then I /= N.Alts.Last_Index
               then
                  return False;
               end if;
            end loop;
            return True;
      end case;
   end Well_Formed;

   function Well_Formed (M : Core_Module; N : Alt_Node) return Boolean is
   begin
      if N.Alt_Body > M.Last_Expr then
         return False;
      end if;
      case N.Kind is
         when Con_Alt =>
            --  The PRD arity promise: alternative binders match the
            --  constructor's declared arity exactly.
            return N.A_Con <= M.Last_DataCon
              and then Natural (N.Binders.Length) =
                         M.DataCons (N.A_Con).Arity
              and then (for all B of N.Binders => B <= M.Last_Var);
         when Lit_Alt | Default_Alt =>
            return True;
      end case;
   end Well_Formed;

   ---------------------------------------------------------------------
   --  Add / Mint / Node / Info
   ---------------------------------------------------------------------

   function Add (M : in out Core_Module; N : Kind_Node) return Real_Kind_Id
   is
   begin
      M.Kinds.Append (N);
      return M.Kinds.Last_Index;
   end Add;

   function Add (M : in out Core_Module; N : Type_Node) return Real_Type_Id
   is
   begin
      M.Types.Append (N);
      return M.Types.Last_Index;
   end Add;

   function Add (M : in out Core_Module; S : Scheme) return Real_Scheme_Id
   is
   begin
      M.Schemes.Append (S);
      return M.Schemes.Last_Index;
   end Add;

   function Add (M : in out Core_Module; N : Expr_Node) return Real_Expr_Id
   is
   begin
      M.Exprs.Append (N);
      return M.Exprs.Last_Index;
   end Add;

   function Add (M : in out Core_Module; N : Alt_Node) return Real_Alt_Id
   is
   begin
      M.Alts.Append (N);
      return M.Alts.Last_Index;
   end Add;

   function Mint_Var
     (M : in out Core_Module; Info : Var_Info) return Real_Var_Id is
   begin
      M.Vars.Append (Info);
      return M.Vars.Last_Index;
   end Mint_Var;

   function Mint_TyVar
     (M : in out Core_Module; Info : TyVar_Info) return Real_TyVar_Id is
   begin
      M.TyVars.Append (Info);
      return M.TyVars.Last_Index;
   end Mint_TyVar;

   function Mint_TyCon
     (M : in out Core_Module; Info : TyCon_Info) return Real_TyCon_Id is
   begin
      M.TyCons.Append (Info);
      return M.TyCons.Last_Index;
   end Mint_TyCon;

   function Mint_DataCon
     (M : in out Core_Module; Info : DataCon_Info) return Real_DataCon_Id
   is
   begin
      M.DataCons.Append (Info);
      M.TyCons (Info.TyCon).Cons.Append (M.DataCons.Last_Index);
      return M.DataCons.Last_Index;
   end Mint_DataCon;

   function Mint_Class
     (M : in out Core_Module; Info : Class_Info) return Real_Class_Id is
   begin
      M.Classes.Append (Info);
      return M.Classes.Last_Index;
   end Mint_Class;

   function Mint_Instance
     (M : in out Core_Module; Info : Instance_Info)
      return Real_Instance_Id is
   begin
      M.Instances.Append (Info);
      M.Classes (Info.Of_Class).Instances.Append (M.Instances.Last_Index);
      return M.Instances.Last_Index;
   end Mint_Instance;

   function Node (M : Core_Module; Id : Real_Kind_Id) return Kind_Node
   is (M.Kinds (Id));
   function Node (M : Core_Module; Id : Real_Type_Id) return Type_Node
   is (M.Types (Id));
   function Node (M : Core_Module; Id : Real_Scheme_Id) return Scheme
   is (M.Schemes (Id));
   function Node (M : Core_Module; Id : Real_Expr_Id) return Expr_Node
   is (M.Exprs (Id));
   function Node (M : Core_Module; Id : Real_Alt_Id) return Alt_Node
   is (M.Alts (Id));

   function Info (M : Core_Module; Id : Real_Var_Id) return Var_Info
   is (M.Vars (Id));
   function Info (M : Core_Module; Id : Real_TyVar_Id) return TyVar_Info
   is (M.TyVars (Id));
   function Info (M : Core_Module; Id : Real_TyCon_Id) return TyCon_Info
   is (M.TyCons (Id));
   function Info (M : Core_Module; Id : Real_DataCon_Id) return DataCon_Info
   is (M.DataCons (Id));
   function Info (M : Core_Module; Id : Real_Class_Id) return Class_Info
   is (M.Classes (Id));
   function Info (M : Core_Module; Id : Real_Instance_Id)
     return Instance_Info
   is (M.Instances (Id));

   function Star (M : in out Core_Module) return Real_Kind_Id is
   begin
      if M.Star_Cache = No_Kind then
         M.Star_Cache := M.Add (Kind_Node'(Kind => Star_K));
      end if;
      return M.Star_Cache;
   end Star;

end AHC.Core;
