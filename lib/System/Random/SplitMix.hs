module System.Random.SplitMix
  ( SMGen
  , nextWord64, nextWord32, nextTwoWord32, nextInt
  , nextDouble, nextFloat, nextInteger
  , splitSMGen
  , bitmaskWithRejection32, bitmaskWithRejection32'
  , bitmaskWithRejection64, bitmaskWithRejection64'
  , mkSMGen, initSMGen, newSMGen, seedSMGen, seedSMGen', unseedSMGen
  ) where

-- splitmix-0.1.3.2's System.Random.SplitMix (M142), TRANSCRIBED from
-- the package source function by function - each comment names the
-- function it copies. Word64 arithmetic wraps here as in GHC, so
-- splitmix's `mult`/`plus` are (*)/(+) (its non-Hugs branch).
-- Differences, all outside the generated sequences:
--   * base's Data.Bits has no countLeadingZeros here; clz64/clz32
--     below compute it, and the Integer path divides by 2^64 where
--     splitmix shifts (the operand is positive, so they agree).
--   * initSMGen's seed (Init.hs's initialSeed, which on unix/macOS is
--     the C `splitmix_init`) is primEntropySeed: getentropy, as
--     cbits-unix/init.c - 64 bits of OS entropy, nondeterministic.
--   * newSMGen's global generator is process-global IORef slot 1
--     (AHC has no unsafePerformIO).
--   * no Read or NFData instance.

import Data.Bits
import Data.Word
import Data.Int
import Data.IORef

-- data SMGen: seed and gamma; gamma is odd. `deriving Show`, as
-- splitmix: show (mkSMGen 42) is "SMGen 9297814886316923340 13679457532755275413".
data SMGen = SMGen !Word64 !Word64
  deriving Show

