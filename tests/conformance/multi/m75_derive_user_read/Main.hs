module Main where
import Prelude hiding (Read)
class Read a where
  name :: a -> String
data T = A | B deriving (Show, Read)
main :: IO ()
main = putStrLn (name A)
