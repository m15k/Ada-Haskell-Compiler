module Lisp.Parser (parseForms) where

import Data.Char (isDigit, isSpace)
import Data.Ratio ((%), numerator, denominator)
import Lisp.Val (Value (..))

--  Tokens: parens, quote sugar, atoms, string literals.
data Token = TOpen | TClose | TQuote | TAtom String | TStr String

--  Errors are threaded by hand (case on Either) throughout: AHC's
--  Monad covers IO, [] and Maybe, not Either - and the explicit
--  style runs identically under GHC.

tokenize :: String -> Either String [Token]
tokenize [] = Right []
tokenize (c : cs)
  | isSpace c = tokenize cs
  | c == ';' = tokenize (dropWhile (\x -> x /= '\n') cs)
  | c == '(' = consToken TOpen (tokenize cs)
  | c == ')' = consToken TClose (tokenize cs)
  | c == '\'' = consToken TQuote (tokenize cs)
  | c == '"' = tokenizeStr cs []
  | otherwise =
      case span isAtomChar (c : cs) of
        (atom, rest) -> consToken (TAtom atom) (tokenize rest)

consToken :: Token -> Either String [Token] -> Either String [Token]
consToken _ (Left e) = Left e
consToken t (Right ts) = Right (t : ts)

isAtomChar :: Char -> Bool
isAtomChar c =
  not (isSpace c) && c /= '(' && c /= ')' && c /= '"'
    && c /= '\'' && c /= ';'

--  String literal body; acc holds the reversed prefix.
tokenizeStr :: String -> String -> Either String [Token]
tokenizeStr [] _ = Left "unterminated string"
tokenizeStr (c : cs) acc
  | c == '"' = consToken (TStr (reverse acc)) (tokenize cs)
  | c == '\\' =
      case cs of
        ('n' : cs') -> tokenizeStr cs' ('\n' : acc)
        ('"' : cs') -> tokenizeStr cs' ('"' : acc)
        ('\\' : cs') -> tokenizeStr cs' ('\\' : acc)
        _ -> Left "bad escape in string"
  | otherwise = tokenizeStr cs (c : acc)

--  An atom becomes a boolean, a number, or a symbol. Numbers are
--  parsed by hand (identical arithmetic under GHC and AHC): integer
--  digits, n/d exact rationals, and d.d doubles built as
--  intpart + fracpart / 10^k.
atomValue :: String -> Value
atomValue "#t" = VBool True
atomValue "#f" = VBool False
atomValue s =
  case numberValue s of
    Just v -> v
    Nothing -> VSym s

numberValue :: String -> Maybe Value
numberValue ('-' : s) =
  case nonNegNumber s of
    Just v -> Just (negateNum v)
    Nothing -> Nothing
numberValue s = nonNegNumber s

nonNegNumber :: String -> Maybe Value
nonNegNumber s =
  case span isDigit s of
    ([], _) -> Nothing
    (ds, []) -> Just (VInt (digitsVal ds))
    (ds, '/' : rest) ->
      case span isDigit rest of
        (es, []) ->
          if null es || digitsVal es == 0
            then Nothing
            else Just (ratOrInt (digitsVal ds) (digitsVal es))
        _ -> Nothing
    (ds, '.' : rest) ->
      case span isDigit rest of
        (es, []) ->
          if null es
            then Nothing
            else Just (VDbl (mkDouble (digitsVal ds) es))
        _ -> Nothing
    _ -> Nothing

negateNum :: Value -> Value
negateNum (VInt n) = VInt (negate n)
negateNum (VRat r) = VRat (negate r)
negateNum (VDbl d) = VDbl (negate d)
negateNum v = v

ratOrInt :: Integer -> Integer -> Value
ratOrInt n d =
  let r = n % d
  in if denominator r == 1 then VInt (numerator r) else VRat r

digitsVal :: String -> Integer
digitsVal = foldl (\a c -> a * 10 + digitVal c) 0

digitVal :: Char -> Integer
digitVal '0' = 0
digitVal '1' = 1
digitVal '2' = 2
digitVal '3' = 3
digitVal '4' = 4
digitVal '5' = 5
digitVal '6' = 6
digitVal '7' = 7
digitVal '8' = 8
digitVal '9' = 9
digitVal _ = 0

mkDouble :: Integer -> String -> Double
mkDouble ip fracDigits =
  fromInteger ip
    + fromInteger (digitsVal fracDigits) / fromInteger (powTen (length fracDigits))

powTen :: Int -> Integer
powTen n = if n <= 0 then 1 else 10 * powTen (n - 1)

--  Parse a whole source text into top-level forms.
parseForms :: String -> Either String [Value]
parseForms src =
  case tokenize src of
    Left e -> Left e
    Right ts -> parseAll ts

parseAll :: [Token] -> Either String [Value]
parseAll [] = Right []
parseAll ts =
  case parseForm ts of
    Left e -> Left e
    Right (v, rest) ->
      case parseAll rest of
        Left e -> Left e
        Right vs -> Right (v : vs)

--  "unclosed '('" is matched by the REPL to detect a form continued
--  on the next line; keep the message stable.
parseForm :: [Token] -> Either String (Value, [Token])
parseForm [] = Left "unclosed '('"
parseForm (TAtom a : ts) = Right (atomValue a, ts)
parseForm (TStr s : ts) = Right (VStr s, ts)
parseForm (TQuote : ts) =
  case parseForm ts of
    Left e -> Left e
    Right (v, rest) -> Right (VList [VSym "quote", v], rest)
parseForm (TOpen : ts) = parseList ts []
parseForm (TClose : _) = Left "unexpected ')'"

parseList :: [Token] -> [Value] -> Either String (Value, [Token])
parseList [] _ = Left "unclosed '('"
parseList (TClose : ts) acc = Right (VList (reverse acc), ts)
parseList ts acc =
  case parseForm ts of
    Left e -> Left e
    Right (v, rest) -> parseList rest (v : acc)
