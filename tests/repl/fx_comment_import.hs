{- a leading comment -}
{-# LANGUAGE ScopedTypeVariables #-}
-- another
module Fx (x) where

{-
import NotThere
-}
import Data.List (sort)

x :: Int
x = length (sort "hello")