-- countLeadingZeros at Word64 / Word32 (GHC's clz primops): the
-- number of zero bits above the highest set bit; the width for 0.
clz64 :: Word64 -> Int
clz64 w = go 63
  where
    go i | i < 0 = 64
         | testBit w i = 63 - i
         | otherwise = go (i - 1)

clz32 :: Word32 -> Int
clz32 w = go 31
  where
    go i | i < 0 = 32
         | testBit w i = 31 - i
         | otherwise = go (i - 1)

-- nextWord64
nextWord64 :: SMGen -> (Word64, SMGen)
nextWord64 (SMGen seed gamma) = (mix64 seed', SMGen seed' gamma)
  where
    seed' = seed + gamma

-- nextWord32: truncating nextWord64.
nextWord32 :: SMGen -> (Word32, SMGen)
nextWord32 g = (fromIntegral w64, g')
  where
    (w64, g') = nextWord64 g

-- nextTwoWord32
nextTwoWord32 :: SMGen -> (Word32, Word32, SMGen)
nextTwoWord32 g = (fromIntegral (w64 `shiftR` 32), fromIntegral w64, g')
  where
    (w64, g') = nextWord64 g

-- nextInt: fromIntegral w64 at a 64-bit Int, i.e. the two's-complement
-- reinterpretation. The cast goes through Int64, from when AHC's Int
-- promoted rather than wrapped (before M146); both wrap now.
nextInt :: SMGen -> (Int, SMGen)
nextInt g = case nextWord64 g of
    (w64, g') -> (fromIntegral (fromIntegral w64 :: Int64), g')

-- nextDouble: [0, 1).
nextDouble :: SMGen -> (Double, SMGen)
nextDouble g = case nextWord64 g of
    (w64, g') -> (fromIntegral (w64 `shiftR` 11) * doubleUlp, g')

-- nextFloat: [0, 1).
nextFloat :: SMGen -> (Float, SMGen)
nextFloat g = case nextWord32 g of
    (w32, g') -> (fromIntegral (w32 `shiftR` 8) * floatUlp, g')

-- nextInteger: closed [x, y] range.
nextInteger :: Integer -> Integer -> SMGen -> (Integer, SMGen)
nextInteger lo hi g = case compare lo hi of
    LT -> let (i, g') = nextInteger' (hi - lo) g in (i + lo, g')
    EQ -> (lo, g)
    GT -> let (i, g') = nextInteger' (lo - hi) g in (i + hi, g')

-- nextInteger': invariant: first argument is positive. Essentially
-- bitmaskWithRejection but for Integers.
nextInteger' :: Integer -> SMGen -> (Integer, SMGen)
nextInteger' range = loop
  where
    leadMask :: Word64
    restDigits :: Int
    (leadMask, restDigits) = go0 0 range
    go0 :: Int -> Integer -> (Word64, Int)
    go0 n x | x < two64 = (complement zeroBits `shiftR` clz64 (fromInteger x :: Word64), n)
            | otherwise = go0 (n + 1) (x `div` two64)

    generate :: SMGen -> (Integer, SMGen)
    generate g0 =
        let (x, g') = nextWord64 g0
            x' = x .&. leadMask
        in go (toInteger x') restDigits g'
      where
        go :: Integer -> Int -> SMGen -> (Integer, SMGen)
        go acc 0 g = acc `seq` (acc, g)
        go acc n g =
            let (x, g') = nextWord64 g
            in go (acc * two64 + toInteger x) (n - 1) g'

    loop g = let (x, g') = generate g
             in if x > range
                then loop g'
                else (x, g')

-- two64
two64 :: Integer
two64 = 2 ^ (64 :: Int)

-- splitSMGen
splitSMGen :: SMGen -> (SMGen, SMGen)
splitSMGen (SMGen seed gamma) =
    (SMGen seed'' gamma, SMGen (mix64 seed') (mixGamma seed''))
  where
    seed'  = seed + gamma
    seed'' = seed' + gamma

-- goldenGamma
goldenGamma :: Word64
goldenGamma = 0x9e3779b97f4a7c15

-- floatUlp
floatUlp :: Float
floatUlp = 1.0 / fromIntegral (1 `shiftL` 24 :: Word32)

-- doubleUlp
doubleUlp :: Double
doubleUlp = 1.0 / fromIntegral (1 `shiftL` 53 :: Word64)

-- mix64: MurmurHash3Mixer.
mix64 :: Word64 -> Word64
mix64 z0 =
    let z1 = shiftXorMultiply 33 0xff51afd7ed558ccd z0
        z2 = shiftXorMultiply 33 0xc4ceb9fe1a85ec53 z1
        z3 = shiftXor 33 z2
    in z3

-- mix64variant13: Stafford's Mix13, used only in mixGamma.
mix64variant13 :: Word64 -> Word64
mix64variant13 z0 =
    let z1 = shiftXorMultiply 30 0xbf58476d1ce4e5b9 z0
        z2 = shiftXorMultiply 27 0x94d049bb133111eb z1
        z3 = shiftXor 31 z2
    in z3

-- mixGamma
mixGamma :: Word64 -> Word64
mixGamma z0 =
    let z1 = mix64variant13 z0 .|. 1             -- force to be odd
        n  = popCount (z1 `xor` (z1 `shiftR` 1))
    in if n >= 24
        then z1
        else z1 `xor` 0xaaaaaaaaaaaaaaaa

-- shiftXor
shiftXor :: Int -> Word64 -> Word64
shiftXor n w = w `xor` (w `shiftR` n)

-- shiftXorMultiply
shiftXorMultiply :: Int -> Word64 -> Word64 -> Word64
shiftXorMultiply n k w = shiftXor n w * k

-- bitmaskWithRejection32: [0, n).
bitmaskWithRejection32 :: Word32 -> SMGen -> (Word32, SMGen)
bitmaskWithRejection32 0 = error "bitmaskWithRejection32 0"
bitmaskWithRejection32 n = bitmaskWithRejection32' (n - 1)

-- bitmaskWithRejection64: [0, n).
bitmaskWithRejection64 :: Word64 -> SMGen -> (Word64, SMGen)
bitmaskWithRejection64 0 = error "bitmaskWithRejection64 0"
bitmaskWithRejection64 n = bitmaskWithRejection64' (n - 1)

-- bitmaskWithRejection32': [0, range].
bitmaskWithRejection32' :: Word32 -> SMGen -> (Word32, SMGen)
bitmaskWithRejection32' range = go where
    mask = complement zeroBits `shiftR` clz32 (range .|. 1)
    go g = let (x, g') = nextWord32 g
               x' = x .&. mask
           in if x' > range
              then go g'
              else (x', g')

-- bitmaskWithRejection64': [0, range].
bitmaskWithRejection64' :: Word64 -> SMGen -> (Word64, SMGen)
bitmaskWithRejection64' range = go where
    mask = complement zeroBits `shiftR` clz64 range
    go g = let (x, g') = nextWord64 g
               x' = x .&. mask
           in if x' > range
              then go g'
              else (x', g')

-- seedSMGen
seedSMGen :: Word64 -> Word64 -> SMGen
seedSMGen seed gamma = SMGen seed (gamma .|. 1)

-- seedSMGen'
seedSMGen' :: (Word64, Word64) -> SMGen
seedSMGen' (seed, gamma) = seedSMGen seed gamma

-- unseedSMGen
unseedSMGen :: SMGen -> (Word64, Word64)
unseedSMGen (SMGen seed gamma) = (seed, gamma)

-- mkSMGen: the preferred deterministic constructor.
mkSMGen :: Word64 -> SMGen
mkSMGen s = SMGen (mix64 s) (mixGamma (s + goldenGamma))

-- initSMGen = fmap mkSMGen initialSeed (seed: see the header).
initSMGen :: IO SMGen
initSMGen = fmap (\t -> mkSMGen (fromIntegral t)) primEntropySeed

-- newSMGen = atomicModifyIORef theSMGen splitSMGen.
-- theSMGen = unsafePerformIO $ initSMGen >>= newIORef becomes global
-- IORef slot 1 holding Nothing until first use. A fresh seed is read
-- BEFORE the one atomic modify and used only if the slot is still
-- empty, so the seed-on-first-use has no bind between its read and
-- its write (two green tasks cannot both initialise it).
newSMGen :: IO SMGen
newSMGen =
  initSMGen >>= \fresh -> primGlobalRef 1 Nothing >>= \r ->
  atomicModifyIORef r (\m -> case splitSMGen (maybe fresh id m) of
                               (g1, g2) -> (Just g1, g2))
