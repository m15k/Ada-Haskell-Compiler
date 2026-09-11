-- Data.Either, Data.Set's index operations, and Report 9's readIO /
-- readLn (readLn reads the line below).
module Main where

import Data.Either
import qualified Data.Set as Set

vals :: [Either Int Char]
vals = [Left 1, Right 'a', Left 2, Right 'b', Left 3]

main :: IO ()
main = do
  print (lefts vals)
  print (rights vals)
  print (partitionEithers vals)
  print (map isLeft vals, map isRight vals)
  print (fromLeft 0 (Left (9 :: Int)), fromLeft 0 (Right 'z'))
  print (fromRight 'x' (Left (9 :: Int)), fromRight 'x' (Right 'q'))
  print (either show (: []) (Left (7 :: Int)))
  print (either show (: []) (Right 'k' :: Either Int Char))
  let s = Set.fromList "haskell"
  print (Set.toAscList s)
  print (Set.elemAt 0 s, Set.elemAt 3 s)
  print (Set.findIndex 'k' s, Set.lookupIndex 'z' s)
  n <- readLn :: IO Int
  m <- readIO "41"
  print (n + m :: Int)
  mapM_ putChar "done\n"
