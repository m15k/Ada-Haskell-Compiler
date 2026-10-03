module Main where
import qualified L
import qualified R
main :: IO ()
main = do
  print (L.radius (21 :: Int))
  print (R.Q 1.5)
