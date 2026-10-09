{-# LANGUAGE FlexibleInstances #-}
-- GHC 9.4.8: Duplicate instance declarations
class C a where
  c :: a -> String
instance C (Maybe Int) where
  c _ = "one"
instance C (Maybe Int) where
  c _ = "two"
main :: IO ()
main = putStrLn (c (Just (1 :: Int)))
