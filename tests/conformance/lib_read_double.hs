-- read at Double, and Text.Read's total readers: two RPN calculators
-- off GitHub wanted both (M141). The digits go through the same exact
-- decimal conversion a float literal takes, so the results are GHC's.
import Text.Read (readMaybe, readEither)

main :: IO ()
main = do
  print (read "3.25" :: Double, read "-0.1" :: Double)
  print (read "1e3" :: Double, read "2.5e-3" :: Double, read "0.1" :: Double)
  print (read "  7  " :: Double, read "(-2.5)" :: Double)
  print (read "0.1" + read "0.2" :: Double, read "1234567890.123" :: Double)
  print (map read ["1", "2.5", "-3e2"] :: [Double])
  print (readMaybe "12.5" :: Maybe Double, readMaybe "oops" :: Maybe Double)
  print (readMaybe "42" :: Maybe Int, readMaybe "4 2" :: Maybe Int)
  print (readEither "8.5" :: Either String Double)
  print (reads "3.5rest" :: [(Double, String)])
