module Lisp.Eval (evalTop, primEnv) where

import Data.Ratio (Rational, (%), numerator, denominator)
import Lisp.Val (Value (..), Env, showVal, displayVal, isTrue)

--  The evaluator is pure: Either String Value everywhere, threaded
--  by hand. Two environments: `g` (globals, shared, grows via
--  define) and `l` (lexical locals, captured by closures). Symbol
--  lookup tries locals then globals-at-call-time, which is what
--  gives top-level mutual recursion and REPL redefinition their
--  Scheme semantics without any mutation.

--  Top level: define extends the globals; anything else evaluates.
evalTop :: Env -> Value -> Either String (Env, Value)
evalTop g (VList (VSym "define" : rest)) =
  case rest of
    [VSym name, e] ->
      case eval g [] e of
        Left err -> Left err
        Right v -> Right ((name, v) : g, VUnit)
    (VList (VSym name : params) : body) ->
      case paramNames params of
        Left err -> Left err
        Right ps ->
          if null body
            then Left "define: empty body"
            else Right ((name, VClosure ps body []) : g, VUnit)
    _ -> Left "define: bad form"
evalTop g e =
  case eval g [] e of
    Left err -> Left err
    Right v -> Right (g, v)

paramNames :: [Value] -> Either String [String]
paramNames [] = Right []
paramNames (VSym s : rest) =
  case paramNames rest of
    Left err -> Left err
    Right ss -> Right (s : ss)
paramNames _ = Left "bad parameter list"

eval :: Env -> Env -> Value -> Either String Value
eval _ _ v@(VInt _) = Right v
eval _ _ v@(VRat _) = Right v
eval _ _ v@(VDbl _) = Right v
eval _ _ v@(VBool _) = Right v
eval _ _ v@(VStr _) = Right v
eval g l (VSym s) =
  case lookup s l of
    Just v -> Right v
    Nothing ->
      case lookup s g of
        Just v -> Right v
        Nothing -> Left ("unbound variable: " ++ s)
eval g l (VList (VSym "quote" : rest)) =
  case rest of
    [v] -> Right v
    _ -> Left "quote: bad form"
eval g l (VList (VSym "if" : rest)) =
  case rest of
    [c, t] -> evalIf g l c t VUnit
    [c, t, e] -> evalIf g l c t e
    _ -> Left "if: bad form"
eval g l (VList (VSym "lambda" : rest)) =
  case rest of
    (VList params : body) ->
      case paramNames params of
        Left err -> Left err
        Right ps ->
          if null body
            then Left "lambda: empty body"
            else Right (VClosure ps body l)
    _ -> Left "lambda: bad form"
eval g l (VList (VSym "let" : rest)) =
  case rest of
    (VList binds : body) -> evalLet g l binds [] body
    _ -> Left "let: bad form"
eval g l (VList (VSym "let*" : rest)) =
  case rest of
    (VList binds : body) -> evalLetStar g l binds body
    _ -> Left "let*: bad form"
eval g l (VList (VSym "letrec" : rest)) =
  case rest of
    (VList binds : body) -> evalLetrec g l binds body
    _ -> Left "letrec: bad form"
eval g l (VList (VSym "begin" : body)) =
  if null body then Left "begin: empty body" else evalBody g l body
eval g l (VList (VSym "cond" : clauses)) = evalCond g l clauses
eval g l (VList (VSym "and" : args)) = evalAnd g l args (VBool True)
eval g l (VList (VSym "or" : args)) = evalOr g l args
eval g l (VList (f : args)) =
  case eval g l f of
    Left err -> Left err
    Right fv ->
      case evalArgs g l args of
        Left err -> Left err
        Right avs -> apply g fv avs
eval _ _ (VList []) = Left "cannot evaluate ()"
eval _ _ (VClosure _ _ _) = Left "cannot evaluate a closure literal"
eval _ _ (VPrim _) = Left "cannot evaluate a primitive literal"
eval _ _ VUnit = Right VUnit

evalIf :: Env -> Env -> Value -> Value -> Value -> Either String Value
evalIf g l c t e =
  case eval g l c of
    Left err -> Left err
    Right cv -> if isTrue cv then eval g l t else eval g l e

