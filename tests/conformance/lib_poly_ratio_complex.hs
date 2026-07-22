-- Polymorphic Ratio a and Complex a, as base has them:
-- Integral-context fractions, RealFloat-context complex ops.
import Data.Ratio
import Data.Complex

half :: Integral a => a -> Ratio a
half n = n % 2

norm2 :: RealFloat a => Complex a -> a
norm2 z = magnitude (z * conjugate z)

main :: IO ()
main = do
  print (1 % 2 :: Ratio Int)
  print (half (7 :: Int), half (2 ^ 70 :: Integer))
  print (numerator (6 % 4 :: Ratio Int), denominator (6 % 4 :: Ratio Int))
  print ((1 % 3 + 1 % 6 :: Ratio Int) == 1 % 2)
  print (compare (2 % 3 :: Ratio Int) (3 % 4))
  print (fromInteger 5 :: Ratio Int)
  print ((2 :+ 3) * (4 :+ 5) :: Complex Double)
  print (norm2 (3 :+ 4 :: Complex Double))
  print (fromInteger 7 :: Complex Double)
  print (signum (0 :+ 0 :: Complex Double), signum (3 :+ 4 :: Complex Double))
  print (polar (0 :+ 2 :: Complex Double))
