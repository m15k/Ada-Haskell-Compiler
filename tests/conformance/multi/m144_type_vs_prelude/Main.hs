module Main where
data Maybe a = Nada | Algo a deriving Show
x :: Maybe Int
x = Algo 3
main :: IO ()
main = print x
