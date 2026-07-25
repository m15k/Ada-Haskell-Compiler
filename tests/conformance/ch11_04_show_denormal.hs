-- show at Double across the normal/denormal boundary. A denormal's
-- neighbours are evenly spaced, so its digit generation takes the
-- SYMMETRIC boundary case; only a power-of-two significand above
-- the minimum exponent is asymmetric. Getting that backwards
-- printed one digit too many below 2^-1022 (fuzzer, M83 seed 5844).
main :: IO ()
main = do
  print (exp (min 20.0 ((14.08 - 74.09e1) + 11.27)) :: Double)
  print (5.0e-324 :: Double)
  print (1.0e-320 :: Double)
  print (2.2250738585072014e-308 :: Double)
  print (2.225073858507201e-308 :: Double)
  print ([1.0, 2.0, 4.0, 0.5, 0.25] :: [Double])
  print (1.7976931348623157e308 :: Double)
