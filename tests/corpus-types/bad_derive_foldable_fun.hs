{-# LANGUAGE DeriveFoldable #-}
-- GHC 9.4.8: Constructor must not contain function types
data F a = F (Int -> a) deriving Foldable
main :: IO ()
main = return ()
