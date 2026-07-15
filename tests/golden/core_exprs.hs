inc x = x + 1
sq = \y -> y * y
choose b = if b then 1 else 2
pairs = [ (x, y) | x <- [1 .. 3], y <- [1, 2], x /= y ]
main = do
  putStrLn "hi"
  print (inc 41)
