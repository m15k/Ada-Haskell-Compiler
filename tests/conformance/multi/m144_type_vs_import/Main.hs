module Main where
import L
data T = Other Bool deriving Show
f :: T -> Int
f _ = 1
main :: IO ()
main = print (f (Other True))
