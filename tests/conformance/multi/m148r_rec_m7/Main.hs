{-# LANGUAGE RecordWildCards, NamedFieldPuns #-}
module Main where
import qualified A as Q
Q.R{..} = Q.R 1 2
other :: Int
other = ra * 10 + rb
main = print other