--  let: all right-hand sides evaluate in the outer scope.
evalLet :: Env -> Env -> [Value] -> Env -> [Value] -> Either String Value
evalLet g l [] acc body = evalBody g (reverse acc ++ l) body
evalLet g l (VList [VSym n, e] : rest) acc body =
  case eval g l e of
    Left err -> Left err
    Right v -> evalLet g l rest ((n, v) : acc) body
evalLet _ _ _ _ _ = Left "let: bad binding"

--  let*: each binding sees the previous ones.
evalLetStar :: Env -> Env -> [Value] -> [Value] -> Either String Value
evalLetStar g l [] body = evalBody g l body
evalLetStar g l (VList [VSym n, e] : rest) body =
  case eval g l e of
    Left err -> Left err
    Right v -> evalLetStar g ((n, v) : l) rest body
evalLetStar _ _ _ _ = Left "let*: bad binding"

--  letrec: right-hand sides must be lambdas; the closures capture
--  an environment that includes themselves. The knot is tied by
--  laziness - l' is defined in terms of the closures and the
--  closures capture l' - which call-by-need evaluates happily.
evalLetrec :: Env -> Env -> [Value] -> [Value] -> Either String Value
evalLetrec g l binds body =
  case letrecBinds binds of
    Left err -> Left err
    Right pairs ->
      let l' = map (\p -> (fst p, close (snd p))) pairs ++ l
          close lam =
            case lam of
              VList (VSym "lambda" : VList params : lamBody) ->
                case paramNames params of
                  Right ps -> VClosure ps lamBody l'
                  Left _ -> VUnit
              _ -> VUnit
      in evalBody g l' body

letrecBinds :: [Value] -> Either String [(String, Value)]
letrecBinds [] = Right []
letrecBinds (VList [VSym n, lam] : rest) =
  case lam of
    VList (VSym "lambda" : VList params : lamBody) ->
      case paramNames params of
        Left err -> Left err
        Right _ ->
          if null lamBody
            then Left "letrec: empty lambda body"
            else
              case letrecBinds rest of
                Left err -> Left err
                Right ps -> Right ((n, lam) : ps)
    _ -> Left "letrec: right-hand sides must be lambdas"
letrecBinds _ = Left "letrec: bad binding"

evalBody :: Env -> Env -> [Value] -> Either String Value
evalBody _ _ [] = Left "empty body"
evalBody g l [e] = eval g l e
evalBody g l (e : rest) =
  case eval g l e of
    Left err -> Left err
    Right _ -> evalBody g l rest

evalCond :: Env -> Env -> [Value] -> Either String Value
evalCond _ _ [] = Right VUnit
evalCond g l (VList (VSym "else" : body) : _) =
  if null body then Left "cond: empty else" else evalBody g l body
evalCond g l (VList (test : body) : rest) =
  case eval g l test of
    Left err -> Left err
    Right tv ->
      if isTrue tv
        then if null body then Right tv else evalBody g l body
        else evalCond g l rest
evalCond _ _ _ = Left "cond: bad clause"

evalAnd :: Env -> Env -> [Value] -> Value -> Either String Value
evalAnd _ _ [] lastV = Right lastV
evalAnd g l (e : rest) _ =
  case eval g l e of
    Left err -> Left err
    Right v -> if isTrue v then evalAnd g l rest v else Right v

evalOr :: Env -> Env -> [Value] -> Either String Value
evalOr _ _ [] = Right (VBool False)
evalOr g l (e : rest) =
  case eval g l e of
    Left err -> Left err
    Right v -> if isTrue v then Right v else evalOr g l rest

evalArgs :: Env -> Env -> [Value] -> Either String [Value]
evalArgs _ _ [] = Right []
evalArgs g l (e : rest) =
  case eval g l e of
    Left err -> Left err
    Right v ->
      case evalArgs g l rest of
        Left err -> Left err
        Right vs -> Right (v : vs)

apply :: Env -> Value -> [Value] -> Either String Value
apply g (VClosure ps body cl) args =
  if length ps /= length args
    then
      Left ("arity mismatch: expected " ++ show (length ps)
              ++ " arguments, got " ++ show (length args))
    else evalBody g (zip ps args ++ cl) body
