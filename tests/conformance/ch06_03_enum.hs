-- Report 6.3.4 / 3.10: stepped sequences, succ/pred at Int.
main :: IO ()
main = do
  print [1, 3 .. 9]
  print [10, 8 .. 1]
  print (take 4 [0, 5 ..])
  print (succ 4, pred 4)
  print (fromEnum 7, toEnum 7 :: Int)
