-- microhm - a miniature Hindley-Milner type inferencer, the third
-- dogfood program: the compiler's most intricate machinery (its
-- typechecker) in ~350-line miniature, compiled by that machinery.
-- Like every example it must behave byte-identically compiled by
-- AHC or interpreted by GHC - the goldens are GHC's output.
--
--   microhm            read terms from stdin, one per line
--   microhm FILE       same, from a file
--
-- The language: lambda calculus with let-polymorphism -
--   \x. e     \x y. e     e1 e2     let x = e1 in e2
--   if c then t else e    integers    true    false
-- Comment lines start with --; blank lines are skipped.
--
-- The unifier states the SAME obligations the real typechecker
-- states as Ada contracts (the PRD's marquee verification claims),
-- here as PRE/POST pragmas: bindVar's occurs-check precondition
-- and the fresh-supply monotonicity postcondition. GHC ignores the
-- pragmas; AHC discharges or checks them like any contract.

import Data.Char (chr, isAlpha, isDigit, ord)
import Data.List (intercalate, nub, (\\))
import System.Environment (getArgs)
import qualified Data.Map as Map

------------------------------------------------------------------
--  Terms and types
------------------------------------------------------------------

data Term
  = TmVar String
  | TmLit Int
  | TmBool Bool
  | TmLam String Term
  | TmApp Term Term
  | TmLet String Term Term
  | TmIf Term Term Term

data Ty = TInt | TBool | TVar Int | TFun Ty Ty
  deriving (Eq)

data Scheme = Forall [Int] Ty

type Env = Map.Map String Scheme
type Sub = Map.Map Int Ty

------------------------------------------------------------------
--  Substitutions
------------------------------------------------------------------

applyS :: Sub -> Ty -> Ty
applyS _ TInt = TInt
applyS _ TBool = TBool
applyS s (TFun a b) = TFun (applyS s a) (applyS s b)
applyS s (TVar v) = Map.findWithDefault (TVar v) v s

--  s2 `after` s1: apply s1 first, then s2.
compose :: Sub -> Sub -> Sub
compose s2 s1 = Map.union (Map.map (applyS s2) s1) s2

metasOf :: Ty -> [Int]
metasOf TInt = []
metasOf TBool = []
metasOf (TVar v) = [v]
metasOf (TFun a b) = nub (metasOf a ++ metasOf b)

metasOfScheme :: Scheme -> [Int]
metasOfScheme (Forall vs t) = metasOf t \\ vs

metasOfEnv :: Env -> [Int]
metasOfEnv env =
  nub (concatMap (\p -> metasOfScheme (snd p)) (Map.toList env))

occursIn :: Int -> Ty -> Bool
occursIn v t = elem v (metasOf t)

------------------------------------------------------------------
--  Unification (the contracts live here)
------------------------------------------------------------------

data TC a = Ok a | Err String

--  The occurs check is the CALLER's obligation - exactly the
--  shape of the real typechecker's Bind_Meta precondition.
{-# PRE bindVar \v t -> not (occursIn v t) #-}
bindVar :: Int -> Ty -> Sub
bindVar v t = Map.insert v t Map.empty

unify :: Ty -> Ty -> TC Sub
unify TInt TInt = Ok Map.empty
unify TBool TBool = Ok Map.empty
unify (TVar v) t = unifyVar v t
unify t (TVar v) = unifyVar v t
unify (TFun a1 b1) (TFun a2 b2) =
  case unify a1 a2 of
    Err e -> Err e
    Ok s1 ->
      case unify (applyS s1 b1) (applyS s1 b2) of
        Err e -> Err e
        Ok s2 -> Ok (compose s2 s1)
unify t1 t2 =
  Err ("cannot match " ++ showTy t1 ++ " with " ++ showTy t2)

unifyVar :: Int -> Ty -> TC Sub
unifyVar v t
  | t == TVar v = Ok Map.empty
  | occursIn v t =
      Err ("occurs check: " ++ showTy (TVar v)
           ++ " ~ " ++ showTy t)
  | otherwise = Ok (bindVar v t)

------------------------------------------------------------------
--  Fresh metas (a threaded supply; the subset has no state monad)
------------------------------------------------------------------

{-# POST fresh \n p -> snd p == n + 1 #-}
fresh :: Int -> (Ty, Int)
fresh n = (TVar n, n + 1)

freshMany :: Int -> Int -> ([Ty], Int)
freshMany 0 n = ([], n)
freshMany k n =
  case fresh n of
    (t, n1) ->
      case freshMany (k - 1) n1 of
        (ts, n2) -> (t : ts, n2)

------------------------------------------------------------------
--  Generalization and instantiation
------------------------------------------------------------------

generalize :: Env -> Ty -> Scheme
generalize env t = Forall (metasOf t \\ metasOfEnv env) t

instantiate :: Scheme -> Int -> (Ty, Int)
instantiate (Forall vs t) n =
  case freshMany (length vs) n of
    (ts, n1) ->
      let s = Map.fromList (zip vs ts)
      in (applyS s t, n1)

------------------------------------------------------------------
--  Algorithm W
------------------------------------------------------------------

applyEnv :: Sub -> Env -> Env
applyEnv s env =
  Map.map (\sch -> case sch of
             Forall vs t ->
               Forall vs (applyS (foldl (flip Map.delete) s vs) t))
          env

infer :: Env -> Term -> Int -> TC (Sub, Ty, Int)
infer env (TmLit _) n = Ok (Map.empty, TInt, n)
infer env (TmBool _) n = Ok (Map.empty, TBool, n)
infer env (TmVar x) n =
  case Map.lookup x env of
    Nothing -> Err ("unbound variable '" ++ x ++ "'")
    Just sch ->
      case instantiate sch n of
        (t, n1) -> Ok (Map.empty, t, n1)
infer env (TmLam x body) n =
  case fresh n of
    (a, n1) ->
      case infer (Map.insert x (Forall [] a) env) body n1 of
        Err e -> Err e
        Ok (s, t, n2) -> Ok (s, TFun (applyS s a) t, n2)
infer env (TmApp f x) n =
  case infer env f n of
    Err e -> Err e
    Ok (s1, tf, n1) ->
      case infer (applyEnv s1 env) x n1 of
        Err e -> Err e
        Ok (s2, tx, n2) ->
          case fresh n2 of
            (b, n3) ->
              case unify (applyS s2 tf) (TFun tx b) of
                Err e -> Err e
                Ok s3 ->
                  Ok (compose s3 (compose s2 s1), applyS s3 b, n3)
infer env (TmLet x e1 e2) n =
  case infer env e1 n of
    Err e -> Err e
    Ok (s1, t1, n1) ->
      let env1 = applyEnv s1 env
          sch = generalize env1 (applyS s1 t1)
      in case infer (Map.insert x sch env1) e2 n1 of
           Err e -> Err e
           Ok (s2, t2, n2) -> Ok (compose s2 s1, t2, n2)
infer env (TmIf c t e) n =
  case infer env c n of
    Err er -> Err er
    Ok (s1, tc, n1) ->
      case unify tc TBool of
        Err er -> Err er
        Ok sc ->
          let s1c = compose sc s1
          in case infer (applyEnv s1c env) t n1 of
               Err er -> Err er
               Ok (s2, tt, n2) ->
                 case infer (applyEnv s2 (applyEnv s1c env)) e n2 of
                   Err er -> Err er
                   Ok (s3, te, n3) ->
                     case unify (applyS s3 tt) te of
                       Err er -> Err er
                       Ok s4 ->
                         Ok (compose s4
                              (compose s3 (compose s2 s1c)),
                             applyS s4 te, n3)

------------------------------------------------------------------
--  Type printing: metas become a, b, c... in first-occurrence
--  order (the same presentation trick as `ahc check`)
------------------------------------------------------------------

showTy :: Ty -> String
showTy t = go (renameMap t) t
  where
    go :: Map.Map Int String -> Ty -> String
    go _ TInt = "Int"
    go _ TBool = "Bool"
    go m (TVar v) = Map.findWithDefault ("t" ++ show v) v m
    go m (TFun a b) = goL m a ++ " -> " ++ go m b

    goL :: Map.Map Int String -> Ty -> String
    goL m f =
      case f of
        TFun _ _ -> "(" ++ go m f ++ ")"
        _ -> go m f

renameMap :: Ty -> Map.Map Int String
renameMap t =
  Map.fromList (zip (firstSeen t) (map letter [0 ..]))
  where
    firstSeen :: Ty -> [Int]
    firstSeen = nub . metasSeq

    metasSeq :: Ty -> [Int]
    metasSeq TInt = []
    metasSeq TBool = []
    metasSeq (TVar v) = [v]
    metasSeq (TFun a b) = metasSeq a ++ metasSeq b

    letter :: Int -> String
    letter i
      | i < 26 = [chr (ord 'a' + i)]
      | otherwise = "t" ++ show i

------------------------------------------------------------------
--  Term parser (ajson's Res pattern: offset-tagged errors)
------------------------------------------------------------------

data Res a = Good a String Int | Bad Int String

skipWS :: String -> Int -> (String, Int)
skipWS (' ' : cs) n = skipWS cs (n + 1)
skipWS ('\t' : cs) n = skipWS cs (n + 1)
skipWS s n = (s, n)

isIdent :: Char -> Bool
isIdent c = isAlpha c || isDigit c || c == '_' || c == '\''

pIdent :: String -> Int -> Res String
pIdent s n =
  case span isIdent s of
    ([], _) -> Bad n "expected an identifier"
    (w, rest) -> Good w rest (n + length w)

pTerm :: String -> Int -> Res Term
pTerm s0 n0 =
  case skipWS s0 n0 of
    ('\\' : cs, n) -> pLambda cs (n + 1)
    (s, n)
      | keywordAt "let" s -> pLet (drop 3 s) (n + 3)
      | keywordAt "if" s -> pIf (drop 2 s) (n + 2)
      | otherwise -> pApp s n

keywordAt :: String -> String -> Bool
keywordAt kw s =
  take (length kw) s == kw
  && (case drop (length kw) s of
        (c : _) -> not (isIdent c)
        [] -> True)

pLambda :: String -> Int -> Res Term
pLambda s0 n0 = params s0 n0 []
  where
    params :: String -> Int -> [String] -> Res Term
    params s n acc =
      case skipWS s n of
        ('.' : cs, m)
          | not (null acc) ->
              case pTerm cs (m + 1) of
                Good body rest m2 ->
                  Good (foldr TmLam body (reverse acc)) rest m2
                Bad m2 e -> Bad m2 e
        (s1, m) ->
          case pIdent s1 m of
            Bad m2 _ -> Bad m2 "expected parameter or '.'"
            Good x rest m2 -> params rest m2 (x : acc)

pLet :: String -> Int -> Res Term
pLet s0 n0 =
  case skipWS s0 n0 of
    (s, n) ->
      case pIdent s n of
        Bad m e -> Bad m e
        Good x rest m ->
          case skipWS rest m of
            ('=' : cs, m2) ->
              case pTerm cs (m2 + 1) of
                Bad m3 e -> Bad m3 e
                Good e1 rest2 m3 ->
                  case skipWS rest2 m3 of
                    (s2, m4)
                      | keywordAt "in" s2 ->
                          case pTerm (drop 2 s2) (m4 + 2) of
                            Bad m5 e -> Bad m5 e
                            Good e2 rest3 m5 ->
                              Good (TmLet x e1 e2) rest3 m5
                    (_, m4) -> Bad m4 "expected 'in'"
            (_, m2) -> Bad m2 "expected '='"

pIf :: String -> Int -> Res Term
pIf s0 n0 =
  case pTerm s0 n0 of
    Bad m e -> Bad m e
    Good c rest m ->
      case skipWS rest m of
        (s1, m1)
          | keywordAt "then" s1 ->
              case pTerm (drop 4 s1) (m1 + 4) of
                Bad m2 e -> Bad m2 e
                Good t rest2 m2 ->
                  case skipWS rest2 m2 of
                    (s2, m3)
                      | keywordAt "else" s2 ->
                          case pTerm (drop 4 s2) (m3 + 4) of
                            Bad m4 e -> Bad m4 e
                            Good e rest3 m4 ->
                              Good (TmIf c t e) rest3 m4
                    (_, m3) -> Bad m3 "expected 'else'"
        (_, m1) -> Bad m1 "expected 'then'"

pApp :: String -> Int -> Res Term
pApp s0 n0 =
  case pAtom s0 n0 of
    Bad m e -> Bad m e
    Good f rest m -> more f rest m
  where
    more :: Term -> String -> Int -> Res Term
    more f s n =
      case skipWS s n of
        (s1@(c : _), m)
          | c == '(' || c == '\\' || isIdent c ->
              if keywordAt "in" s1 || keywordAt "then" s1
                 || keywordAt "else" s1
              then Good f s1 m
              else case pAtom s1 m of
                     Bad m2 e -> Bad m2 e
                     Good x rest m2 -> more (TmApp f x) rest m2
        (s1, m) -> Good f s1 m

pAtom :: String -> Int -> Res Term
pAtom s0 n0 =
  case skipWS s0 n0 of
    ('(' : cs, n) ->
      case pTerm cs (n + 1) of
        Bad m e -> Bad m e
        Good t rest m ->
          case skipWS rest m of
            (')' : cs2, m2) -> Good t cs2 (m2 + 1)
            (_, m2) -> Bad m2 "expected ')'"
    ('\\' : cs, n) -> pLambda cs (n + 1)
    (s@(c : _), n)
      | isDigit c ->
          case span isDigit s of
            (ds, rest) ->
              Good (TmLit (foldl (\a d -> a * 10 + ord d - 48) 0 ds))
                   rest (n + length ds)
      | keywordAt "true" s -> Good (TmBool True) (drop 4 s) (n + 4)
      | keywordAt "false" s -> Good (TmBool False) (drop 5 s) (n + 5)
      | isAlpha c || c == '_' ->
          case pIdent s n of
            Bad m e -> Bad m e
            Good x rest m -> Good (TmVar x) rest m
    (_, n) -> Bad n "expected a term"

------------------------------------------------------------------
--  Driver: one term per line, aligned output
------------------------------------------------------------------

inferLine :: String -> String
inferLine src =
  case pTerm src 0 of
    Bad m e -> "parse error at column " ++ show m ++ ": " ++ e
    Good tm rest m ->
      case skipWS rest m of
        ([], _) ->
          case infer Map.empty tm 0 of
            Err e -> "type error: " ++ e
            Ok (s, t, _) -> showTy (applyS s t)
        (_, m2) ->
          "parse error at column " ++ show m2 ++ ": trailing input"

run :: String -> String
run text =
  let ls = filter keep (lines text)
      width = foldl max 0 (map length ls)
      one l = padTo width l ++ "  :: " ++ inferLine l
  in intercalate "\n" (map one ls)
  where
    keep :: String -> Bool
    keep l = not (null l) && take 2 l /= "--"

    padTo :: Int -> String -> String
    padTo w l = l ++ replicate (w - length l) ' '

main :: IO ()
main = do
  args <- getArgs
  case args of
    [path] -> readFile path >>= putStrLn . run
    [] -> getContents >>= putStrLn . run
    _ -> putStrLn "usage: microhm [FILE]"
