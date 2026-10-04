module Main where
import L
helper :: Int -> Int
helper x = x * 2
main :: IO ()
main = print (helper 3)
