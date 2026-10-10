{-# LANGUAGE LambdaCase #-}
-- GHC 9.4.8: \cases alternatives have different numbers of patterns
f :: Int -> Int -> Int
f = \cases
  0 y -> y
  n -> n
main :: IO ()
main = print (f 1 2)
