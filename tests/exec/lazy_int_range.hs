main :: IO ()
main = do
  print (take 3 [1 .. 10 ^ (18 :: Int) :: Int])
  print (takeWhile (< 5) [1 .. maxBound :: Int])
  print (take 2 [maxBound - 1 .. maxBound :: Int], [maxBound .. maxBound :: Int])
  print (length [minBound .. minBound + 2 :: Int], [5 .. 1 :: Int])
  print (take 3 ['a' ..], take 3 ['\0' .. '\1114111'])
  print (head [1 .. 10 ^ (18 :: Int) :: Integer])
