module Main where
import qualified A
import qualified B
main :: IO ()
main = do
  print (B.step 0)
  print (A.step 5)
