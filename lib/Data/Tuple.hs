module Data.Tuple (fst, snd, curry, uncurry, swap) where

swap :: (a, b) -> (b, a)
swap (a, b) = (b, a)
