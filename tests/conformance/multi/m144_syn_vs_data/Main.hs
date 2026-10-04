module Main where
import L
type S = Int
f :: S -> S
f x = x + 1
main :: IO ()
main = print (f 2)
