{-# LANGUAGE BangPatterns #-}
-- GHC 9.4.8: Top-level strict bindings aren't allowed: !x = 3
!x = (3 :: Int)
main :: IO ()
main = print x
