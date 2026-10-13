-- M149: (!!) past the end, reported at the operator.
main :: IO ()
main = do
  let xs = [10, 20, 30] :: [Int]
  print (xs !! 1)
  print (xs !! 7)
