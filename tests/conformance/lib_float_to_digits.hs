-- Numeric.floatToDigits honours its base (the M142 review round):
-- GHC's Burger-Dybvig digit generation for every base.
import Numeric (floatToDigits)

main :: IO ()
main = do
  print (floatToDigits 2 (0.75 :: Double), floatToDigits 16 (255 :: Double))
  print (floatToDigits 10 (0.75 :: Double), floatToDigits 10 (1.0e-2 :: Double))
  print [floatToDigits b (0.1 :: Double) | b <- [2, 3, 7, 8, 16, 36]]
  print [floatToDigits b (123456.789 :: Double) | b <- [2, 5, 8, 12, 16]]
  print [floatToDigits b (1.0e300 :: Double) | b <- [2, 16]]
  print [floatToDigits b (5.0e-324 :: Double) | b <- [2, 10, 16]]
  print [floatToDigits b (2.2250738585072014e-308 :: Double) | b <- [2, 8]]
  print [floatToDigits b (1.7976931348623157e308 :: Double) | b <- [16, 10]]
  print [floatToDigits b (1 :: Double) | b <- [2, 3, 10, 16]]
  print [floatToDigits b (0 :: Double) | b <- [2, 10]]
  print [floatToDigits b (1 / 3 :: Double) | b <- [3, 9, 10]]
  print [floatToDigits b (4096 :: Double) | b <- [2, 4, 8, 16, 64]]
  print (floatToDigits 2 (0.75 :: Float), floatToDigits 16 (255 :: Float), floatToDigits 10 (0.1 :: Float))
