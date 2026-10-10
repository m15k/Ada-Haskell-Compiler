{-# LANGUAGE RecordWildCards #-}
module Main where
import A (R(R, ra))
rb :: Int
rb = 100
f :: R -> Int
f R{..} = ra + rb
main = print (f (R 1 2))
