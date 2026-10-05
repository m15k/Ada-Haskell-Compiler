import Data.Int
import Data.Word
import Data.Ratio ()

row :: (Show a, Bounded a, Num a, Integral a, Read a, Enum a) => a -> [String]
row z =
  let lo = minBound `asTypeOf` z
      hi = maxBound `asTypeOf` z
  in [ show (lo, hi), show (hi + 1, lo - 1, hi * hi, negate lo, abs lo)
     , show (hi `quot` 3, hi `rem` 7, hi `div` 2, hi `mod` 10)
     , show (lo `quot` 3, lo `rem` 7, lo `div` 2, lo `mod` 10)
     , show (toInteger hi, toInteger lo, fromIntegral hi :: Int)
     , show (fromInteger (2 ^ 70 + 5) `asTypeOf` z, fromIntegral (-1 :: Int) `asTypeOf` z)
     , show (read (show (toInteger hi + 1)) `asTypeOf` z)
     , show (take 3 [hi - 2 ..], take 3 [lo ..], [hi - 1, hi .. hi])
     , show (succ lo, pred hi)
     , show (toRational hi) ]

main :: IO ()
main = mapM_ (mapM_ putStrLn)
  [ row (0 :: Int8), row (0 :: Int16), row (0 :: Int32), row (0 :: Int64)
  , row (0 :: Word8), row (0 :: Word16), row (0 :: Word32), row (0 :: Word64)
  , row (0 :: Word) ]
