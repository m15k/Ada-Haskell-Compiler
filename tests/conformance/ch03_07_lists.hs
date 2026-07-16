-- Report 3.7: list literals, cons, append.
main :: IO ()
main = do
  print ([] :: [Int])
  print [1, 2, 3]
  print (1 : 2 : [3])
  print ([1, 2] ++ [3] ++ [])
  print [[1], [2, 3], []]
  print [(1, 'a'), (2, 'b')]
  print [Just 1, Nothing]
