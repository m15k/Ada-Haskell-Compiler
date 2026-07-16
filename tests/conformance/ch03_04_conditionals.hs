-- Report 3.6: conditionals are expressions.
classify :: Int -> Int
classify n = if n < 0 then -1 else if n == 0 then 0 else 1

main :: IO ()
main = do
  print (classify (-5), classify 0, classify 9)
  print (if True then 1 else 2)
  print ((if odd 3 then (+ 1) else (* 2)) 10)
