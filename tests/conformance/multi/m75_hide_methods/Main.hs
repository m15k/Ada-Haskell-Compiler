module Main where
import L hiding (C(..))
main :: IO ()
main = putStrLn (c (1::Int))
