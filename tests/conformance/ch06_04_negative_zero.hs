-- Report 6.4 / IEEE 754: negative zero is a distinct value and show
-- must print its sign; showsPrec 11 parenthesizes it like any
-- negative. Fuzzer find (M77 campaign, seed 17): -0.0 == 0.0 is
-- True, so an equality-based zero fast path in show swallowed the
-- sign.
main :: IO ()
main = do
  print ((0.0 / (-3.0)) :: Double)
  print (negate 0.0 :: Double)
  print ((-0.0) == 0.0)
  print (isNegativeZero ((0.0 / (-3.0)) :: Double))
  print (Just ((0.0 / (-3.0)) :: Double))
  print ((1.0 / 0.0, (-1.0) / 0.0) :: (Double, Double))
  print (Just ((-1.0) / 0.0 :: Double))
