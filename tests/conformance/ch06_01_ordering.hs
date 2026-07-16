-- Report 6.1.8: Ordering.
main :: IO ()
main = do
  print (compare 1 2, compare 2 2, compare 3 2)
  print [LT, EQ, GT]
  print (compare 'a' 'b')
  print (compare [1, 2] [1, 3])
  print (min 3 5, max 3 5)
  print (compare (1, 'b') (1, 'a'))
