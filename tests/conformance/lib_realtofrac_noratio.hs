-- realToFrac and toRational WITHOUT importing Data.Ratio (M142): the
-- Rational only flows into fromRational, which reads its two fields.
main :: IO ()
main = do
  print (realToFrac (2.5 :: Double) :: Double)
  print (realToFrac (7 :: Int) :: Double, realToFrac (7 :: Integer) :: Float)
  print (fromRational (toRational (0.1 :: Double)) :: Double)
  print (realToFrac (0.1 :: Float) :: Double)
