-- Report 3.3: currying, operator applications and sections.
main :: IO ()
main = do
  print (map (+ 1) [1, 2, 3])
  print (map (1 +) [1, 2, 3])
  print (map (subtract 2) [10, 20])
  print (map (* 3) [1, 2])
  print (map (10 -) [1, 2])
  print (map (`div` 2) [9, 10])
  print (map (10 `div`) [2, 5])
  print ((\x y -> x * 10 + y) 4 2)
  print (map negate [1, -2])
