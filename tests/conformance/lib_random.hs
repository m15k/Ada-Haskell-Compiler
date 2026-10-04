-- System.Random known answers (M142): AHC's transcription of
-- random-1.2.1.2 (on splitmix-0.1.3.2) against the packages
-- themselves under GHC. Sums run over EVERY element, so drift
-- anywhere in a list shows; first/last 5 localise it.
import System.Random
import Data.Word
import Data.Int

seeds :: [Int]
seeds = [0, 1, 42, -1, 9223372036854775807]

summary :: (Show a) => String -> ([a] -> String) -> [a] -> IO ()
summary name sumOf xs =
  putStrLn (name ++ ": sum " ++ sumOf xs ++ " first " ++ show (take 5 xs)
            ++ " last " ++ show (drop (length xs - 5) xs))

-- 10 mixed split/random steps
mixed :: StdGen -> StdGen
mixed g0 = go (10 :: Int) g0
  where
    go 0 g = g
    go n g
      | even n = go (n - 1) (fst (split g))
      | n `mod` 3 == 0 = go (n - 1) (snd (random g :: (Double, StdGen)))
      | otherwise = go (n - 1) (snd (split (snd (randomR (1, 100 :: Int) g))))

report :: Int -> IO ()
report s = do
  let g = mkStdGen s
  putStrLn ("seed " ++ show s ++ ": " ++ show g)
  summary "Int" (show . sum . map toInteger) (take 1000 (randoms g :: [Int]))
  summary "Double" (show . sum) (take 1000 (randoms g :: [Double]))
  summary "Bool" (show . length . filter id) (take 1000 (randoms g :: [Bool]))
  summary "Word8" (show . sum . map toInteger) (take 1000 (randoms g :: [Word8]))
  summary "Integer" (show . sum) (take 1000 (randoms g :: [Integer]))
  summary "Int8" (show . sum . map toInteger) (take 1000 (randoms g :: [Int8]))
  summary "Int16" (show . sum . map toInteger) (take 1000 (randoms g :: [Int16]))
  summary "Int32" (show . sum . map toInteger) (take 1000 (randoms g :: [Int32]))
  summary "Int64" (show . sum . map toInteger) (take 1000 (randoms g :: [Int64]))
  summary "Word16" (show . sum . map toInteger) (take 1000 (randoms g :: [Word16]))
  summary "Word32" (show . sum . map toInteger) (take 1000 (randoms g :: [Word32]))
  summary "Word64" (show . sum . map toInteger) (take 1000 (randoms g :: [Word64]))
  summary "Char" (show . sum . map fromEnum) (take 1000 (randoms g :: [Char]))
  summary "die" (show . sum) (take 1000 (randomRs (1, 6 :: Int) g))
  summary "letters" (show . sum . map fromEnum) (take 100 (randomRs ('a', 'z') g))
  summary "bigInteger" (show . sum) (take 100 (randomRs (-10 ^ (30 :: Int), 10 ^ (30 :: Int) :: Integer) g))
  summary "smallInteger" (show . sum) (take 100 (randomRs (-1000, 1000 :: Integer) g))
  summary "rangeDouble" (show . sum) (take 100 (randomRs (-1.5, 2.5 :: Double) g))
  summary "rangeInt" (show . sum . map toInteger) (take 100 (randomRs (-9223372036854775807, 9223372036854775807 :: Int) g))
  summary "rangeInt8" (show . sum . map toInteger) (take 100 (randomRs (-100, 7 :: Int8) g))
  summary "rangeInt16" (show . sum . map toInteger) (take 100 (randomRs (-3000, 30000 :: Int16) g))
  summary "rangeInt32" (show . sum . map toInteger) (take 100 (randomRs (minBound, maxBound :: Int32) g))
  summary "rangeWord16" (show . sum . map toInteger) (take 100 (randomRs (5, 60000 :: Word16) g))
  summary "rangeWord32" (show . sum . map toInteger) (take 100 (randomRs (0, 4294967295 :: Word32) g))
  summary "rangeWord64" (show . sum . map toInteger) (take 100 (randomRs (3, 18446744073709551000 :: Word64) g))
  summary "rangeBool" (show . length . filter id) (take 100 (randomRs (False, True) g))
  print (fst (randomR (6, 1 :: Int) g), fst (randomR (3, 3 :: Int) g))
  print (fst (randomR (2.5, -1.5 :: Double) g), fst (randomR (7.25, 7.25 :: Double) g))
  print (fst (randomR (100, -100 :: Integer) g), fst (randomR ('z', 'a') g))
  print (fst (randomR (True, True) g), fst (randomR (False, False) g))
  print (fst (uniformR (0, 255 :: Word8) g), fst (uniformR (200, 10 :: Word8) g))
  print (fst (uniform g :: (Int, StdGen)), fst (uniform g :: (Word32, StdGen)))
  print (fst (uniform g :: (Bool, StdGen)), fst (uniform g :: (Char, StdGen)))
  print (fst (uniformR (1, 10 ^ (25 :: Int) :: Integer) g))
  print (fst (random g :: ((Int, Bool), StdGen)))
  print (fst (randomR ((1, 'a', 0.5), (6, 'f', 1.5)) g :: ((Int, Char, Double), StdGen)))
  print (fst (next g), genRange g)
  print (fst (genWord8 g), fst (genWord16 g), fst (genWord32 g), fst (genWord64 g))
  print (fst (genWord32R 1000 g), fst (genWord64R 123456789012345 g))
  print (mixed g)
  print (split g)
  print (mkStdGen s == g, mkStdGen s == fst (split g))

-- Two user generators that lean on RandomGen's defaults: one gives
-- only genWord32 (genWord64 = two genWord32s, low first), the other
-- only the deprecated next/genRange (genWord32 = randomIvalIntegral).
newtype LCG = LCG Word32 deriving Show
instance RandomGen LCG where
  genWord32 (LCG s) = let s' = s * 1664525 + 1013904223 in (s', LCG s')
  split (LCG s) = (LCG (s + 1), LCG (s * 3))

newtype Old = Old Int deriving Show
instance RandomGen Old where
  next (Old s) = let s' = (s * 48271) `mod` 2147483647 in (s', Old s')
  genRange _ = (1, 2147483646)
  split (Old s) = (Old (s + 7), Old (s + 11))

defaults :: (RandomGen g, Show g) => g -> IO ()
defaults g = do
  print (fst (genWord8 g), fst (genWord16 g), fst (genWord32 g), fst (genWord64 g))
  print (fst (genWord32R 77 g), fst (genWord64R 5000000000 g), fst (next g))
  print (take 8 (randoms g :: [Int]))
  print (take 8 (randomRs (1, 6 :: Int) g))
  print (take 4 (randoms g :: [Double]))
  print (take 4 (randomRs (-10 ^ (30 :: Int), 10 ^ (30 :: Int) :: Integer) g))
  print (case random g of (b, g') -> (b :: Bool, g'))

main :: IO ()
main = do
  mapM_ report seeds
  defaults (LCG 12345)
  defaults (Old 4242)
