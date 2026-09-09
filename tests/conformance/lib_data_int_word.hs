-- Data.Int / Data.Word: wrapping arithmetic at every width, Bounded,
-- Enum (with GHC's error texts), Integral (division overflow),
-- Read (wraps), Real, and conversions through fromIntegral.
import Data.Int
import Data.Word
import Data.Ix
import Control.Exception

attempt :: Show a => a -> IO ()
attempt x = do
  r <- try (evaluate x)
  putStrLn (either (\e -> takeWhile (/= '\n') (show (e :: SomeException))) show r)

main :: IO ()
main = do
  print (200 :: Int8, 128 :: Int8, 100 + 100 :: Int8, 100 * 3 :: Int8)
  print (250 + 10 :: Word8, negate 1 :: Word8, 0 - 1 :: Word16)
  print (fromIntegral (300 :: Int) :: Word8, fromIntegral (-1 :: Int) :: Word32)
  print (fromIntegral (maxBound :: Word64) :: Integer, fromIntegral (2 ^ 64 + 5 :: Integer) :: Word64)
  print (minBound :: Int8, maxBound :: Int8, minBound :: Word, maxBound :: Word)
  print (maxBound :: Int32, minBound :: Int64, maxBound :: Word16)
  print (div (200 :: Word8) 7, mod (-7 :: Int8) 3, quot (-7 :: Int16) 3, rem (-7 :: Int32) 3)
  print (toInteger (maxBound :: Int64) + 1, toInteger (minBound :: Int8) - 1)
  print (abs (minBound :: Int8), signum (-5 :: Int16), negate (minBound :: Int32))
  print (length [minBound .. maxBound :: Int8], [250 ..] :: [Word8], [1, 3 .. 9] :: [Int16])
  print (fromEnum (200 :: Word8), toEnum 65 :: Int8, succ (126 :: Int8), pred (1 :: Word8))
  print (read "-128" :: Int8, read "300" :: Word8, reads "77 rest" :: [(Int64, String)])
  print (fromInteger (truncate (3.7 :: Double)) :: Int8, fromInteger (round (300.6 :: Double)) :: Word8,
         fromInteger (floor (-2.5 :: Double)) :: Int16)
  print (sum (map fromIntegral [1 .. 100 :: Int]) :: Word8, product [1 .. 6] :: Int8)
  print (compare (1 :: Word8) 200, (255 :: Word8) > 0, maximum [3, 250, 7 :: Word8])
  attempt (toEnum 300 :: Word8)
  attempt (succ (maxBound :: Int8))
  attempt (pred (minBound :: Word16))
  attempt (quot (minBound :: Int8) (-1))
  attempt (div (minBound :: Int64) (-1))
  attempt (5 `div` (0 :: Word8))
  attempt (toEnum (-1) :: Word8)
  -- Ix at the fixed widths, with the range check
  print (range (250, 255 :: Word8), index (10, 20 :: Int16) 15, inRange (-5, 5 :: Int8) (-6), rangeSize (0, 255 :: Word8))
  attempt (index (0, 10 :: Word8) 11)
  attempt (index (0, 10 :: Int) 11)
  attempt (index ('a', 'e') 'z')
  attempt (rem (minBound :: Int8) (-1), mod (minBound :: Int64) (-1))
  print (quotRem (-7 :: Int8) 2, divMod (-7 :: Int8) 2, quotRem (200 :: Word8) 7)
  -- Word64 above 2^63: enumeration, comparison, folds
  print (length ([maxBound - 2 ..] :: [Word64]), [maxBound - 1 .. maxBound] :: [Word64])
  print ([maxBound, maxBound - 1 .. maxBound - 3] :: [Word64])
  print (compare (5 :: Word64) (2 ^ 63), maximum [1, 2 ^ 63, 7 :: Word64], sum [2 ^ 63, 2 ^ 63 :: Word64])
  print ([1, 3 .. 9] :: [Word64], [5, 3 ..] :: [Int8], [250, 253 ..] :: [Word8], take 3 [maxBound, maxBound - 2 ..] :: [Int16])
  -- laziness and strides: wide ranges are produced one element at a time
  print (take 3 [minBound ..] :: [Int64], take 2 [0 ..] :: [Int32], take 3 [maxBound - 5 ..] :: [Word64])
  print ([minBound, maxBound ..] :: [Int64], [maxBound, minBound ..] :: [Int64], take 3 ([5, 5 .. 7] :: [Word8]))
  print ([7, 5 .. 7] :: [Int8], [2, 1 .. 3] :: [Word8], [2 ^ 63 - 1, 2 ^ 63 + 1 .. 2 ^ 63 + 4] :: [Word64])
  -- subtract goes through the type's own Num instance
  print (subtract 1 (0 :: Word16), subtract 1 (minBound :: Int8), map (subtract 3) [1, 2, 3 :: Word8], subtract 1 (2.5 :: Double))
