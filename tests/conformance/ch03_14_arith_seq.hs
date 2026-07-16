-- Report 3.10: arithmetic sequences (enumFrom, enumFromTo).
main :: IO ()
main = do
  print [1 .. 5]
  print [3 .. 3]
  print ([5 .. 2] :: [Int])
  print (take 5 [10 ..])
  print (sum [1 .. 100])
