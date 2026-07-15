sq x = x * x
sumSquares = foldr (+) 0 (map sq [1 .. 10])
facts = map fact [0 .. 6]
  where fact n = if n == 0 then 1 else n * fact (n - 1)
main = do
  print sumSquares
  print facts
  print (17 `div` 5)
  print (17 `mod` 5)
  print (negate 3 + abs (-4) * signum 2)
