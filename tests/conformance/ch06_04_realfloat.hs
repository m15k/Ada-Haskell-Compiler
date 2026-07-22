-- Report 6.4.6: properFraction (RealFrac) and the RealFloat
-- IEEE predicates + atan2, at Double.
main :: IO ()
main = do
  print (properFraction 3.7 :: (Integer, Double))
  print (properFraction (-3.7) :: (Integer, Double))
  print (properFraction 5.0 :: (Integer, Double))
  print (isNaN (0 / 0 :: Double), isNaN (1.5 :: Double))
  print (isInfinite (1 / 0 :: Double), isInfinite (2.5 :: Double))
  print (isNegativeZero (-0.0 :: Double), isNegativeZero (0.0 :: Double))
  print (atan2 1.0 (1.0 :: Double))
  print (atan2 0.0 (-1.0 :: Double))
  let (n, f) = properFraction (2.25 :: Double)
  print (n + 1, f * 4)
