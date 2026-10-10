{-# LANGUAGE NamedFieldPuns #-}
module Main where
import A
f :: R -> Int
f R{A.ra} = ra
main = print (f (R 1 2))
