main :: IO ()
main = do
  print (maxBound + 1 :: Int)
  print (minBound `div` (-1 :: Int))
