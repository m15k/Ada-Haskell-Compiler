-- Report 6.4 / 5.6.1 (M75 fuzz regression): Rational is a PRELUDE
-- export. An only-list import of Data.Ratio that omits its synonym
-- must still see `Rational` as `Ratio Integer` - AHC's Prelude
-- Rational is a wired placeholder that Data.Ratio defines, and once
-- types stopped being found by name the placeholder stayed opaque
-- ("no instance for 'Num Rational'") on 258 of 300 fuzz seeds.
import Data.Ratio ((%), numerator, denominator)

half :: Rational
half = 1 % 2

main :: IO ()
main = do
  print (half + 0.25 :: Rational)
  print (numerator (3.5 :: Rational), denominator (3.5 :: Rational))
  print ((20.85e-5 * 0.03e-1 :: Rational) == 6255 % 10000000000)
