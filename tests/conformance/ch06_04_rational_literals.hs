-- Report 6.4: a float literal denotes fromRational of the EXACT
-- decimal ratio. At Rational that ratio survives untouched (then
-- reduces); at Double it takes one correctly-rounded conversion,
-- so 0.1 :: Rational is 1 % 10, never the double's 55-digit truth.
import Data.Ratio

main :: IO ()
main = do
  print (2.5 :: Rational)
  print (0.1 :: Rational)
  print (3.14159 :: Rational)
  print (1.25e2 :: Rational)
  print (0.125e-2 :: Rational)
  print ((2.5 :: Rational) + 0.1)
  print ((0.1 :: Rational) * 10 == 1)
  print (numerator (3.75 :: Rational), denominator (3.75 :: Rational))
  print (fromRational (1 % 3) :: Double)
  print (fromRational (123456789012345678901 % 7) :: Double)
  print (fromRational (2.5 :: Rational) :: Double)
  print (0.1 + 0.2 :: Double)