apply g (VPrim name) args = applyPrim g name args
apply _ v _ = Left ("not a procedure: " ++ showVal v)

--  ---------------------------------------------------------------
--  Primitives. VPrim carries only the name; dispatch happens here.

primEnv :: Env
primEnv = map (\n -> (n, VPrim n)) primNames

primNames :: [String]
primNames =
  [ "+", "-", "*", "/", "quotient", "remainder", "modulo"
  , "abs", "min", "max", "expt", "sqrt", "numerator", "denominator"
  , "exact->inexact"
  , "=", "<", ">", "<=", ">=", "zero?", "positive?", "negative?"
  , "car", "cdr", "cons", "list", "append", "length", "reverse"
  , "null?", "pair?", "list?"
  , "number?", "integer?", "rational?", "real?", "symbol?"
  , "string?", "boolean?", "procedure?"
  , "eq?", "equal?", "not"
  , "string-append", "string-length", "number->string"
  , "symbol->string", "string->symbol"
  , "error"
  , "apply"
  ]

applyPrim :: Env -> String -> [Value] -> Either String Value
applyPrim _ "+" args = numFold addNum (VInt 0) args
applyPrim _ "*" args = numFold mulNum (VInt 1) args
applyPrim _ "-" args =
  case args of
    [] -> Left "-: needs at least one argument"
    [x] -> numBin subNum (VInt 0) x
    (x : rest) -> numFold subNum x rest
applyPrim _ "/" args =
  case args of
    [] -> Left "/: needs at least one argument"
    [x] -> divNum (VInt 1) x
    (x : rest) -> foldDiv x rest
applyPrim _ "quotient" [a, b] = intBin "quotient" quot2 a b
applyPrim _ "remainder" [a, b] = intBin "remainder" rem2 a b
applyPrim _ "modulo" [a, b] = intBin "modulo" mod2 a b
applyPrim _ "abs" [v] = numUnary "abs" absNum v
applyPrim _ "min" args = numReduce "min" minNum args
applyPrim _ "max" args = numReduce "max" maxNum args
applyPrim _ "expt" [a, b] = exptNum a b
applyPrim _ "sqrt" [v] =
  case toDouble v of
    Just d ->
      if d < 0.0
        then Left "sqrt: negative argument"
        else Right (VDbl (sqrt d))
    Nothing -> Left "sqrt: not a number"
applyPrim _ "numerator" [VInt n] = Right (VInt n)
applyPrim _ "numerator" [VRat r] = Right (VInt (numerator r))
applyPrim _ "numerator" [_] = Left "numerator: not an exact number"
applyPrim _ "denominator" [VInt _] = Right (VInt 1)
applyPrim _ "denominator" [VRat r] = Right (VInt (denominator r))
applyPrim _ "denominator" [_] = Left "denominator: not an exact number"
applyPrim _ "exact->inexact" [v] =
  case toDouble v of
    Just d -> Right (VDbl d)
    Nothing -> Left "exact->inexact: not a number"
applyPrim _ "=" args = compareChain "=" isOrdEq args
applyPrim _ "<" args = compareChain "<" isOrdLt args
applyPrim _ ">" args = compareChain ">" isOrdGt args
applyPrim _ "<=" args = compareChain "<=" notOrdGt args
applyPrim _ ">=" args = compareChain ">=" notOrdLt args
applyPrim _ "zero?" [v] = numPred isOrdEq v
applyPrim _ "positive?" [v] = numPred isOrdGt v
applyPrim _ "negative?" [v] = numPred isOrdLt v
applyPrim _ "car" [VList (x : _)] = Right x
applyPrim _ "car" [v] = Left ("car: not a pair: " ++ showVal v)
applyPrim _ "cdr" [VList (_ : xs)] = Right (VList xs)
applyPrim _ "cdr" [v] = Left ("cdr: not a pair: " ++ showVal v)
applyPrim _ "cons" [x, VList xs] = Right (VList (x : xs))
applyPrim _ "cons" [_, v] =
  Left ("cons: second argument must be a list: " ++ showVal v)
