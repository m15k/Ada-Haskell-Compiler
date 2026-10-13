-- M149: the report never forces anything. The failing value holds an
-- undefined field, an infinite list and an unevaluated expression;
-- the report shows each as `_` and the program still exits 1.
data Box = Box Int [Int] Int | Other

open :: Box -> Int
open Other = 0

main :: IO ()
main = do
  let b = Box undefined [1 ..] (length [1 .. 10 :: Int])
  b `seq` print (open b)
