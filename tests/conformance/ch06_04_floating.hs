-- Report 6.4.3: Floating and RealFrac at Double.
main :: IO ()
main = do
  print (sqrt 2)
  print pi
  print (exp 1)
  print (2 ** 10, logBase 2 1024)
  print (sin 0, cos 0)
  print (floor 3.7, ceiling 3.2, truncate (-3.7))
  print (round 2.5, round 3.5, round (-2.5))
  print (0.1 + 0.2)
  print (1.0e7, 12345678.0, 0.05, 1.0e-3)
  print (1 / 0 :: Double)
  print (fromIntegral 7 / 2)
