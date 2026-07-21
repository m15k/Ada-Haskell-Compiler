half :: Integral a => a -> a
half n = div n 2

main :: IO ()
main = do
  print (div 7 2, mod 7 2, quot (-7) 2, rem (-7) 2)
  print (half (10 :: Int), half (2 ^ 70 :: Integer))
  print (sqrt 2, pi, exp 1)
  print (sin (pi / 2), logBase 2 1024, 2 ** 10)
  print (floor 3.7, ceiling 3.2, round 2.5, truncate (-3.9))
  print (fromIntegral (3 :: Int) / 2)
  print (fromIntegral (2 ^ 64 :: Integer) + (0.5 :: Double))
  print (fromIntegral (7 :: Int) :: Integer)
  print (2 ^ 100, (-3) ^ 3, 2 ^^ (-2), 10 ^^ 3)
  print (even (4 :: Int), odd (2 ^ 65 :: Integer))
  print (gcd (12 :: Int) 18, lcm 4 (6 :: Integer))
  print (toInteger (42 :: Int))
