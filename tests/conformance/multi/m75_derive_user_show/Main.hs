module Main where
import Prelude hiding (Show (..))
class Show a where
  name :: a -> String
data T = A | B deriving (Show)
main :: IO ()
main = putStrLn (name A)
