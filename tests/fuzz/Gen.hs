-- Gen.hs - random well-typed Haskell 2010 program generator for the
-- AHC/GHC differential fuzzer (scripts/run_fuzz.sh).
--
--   runghc Gen.hs SEED    -- deterministic program on stdout
--
-- The generator runs under GHC only (base-only imports) and emits
-- programs drawn from the VERIFIED intersection of AHC's subset and
-- GHC's Prelude - every construct and library function below was
-- pinned byte-identical on both compilers before entering the menu,
-- so an AHC rejection or output divergence on a generated program is
-- a real finding, never menu noise. Known-divergent territory from
-- tests/conformance/EXCLUSIONS.md is avoided by construction:
-- Int arithmetic stays small (AHC promotes on overflow, the Report
-- leaves it undefined), text stays ASCII, partial functions are
-- never emitted (division is guarded, maximum/minimum get a consed
-- head, recursion is structural on the tail).
module Main where

import Data.List (intercalate)
import System.Environment (getArgs)

-- ===== deterministic RNG: 64-bit LCG threaded with a name supply ==

type S = (Integer, Int)

newtype R a = R { runR :: S -> (a, S) }

instance Functor R where
  fmap f (R g) = R (\s -> let (a, s') = g s in (f a, s'))

instance Applicative R where
  pure a = R (\s -> (a, s))
  R mf <*> R ma = R (\s -> let (f, s1) = mf s
                               (a, s2) = ma s1
                           in (f a, s2))

instance Monad R where
  R ma >>= k = R (\s -> let (a, s1) = ma s in runR (k a) s1)

