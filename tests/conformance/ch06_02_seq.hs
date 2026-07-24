-- Report 6.2: seq and ($!). Values only - the strictness itself is
-- pinned by tests/exec/seq_strict.hs (observable order of effects
-- and the forced error); here the oracle checks that seq/($!) and
-- the now-honest Data.List.foldl' compute the same values as GHC.
import Data.List (foldl')

main :: IO ()
main = do
  print (seq (1 + 1 :: Int) "after seq")
  print ((+ 1) $! (41 :: Int))
  print (foldl' (+) 0 [1 .. 100000 :: Int])
  print (foldl' (flip (:)) [] [1, 2, 3 :: Int])
  print (foldl' max 'a' "oracle")
  print (seq [undefined] "spine only")
  print (let xs = [1, 2, 3 :: Int] in xs `seq` length xs)
  print (foldl' (\a b -> a * 2 + b) 0 [1, 0, 1, 1 :: Integer])
