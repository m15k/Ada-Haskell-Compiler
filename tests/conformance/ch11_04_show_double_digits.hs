-- Report 11.4 / show at Double: shortest ROUND-TRIP digits chosen
-- exactly as GHC's floatToDigits (Burger-Dybvig) chooses them.
-- printf's correctly-rounded N-digit decimal agrees except on
-- last-digit boundary cases where two candidates both round-trip;
-- the fuzzer's first deep campaign (M83) found four in 10k seeds.
import Data.Ratio

main :: IO ()
main = do
  print (fromRational ((4482899028702386 % 214) + (699848027990907389637078020642 % 9913387431838394) + (7319 % 100)) :: Double)
  print ((10.39 - 83.09) * 35.74 - 1.359515625836895e15 :: Double)
  print (5.0e-324 :: Double)
  print (1.7976931348623157e308 :: Double)
  print (2.2250738585072014e-308 :: Double)
  print (9007199254740993.0 :: Double)
  print (123456789.123456789 :: Double)
