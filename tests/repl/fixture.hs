module Fixture (grid, area) where

import Data.List (intercalate)

area :: Int -> Int -> Int
area w h = w * h

grid :: Int -> String
grid n = intercalate "\n" (replicate n (replicate n '*'))

main :: IO ()
main = putStrLn (grid 3)
