-- Report 6.4: fromRational at Double on COMPUTED rationals - the
-- numerator can be a signed bignum, unlike the always-positive
-- literal pairs. Fuzzer find (M83, seed 205): the sign bits of the
-- scaled quotient corrupted the mantissa extraction, off by ~522x.
import Data.Ratio

main :: IO ()
main = do
  let a = negate (10.56 - 33.93e-7) :: Rational
  let b = (59.76 / (93.01e6 + 23.19)) :: Rational
  print (fromRational (a / b) :: Double)
  print (fromRational (negate 32739517643446377211 % 1992000000000) :: Double)
  print (fromRational (32739517643446377211 % 1992000000000) :: Double)
  print (fromRational ((-1) % 3) :: Double)
  print (fromRational (negate (10 ^ 25) % 7) :: Double)
