-- Foldable (base-compat beyond the 2010 Report, like Applicative and
-- Traversable): the Prelude's list functions generalised over a
-- container, with instances for [], Maybe, Either a, Set and Map.
module Main where

import qualified Data.Set as Set
import qualified Data.Map as Map
import Data.Foldable (toList, foldl', foldr', find, forM_)

s :: Set.Set Char
s = Set.fromList "haskell"

m :: Map.Map Int String
m = Map.fromList [(2, "two"), (1, "one"), (3, "three")]

main :: IO ()
main = do
  -- Lists keep working exactly as before.
  print (length [1, 2, 3 :: Int], null ([] :: [Int]), sum [1 .. 10 :: Int])
  print (maximum [3, 1, 2 :: Int], minimum "cab", product [1, 2, 3, 4 :: Int])
  print (and [True, True], or [False], any even [1, 3 :: Int])
  print (all odd [1, 3 :: Int], concat [[1 :: Int], [2]], foldr (:) [] "ab")
  print (foldr1 (-) [10, 2, 3 :: Int], foldl1 (-) [10, 2, 3 :: Int])

  -- Set: elem/length/null off the tree, folded in ascending order.
  print (elem 'k' s, notElem 'z' s, length s, null s)
  print (toList s, maximum s, minimum s)
  print (foldr (:) [] s, foldl (flip (:)) [] s)
  print (any (> 'k') s, all (< 'z') s, find (> 'k') s)

  -- Map folds over its VALUES in ascending key order.
  print (length m, elem "two" m, toList m, null m)
  print (concat (toList m))

  -- Maybe and Either are one-or-zero element containers.
  print (length (Just 'x'), null (Nothing :: Maybe Int), toList (Just (1 :: Int)))
  print (sum (Just (3 :: Int)), sum (Nothing :: Maybe Int))
  print (length (Right 'r' :: Either Int Char), length (Left 1 :: Either Int Char))
  print (toList (Right 'r' :: Either Int Char), or (Just True))

  -- Strict folds, and the string-literal shape that defaulting has
  -- to keep working: a section over a literal container.
  print (foldl' (+) 0 (Set.fromList [1, 2, 3 :: Int]))
  print (foldr' (-) 0 [1, 2, 3 :: Int])
  print (filter (`elem` "[]+-><.,") "a+b>c", elem 'a' "cab")

  mapM_ print (Set.fromList [1, 2 :: Int])
  forM_ (Just (9 :: Int)) print
