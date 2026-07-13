module Main where

import Data.List (sort)
import qualified Data.Map as M

main :: IO ()
main = print (Data.List.sort [3, 1, 2])  -- trailing comment

f --> g = f . g
compose = (Prelude..)

{- block {- nested -} comment -}
answer = 0x2A
