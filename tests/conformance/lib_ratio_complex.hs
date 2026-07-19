import Data.Ratio
import Data.Complex

main :: IO ()
main = do
  print (1 % 2 :: Rational)
  print (3 % 6 :: Rational, (-1) % 2 :: Rational, 1 % (-2) :: Rational)
  print (1 % 2 + 1 % 3 :: Rational)
  print ((1 % 2) * (2 % 3) :: Rational)
  print ((1 % 2) / (3 % 4) :: Rational)
  print (numerator (6 % 4 :: Rational), denominator (6 % 4 :: Rational))
  print (compare (1 % 2 :: Rational) (2 % 3), (1 % 2 :: Rational) == 2 % 4)
  print (Just (1 % 2 :: Rational))
  print (negate (1 % 2 :: Rational), abs ((-3) % 4 :: Rational), signum ((-3) % 4 :: Rational))
  print (2.0 :+ 3.0)
  print ((1.0 :+ 2.0) + (3.0 :+ 4.0), (1.0 :+ 2.0) * (3.0 :+ 4.0))
  print (conjugate (1.0 :+ 2.0), realPart (5.0 :+ 1.0), imagPart (5.0 :+ 1.0))
  print (magnitude (3.0 :+ 4.0))
  print (phase (0.0 :+ 1.0))
  print (Just (1.0 :+ (-2.0)))
  print (mkPolar 2.0 0.0, cis 0.0)