applyPrim _ "list" args = Right (VList args)
applyPrim _ "append" args = appendLists args []
applyPrim _ "length" [VList xs] = Right (VInt (intLen xs))
applyPrim _ "length" [v] = Left ("length: not a list: " ++ showVal v)
applyPrim _ "reverse" [VList xs] = Right (VList (reverse xs))
applyPrim _ "reverse" [v] = Left ("reverse: not a list: " ++ showVal v)
applyPrim _ "null?" [VList []] = Right (VBool True)
applyPrim _ "null?" [_] = Right (VBool False)
applyPrim _ "pair?" [VList (_ : _)] = Right (VBool True)
applyPrim _ "pair?" [_] = Right (VBool False)
applyPrim _ "list?" [VList _] = Right (VBool True)
applyPrim _ "list?" [_] = Right (VBool False)
applyPrim _ "number?" [v] = Right (VBool (isNumber v))
applyPrim _ "integer?" [VInt _] = Right (VBool True)
applyPrim _ "integer?" [_] = Right (VBool False)
applyPrim _ "rational?" [VInt _] = Right (VBool True)
applyPrim _ "rational?" [VRat _] = Right (VBool True)
applyPrim _ "rational?" [_] = Right (VBool False)
applyPrim _ "real?" [v] = Right (VBool (isNumber v))
applyPrim _ "symbol?" [VSym _] = Right (VBool True)
applyPrim _ "symbol?" [_] = Right (VBool False)
applyPrim _ "string?" [VStr _] = Right (VBool True)
applyPrim _ "string?" [_] = Right (VBool False)
applyPrim _ "boolean?" [VBool _] = Right (VBool True)
applyPrim _ "boolean?" [_] = Right (VBool False)
applyPrim _ "procedure?" [VClosure _ _ _] = Right (VBool True)
applyPrim _ "procedure?" [VPrim _] = Right (VBool True)
applyPrim _ "procedure?" [_] = Right (VBool False)
applyPrim _ "eq?" [a, b] = Right (VBool (eqAtom a b))
applyPrim _ "equal?" [a, b] = Right (VBool (equalVal a b))
applyPrim _ "not" [v] = Right (VBool (not (isTrue v)))
applyPrim _ "string-append" args = stringAppend args []
applyPrim _ "string-length" [VStr s] = Right (VInt (intLen s))
applyPrim _ "string-length" [v] =
  Left ("string-length: not a string: " ++ showVal v)
applyPrim _ "number->string" [v] =
  if isNumber v
    then Right (VStr (showVal v))
    else Left "number->string: not a number"
applyPrim _ "symbol->string" [VSym s] = Right (VStr s)
applyPrim _ "symbol->string" [_] = Left "symbol->string: not a symbol"
applyPrim _ "string->symbol" [VStr s] = Right (VSym s)
applyPrim _ "string->symbol" [_] = Left "string->symbol: not a string"
applyPrim _ "error" args =
  Left (unwords (map displayVal args))
applyPrim g "apply" [f, VList args] = apply g f args
applyPrim _ "apply" _ = Left "apply: expects a procedure and a list"
applyPrim _ name _ = Left (name ++ ": bad arguments")

intLen :: [a] -> Integer
intLen [] = 0
intLen (_ : xs) = 1 + intLen xs

isNumber :: Value -> Bool
isNumber (VInt _) = True
isNumber (VRat _) = True
isNumber (VDbl _) = True
isNumber _ = False

appendLists :: [Value] -> [Value] -> Either String Value
appendLists [] acc = Right (VList acc)
appendLists (VList xs : rest) acc = appendLists rest (acc ++ xs)
appendLists (v : _) _ = Left ("append: not a list: " ++ showVal v)

stringAppend :: [Value] -> String -> Either String Value
stringAppend [] acc = Right (VStr acc)
stringAppend (VStr s : rest) acc = stringAppend rest (acc ++ s)
stringAppend (v : _) _ =
  Left ("string-append: not a string: " ++ showVal v)

