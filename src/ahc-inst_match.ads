--  Instance selection by one-way matching (M147, FlexibleInstances).
--
--  Haskell 2010 instance heads are C (T a1..an), so selection used to
--  key on the head TyCon. GHC's FlexibleInstances and
--  TypeSynonymInstances allow any head - C [Char], C (Maybe Int),
--  C a - so an instance keeps its full head type (Instance_Info's
--  Head_Type) and every place that selects instances (the
--  typechecker's Solve, elaborate's Solve_Ev, the duplicate check)
--  asks this one matcher, so they can never disagree.

with AHC.Core;
with AHC.Builtins;

package AHC.Inst_Match is
   use AHC.Core;

   --  Matched: the head's variables bind and nothing else is needed.
   --  No_Match: no instantiation of the head equals the type.
   --  Undecided: a metavariable in the type sits where the head needs
   --  structure, so the answer waits for unification.
   type Match_Result is (Matched, No_Match, Undecided);

   --  Norm follows solved metavariables and expands the wired Rational
   --  placeholder (the typechecker passes Repr plus expansion,
   --  elaborate expansion alone - its types are zonked). Args receives
   --  the binding of each of Vars, in order (meaningful only when the
   --  result is Matched).
   generic
      with function Norm (T : Real_Type_Id) return Real_Type_Id;
   function Match_Head
     (M      : in out Core_Module;
      Env    : Builtins.Global_Env;
      Pat    : Real_Type_Id;
      Vars   : TyVar_Id_Vectors.Vector;
      Target : Real_Type_Id;
      Args   : out Type_Id_Vectors.Vector) return Match_Result;

   --  Instance selection proper: a source instance (Head_Type set)
   --  matches its full head one way; a wired or stock-derived one keeps
   --  the Haskell 2010 rule - the wanted's spine TyCon equals Head, and
   --  its spine arguments bind Head_Vars by position (that is what
   --  `Functor Maybe`, whose Head_Vars are empty, and `IsString [a]`
   --  have always meant). Every selector calls this one function.
   generic
      with function Norm (T : Real_Type_Id) return Real_Type_Id;
   function Match_Instance
     (M      : in out Core_Module;
      Env    : Builtins.Global_Env;
      Inst   : Instance_Info;
      Target : Real_Type_Id;
      Args   : out Type_Id_Vectors.Vector) return Match_Result;

   --  The head type of an instance: Head_Type, or Head applied to
   --  Head_Vars for a wired or stock-derived one.
   function Instance_Type
     (M : in out Core_Module; Env : Builtins.Global_Env;
      I : Instance_Info) return Real_Type_Id
     with Pre => I.Head_Type /= No_Type or else I.Head /= No_TyCon;

   --  Equal up to a consistent renaming of type variables: two such
   --  instance heads are a duplicate, not an overlap.
   function Heads_Equal
     (M : Core_Module; A, B : Real_Type_Id) return Boolean;

end AHC.Inst_Match;
