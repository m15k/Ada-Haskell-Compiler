{-# LANGUAGE GeneralizedNewtypeDeriving #-}
-- GHC 9.4.8: No instance for (Num (Int -> Int))
newtype P = P (Int -> Int) deriving (Num)
main :: IO ()
main = return ()
