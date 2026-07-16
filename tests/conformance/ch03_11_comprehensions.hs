-- Report 3.11: list comprehensions - generators, guards, lets,
-- multiple generators (rightmost varies fastest).
main :: IO ()
main = do
  print [x * x | x <- [1 .. 5]]
  print [x | x <- [1 .. 10], even x]
  print [(x, y) | x <- [1, 2], y <- "ab"]
  print [x + y | x <- [1, 2, 3], y <- [10, 20], x /= 2]
  print [y | x <- [1 .. 4], let y = x * 10, y > 15]
