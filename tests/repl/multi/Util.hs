module Util (double, Color(..), label) where
double :: Int -> Int
double x = x * 2
data Color = Red | Green deriving (Show, Eq)
label :: Color -> String
label Red = "red"
label Green = "green"
