-- Report 3.16: expression type signatures.
main :: IO ()
main = do
  print (3 :: Int)
  print ((2 + 3 :: Int) * 2)
  print (map (id :: Int -> Int) [1, 2])
  print (([] :: [Bool]), (Nothing :: Maybe Int))