rnd :: Int -> R Int          -- uniform in [0, n)
rnd n = R (\(g, c) ->
  let g' = (6364136223846793005 * g + 1442695040888963407)
             `mod` 18446744073709551616
      v  = fromInteger ((g' `div` 2048) `mod` toInteger (max 1 n))
  in (v, (g', c)))

fresh :: R String
fresh = R (\(g, c) -> ("v" ++ show c, (g, c + 1)))

pick :: [a] -> R a
pick xs = do i <- rnd (length xs)
             return (xs !! i)

freq :: [(Int, R a)] -> R a
freq ws = do
  i <- rnd (sum (map fst ws))
  go i ws
  where go i ((w, g) : rest) | i < w = g
                             | otherwise = go (i - w) rest
        go _ [] = error "freq: empty"

chance :: Int -> Int -> R Bool   -- true k times in n
chance k n = do i <- rnd n
                return (i < k)

-- ===== the type universe ==========================================

data Ty = TInt | TInteger | TDouble | TBool | TChar | TEnum
        | TList Ty | TMaybe Ty | TPair Ty Ty
  deriving (Eq, Show)

rTy :: Ty -> String
rTy TInt          = "Int"
rTy TInteger      = "Integer"
rTy TDouble       = "Double"
rTy TBool         = "Bool"
rTy TChar         = "Char"
rTy TEnum         = "E0"
rTy (TList TChar) = "String"
rTy (TList t)     = "[" ++ rTy t ++ "]"
rTy (TMaybe t)    = "(Maybe " ++ rTy t ++ ")"
rTy (TPair a b)   = "(" ++ rTy a ++ ", " ++ rTy b ++ ")"

scalars :: [Ty]
scalars = [TInt, TInteger, TDouble, TBool, TChar, TEnum]

scalarTy :: R Ty
scalarTy = pick scalars

anyTy :: R Ty
anyTy = freq
  [ (6, scalarTy)
  , (3, TList <$> scalarTy)
  , (2, TMaybe <$> scalarTy)
  , (2, TPair <$> scalarTy <*> scalarTy)
  , (1, TList <$> (TPair <$> scalarTy <*> scalarTy)) ]

enumCons :: [String]
enumCons = ["K0", "K1", "K2", "K3"]

safeChars :: [Char]
safeChars = ['a' .. 'z'] ++ ['A' .. 'Z'] ++ ['0' .. '9'] ++ " "

safeWords :: [String]
safeWords = ["fuzz", "oracle", "Ada", "graph", "x1 y2", "thunk", ""]

-- ===== environments ===============================================

data Fun = Fun String [Ty] Ty

data Env = Env { evars :: [(String, Ty)]
               , efuns :: [Fun]
               , erec  :: Maybe (String, String, Ty) }
               -- erec: (f, xs, result) - the one legal recursive
               -- call "(f xs)", structural on the match's own tail

addV :: (String, Ty) -> Env -> Env
addV p e = e { evars = p : evars e }

varOf :: Env -> Ty -> [String]
varOf env t = [n | (n, t') <- evars env, t' == t]

recOf :: Env -> Ty -> [String]
recOf env t = case erec env of
  Just (f, xs, r) | r == t -> ["(" ++ f ++ " " ++ xs ++ ")"]
  _                        -> []

-- ===== literals ===================================================

lit :: Ty -> R String
lit TInt = fmap show (rnd 100)
lit TInteger = freq
  [ (3, fmap show (rnd 1000))
  , (2, do k  <- rnd 16                    -- 15..30 digit bignum
           d0 <- rnd 9
           ds <- mapM (const (rnd 10)) [1 .. 14 + k]
           return (concatMap show (d0 + 1 : ds))) ]
lit TDouble = do a <- rnd 100
                 b <- rnd 100
                 return (show a ++ "." ++ (if b < 10 then "0" else "")
                         ++ show b)
lit TBool = pick ["True", "False"]
lit TChar = fmap show (pick safeChars)
lit TEnum = pick enumCons
lit (TMaybe t) = freq
  [ (1, return "Nothing")
  , (2, do e <- lit t
           return ("(Just " ++ e ++ ")")) ]
lit (TPair a b) = do x <- lit a
                     y <- lit b
                     return ("(" ++ x ++ ", " ++ y ++ ")")
lit (TList TChar) = fmap show (pick safeWords)
lit (TList t) = do n  <- rnd 4
                   es <- mapM (const (lit t)) [1 .. n]
                   return ("[" ++ intercalate ", " es ++ "]")

-- ===== expression generation ======================================

genE :: Int -> Env -> Ty -> R String
genE sz env t = do
  takeLeaf <- if sz <= 0 then return True else chance 1 5
  if takeLeaf then leaf env t else node sz env t

leaf :: Env -> Ty -> R String
leaf env t = freq
  ([(3, lit t)]
   ++ [(4, pick vs) | let vs = varOf env t, not (null vs)]
   ++ [(3, pick rc) | let rc = recOf env t, not (null rc)])

-- productions available at every type
common :: Int -> Env -> Ty -> [(Int, R String)]
common sz env t =
  [ (2, ifE), (2, letE), (2, caseE) ]
  ++ [ (2, appE f) | f@(Fun _ _ r) <- efuns env, r == t ]
  ++ [ (1, projE) ]
  where
    h = sz `div` 2
    ifE = do c <- genE (sz `div` 3) env TBool
             a <- genE h env t
             b <- genE h env t
             return ("(if " ++ c ++ " then " ++ a
                     ++ " else " ++ b ++ ")")
    letE = do v  <- fresh
              vt <- scalarTy
              r  <- genE h env vt
              b  <- genE h (addV (v, vt) env) t
              return ("(let " ++ v ++ " = " ++ r
                      ++ " in " ++ b ++ ")")
    caseE = freq
      [ (2, do st <- scalarTy
               s  <- genE h env (TMaybe st)
               v  <- fresh
               e1 <- genE h env t
               e2 <- genE h (addV (v, st) env) t
               return ("(case (" ++ s ++ " :: (Maybe " ++ rTy st
                       ++ ")) of { Nothing -> " ++ e1
                       ++ " ; Just " ++ v ++ " -> " ++ e2 ++ " })"))
      , (2, do st <- scalarTy
               s  <- genE h env (TList st)
               v1 <- fresh
               v2 <- fresh
               e1 <- genE h env t
               e2 <- genE h (addV (v1, st)
                              (addV (v2, TList st) env)) t
               return ("(case (" ++ s ++ " :: [" ++ rTy st
                       ++ "]) of { [] -> " ++ e1
                       ++ " ; (" ++ v1 ++ " : " ++ v2 ++ ") -> "
                       ++ e2 ++ " })"))
      , (1, do a  <- scalarTy
               b  <- scalarTy
               s  <- genE h env (TPair a b)
               v1 <- fresh
               v2 <- fresh
               e  <- genE h (addV (v1, a) (addV (v2, b) env)) t
               return ("(case (" ++ s ++ " :: " ++ rTy (TPair a b)
                       ++ ") of { (" ++ v1 ++ ", "
                       ++ v2 ++ ") -> " ++ e ++ " })"))
      , (1, do s  <- genE h env TEnum
               es <- mapM (const (genE (sz `div` 3) env t)) enumCons
               full <- chance 1 2
               let alts = zipWith (\k e -> k ++ " -> " ++ e)
                            enumCons es
               d <- genE (sz `div` 3) env t
               let body = if full
                          then intercalate " ; " alts
                          else intercalate " ; " (take 2 alts)
                               ++ " ; _ -> " ++ d
               return ("(case " ++ s ++ " of { " ++ body ++ " })")) ]
    appE (Fun n args _) = do
      as <- mapM (genE (max 0 (sz `div` (1 + length args))) env) args
      return ("(" ++ n ++ " " ++ unwords as ++ ")")
    projE = do side <- pick ["fst", "snd"]
               ot   <- scalarTy
               let pt = if side == "fst" then TPair t ot
                        else TPair ot t
               p <- genE h env pt
               return ("(" ++ side ++ " (" ++ p ++ " :: "
                       ++ rTy pt ++ "))")

node :: Int -> Env -> Ty -> R String
node sz env t = freq (common sz env t ++ own)
  where
    h  = sz `div` 2
    s3 = sz `div` 3
    sub    = genE h env
    binOp op a b = "(" ++ a ++ " " ++ op ++ " " ++ b ++ ")"
    bin ty op = do a <- sub ty
                   b <- sub ty
                   return (binOp op a b)
    -- x `op` y with y guarded away from zero, sharing y via let
    guarded ty zero one ops = do
      op <- pick ops
      a  <- sub ty
      b  <- sub ty
      d  <- fresh
      return ("(" ++ a ++ " `" ++ op ++ "` (let " ++ d ++ " = " ++ b
              ++ " in (if (" ++ d ++ " == " ++ zero ++ ") then "
              ++ one ++ " else " ++ d ++ ")))")
    unary ty fs = do f <- pick fs
                     a <- sub ty
                     return ("(" ++ f ++ " " ++ a ++ ")")
    nonEmpty et = do x  <- genE s3 env et
                     xs <- genE s3 env (TList et)
                     return ("(" ++ x ++ " : " ++ xs ++ ")")
    lam vt body = do v <- fresh
                     b <- body v
                     return ("(\\" ++ v ++ " -> " ++ b ++ ")")
    intSection = pick ["(+ 3)", "(* 2)", "(subtract 1)", "(`div` 2)"]
    own = case t of
      TInt ->
        [ (3, bin TInt "+"), (3, bin TInt "-")
        , (2, do a <- sub TInt
                 l <- rnd 8
                 return (binOp "*" a (show (l + 2))))
        , (2, guarded TInt "0" "1" ["div", "mod", "quot", "rem"])
        , (1, unary TInt ["abs", "negate", "signum"])
        , (1, do f <- pick ["min", "max", "gcd", "lcm"]
                 a <- sub TInt
                 b <- sub TInt
                 return ("(" ++ f ++ " " ++ a ++ " " ++ b ++ ")"))
        , (1, do et <- scalarTy
                 l  <- sub (TList et)
                 return ("(length (" ++ l ++ " :: ["
                         ++ rTy et ++ "]))"))
        , (1, do l <- sub (TList TInt)
                 return ("(sum " ++ l ++ ")"))
        , (1, do f  <- pick ["maximum", "minimum"]
                 ne <- nonEmpty TInt
                 return ("(" ++ f ++ " " ++ ne ++ ")"))
        , (1, do c <- sub TChar
                 return ("(ord " ++ c ++ ")"))
        , (1, do e <- freq [(2, sub TEnum), (1, sub TBool)]
                 return ("(fromEnum " ++ e ++ ")"))
        , (1, do l <- rnd 60
                 x <- sub TInt
                 return ("(until (> " ++ show (l + 20)
                         ++ ") (* 2) (max 1 (abs " ++ x ++ ")))")) ]
      TInteger ->
        [ (3, bin TInteger "+"), (2, bin TInteger "-")
        , (2, bin TInteger "*")
        , (2, guarded TInteger "0" "1" ["div", "mod", "quot", "rem"])
        , (1, do a <- sub TInteger
                 l <- rnd 7
                 return (binOp "^" a (show l)))
        , (1, do ne <- nonEmpty TInteger
                 return ("(product " ++ ne ++ ")"))
        , (1, do l <- sub (TList TInteger)
                 return ("(sum " ++ l ++ ")"))
        , (1, unary TInteger ["abs", "negate", "signum"])
        , (1, do f <- pick ["min", "max", "gcd", "lcm"]
                 a <- sub TInteger
                 b <- sub TInteger
                 return ("(" ++ f ++ " " ++ a ++ " " ++ b ++ ")"))
        , (1, do e <- sub TInt
                 return ("(toInteger (" ++ e ++ " :: Int))")) ]
      TDouble ->
        [ (3, bin TDouble "+"), (2, bin TDouble "-")
        , (2, bin TDouble "*")
        , (2, do a <- sub TDouble
                 b <- sub TDouble
                 d <- fresh
                 return ("(" ++ a ++ " / (let " ++ d ++ " = " ++ b
                         ++ " in (if (" ++ d ++ " == 0.0) then 1.0"
                         ++ " else " ++ d ++ ")))"))
        , (1, do a <- sub TDouble
                 return ("(sqrt (abs " ++ a ++ "))"))
        , (1, unary TDouble ["abs", "negate"])
        , (1, do f <- pick ["min", "max"]
                 a <- sub TDouble
                 b <- sub TDouble
                 return ("(" ++ f ++ " " ++ a ++ " " ++ b ++ ")"))
        , (1, do it <- pick [TInt, TInteger]
                 e  <- sub it
                 return ("(fromIntegral (" ++ e ++ " :: "
                         ++ rTy it ++ "))")) ]
      TBool ->
        [ (4, do ct <- freq [ (4, scalarTy)
                            , (2, TList <$> scalarTy)
                            , (1, TMaybe <$> scalarTy)
                            , (1, TPair <$> scalarTy <*> scalarTy) ]
                 op <- pick ["==", "/=", "<", "<=", ">", ">="]
                 a  <- sub ct
                 b  <- sub ct
                 return ("((" ++ a ++ " :: " ++ rTy ct ++ ") "
                         ++ op ++ " " ++ b ++ ")"))
        , (2, bin TBool "&&"), (2, bin TBool "||")
        , (1, unary TBool ["not"])
        , (1, do f  <- pick ["even", "odd"]
                 it <- pick [TInt, TInteger]
                 e  <- sub it
                 return ("(" ++ f ++ " (" ++ e ++ " :: "
                         ++ rTy it ++ "))"))
        , (1, do et <- scalarTy
                 l  <- sub (TList et)
                 return ("(null (" ++ l ++ " :: ["
                         ++ rTy et ++ "]))"))
        , (1, do et <- pick [TInt, TChar]
                 x  <- sub et
                 l  <- sub (TList et)
                 return ("(elem (" ++ x ++ " :: " ++ rTy et ++ ") "
                         ++ l ++ ")"))
        , (1, do f  <- pick ["isJust", "isNothing"]
                 st <- scalarTy
                 m  <- sub (TMaybe st)
                 return ("(" ++ f ++ " " ++ m ++ ")"))
        , (1, do f <- pick ["all", "any"]
                 p <- pick ["even", "odd"]
                 l <- sub (TList TInt)
                 return ("(" ++ f ++ " " ++ p ++ " (" ++ l
                         ++ " :: [Int]))"))
        , (1, do f <- pick ["and", "or"]
                 l <- sub (TList TBool)
                 return ("(" ++ f ++ " " ++ l ++ ")"))
        , (1, do f <- pick ["isDigit", "isUpper"]
                 c <- sub TChar
                 return ("(" ++ f ++ " " ++ c ++ ")"))
        , (1, do a <- sub (TList TChar)
                 b <- sub (TList TChar)
                 return ("(isPrefixOf " ++ a ++ " " ++ b ++ ")")) ]
      TChar ->
        [ (3, do e <- sub TInt
                 return ("(chr (97 + ((" ++ e ++ ") `mod` 26)))"))
        , (2, unary TChar ["toUpper", "toLower"])
        , (1, do c <- genE s3 env TChar
                 w <- pick (filter (not . null) safeWords)
                 return ("(minimum (" ++ c ++ " : " ++ show w
                         ++ "))")) ]
      TEnum ->
        [ (2, do e <- sub TEnum
                 v <- fresh
                 return ("(let " ++ v ++ " = " ++ e ++ " in (if ("
                         ++ v ++ " == K3) then K0 else (succ "
                         ++ v ++ ")))"))
        , (2, do e <- sub TInt
                 return ("((toEnum ((" ++ e ++ ") `mod` 4)) :: E0)"))
        , (1, do f <- pick ["min", "max"]
                 a <- sub TEnum
                 b <- sub TEnum
                 return ("(" ++ f ++ " " ++ a ++ " " ++ b ++ ")")) ]
      TList TChar ->
        [ (3, do st <- anyTy
                 e  <- genE h env st
                 return ("(show (" ++ e ++ " :: " ++ rTy st ++ "))"))
        , (2, bin (TList TChar) "++")
        , (1, do f <- pick ["toUpper", "toLower"]
                 s <- sub (TList TChar)
                 return ("(map " ++ f ++ " " ++ s ++ ")"))
        , (1, do f <- pick ["reverse"]
                 s <- sub (TList TChar)
                 return ("(" ++ f ++ " " ++ s ++ ")"))
        , (1, do f <- pick ["take", "drop"]
                 n <- rnd 6
                 s <- sub (TList TChar)
                 return ("(" ++ f ++ " " ++ show n ++ " "
                         ++ s ++ ")"))
        , (1, do f <- pick ["isDigit", "isUpper"]
                 s <- sub (TList TChar)
                 return ("(filter " ++ f ++ " " ++ s ++ ")"))
        , (1, do a <- genE s3 env (TList TChar)
                 b <- genE s3 env (TList TChar)
                 return ("(unwords [" ++ a ++ ", " ++ b ++ "])"))
        , (1, do sep <- pick [", ", "-", " "]
                 a   <- genE s3 env (TList TChar)
                 b   <- genE s3 env (TList TChar)
                 return ("(intercalate " ++ show sep ++ " ["
                         ++ a ++ ", " ++ b ++ "])"))
        , (1, do n <- rnd 5
                 c <- sub TChar
                 return ("(replicate " ++ show n ++ " " ++ c ++ ")"))
        , (1, do c1 <- pick safeChars
                 c2 <- pick safeChars
                 return ("[" ++ show c1 ++ " .. " ++ show c2
                         ++ "]")) ]
      TList et -> listProds et
      TMaybe mt ->
        [ (2, do e <- sub mt
                 return ("(Just " ++ e ++ ")"))
        , (1, return "Nothing")
        , (2, do kt <- pick [TInt, TChar, TEnum]
                 k  <- genE s3 env kt
                 n  <- rnd 4
                 ps <- mapM (const (do a <- lit kt
                                       b <- genE 0 env mt
                                       return ("(" ++ a ++ ", "
                                               ++ b ++ ")")))
                            [1 .. n]
                 return ("(lookup (" ++ k ++ " :: " ++ rTy kt
                         ++ ") [" ++ intercalate ", " ps ++ "])"))
        , (1, do l <- sub (TList mt)
                 return ("(listToMaybe " ++ l ++ ")")) ]
      TPair a b ->
        [ (5, do x <- sub a
                 y <- sub b
                 return ("(" ++ x ++ ", " ++ y ++ ")")) ]
    listProds et =
      [ (2, do n  <- rnd 4
               es <- mapM (const (genE s3 env et)) [1 .. n]
               return ("[" ++ intercalate ", " es ++ "]"))
      , (2, nonEmpty et)
      , (2, bin (TList et) "++")
      , (2, do st <- scalarTy
               f  <- lam st (\v ->
                       genE h (addV (v, st) env) et)
               l  <- sub (TList st)
               return ("(map " ++ f ++ " (" ++ l ++ " :: ["
                       ++ rTy st ++ "]))"))
      , (1, do f <- lam et (\v ->
                      genE h (addV (v, et) env) TBool)
               l <- sub (TList et)
               return ("(filter " ++ f ++ " " ++ l ++ ")"))
      , (1, do f <- pick ["sort", "nub", "reverse"]
               l <- sub (TList et)
               return ("(" ++ f ++ " " ++ l ++ ")"))
      , (1, do f <- pick ["take", "drop"]
               n <- rnd 6
               l <- sub (TList et)
               return ("(" ++ f ++ " " ++ show n ++ " " ++ l ++ ")"))
      , (1, do n <- rnd 4
               e <- sub et
               return ("(replicate " ++ show n ++ " " ++ e ++ ")"))
      , (1, do st <- scalarTy
               v  <- fresh
               b  <- genE h (addV (v, st) env) et
               l  <- genE s3 env (TList st)
               g  <- genE s3 (addV (v, st) env) TBool
               withG <- chance 1 2
               return ("[ " ++ b ++ " | " ++ v ++ " <- (" ++ l
                       ++ " :: [" ++ rTy st ++ "])"
                       ++ (if withG then ", " ++ g else "")
                       ++ " ]")) ]
      ++ rangeProds et ++ pairListProds et ++ deepProds et
    rangeProds TInt =
      [ (1, do v <- fresh
               a <- genE s3 env TInt
               k <- rnd 7
               return ("(let " ++ v ++ " = " ++ a ++ " in [" ++ v
                       ++ " .. (" ++ v ++ " + " ++ show k ++ ")])"))
      , (1, do v <- fresh
               a <- genE s3 env TInt
               k <- rnd 6
               return ("(let " ++ v ++ " = " ++ a ++ " in [" ++ v
                       ++ ", (" ++ v ++ " - 1) .. (" ++ v ++ " - "
                       ++ show k ++ ")])"))
      , (1, do sec <- intSection
               k   <- rnd 6
               x   <- genE s3 env TInt
               return ("(take " ++ show k ++ " (iterate " ++ sec
                       ++ " " ++ x ++ "))"))
      , (1, do a <- genE s3 env (TList TInt)
               b <- genE s3 env (TList TInt)
               return ("(zipWith (+) " ++ a ++ " " ++ b ++ ")")) ]
    rangeProds TDouble =
      [ (1, do v    <- fresh
               a    <- genE s3 env TDouble
               step <- pick ["0.25", "0.5", "1.5", "2.0"]
               span_ <- pick ["1.0", "3.0", "4.5"]
               return ("(let " ++ v ++ " = " ++ a ++ " in [" ++ v
                       ++ ", (" ++ v ++ " + " ++ step ++ ") .. ("
                       ++ v ++ " + " ++ span_ ++ ")])")) ]
    rangeProds _ = []
    pairListProds (TPair a b) =
      [ (2, do la <- sub (TList a)
               lb <- sub (TList b)
               return ("(zip " ++ la ++ " " ++ lb ++ ")")) ]
    pairListProds _ = []
    deepProds et =
      [ (1, do st <- scalarTy
               v  <- fresh
               b  <- genE s3 (addV (v, st) env) et
               c  <- genE s3 (addV (v, st) env) TBool
               l  <- genE s3 env (TList st)
               return ("(mapMaybe (\\" ++ v ++ " -> (if " ++ c
                       ++ " then (Just " ++ b ++ ") else Nothing)) ("
                       ++ l ++ " :: [" ++ rTy st ++ "]))"))
      , (1, do l <- sub (TList (TMaybe et))
               return ("(catMaybes " ++ l ++ ")")) ]

-- ===== top-level definitions ======================================

data Def = Def { dText :: [String], dFun :: Fun }

genDef :: [Fun] -> Int -> R Def
genDef prior i = freq
  [ (3, simple), (3, listRec), (2, withWhere), (2, guarded_) ]
  where
    fn = "f" ++ show i
    env0 = Env [] prior Nothing
    simple = do
      at <- anyTy
      rt <- anyTy
      v  <- fresh
      b  <- genE 8 (addV (v, at) env0) rt
      return (Def [ fn ++ " :: " ++ rTy at ++ " -> " ++ rTy rt
                  , fn ++ " " ++ v ++ " = " ++ b ]
                  (Fun fn [at] rt))
    listRec = do
      et <- scalarTy
      rt <- freq [(2, scalarTy), (1, TList <$> scalarTy)]
      b0 <- genE 5 env0 rt
      v1 <- fresh
      v2 <- fresh
      let envC = addV (v1, et) (addV (v2, TList et) env0)
      bc <- genE 8 (envC { erec = Just (fn, v2, rt) }) rt
      return (Def [ fn ++ " :: [" ++ rTy et ++ "] -> " ++ rTy rt
                  , fn ++ " [] = " ++ b0
                  , fn ++ " (" ++ v1 ++ " : " ++ v2 ++ ") = " ++ bc ]
                  (Fun fn [TList et] rt))
    withWhere = do
      a1 <- scalarTy
      a2 <- anyTy
      rt <- anyTy
      wt <- scalarTy
      v1 <- fresh
      v2 <- fresh
      w  <- fresh
      let envP = addV (v1, a1) (addV (v2, a2) env0)
      we <- genE 6 envP wt
      b  <- genE 8 (addV (w, wt) envP) rt
      return (Def [ fn ++ " :: " ++ rTy a1 ++ " -> " ++ rTy a2
                    ++ " -> " ++ rTy rt
                  , fn ++ " " ++ v1 ++ " " ++ v2 ++ " = " ++ b
                  , "  where " ++ w ++ " :: " ++ rTy wt
                  , "        " ++ w ++ " = " ++ we ]
                  (Fun fn [a1, a2] rt))
    guarded_ = do
      rt <- anyTy
      v  <- fresh
      l  <- rnd 80
      let envP = addV (v, TInt) env0
      e1 <- genE 6 envP rt
      e2 <- genE 6 envP rt
      return (Def [ fn ++ " :: Int -> " ++ rTy rt
                  , fn ++ " " ++ v
                  , "  | (" ++ v ++ " > " ++ show l ++ ") = " ++ e1
                  , "  | otherwise = " ++ e2 ]
                  (Fun fn [TInt] rt))

-- ===== main-line generation =======================================

genMainLine :: Env -> R String
genMainLine env = freq
  [ (8, do t <- anyTy
           e <- genE 8 env t
           return ("  print ((" ++ e ++ ") :: " ++ rTy t ++ ")"))
  , (1, do t <- anyTy
           e <- genE 7 env t
           return ("  putStrLn (show ((" ++ e ++ ") :: "
                   ++ rTy t ++ "))"))
  , (1, freq
      [ (2, do a <- rnd 50
               b <- rnd 50
               c <- rnd 50
               return ("  print (" ++ show a ++ " + " ++ show b
                       ++ " * " ++ show c ++ ")"))
      , (1, do a <- lit TDouble
               b <- lit TDouble
               return ("  print (" ++ a ++ " * " ++ b ++ ")")) ]) ]

-- ===== program assembly ===========================================

program :: Int -> R String
program seed = do
  nDefs <- fmap (3 +) (rnd 3)
  defs  <- goDefs 0 nDefs []
  let funs = map dFun defs
  nMain <- fmap (10 +) (rnd 5)
  ls    <- mapM (const (genMainLine (Env [] funs Nothing)))
                [1 .. nMain]
  return (unlines
    ([ "-- fuzz seed " ++ show seed
     , "import Data.Char (chr, ord, toUpper, toLower, isDigit,"
     , "                  isUpper, digitToInt)"
     , "import Data.List (sort, nub, tails, intercalate, partition,"
     , "                  isPrefixOf)"
     , "import Data.Maybe (isJust, isNothing, fromMaybe, catMaybes,"
     , "                   mapMaybe, listToMaybe)"
     , ""
     , "data E0 = K0 | K1 | K2 | K3"
     , "  deriving (Eq, Ord, Show, Enum, Bounded)"
     , "" ]
     ++ concatMap (\d -> dText d ++ [""]) defs
     ++ [ "main :: IO ()", "main = do" ]
     ++ ls))
  where
    goDefs _ 0 acc = return (reverse acc)
    goDefs i n acc = do
      d <- genDef (map dFun acc) i
      goDefs (i + 1) (n - 1) (d : acc)

main :: IO ()
main = do
  args <- getArgs
  case args of
    [s] -> putStr (fst (runR (program (read s))
                             (toInteger (read s :: Int) * 2654435761
                              + 1, 0)))
    _   -> error "usage: runghc Gen.hs SEED"
