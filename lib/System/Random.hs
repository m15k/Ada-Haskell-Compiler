module System.Random
  ( RandomGen (..)
  , uniform, uniformR
  , Random (..)
  , Uniform, UniformRange
  , StdGen, mkStdGen
  , initStdGen, getStdRandom, getStdGen, setStdGen, newStdGen
  , randomIO, randomRIO
  ) where

-- random-1.2.1.2's System.Random (M142), bit-for-bit on StdGen: every
-- algorithm below is TRANSCRIBED from the package's
-- System/Random.hs and System/Random/Internal.hs, and each comment
-- names the function it copies. What is NOT reproduced is the monadic
-- plumbing: random runs each algorithm in `State g` through a
-- `StatefulGen (StateGenM g) m` instance whose methods are exactly
-- `state genWord8` .. `state genWord64R`. Here each one is written as
-- the direct pure `g -> (a, g)` function it denotes, making the SAME
-- generator calls at the SAME widths in the SAME order (a genWord32
-- where random draws 32 bits, a genWord64 where it draws 64).
--
-- Representation notes (values identical to GHC's):
--   * Every Int result is computed at Int64 (written before M146, when
--     AHC's Int promoted on overflow; Int64 wraps, and its random
--     algorithms are random's Int algorithms verbatim: both draw a
--     genWord64 and reject through a 64-bit mask) and then narrowed.
--   * `Word` is AHC's synonym for Word64, so the Word64 instances
--     serve Word (random's two Word instances are the same algorithm).
--   * Integer has no Bits instance here; the Integer algorithms use
--     the arithmetic each bit operation denotes on non-negatives.
--   * countLeadingZeros is computed by `clz` below.
--   * maxBound/minBound at Int have no runtime in AHC yet, so Int's
--     bounds are written as literals.
-- Absent (see tests/conformance/EXCLUSIONS.md): StatefulGen/FrozenGen,
-- IOGen/AtomicGen/STGen, System.Random.Stateful, genByteString /
-- genShortByteString, Uniform for tuples and the Generic-derived
-- Uniform, Random at the C types and at 4..7-tuples, Natural. The IO
-- functions are at IO rather than `MonadIO m`.

import Data.Bits
import Data.Word
import Data.Int
import Data.Char (chr, ord)
import Data.IORef
import System.Random.SplitMix

-- ---------------------------------------------------------------------
-- RandomGen

-- class RandomGen. The deprecated `next`/`genRange` keep their
-- defaults; genShortByteString is absent.
class RandomGen g where
  next :: g -> (Int, g)
  genWord8 :: g -> (Word8, g)
  genWord16 :: g -> (Word16, g)
  genWord32 :: g -> (Word32, g)
  genWord64 :: g -> (Word64, g)
  genWord32R :: Word32 -> g -> (Word32, g)
  genWord64R :: Word64 -> g -> (Word64, g)
  genRange :: g -> (Int, Int)
  split :: g -> (g, g)

  -- next g = runStateGen g (uniformRM (genRange g))
  next g = uniformRInt (genRange g) g
  -- genWord8 = first fromIntegral . genWord32
  genWord8 g = case genWord32 g of (w, g') -> (fromIntegral w, g')
  -- genWord16 = first fromIntegral . genWord32
  genWord16 g = case genWord32 g of (w, g') -> (fromIntegral w, g')
  -- genWord32 = randomIvalIntegral (minBound, maxBound)
  genWord32 = randomIvalIntegral (0 :: Word32, 4294967295)
  -- genWord64: low 32 bits first, then high
  genWord64 g =
    case genWord32 g of
      (l32, g') ->
        case genWord32 g' of
          (h32, g'') ->
            ((fromIntegral h32 `shiftL` 32) .|. fromIntegral l32, g'')
  -- genWord32R m g = runStateGen g (unbiasedWordMult32 m)
  genWord32R m g = unbiasedWordMult32 m g
  -- genWord64R m g = runStateGen g (unsignedBitmaskWithRejectionM uniformWord64 m)
  genWord64R m g = unsignedBitmaskWithRejectionM genWord64 m g
  -- genRange _ = (minBound, maxBound)
  genRange _ = (intMin, intMax)

intMin, intMax :: Int
intMin = -9223372036854775808
intMax = 9223372036854775807

-- newtype StdGen = StdGen { unStdGen :: SM.SMGen } deriving (Show, RandomGen)
newtype StdGen = StdGen { unStdGen :: SMGen }
  deriving Show

-- instance Eq StdGen
instance Eq StdGen where
  StdGen x1 == StdGen x2 = unseedSMGen x1 == unseedSMGen x2

-- instance RandomGen SM.SMGen
instance RandomGen SMGen where
  next = nextInt
  genWord32 = nextWord32
  genWord64 = nextWord64
  split = splitSMGen

-- StdGen's RandomGen is GeneralizedNewtypeDeriving'd from SMGen's, so
-- its methods are SMGen's: the four above, every other one defaulted.
instance RandomGen StdGen where
  next (StdGen g) = case nextInt g of (x, g') -> (x, StdGen g')
  genWord32 (StdGen g) = case nextWord32 g of (x, g') -> (x, StdGen g')
  genWord64 (StdGen g) = case nextWord64 g of (x, g') -> (x, StdGen g')
  split (StdGen g) = case splitSMGen g of (a, b) -> (StdGen a, StdGen b)

-- mkStdGen = StdGen . SM.mkSMGen . fromIntegral
mkStdGen :: Int -> StdGen
mkStdGen n = StdGen (mkSMGen (fromIntegral n))

-- ---------------------------------------------------------------------
-- Uniform / UniformRange: the classes are exported abstractly, as
-- random's System.Random does; their (hidden) methods are the pure
-- forms of uniformM / uniformRM.

class Uniform a where
  uniformP :: RandomGen g => g -> (a, g)

class UniformRange a where
  uniformRP :: RandomGen g => (a, a) -> g -> (a, g)

-- uniform g = runStateGen g uniformM
uniform :: (RandomGen g, Uniform a) => g -> (a, g)
uniform = uniformP

-- uniformR r g = runStateGen g (uniformRM r)
uniformR :: (RandomGen g, UniformRange a) => (a, a) -> g -> (a, g)
uniformR = uniformRP

-- countLeadingZeros at the type's finite width.
clz :: Bits a => a -> Int
clz x = go (w - 1)
  where
    w = finiteBitSize x
    go i | i < 0 = w
         | testBit x i = w - 1 - i
         | otherwise = go (i - 1)

-- unsignedBitmaskWithRejectionM
unsignedBitmaskWithRejectionM
  :: (Ord a, Bits a, Num a) => (g -> (a, g)) -> a -> g -> (a, g)
unsignedBitmaskWithRejectionM genUniformM range = go
  where
    mask = complement zeroBits `shiftR` clz (range .|. 1)
    go g = case genUniformM g of
      (x, g') -> let x' = x .&. mask
                 in if x' > range then go g' else (x', g')

-- unsignedBitmaskWithRejectionRM
unsignedBitmaskWithRejectionRM
  :: (Ord a, Bits a, Num a) => (g -> (a, g)) -> (a, a) -> g -> (a, g)
unsignedBitmaskWithRejectionRM uniformM' (bottom, top) gen
  | bottom == top = (top, gen)
  | otherwise = case unsignedBitmaskWithRejectionM uniformM' r gen of
      (x, g') -> (b + x, g')
  where
    (b, r) = if bottom > top then (top, bottom - top) else (bottom, top - bottom)

-- signedBitmaskWithRejectionRM
signedBitmaskWithRejectionRM
  :: (Num a, Num b, Ord b, Ord a, Bits a)
  => (b -> a) -> (a -> b) -> (g -> (a, g)) -> (b, b) -> g -> (b, g)
signedBitmaskWithRejectionRM toUnsigned fromUnsigned uniformM' (bottom, top) gen
  | bottom == top = (top, gen)
  | otherwise = case unsignedBitmaskWithRejectionM uniformM' r gen of
      (x, g') -> (b + fromUnsigned x, g')
  where
    (b, r) =
      if bottom > top
        then (top, toUnsigned bottom - toUnsigned top)
        else (bottom, toUnsigned top - toUnsigned bottom)

-- unbiasedWordMult32RM
unbiasedWordMult32RM :: (RandomGen g, Integral a) => (a, a) -> g -> (a, g)
unbiasedWordMult32RM (b, t) g
  | b <= t    = case unbiasedWordMult32 (fromIntegral (t - b)) g of
                  (x, g') -> (fromIntegral x + b, g')
  | otherwise = case unbiasedWordMult32 (fromIntegral (b - t)) g of
                  (x, g') -> (fromIntegral x + t, g')

-- unbiasedWordMult32
unbiasedWordMult32 :: RandomGen g => Word32 -> g -> (Word32, g)
unbiasedWordMult32 s g
  | s == 4294967295 = genWord32 g
  | otherwise = unbiasedWordMult32Exclusive (s + 1) g

-- unbiasedWordMult32Exclusive (Lemire's multiply-and-reject)
unbiasedWordMult32Exclusive :: RandomGen g => Word32 -> g -> (Word32, g)
unbiasedWordMult32Exclusive r = go
  where
    t :: Word32
    t = (negate r) `mod` r -- 2^32 `mod` r
    go g = case genWord32 g of
      (x, g') ->
        let m :: Word64
            m = fromIntegral x * fromIntegral r
            l :: Word32
            l = fromIntegral m
        in if l >= t then (fromIntegral (m `shiftR` 32), g') else go g'

-- uniformIntegralM, at Integer
uniformIntegerM :: RandomGen g => (Integer, Integer) -> g -> (Integer, g)
uniformIntegerM (l, h) gen = case l `compare` h of
  LT ->
    let limit = h - l
    in if limit < two64     -- toIntegralSized limit :: Maybe Word64
         then case unsignedBitmaskWithRejectionM genWord64 (fromInteger limit) gen of
                (x, g') -> (l + toInteger x, g')
         else case boundedExclusiveIntegralM (limit + 1) gen of
                (x, g') -> (l + x, g')
  GT -> uniformIntegerM (h, l) gen
  EQ -> (l, gen)

two64 :: Integer
two64 = 18446744073709551616

-- boundedExclusiveIntegralM, at Integer (Lemire's method over n words):
-- `m .&. modTwoToKMask` and `m `shiftR` k` are mod/div by 2^k, m >= 0.
boundedExclusiveIntegralM :: RandomGen g => Integer -> g -> (Integer, g)
boundedExclusiveIntegralM s = go
  where
    n = integralWordSize s
    twoToK = two64 ^ n
    t = (twoToK - s) `rem` s
    go g = case uniformIntegralWords n g of
      (x, g') -> let m = x * s
                     l = m `mod` twoToK
                 in if l < t then go g' else (m `div` twoToK, g')

-- integralWordSize: the number of 64-bit words in a non-negative.
integralWordSize :: Integer -> Int
integralWordSize = go 0
  where
    go acc i
      | i == 0 = acc
      | otherwise = go (acc + 1) (i `div` two64)

-- uniformIntegralWords: n draws of Word (= uniformWord64), most
-- significant first.
uniformIntegralWords :: RandomGen g => Int -> g -> (Integer, g)
uniformIntegralWords n0 = go 0 n0
  where
    go acc i g
      | i == 0 = (acc, g)
      | otherwise = case genWord64 g of
          (w, g') -> go (acc * two64 + toInteger w) (i - 1) g'

-- randomIvalIntegral / randomIvalInteger: the default genWord32's
-- generator-agnostic path through next and genRange.
randomIvalIntegral :: (RandomGen g, Integral a) => (a, a) -> g -> (a, g)
randomIvalIntegral (l, h) = randomIvalInteger (toInteger l, toInteger h)

randomIvalInteger :: (RandomGen g, Num a) => (Integer, Integer) -> g -> (a, g)
randomIvalInteger (l, h) rng
 | l > h     = randomIvalInteger (h, l) rng
 | otherwise = case f 1 0 rng of (v, rng') -> (fromInteger (l + v `mod` k), rng')
     where
       (genlo, genhi) = genRange rng
       b = fromIntegral genhi - fromIntegral genlo + 1 :: Integer
       q = 1000 :: Integer
       k = h - l + 1
       magtgt = k * q
       f mag v g | mag >= magtgt = (v, g)
                 | otherwise = v' `seq` f (mag * b) v' g' where
                        (x, g') = next g
                        v' = v * b + (fromIntegral x - fromIntegral genlo)

-- uniformDouble01M
uniformDouble01M :: RandomGen g => g -> (Double, g)
uniformDouble01M g = case genWord64 g of
  (w64, g') -> (fromIntegral w64 / m, g')
  where
    m = fromIntegral (18446744073709551615 :: Word64) :: Double

-- uniformFloat01M
uniformFloat01M :: RandomGen g => g -> (Float, g)
uniformFloat01M g = case genWord32 g of
  (w32, g') -> (fromIntegral w32 / m, g')
  where
    m = fromIntegral (4294967295 :: Word32) :: Float

-- ---------------------------------------------------------------------
-- Instances (instance Uniform X / instance UniformRange X)

instance Uniform Int8 where
  uniformP g = case genWord8 g of (w, g') -> (fromIntegral w, g')
instance UniformRange Int8 where
  uniformRP = signedBitmaskWithRejectionRM
                (fromIntegral :: Int8 -> Word8) fromIntegral genWord8

instance Uniform Int16 where
  uniformP g = case genWord16 g of (w, g') -> (fromIntegral w, g')
instance UniformRange Int16 where
  uniformRP = signedBitmaskWithRejectionRM
                (fromIntegral :: Int16 -> Word16) fromIntegral genWord16

instance Uniform Int32 where
  uniformP g = case genWord32 g of (w, g') -> (fromIntegral w, g')
instance UniformRange Int32 where
  uniformRP = signedBitmaskWithRejectionRM
                (fromIntegral :: Int32 -> Word32) fromIntegral genWord32

instance Uniform Int64 where
  uniformP g = case genWord64 g of (w, g') -> (fromIntegral w, g')
instance UniformRange Int64 where
  uniformRP = signedBitmaskWithRejectionRM
                (fromIntegral :: Int64 -> Word64) fromIntegral genWord64

-- instance Uniform Int / UniformRange Int: at a 64-bit word, random's
-- Int algorithms are its Int64 ones (genWord64, Word = Word64), so
-- they run at Int64, where (+) wraps as GHC's Int does.
instance Uniform Int where
  uniformP g = case uniformP g of (x, g') -> (fromIntegral (x :: Int64), g')
instance UniformRange Int where
  uniformRP = uniformRInt

uniformRInt :: RandomGen g => (Int, Int) -> g -> (Int, g)
uniformRInt (l, h) g =
  case uniformRP (fromIntegral l :: Int64, fromIntegral h) g of
    (x, g') -> (fromIntegral x, g')

instance Uniform Word8 where
  uniformP = genWord8
instance UniformRange Word8 where
  uniformRP = unbiasedWordMult32RM

instance Uniform Word16 where
  uniformP = genWord16
instance UniformRange Word16 where
  uniformRP = unbiasedWordMult32RM

instance Uniform Word32 where
  uniformP = genWord32
instance UniformRange Word32 where
  uniformRP = unbiasedWordMult32RM

instance Uniform Word64 where
  uniformP = genWord64
instance UniformRange Word64 where
  uniformRP = unsignedBitmaskWithRejectionRM genWord64

instance UniformRange Integer where
  uniformRP = uniformIntegerM

-- instance Uniform Char / UniformRange Char: over code points as
-- Word32, surrogates included (random has no gap).
instance Uniform Char where
  uniformP g = case unbiasedWordMult32 1114111 g of
    (w, g') -> (word32ToChar w, g')
instance UniformRange Char where
  uniformRP (l, h) g =
    case unbiasedWordMult32RM (charToWord32 l, charToWord32 h) g of
      (w, g') -> (word32ToChar w, g')

word32ToChar :: Word32 -> Char
word32ToChar w = chr (fromIntegral w)

charToWord32 :: Char -> Word32
charToWord32 c = fromIntegral (ord c)

instance Uniform () where
  uniformP g = ((), g)
instance UniformRange () where
  uniformRP _ g = ((), g)

-- instance Uniform Bool: the low bit of a genWord8.
instance Uniform Bool where
  uniformP g = case genWord8 g of (w, g') -> ((w .&. 1) /= 0, g')
instance UniformRange Bool where
  uniformRP (False, False) g = (False, g)
  uniformRP (True, True)   g = (True, g)
  uniformRP _              g = uniformP g

-- instance UniformRange Double
instance UniformRange Double where
  uniformRP (l, h) g
    | l == h = (l, g)
    | isInfinite l || isInfinite h = let r = h + l in r `seq` (r, g)
    | otherwise = case uniformDouble01M g of
        (x, g') -> (x * l + (1 - x) * h, g')

-- instance UniformRange Float
instance UniformRange Float where
  uniformRP (l, h) g
    | l == h = (l, g)
    | isInfinite l || isInfinite h = let r = h + l in r `seq` (r, g)
    | otherwise = case uniformFloat01M g of
        (x, g') -> (x * l + (1 - x) * h, g')

-- ---------------------------------------------------------------------
-- Random

-- class Random. randomR/random have DefaultSignatures defaults in
-- random (uniformRM / uniformM); Haskell 2010 has none, so every
-- instance below states them.
class Random a where
  randomR :: RandomGen g => (a, a) -> g -> (a, g)
  random :: RandomGen g => g -> (a, g)
  randomRs :: RandomGen g => (a, a) -> g -> [a]
  randoms :: RandomGen g => g -> [a]

  randomRs ival g = buildRandoms (randomR ival) g
  randoms g = buildRandoms random g

-- buildRandoms (with (:) for the fusion-friendly cons)
buildRandoms :: (g -> (a, g)) -> g -> [a]
buildRandoms rand = go
  where
    go g = case rand g of (x, g') -> x `seq` (x : go g')

instance Random Integer where
  randomR = uniformRP
  -- random = first (toInteger :: Int -> Integer) . random
  random g = case random g of (x, g') -> (toInteger (x :: Int), g')

instance Random Int8 where
  randomR = uniformRP
  random = uniformP
instance Random Int16 where
  randomR = uniformRP
  random = uniformP
instance Random Int32 where
  randomR = uniformRP
  random = uniformP
instance Random Int64 where
  randomR = uniformRP
  random = uniformP
instance Random Int where
  randomR = uniformRP
  random = uniformP
instance Random Word8 where
  randomR = uniformRP
  random = uniformP
instance Random Word16 where
  randomR = uniformRP
  random = uniformP
instance Random Word32 where
  randomR = uniformRP
  random = uniformP
instance Random Word64 where
  randomR = uniformRP
  random = uniformP
instance Random Char where
  randomR = uniformRP
  random = uniformP
instance Random Bool where
  randomR = uniformRP
  random = uniformP

-- instance Random Double: random is (1 -) of uniformDouble01M
instance Random Double where
  randomR = uniformRP
  random g = case uniformDouble01M g of (x, g') -> (1 - x, g')

-- instance Random Float: random is (1 -) of uniformFloat01M
instance Random Float where
  randomR = uniformRP
  random g = case uniformFloat01M g of (x, g') -> (1 - x, g')

-- instance (Random a, Random b) => Random (a, b): left then right
instance (Random a, Random b) => Random (a, b) where
  randomR ((al, bl), (ah, bh)) g0 =
    case randomR (al, ah) g0 of
      (a, g1) -> case randomR (bl, bh) g1 of
        (b, g2) -> ((a, b), g2)
  random g0 =
    case random g0 of
      (a, g1) -> case random g1 of
        (b, g2) -> ((a, b), g2)

instance (Random a, Random b, Random c) => Random (a, b, c) where
  randomR ((al, bl, cl), (ah, bh, ch)) g0 =
    case randomR (al, ah) g0 of
      (a, g1) -> case randomR (bl, bh) g1 of
        (b, g2) -> case randomR (cl, ch) g2 of
          (c, g3) -> ((a, b, c), g3)
  random g0 =
    case random g0 of
      (a, g1) -> case random g1 of
        (b, g2) -> case random g2 of
          (c, g3) -> ((a, b, c), g3)

-- ---------------------------------------------------------------------
-- The global generator

-- initStdGen = liftIO (StdGen <$> SM.initSMGen)
initStdGen :: IO StdGen
initStdGen = fmap StdGen initSMGen

-- theStdGen = unsafePerformIO $ SM.initSMGen >>= newIORef . StdGen
-- becomes process-global IORef slot 0, holding Nothing until first
-- use. Every access is ONE atomic modify (no bind between its read
-- and its write); a fresh seed is read beforehand and used only if
-- the slot is still empty.
withStdGen :: (StdGen -> (StdGen, a)) -> IO a
withStdGen f =
  initStdGen >>= \fresh -> primGlobalRef 0 Nothing >>= \r ->
  atomicModifyIORef' r (\m -> case f (maybe fresh id m) of
                                (g, a) -> g `seq` (Just g, a))

-- setStdGen = liftIO . writeIORef theStdGen
setStdGen :: StdGen -> IO ()
setStdGen g = primGlobalRef 0 Nothing >>= \r -> writeIORef r (Just g)

-- getStdGen = liftIO $ readIORef theStdGen
getStdGen :: IO StdGen
getStdGen = withStdGen (\g -> (g, g))

-- newStdGen = liftIO $ atomicModifyIORef' theStdGen split
newStdGen :: IO StdGen
newStdGen = withStdGen split

-- getStdRandom f = liftIO $ atomicModifyIORef' theStdGen (swap . f)
getStdRandom :: (StdGen -> (a, StdGen)) -> IO a
getStdRandom f = withStdGen (\g -> case f g of (v, g') -> (g', v))

-- randomRIO range = getStdRandom (randomR range)
randomRIO :: Random a => (a, a) -> IO a
randomRIO range = getStdRandom (randomR range)

-- randomIO = getStdRandom random
randomIO :: Random a => IO a
randomIO = getStdRandom random
