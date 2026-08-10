-- Deliberately the same module name as liba's, to provoke the
-- ambiguity error when both are dependencies at once.
module Data.Greet (greeting) where

greeting :: String -> String
greeting who = "hi, " ++ who
