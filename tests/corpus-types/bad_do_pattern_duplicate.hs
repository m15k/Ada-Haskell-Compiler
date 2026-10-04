-- A name bound twice by one pattern is still an error, inside a do
-- block as anywhere (both compilers reject).
main :: IO ()
main = do
  (x, x) <- return (1 :: Int, 2 :: Int)
  print x
