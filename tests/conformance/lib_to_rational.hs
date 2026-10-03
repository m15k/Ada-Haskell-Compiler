-- toRational (M142): exact at every Real instance, as GHC - Double and
-- Float decode their own IEEE bits (infinities included); the
-- fixed-width types go through Integer. Was "method 'toRational' has
-- no runtime yet" (EXCLUSIONS lib 23/24).
import Data.Ratio
import Data.Int
import Data.Word

main :: IO ()
main = do
  print (toRational (7 :: Int), toRational (-12345678901234567890 :: Integer))
  print (toRational (0.1 :: Double), toRational (0.5 :: Double), toRational (0 :: Double))
  print (toRational (-2.75 :: Double), toRational (1.0e-300 :: Double))
  print (toRational (5.0e-324 :: Double), toRational (1.0e300 :: Double))
  print (toRational (0.1 :: Float), toRational (-3.5 :: Float))
  print (toRational (1/0 :: Double))
  print (toRational (1/0 :: Float), toRational (-1/0 :: Float))
  print (toRational (200 :: Int8), toRational (maxBound :: Word64))
  print (realToFrac (1.5 :: Double) :: Double, realToFrac (3 :: Int) :: Double)
  print (numerator (toRational (0.75 :: Double)), denominator (toRational (0.75 :: Double)))
  print (toRational (0.1 :: Double) == 1 % 10, toRational (0.1 :: Double) > 1 % 10)
