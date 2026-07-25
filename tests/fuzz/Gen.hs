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
        | TShape | TRec | TRational
        | TList Ty | TMaybe Ty | TPair Ty Ty | TEither Ty Ty
  deriving (Eq, Show)

rTy :: Ty -> String
rTy TInt          = "Int"
rTy TInteger      = "Integer"
rTy TDouble       = "Double"
rTy TBool         = "Bool"
rTy TChar         = "Char"
rTy TEnum         = "E0"
rTy TShape        = "S0"
rTy TRec          = "R0"
rTy TRational     = "Rational"
rTy (TList TChar) = "String"
rTy (TList t)     = "[" ++ rTy t ++ "]"
rTy (TMaybe t)    = "(Maybe " ++ rTy t ++ ")"
rTy (TPair a b)   = "(" ++ rTy a ++ ", " ++ rTy b ++ ")"
rTy (TEither a b) = "(Either " ++ rTy a ++ " " ++ rTy b ++ ")"

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
  , (1, TList <$> (TPair <$> scalarTy <*> scalarTy))
  , (2, pure TShape)
  , (2, pure TRec)
  , (2, pure TRational)
  , (1, TEither <$> scalarTy <*> scalarTy) ]

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
               , erec  :: Maybe (String, Ty) }
               -- erec: (name, type) of the LET-BOUND recursive
               -- call. Binding it once and exposing the variable
               -- makes repeated uses SHARE one thunk: the body
               -- stays linear where inlining "(f xs)" at k sites
               -- would be k^depth. Structural termination is not
               -- enough - a 3^n body once pinned three oracle
               -- processes at 100% CPU for six hours (M83).

addV :: (String, Ty) -> Env -> Env
addV p e = e { evars = p : evars e }

