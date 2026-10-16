-- M150: Word is its own type, as in GHC - Word64's width and
-- wrapping, every instance Word64 has, texts that name {Word}, and
-- a class with separate Word and Word64 instances.
import Control.Exception
import Data.Bits
import Data.Ix
import Data.Word
import System.Random
import Text.Printf

class Describe a where
  describe :: a -> String

instance Describe Word where
  describe w = "Word " ++ show w

instance Describe Word64 where
  describe w = "Word64 " ++ show w

t :: String -> IO () -> IO ()
t name act = do
  r <- try act
  case r of
    Left e -> putStrLn (name ++ " => " ++ show (e :: SomeException))
    Right () -> putStrLn (name ++ " ok")

f :: a -> IO ()
f x = evaluate x >> return ()

main :: IO ()
main = do
  let w = 41 :: Word
  print (w + 1, w * 3 - 200, negate w, abs w, signum w)
  print (maxBound :: Word, minBound :: Word)
  print (fromIntegral (maxBound :: Word) :: Int)
  print (fromIntegral (-1 :: Int) :: Word)
  print (toInteger (maxBound :: Word) + 1)
  print (read "123" :: Word, read "-1" :: Word, read "18446744073709551616" :: Word)
  print (reads "42 rest" :: [(Word, String)])
  print (quotRem (100 :: Word) 7, divMod (100 :: Word) 7)
  print (w .&. 12, w .|. 2, xor w 1, shiftL w 60, shiftR (maxBound :: Word) 60)
  print (complement (0 :: Word), popCount (maxBound :: Word), testBit w 0)
  print (finiteBitSize w, bit 63 :: Word, setBit w 7, clearBit w 0)
  print ([1 .. 5] :: [Word], [10, 8 .. 1] :: [Word])
  print (take 3 [maxBound - 1 ..] :: [Word])
  print (range (3, 6 :: Word), index (3, 6 :: Word) 5, inRange (3, 6 :: Word) 9, rangeSize (3, 6 :: Word))
  print (toRational w, realToFrac w :: Double, fromIntegral w :: Double)
  print (showsPrec 11 w "", show [w, 0])
  print (compare w 42, max w 50, w == 41)
  putStrLn (printf "%d %5d %x %o %u" w w (255 :: Word) (8 :: Word) w)
  print (fromIntegral (300 :: Word) :: Word8, fromIntegral (maxBound :: Word64) :: Word)
  print (succ w, pred w, toEnum 7 :: Word, fromEnum w)
  putStrLn (describe w ++ ", " ++ describe (fromIntegral w + 1 :: Word64))
  let g = mkStdGen 42
  print (take 3 (randoms g :: [Word]), fst (randomR (10, 20 :: Word) g))
  print (take 3 (randoms g :: [Word]) == map fromIntegral (take 3 (randoms g :: [Word64])))
  t "succ maxBound" (f (succ (maxBound :: Word)))
  t "pred minBound" (f (pred (minBound :: Word)))
  t "toEnum negative" (f (toEnum (-1) :: Word))
  t "fromEnum big" (f (fromEnum (maxBound :: Word)))
  t "div zero" (f (div w 0))
  t "quot zero" (f (quot w 0))
  t "rem zero" (f (rem w 0))
  t "mod zero" (f (mod w 0))
  t "index out of range" (f (index (3, 6 :: Word) 9))
  t "read no parse" (f (read "x" :: Word))
  t "Word64 succ maxBound" (f (succ (maxBound :: Word64)))
  t "Word64 toEnum negative" (f (toEnum (-1) :: Word64))
