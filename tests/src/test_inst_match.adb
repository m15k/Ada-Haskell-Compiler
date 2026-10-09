--  AHC.Inst_Match (M147): one-way matching of instance heads.
with AHC.Core;         use AHC.Core;
with AHC.Builtins;
with AHC.Inst_Match;   use AHC.Inst_Match;
with AHC.Names;

with Test_Harness; use Test_Harness;

package body Test_Inst_Match is

   Table : AHC.Names.Name_Table;

   procedure Run is
      M   : Core_Module;
      Env : AHC.Builtins.Global_Env;
      Star : constant Real_Kind_Id := M.Star;

      function Id (T : Real_Type_Id) return Real_Type_Id is (T);
      function Match is new Match_Head (Id);

      function TC (Name : String) return Real_TyCon_Id is
        (M.Mint_TyCon ((Name => Table.Intern (Name), Arity => 0,
                        TC_Kind => Star, others => <>)));

      List_TC  : constant Real_TyCon_Id := TC ("[]");
      Int_TC   : constant Real_TyCon_Id := TC ("Int");
      Char_TC  : constant Real_TyCon_Id := TC ("Char");
      Bool_TC  : constant Real_TyCon_Id := TC ("Bool");
      Either_TC : constant Real_TyCon_Id := TC ("Either");

      A_Tv : constant Real_TyVar_Id :=
        M.Mint_TyVar ((Name => Table.Intern ("a"),
                       Tv_Kind => Kind_Id (Star)));

      function Con (C : Real_TyCon_Id) return Real_Type_Id is
        (M.Add (Type_Node'(Kind => TCon_T, Con => C,
                           Refine => No_Refinement)));
      function App (F, X : Real_Type_Id) return Real_Type_Id is
        (M.Add (Type_Node'(Kind => TApp_T, T_Fun => F, T_Arg => X)));
      function Var return Real_Type_Id is
        (M.Add (Type_Node'(Kind => TVar_T, Tv => A_Tv)));
      function Meta return Real_Type_Id is
        (M.Add (Type_Node'(Kind => TMeta_T, Meta => 1)));

      Vars : TyVar_Id_Vectors.Vector;
      Args : Type_Id_Vectors.Vector;
   begin
      Start_Suite ("Inst_Match");
      Vars.Append (A_Tv);

      --  [a] against [Int]: Matched, a := Int.
      Check (Match (M, Env, App (Con (List_TC), Var), Vars,
                    App (Con (List_TC), Con (Int_TC)), Args) = Matched,
             "[a] matches [Int]");
      Check (M.Node (Args (1)).Kind = TCon_T
               and then M.Node (Args (1)).Con = Int_TC,
             "[a] against [Int] binds a := Int");

      --  [Char] against [Int]: No_Match; against [?m]: Undecided.
      Check (Match (M, Env, App (Con (List_TC), Con (Char_TC)),
                    TyVar_Id_Vectors.Empty_Vector,
                    App (Con (List_TC), Con (Int_TC)), Args) = No_Match,
             "[Char] does not match [Int]");
      Check (Match (M, Env, App (Con (List_TC), Con (Char_TC)),
                    TyVar_Id_Vectors.Empty_Vector,
                    App (Con (List_TC), Meta), Args) = Undecided,
             "[Char] against [?m] is undecided");

      --  Either a a: a repeated variable needs equal arguments.
      Check (Match (M, Env, App (App (Con (Either_TC), Var), Var), Vars,
                    App (App (Con (Either_TC), Con (Int_TC)), Con (Int_TC)),
                    Args) = Matched,
             "Either a a matches Either Int Int");
      Check (Match (M, Env, App (App (Con (Either_TC), Var), Var), Vars,
                    App (App (Con (Either_TC), Con (Int_TC)), Con (Bool_TC)),
                    Args) = No_Match,
             "Either a a does not match Either Int Bool");

      --  A bare-variable head matches anything, even a metavariable.
      Check (Match (M, Env, Var, Vars, Con (Bool_TC), Args) = Matched,
             "a matches Bool");
      Check (Match (M, Env, Var, Vars, Meta, Args) = Matched,
             "a matches ?m");

      --  Heads_Equal: equal up to renaming, not merely unifiable.
      Check (Heads_Equal (M, App (Con (List_TC), Var),
                          App (Con (List_TC), Var)),
             "[a] equals [a]");
      Check (not Heads_Equal (M, App (Con (List_TC), Var),
                              App (Con (List_TC), Con (Char_TC))),
             "[a] is not [Char] (overlap, not duplicate)");
   end Run;

end Test_Inst_Match;
