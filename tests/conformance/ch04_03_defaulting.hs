-- Report 4.3.4: ambiguous numeric types default (Integer first).
main :: IO ()
main = do
  print (2 + 3)
  print (2 * 3 - 1)
  print (div 10 3 + mod 10 3)
  print (negate 5)
  print (abs (-7) + signum (-7))
  print (sum [1, 2, 3] == 6)