--  eq?: variant-identical atoms; empty lists. Everything else #f.
eqAtom :: Value -> Value -> Bool
eqAtom (VInt a) (VInt b) = a == b
eqAtom (VRat a) (VRat b) = a == b
eqAtom (VBool a) (VBool b) = a == b
eqAtom (VSym a) (VSym b) = a == b
eqAtom (VStr a) (VStr b) = a == b
eqAtom (VList []) (VList []) = True
eqAtom _ _ = False

--  equal?: deep structural equality; numbers compare exactly
--  within the same exactness class, doubles only with doubles.
equalVal :: Value -> Value -> Bool
equalVal (VDbl a) (VDbl b) = a == b
equalVal (VList as) (VList bs) = equalLists as bs
equalVal a b = eqAtom a b

equalLists :: [Value] -> [Value] -> Bool
equalLists [] [] = True
equalLists (a : as) (b : bs) = equalVal a b && equalLists as bs
equalLists _ _ = False

--  ---------------------------------------------------------------
--  The numeric tower: Integer < Rational < Double. Operands promote
--  to the wider representation; exact results demote to VInt when
--  the denominator is 1.

data NumPair
  = NInts Integer Integer
  | NRats Rational Rational
  | NDbls Double Double

promote :: Value -> Value -> Maybe NumPair
promote (VInt a) (VInt b) = Just (NInts a b)
promote (VInt a) (VRat b) = Just (NRats (a % 1) b)
promote (VRat a) (VInt b) = Just (NRats a (b % 1))
promote (VRat a) (VRat b) = Just (NRats a b)
promote a b =
  case toDouble a of
    Nothing -> Nothing
    Just da ->
      case toDouble b of
        Nothing -> Nothing
        Just db ->
          if isDouble a || isDouble b
            then Just (NDbls da db)
            else Nothing

isDouble :: Value -> Bool
isDouble (VDbl _) = True
isDouble _ = False

toDouble :: Value -> Maybe Double
toDouble (VInt n) = Just (fromInteger n)
toDouble (VRat r) =
  Just (fromInteger (numerator r) / fromInteger (denominator r))
toDouble (VDbl d) = Just d
toDouble _ = Nothing

ratValue :: Rational -> Value
ratValue r = if denominator r == 1 then VInt (numerator r) else VRat r

addNum :: NumPair -> Either String Value
addNum (NInts a b) = Right (VInt (a + b))
addNum (NRats a b) = Right (ratValue (a + b))
addNum (NDbls a b) = Right (VDbl (a + b))

subNum :: NumPair -> Either String Value
subNum (NInts a b) = Right (VInt (a - b))
subNum (NRats a b) = Right (ratValue (a - b))
subNum (NDbls a b) = Right (VDbl (a - b))

mulNum :: NumPair -> Either String Value
mulNum (NInts a b) = Right (VInt (a * b))
mulNum (NRats a b) = Right (ratValue (a * b))
mulNum (NDbls a b) = Right (VDbl (a * b))

minNum :: NumPair -> Either String Value
minNum (NInts a b) = Right (VInt (if a <= b then a else b))
minNum (NRats a b) = Right (ratValue (if a <= b then a else b))
minNum (NDbls a b) = Right (VDbl (if a <= b then a else b))

maxNum :: NumPair -> Either String Value
maxNum (NInts a b) = Right (VInt (if a >= b then a else b))
maxNum (NRats a b) = Right (ratValue (if a >= b then a else b))
maxNum (NDbls a b) = Right (VDbl (if a >= b then a else b))

numBin :: (NumPair -> Either String Value) -> Value -> Value
       -> Either String Value
numBin op a b =
  case promote a b of
    Just p -> op p
    Nothing -> Left "arithmetic on a non-number"

numFold :: (NumPair -> Either String Value) -> Value -> [Value]
        -> Either String Value
numFold _ acc [] = Right acc
numFold op acc (v : rest) =
  case numBin op acc v of
    Left err -> Left err
    Right acc' -> numFold op acc' rest

numReduce :: String -> (NumPair -> Either String Value) -> [Value]
          -> Either String Value
numReduce name _ [] = Left (name ++ ": needs at least one argument")
numReduce _ op (v : rest) = numFold op v rest

