-- GHC 9.4.8: illegal .. in a record update
{-# LANGUAGE RecordWildCards #-}
data P = P { px :: Int } deriving Show
f :: P -> Int -> P
f p px = p { .. }
main :: IO ()
main = print (f (P 1) 2)
