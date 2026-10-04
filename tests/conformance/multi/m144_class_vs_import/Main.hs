module Main where
import L
class Named a where
  label :: a -> String
instance Named Int where
  label _ = "int"
main :: IO ()
main = putStrLn (label (3 :: Int))