varOf :: Env -> Ty -> [String]
varOf env t = [n | (n, t') <- evars env, t' == t]

recOf :: Env -> Ty -> [String]
recOf env t = case erec env of
  Just (v, r) | r == t -> [v]
  _                    -> []

-- ===== literals ===================================================

lit :: Ty -> R String
lit TInt = fmap show (rnd 100)
lit TInteger = freq
  [ (3, fmap show (rnd 1000))
  , (2, do k  <- rnd 16                    -- 15..30 digit bignum
           d0 <- rnd 9
           ds <- mapM (const (rnd 10)) [1 .. 14 + k]
           return (concatMap show (d0 + 1 : ds))) ]
lit TDouble = freq
  [ (3, do a <- rnd 100
           b <- rnd 100
           return (show a ++ "." ++ (if b < 10 then "0" else "")
                   ++ show b))
  , (1, do a <- rnd 100          -- exponent form (M82 exact path)
           b <- rnd 100
           e <- rnd 13
           return (show a ++ "." ++ (if b < 10 then "0" else "")
                   ++ show b ++ "e" ++ (if even e then "-" else "")
                   ++ show (e `div` 2 + 1))) ]
lit TBool = pick ["True", "False"]
lit TChar = fmap show (pick safeChars)
lit TEnum = pick enumCons
lit TShape = freq
  [ (1, return "SP")
  , (2, do e <- lit TInt
           return ("(SC " ++ e ++ ")"))
  , (2, do e <- lit TInt
           c <- lit TChar
           return ("(SR " ++ e ++ " " ++ c ++ ")")) ]
lit TRec = do a <- lit TInt
              b <- lit TChar
              c <- lit TBool
              return ("(MkR0 { r0a = " ++ a ++ ", r0b = " ++ b
                      ++ ", r0c = " ++ c ++ " })")
lit TRational = lit TDouble        -- decimal text; exact by M82
lit (TEither a b) = freq
  [ (1, do e <- lit a
           return ("(Left " ++ e ++ ")"))
  , (1, do e <- lit b
           return ("(Right " ++ e ++ ")")) ]
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
  [ (2, ifE), (2, letE), (2, caseE), (1, seqE) ]
  ++ [ (2, appE f) | f@(Fun _ _ r) <- efuns env, r == t ]
  ++ [ (1, projE) ]
  where
    h = sz `div` 2
    seqE = do st <- scalarTy
              a  <- genE (sz `div` 3) env st
              b  <- genE h env t
              return ("(seq (" ++ a ++ " :: " ++ rTy st ++ ") "
                      ++ b ++ ")")
    ifE = do c <- genE (sz `div` 3) env TBool
             a <- genE h env t
             b <- genE h env t
             return ("(if " ++ c ++ " then " ++ a
                     ++ " else " ++ b ++ ")")
    letE = freq
      [ (3, do v  <- fresh
               vt <- scalarTy
               r  <- genE h env vt
               b  <- genE h (addV (v, vt) env) t
               return ("(let " ++ v ++ " = " ++ r
                       ++ " in " ++ b ++ ")"))
      , (1, do v1 <- fresh
               t1 <- scalarTy
               r1 <- genE (sz `div` 3) env t1
               v2 <- fresh
               t2 <- scalarTy
               r2 <- genE (sz `div` 3) (addV (v1, t1) env) t2
               b  <- genE h (addV (v2, t2)
                              (addV (v1, t1) env)) t
               return ("(let " ++ v1 ++ " = " ++ r1 ++ "; " ++ v2
                       ++ " = " ++ r2 ++ " in " ++ b ++ ")")) ]
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
               return ("(case " ++ s ++ " of { " ++ body ++ " })"))
      , (2, do s  <- genE h env TShape
               e0 <- genE (sz `div` 3) env t
               v1 <- fresh
               e1 <- genE (sz `div` 3) (addV (v1, TInt) env) t
               v2 <- fresh
               v3 <- fresh
               e2 <- genE (sz `div` 3)
                       (addV (v2, TInt) (addV (v3, TChar) env)) t
               return ("(case " ++ s ++ " of { SP -> " ++ e0
                       ++ " ; SC " ++ v1 ++ " -> " ++ e1
                       ++ " ; SR " ++ v2 ++ " " ++ v3 ++ " -> "
                       ++ e2 ++ " })"))
      , (1, do a  <- scalarTy
               b  <- scalarTy
               s  <- genE h env (TEither a b)
               v1 <- fresh
               e1 <- genE h (addV (v1, a) env) t
               v2 <- fresh
               e2 <- genE h (addV (v2, b) env) t
               return ("(case (" ++ s ++ " :: " ++ rTy (TEither a b)
                       ++ ") of { Left " ++ v1 ++ " -> " ++ e1
                       ++ " ; Right " ++ v2 ++ " -> " ++ e2
                       ++ " })")) ]
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
        , (1, do op <- pick ["(+)", "(-)", "max", "min"]
                 z  <- genE s3 env TInt
                 l  <- sub (TList TInt)
                 return ("(foldl' " ++ op ++ " " ++ z ++ " "
                         ++ l ++ ")"))
        , (1, do f  <- pick ["maximum", "minimum"]
                 ne <- nonEmpty TInt
                 return ("(" ++ f ++ " " ++ ne ++ ")"))
        , (1, do c <- sub TChar
                 return ("(ord " ++ c ++ ")"))
        , (1, do r <- sub TRec
                 return ("(r0a " ++ r ++ ")"))
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
                 return ("(toInteger (" ++ e ++ " :: Int))"))
        , (1, do f <- pick ["numerator", "denominator"]
                 r <- sub TRational
                 return ("(" ++ f ++ " (" ++ r
                         ++ " :: Rational))")) ]
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
        , (1, do f <- pick ["sin", "cos"]
                 a <- sub TDouble
                 return ("(" ++ f ++ " " ++ a ++ ")"))
        , (1, do a <- sub TDouble
                 return ("(log ((abs " ++ a ++ ") + 1.0))"))
        , (1, do a <- genE s3 env TDouble
                 return ("(exp (min 20.0 " ++ a ++ "))"))
        , (1, do r <- sub TRational
                 return ("(fromRational (" ++ r
                         ++ " :: Rational))"))
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
                            , (1, TPair <$> scalarTy <*> scalarTy)
                            , (2, pure TShape)
                            , (1, pure TRec)
                            , (2, pure TRational)
                            , (1, TEither <$> scalarTy
                                          <*> scalarTy) ]
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
                 --  Erasure point: isJust drops the element type,
                 --  so a chain like isJust (listToMaybe (sort []))
                 --  is ambiguous without this annotation.
                 return ("(" ++ f ++ " (" ++ m ++ " :: (Maybe "
                         ++ rTy st ++ ")))"))
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
      TShape ->
        [ (3, do e <- sub TInt
                 return ("(SC " ++ e ++ ")"))
        , (2, do e <- sub TInt
                 c <- sub TChar
                 return ("(SR " ++ e ++ " " ++ c ++ ")"))
        , (1, return "SP")
        , (1, do f <- pick ["min", "max"]
                 a <- sub TShape
                 b <- sub TShape
                 return ("(" ++ f ++ " " ++ a ++ " " ++ b ++ ")")) ]
      TRec ->
        [ (3, do a <- sub TInt
                 b <- sub TChar
                 c <- sub TBool
                 return ("(MkR0 { r0a = " ++ a ++ ", r0b = " ++ b
                         ++ ", r0c = " ++ c ++ " })"))
        , (2, do r <- sub TRec
                 a <- sub TInt
                 return ("((" ++ r ++ ") { r0a = " ++ a ++ " })"))
        , (1, do r <- sub TRec
                 b <- sub TChar
                 c <- sub TBool
                 return ("((" ++ r ++ ") { r0b = " ++ b
                         ++ ", r0c = " ++ c ++ " })")) ]
      TRational ->
        [ (3, bin TRational "+"), (2, bin TRational "-")
        , (2, bin TRational "*")
        , (2, do a <- sub TInteger
                 b <- sub TInteger
                 return ("((" ++ a ++ ") % (max 1 (abs ("
                         ++ b ++ "))))"))
        , (1, do a <- sub TRational
                 b <- sub TRational
                 d <- fresh
                 return ("(" ++ a ++ " / (let " ++ d ++ " = " ++ b
                         ++ " in (if (" ++ d ++ " == 0) then 1"
                         ++ " else " ++ d ++ ")))"))
        , (1, do a <- sub TRational
                 v <- fresh
                 return ("(let " ++ v ++ " = " ++ a
                         ++ " in (if (" ++ v ++ " == 0) then 1"
                         ++ " else (recip " ++ v ++ ")))"))
        , (1, unary TRational ["abs", "negate", "signum"]) ]
      TEither a b ->
        [ (2, do e <- sub a
                 return ("(Left " ++ e ++ ")"))
        , (2, do e <- sub b
                 return ("(Right " ++ e ++ ")")) ]
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
    -- The base is CLAMPED: at a magnitude where the step falls
    -- below one ULP, v + step == v, the limit test never fails,
    -- and the range is an infinite list of one value - a program
    -- that hangs both compilers (M83 campaign, seed 2788).
    rangeProds TDouble =
      [ (1, do v    <- fresh
               a    <- genE s3 env TDouble
               step <- pick ["0.25", "0.5", "1.5", "2.0"]
               span_ <- pick ["1.0", "3.0", "4.5"]
               return ("(let " ++ v ++ " = (min 1000.0 (abs ("
                       ++ a ++ "))) in [" ++ v
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
      vr <- fresh
      let envC = addV (v1, et) (addV (v2, TList et) env0)
      bc <- genE 8 (envC { erec = Just (vr, rt) }) rt
      return (Def [ fn ++ " :: [" ++ rTy et ++ "] -> " ++ rTy rt
                  , fn ++ " [] = " ++ b0
                  , fn ++ " (" ++ v1 ++ " : " ++ v2 ++ ") = (let "
                    ++ vr ++ " = " ++ fn ++ " " ++ v2 ++ " in "
                    ++ bc ++ ")" ]
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
     , "                  isPrefixOf, foldl')"
     , "import Data.Maybe (isJust, isNothing, fromMaybe, catMaybes,"
     , "                   mapMaybe, listToMaybe)"
     , "import Data.Ratio ((%), numerator, denominator)"
     , ""
     , "data E0 = K0 | K1 | K2 | K3"
     , "  deriving (Eq, Ord, Show, Enum, Bounded)"
     , "data S0 = SP | SC Int | SR Int Char"
     , "  deriving (Eq, Ord, Show)"
     , "data R0 = MkR0 { r0a :: Int, r0b :: Char, r0c :: Bool }"
     , "  deriving (Eq, Ord, Show)"
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
