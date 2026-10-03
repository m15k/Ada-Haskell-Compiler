module Main where
import L
import qualified Prelude
import Prelude

helper :: Int -> Int
helper x = x * 2

data T = Other Bool deriving Show

data Blob = Circle Bool deriving Show

class Named a where
  label :: a -> String

filter :: Int -> Int
filter x = x + 100

main :: IO ()
main = do
  print (Main.helper 3, L.helper 3)
  print (Main.Circle True, L.Circle 1)
  print (Other False, MkT 7)
  print (Main.filter 1, Prelude.filter even [1 .. 6 :: Int])
