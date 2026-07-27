-- B1 gate workload 2 (design note 7.6): parallel mergesort over
-- 400k LCG-random Ints. Laziness discipline: the sparked value is
-- forceList of a half - forcing the SPINE AND ELEMENTS is what
-- makes the spark do the sort's work rather than build a thunk.
import Control.Parallel
import Data.List (sort)

lcg :: Int -> Int
lcg x = (1103515245 * x + 12345) `mod` 2147483648

randoms :: Int -> Int -> [Int]
randoms 0 _ = []
randoms n s = s : randoms (n - 1) (lcg s)

forceList :: [Int] -> ()
forceList [] = ()
forceList (x : xs) = x `pseq` forceList xs

merge :: [Int] -> [Int] -> [Int]
merge [] ys = ys
merge xs [] = xs
merge (x : xs) (y : ys) =
  if x <= y then x : merge xs (y : ys) else y : merge (x : xs) ys

psort :: Int -> [Int] -> [Int]
psort len xs =
  if len < 25000
    then sort xs
    else let half = len `div` 2
             a = take half xs
             b = drop half xs
             sa = psort half a
             sb = psort (len - half) b
         in forceList sa `par` (forceList sb `pseq` merge sa sb)

main :: IO ()
main = do
  let n = 400000
      xs = randoms n 42
      ys = psort n xs
  print (sum ys)
  print (head ys)
  print (last ys)
