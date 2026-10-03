module Main where
import L
import Prelude

main :: IO ()
main = do
  let helper = 5 :: Int
      map = "local"
  print (helper, map)
  print ((\helper -> helper * 2) (4 :: Int))
  print (go 3)
  where
    go n = helper + n where helper = 10 :: Int
