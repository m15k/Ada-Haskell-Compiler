module Main where

import Data.Greet (greeting)

main :: IO ()
main = putStrLn (greeting "packages")
