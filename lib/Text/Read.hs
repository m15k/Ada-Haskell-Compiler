module Text.Read (Read (..), reads, read) where

import Data.Char (isAlphaNum, isDigit, isSpace)

--  The Report's Read, as an ordinary source class (readsPrec only;
--  readList via the default-free list instance below).
class Read a where
  readsPrec :: Int -> String -> [(a, String)]

reads :: Read a => String -> [(a, String)]
reads s = readsPrec 0 s

read :: Read a => String -> a
read s =
  case [x | (x, t) <- reads s, all isSpace t] of
    [x] -> x
    _   -> error "Prelude.read: no parse"

--  Derived-Read support (bound by the compiler for
--  deriving Read on enumerations): match one maximal identifier
--  token against the constructor table.
readsEnum_ :: [(String, a)] -> Int -> String -> [(a, String)]
readsEnum_ table _ s =
  case span isIdChar_ (dropWhile isSpace s) of
    (tok, rest) -> [ (v, rest) | (nm, v) <- table, nm == tok ]

isIdChar_ :: Char -> Bool
isIdChar_ c = isAlphaNum c || c == '\''

skipSpace :: String -> String
skipSpace = dropWhile isSpace

--  Integers: optional parenthesized negative, per the Report's lex.
readsInteger :: String -> [(Integer, String)]
readsInteger s0 =
  case skipSpace s0 of
    ('-' : t) -> [(negate n, r) | (n, r) <- readsNat t]
    ('(' : t) ->
      [ (n, r2)
      | (n, r) <- readsInteger t
      , (')' : r2) <- [skipSpace r]
      ]
    t -> readsNat t

readsNat :: String -> [(Integer, String)]
readsNat s =
  case span isDigit s of
    ([], _)     -> []
    (digits, r) ->
      [(foldl (\a c -> a * 10 + digitVal c) 0 digits, r)]

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
digitVal _   = error "Read.digitVal: not a digit"

instance Read Integer where
  readsPrec _ s = readsInteger s

instance Read Int where
  readsPrec _ s =
    [(integerToInt n, r) | (n, r) <- readsInteger s]

integerToInt :: Integer -> Int
integerToInt n = fromInteger n

instance Read Bool where
  readsPrec _ s =
    case skipSpace s of
      ('T' : 'r' : 'u' : 'e' : r) -> [(True, r)]
      ('F' : 'a' : 'l' : 's' : 'e' : r) -> [(False, r)]
      _ -> []

instance Read a => Read [a] where
  readsPrec _ s =
    case skipSpace s of
      ('[' : t) ->
        case skipSpace t of
          (']' : r) -> [([], r)]
          _         -> readItems t
      _ -> []
    where
      readItems u =
        [ (x : xs, r2)
        | (x, r) <- readsPrec 0 u
        , (xs, r2) <- readRest (skipSpace r)
        ]
      readRest (',' : u) = readItems u
      readRest (']' : u) = [([], u)]
      readRest _ = []

instance (Read a, Read b) => Read (a, b) where
  readsPrec _ s =
    case skipSpace s of
      ('(' : t) ->
        [ ((x, y), r4)
        | (x, r) <- readsPrec 0 t
        , (',' : r2) <- [skipSpace r]
        , (y, r3) <- readsPrec 0 r2
        , (')' : r4) <- [skipSpace r3]
        ]
      _ -> []
