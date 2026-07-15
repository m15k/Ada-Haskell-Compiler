main = do
  print (take 5 (iterate (* 2) 1))
  print (reverse [1, 2, 3])
  print (zip [1, 2, 3] "abc")
  print (sum [1 .. 10], product [1 .. 5])
  print (lookup 2 (zip [1, 2, 3] "xyz"))
  print (either (+ 1) (* 2) (Right 10))
  print (maximum [3, 1, 4, 1, 5], minimum [3, 1, 4])
  putStrLn (unwords ["ada", "meets", "haskell"])