numUnary :: String -> (Value -> Maybe Value) -> Value
         -> Either String Value
numUnary name f v =
  case f v of
    Just r -> Right r
    Nothing -> Left (name ++ ": not a number")

absNum :: Value -> Maybe Value
absNum (VInt n) = Just (VInt (abs n))
absNum (VRat r) = Just (ratValue (abs r))
absNum (VDbl d) = Just (VDbl (abs d))
absNum _ = Nothing

--  Division: exact stays exact (an Integer result demotes), any
--  Double operand makes it Double. Zero divisors error in both
--  worlds - no Infinity, so output never depends on IEEE corners.
divNum :: Value -> Value -> Either String Value
divNum a b =
  case promote a b of
    Nothing -> Left "arithmetic on a non-number"
    Just (NInts x y) ->
      if y == 0 then Left "division by zero"
                else Right (ratValue ((x % 1) / (y % 1)))
    Just (NRats x y) ->
      if y == 0 % 1 then Left "division by zero"
                    else Right (ratValue (x / y))
    Just (NDbls x y) ->
      if y == 0.0 then Left "division by zero"
                  else Right (VDbl (x / y))

foldDiv :: Value -> [Value] -> Either String Value
foldDiv acc [] = Right acc
foldDiv acc (v : rest) =
  case divNum acc v of
    Left err -> Left err
    Right acc' -> foldDiv acc' rest

intBin :: String -> (Integer -> Integer -> Integer) -> Value -> Value
       -> Either String Value
intBin name f (VInt a) (VInt b) =
  if b == 0
    then Left (name ++ ": division by zero")
    else Right (VInt (f a b))
intBin name _ _ _ = Left (name ++ ": integer arguments required")

quot2 :: Integer -> Integer -> Integer
quot2 a b = quot a b

rem2 :: Integer -> Integer -> Integer
rem2 a b = rem a b

mod2 :: Integer -> Integer -> Integer
mod2 a b = mod a b

--  expt: exact for integer base and non-negative integer exponent
--  (bignum shines here); Double via ** otherwise.
exptNum :: Value -> Value -> Either String Value
exptNum (VInt a) (VInt b) =
  if b >= 0
    then Right (VInt (powInt a b))
    else divNum (VInt 1) (VInt (powInt a (negate b)))
exptNum a b =
  case toDouble a of
    Nothing -> Left "expt: not a number"
    Just da ->
      case toDouble b of
        Nothing -> Left "expt: not a number"
        Just db -> Right (VDbl (da ** db))

powInt :: Integer -> Integer -> Integer
powInt _ 0 = 1
powInt a n =
  let h = powInt a (quot n 2)
      s = h * h
  in if rem n 2 == 0 then s else s * a

isOrdEq :: Ordering -> Bool
isOrdEq EQ = True
isOrdEq _ = False

isOrdLt :: Ordering -> Bool
isOrdLt LT = True
isOrdLt _ = False

isOrdGt :: Ordering -> Bool
isOrdGt GT = True
isOrdGt _ = False

notOrdGt :: Ordering -> Bool
notOrdGt o = not (isOrdGt o)

notOrdLt :: Ordering -> Bool
notOrdLt o = not (isOrdLt o)

compareNum :: Value -> Value -> Maybe Ordering
compareNum a b =
  case promote a b of
    Just (NInts x y) -> Just (compare x y)
    Just (NRats x y) -> Just (compare x y)
    Just (NDbls x y) -> Just (compare x y)
    Nothing -> Nothing

compareChain :: String -> (Ordering -> Bool) -> [Value]
             -> Either String Value
compareChain name _ [] = Left (name ++ ": needs arguments")
compareChain name ok (v0 : vs) = chain v0 vs
  where
    chain _ [] = Right (VBool True)
    chain a (b : rest) =
      case compareNum a b of
        Nothing -> Left (name ++ ": not a number")
        Just o -> if ok o then chain b rest else Right (VBool False)

numPred :: (Ordering -> Bool) -> Value -> Either String Value
numPred ok v =
  case compareNum v (VInt 0) of
    Just o -> Right (VBool (ok o))
    Nothing -> Left "not a number"
