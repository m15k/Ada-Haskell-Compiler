{-# LANGUAGE FlexibleInstances #-}
-- GHC 9.4.8: Overlapping instances for Describe String arising from a use of 'describe'
class Describe a where
  describe :: a -> String
instance Describe [Char] where
  describe _ = "a string"
instance Describe [a] where
  describe _ = "a list"
main :: IO ()
main = putStrLn (describe ("x" :: String))
