{-# LANGUAGE RecordWildCards, NamedFieldPuns #-}
module Main where
import qualified A as Q
f :: Q.R -> Int
f Q.R{Q.ra, ..} = ra * 10 + rb
main = print (f (Q.R 1 2))
