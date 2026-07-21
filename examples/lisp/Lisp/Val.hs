module Lisp.Val
  ( Value (..), Env
  , showVal, displayVal, isTrue
  ) where

import Data.Ratio (Rational, numerator, denominator)

--  One Value type serves as both the parsed S-expression and the
--  evaluated result: code is data. Closures capture only their
--  lexical locals; free variables resolve against the global
--  environment at call time (Scheme top-level semantics, and what
--  makes mutual recursion work with pure environments).
data Value
  = VInt Integer
  | VRat Rational
  | VDbl Double
  | VBool Bool
  | VStr String
  | VSym String
  | VList [Value]
  | VClosure [String] [Value] Env
  | VPrim String
  | VUnit

type Env = [(String, Value)]

--  write-style printing: strings come out quoted.
showVal :: Value -> String
showVal (VInt n) = show n
showVal (VRat r) = show (numerator r) ++ "/" ++ show (denominator r)
showVal (VDbl d) = show d
showVal (VBool True) = "#t"
showVal (VBool False) = "#f"
showVal (VStr s) = "\"" ++ escape s ++ "\""
showVal (VSym s) = s
showVal (VList vs) = "(" ++ unwords (map showVal vs) ++ ")"
showVal (VClosure _ _ _) = "#<closure>"
showVal (VPrim n) = "#<primitive:" ++ n ++ ">"
showVal VUnit = "#<unspecified>"

--  display-style printing: strings come out raw.
displayVal :: Value -> String
displayVal (VStr s) = s
displayVal (VList vs) = "(" ++ unwords (map displayVal vs) ++ ")"
displayVal v = showVal v

escape :: String -> String
escape [] = []
escape (c : cs)
  | c == '"' = '\\' : '"' : escape cs
  | c == '\\' = '\\' : '\\' : escape cs
  | c == '\n' = '\\' : 'n' : escape cs
  | otherwise = c : escape cs

--  Scheme truth: everything is true except #f.
isTrue :: Value -> Bool
isTrue (VBool False) = False
isTrue _ = True
