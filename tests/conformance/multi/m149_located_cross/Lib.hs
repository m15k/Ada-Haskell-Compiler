module Lib (firstOf, failNow) where

-- M149: failures raised from a second module carry that module's file
-- and name in GHC's call stack ("in main:Lib").
firstOf :: [Int] -> Int
firstOf xs = head xs

failNow :: String -> Int
failNow why = error ("Lib refused: " ++ why)
