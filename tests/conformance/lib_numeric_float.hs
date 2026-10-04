-- Numeric's float formatting (M142): showEFloat / showFFloat /
-- showGFloat round GHC's shortest digits half-to-even, exactly as
-- base's formatRealFloatAlt.
import Numeric

xs :: [Double]
xs = [0, 1, 0.1, 123.456, 1.0e-4, 9.999999, 1.0e21, -2.5, 5.0e-324,
      1.7976931348623157e308, 0.125, 2.5, 0.005, 1234567.0, 12345678.9]

precs :: [Maybe Int]
precs = [Nothing, Just 0, Just 2, Just 10]

main :: IO ()
main = do
  mapM_ (\(name, f) -> mapM_ (\p -> putStrLn (name ++ " " ++ show p ++ ": " ++ unwords [f p x "" | x <- xs])) precs)
    [ ("E", showEFloat), ("F", showFFloat), ("G", showGFloat) ]
  putStrLn (unwords [showFFloatAlt (Just 0) (3 :: Double) "", showGFloatAlt (Just 0) (3 :: Double) ""])
  putStrLn (unwords [showFFloat (Just 2) (0.1 :: Float) "", showEFloat Nothing (0.1 :: Float) ""])
  print (floatToDigits 10 (0.3 :: Double), floatToDigits 10 (1.0e22 :: Double))
