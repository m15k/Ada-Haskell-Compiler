module Main where
import Prelude hiding (lookup, filter)

data Shape = Maybe | Nada deriving Show

lookup :: Int -> [(Int, String)] -> String
lookup k kvs = case [v | (k', v) <- kvs, k' == k] of
  (v : _) -> v
  [] -> "none"

filter :: Int -> Int
filter x = x + 1

main :: IO ()
main = do
  putStrLn (lookup 2 [(1, "a"), (2, "b")])
  print (filter 4)
