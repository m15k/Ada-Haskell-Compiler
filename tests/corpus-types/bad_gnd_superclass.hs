{-# LANGUAGE GeneralizedNewtypeDeriving #-}
-- GHC 9.4.8: No instance for (Real I)
newtype I = I Int deriving (Integral)
main :: IO ()
main = return ()
