-- Strict loops run in constant C stack (M146): each step's result is
-- a thunk returned by `seq`, and the evaluator now updates and loops
-- instead of recursing. strict_loop_stack.env runs this on a 1 MB
-- main stack; before M146 each of these overflowed it within ~20k
-- elements (and a 1 GB stack at 3*10^7).
import Data.List (foldl')

loop :: Int -> Int -> Int
loop acc 0 = acc
loop acc n = let acc' = acc + n in acc' `seq` loop acc' (n - 1)

main :: IO ()
main = do
  print (foldl' (+) 0 [1 .. 1000000 :: Int])
  print (loop 0 1000000)
  mapM_ (\i -> if i `mod` 100000 == 0 then print i else return ()) [1 .. 200000 :: Int]
