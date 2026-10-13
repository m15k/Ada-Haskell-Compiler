-- M149: an uncaught pattern failure in a function prints AHC's report:
-- where, the equations, the value that arrived, what is handled.
data Shape = Circle Double | Square Double | Triangle Double Double

area :: Shape -> Double
area (Circle r) = pi * r * r
area (Square s) = s * s

main :: IO ()
main = do
  print (area (Square 2))
  let t = Triangle 3 4
  t `seq` print (area t)
