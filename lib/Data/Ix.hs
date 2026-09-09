module Data.Ix (Ix (..)) where

import Data.Char (ord, chr)

class Ord a => Ix a where
  range :: (a, a) -> [a]
  index :: (a, a) -> a -> Int
  inRange :: (a, a) -> a -> Bool
  rangeSize :: (a, a) -> Int
  rangeSize b = length (range b)

instance Ix Int where
  range (lo, hi) = [lo .. hi]
  index (lo, _) i = i - lo
  inRange (lo, hi) i = i >= lo && i <= hi
  rangeSize (lo, hi) = if hi < lo then 0 else hi - lo + 1

instance Ix Char where
  range (lo, hi) = map chr [ord lo .. ord hi]
  index (lo, _) c = ord c - ord lo
  inRange (lo, hi) c = c >= lo && c <= hi
  rangeSize (lo, hi) =
    if hi < lo then 0 else ord hi - ord lo + 1

-- The fixed-width types (Data.Int / Data.Word, M139): through Int.

instance Ix Int8 where
  range (lo, hi) = [lo .. hi]
  index (lo, _) i = fromIntegral i - fromIntegral lo
  inRange (lo, hi) i = i >= lo && i <= hi
  rangeSize (lo, hi) =
    if hi < lo then 0 else fromIntegral hi - fromIntegral lo + 1

instance Ix Int16 where
  range (lo, hi) = [lo .. hi]
  index (lo, _) i = fromIntegral i - fromIntegral lo
  inRange (lo, hi) i = i >= lo && i <= hi
  rangeSize (lo, hi) =
    if hi < lo then 0 else fromIntegral hi - fromIntegral lo + 1

instance Ix Int32 where
  range (lo, hi) = [lo .. hi]
  index (lo, _) i = fromIntegral i - fromIntegral lo
  inRange (lo, hi) i = i >= lo && i <= hi
  rangeSize (lo, hi) =
    if hi < lo then 0 else fromIntegral hi - fromIntegral lo + 1

instance Ix Int64 where
  range (lo, hi) = [lo .. hi]
  index (lo, _) i = fromIntegral i - fromIntegral lo
  inRange (lo, hi) i = i >= lo && i <= hi
  rangeSize (lo, hi) =
    if hi < lo then 0 else fromIntegral hi - fromIntegral lo + 1

instance Ix Word8 where
  range (lo, hi) = [lo .. hi]
  index (lo, _) i = fromIntegral i - fromIntegral lo
  inRange (lo, hi) i = i >= lo && i <= hi
  rangeSize (lo, hi) =
    if hi < lo then 0 else fromIntegral hi - fromIntegral lo + 1

instance Ix Word16 where
  range (lo, hi) = [lo .. hi]
  index (lo, _) i = fromIntegral i - fromIntegral lo
  inRange (lo, hi) i = i >= lo && i <= hi
  rangeSize (lo, hi) =
    if hi < lo then 0 else fromIntegral hi - fromIntegral lo + 1

instance Ix Word32 where
  range (lo, hi) = [lo .. hi]
  index (lo, _) i = fromIntegral i - fromIntegral lo
  inRange (lo, hi) i = i >= lo && i <= hi
  rangeSize (lo, hi) =
    if hi < lo then 0 else fromIntegral hi - fromIntegral lo + 1

instance Ix Word64 where
  range (lo, hi) = [lo .. hi]
  index (lo, _) i = fromIntegral i - fromIntegral lo
  inRange (lo, hi) i = i >= lo && i <= hi
  rangeSize (lo, hi) =
    if hi < lo then 0 else fromIntegral hi - fromIntegral lo + 1
