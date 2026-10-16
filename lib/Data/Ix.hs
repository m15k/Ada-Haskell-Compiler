module Data.Ix (Ix (..)) where

import Data.Char (ord, chr)

class Ord a => Ix a where
  range :: (a, a) -> [a]
  index :: (a, a) -> a -> Int
  inRange :: (a, a) -> a -> Bool
  rangeSize :: (a, a) -> Int
  rangeSize b = length (range b)

-- GHC 9.4.8's texts (recorded, M150): Int, Char and Integer name
-- themselves (base's indexError, no call stack); the fixed-width
-- types, tuples and derived instances say "Error in array index".
instance Ix Int where
  range (lo, hi) = [lo .. hi]
  index b@(lo, _) i =
    if inRange b i then i - lo
    else errorWithoutStackTrace ("Ix{Int}.index: Index (" ++ show i
                                 ++ ") out of range (" ++ show b ++ ")")
  inRange (lo, hi) i = i >= lo && i <= hi
  rangeSize (lo, hi) = if hi < lo then 0 else hi - lo + 1

instance Ix Char where
  range (lo, hi) = map chr [ord lo .. ord hi]
  index b@(lo, _) c =
    if inRange b c then ord c - ord lo
    else errorWithoutStackTrace ("Ix{Char}.index: Index (" ++ show c
                                 ++ ") out of range (" ++ show b ++ ")")
  inRange (lo, hi) c = c >= lo && c <= hi
  rangeSize (lo, hi) =
    if hi < lo then 0 else ord hi - ord lo + 1

instance Ix Integer where
  range (lo, hi) = [lo .. hi]
  index b@(lo, _) i =
    if inRange b i then fromInteger (i - lo)
    else errorWithoutStackTrace ("Ix{Integer}.index: Index (" ++ show i
                                 ++ ") out of range (" ++ show b ++ ")")
  inRange (lo, hi) i = i >= lo && i <= hi
  rangeSize (lo, hi) = if hi < lo then 0 else fromInteger (hi - lo + 1)

-- Tuples, row-major as base's; an index outside the box is base's
-- hopelessIndexError, whatever the component types.
instance (Ix a, Ix b) => Ix (a, b) where
  range ((l1, l2), (u1, u2)) =
    [(i1, i2) | i1 <- range (l1, u1), i2 <- range (l2, u2)]
  index b@((l1, l2), (u1, u2)) i@(i1, i2) =
    if inRange b i
      then index (l1, u1) i1 * rangeSize (l2, u2) + index (l2, u2) i2
      else errorWithoutStackTrace "Error in array index"
  inRange ((l1, l2), (u1, u2)) (i1, i2) =
    inRange (l1, u1) i1 && inRange (l2, u2) i2
  rangeSize ((l1, l2), (u1, u2)) = rangeSize (l1, u1) * rangeSize (l2, u2)

-- The fixed-width types (Data.Int / Data.Word, M139): through Int.

instance Ix Int8 where
  range (lo, hi) = [lo .. hi]
  index b@(lo, _) i =
    if inRange b i then fromIntegral i - fromIntegral lo
    else error "Error in array index"
  inRange (lo, hi) i = i >= lo && i <= hi
  rangeSize (lo, hi) =
    if hi < lo then 0 else fromIntegral hi - fromIntegral lo + 1

instance Ix Int16 where
  range (lo, hi) = [lo .. hi]
  index b@(lo, _) i =
    if inRange b i then fromIntegral i - fromIntegral lo
    else error "Error in array index"
  inRange (lo, hi) i = i >= lo && i <= hi
  rangeSize (lo, hi) =
    if hi < lo then 0 else fromIntegral hi - fromIntegral lo + 1

instance Ix Int32 where
  range (lo, hi) = [lo .. hi]
  index b@(lo, _) i =
    if inRange b i then fromIntegral i - fromIntegral lo
    else error "Error in array index"
  inRange (lo, hi) i = i >= lo && i <= hi
  rangeSize (lo, hi) =
    if hi < lo then 0 else fromIntegral hi - fromIntegral lo + 1

instance Ix Int64 where
  range (lo, hi) = [lo .. hi]
  index b@(lo, _) i =
    if inRange b i then fromIntegral i - fromIntegral lo
    else error "Error in array index"
  inRange (lo, hi) i = i >= lo && i <= hi
  rangeSize (lo, hi) =
    if hi < lo then 0 else fromIntegral hi - fromIntegral lo + 1

instance Ix Word8 where
  range (lo, hi) = [lo .. hi]
  index b@(lo, _) i =
    if inRange b i then fromIntegral i - fromIntegral lo
    else error "Error in array index"
  inRange (lo, hi) i = i >= lo && i <= hi
  rangeSize (lo, hi) =
    if hi < lo then 0 else fromIntegral hi - fromIntegral lo + 1

instance Ix Word16 where
  range (lo, hi) = [lo .. hi]
  index b@(lo, _) i =
    if inRange b i then fromIntegral i - fromIntegral lo
    else error "Error in array index"
  inRange (lo, hi) i = i >= lo && i <= hi
  rangeSize (lo, hi) =
    if hi < lo then 0 else fromIntegral hi - fromIntegral lo + 1

instance Ix Word32 where
  range (lo, hi) = [lo .. hi]
  index b@(lo, _) i =
    if inRange b i then fromIntegral i - fromIntegral lo
    else error "Error in array index"
  inRange (lo, hi) i = i >= lo && i <= hi
  rangeSize (lo, hi) =
    if hi < lo then 0 else fromIntegral hi - fromIntegral lo + 1

instance Ix Word64 where
  range (lo, hi) = [lo .. hi]
  index b@(lo, _) i =
    if inRange b i then fromIntegral i - fromIntegral lo
    else error "Error in array index"
  inRange (lo, hi) i = i >= lo && i <= hi
  rangeSize (lo, hi) =
    if hi < lo then 0 else fromIntegral hi - fromIntegral lo + 1

instance Ix Word where
  range (lo, hi) = [lo .. hi]
  index b@(lo, _) i =
    if inRange b i then fromIntegral i - fromIntegral lo
    else errorWithoutStackTrace "Error in array index"
  inRange (lo, hi) i = i >= lo && i <= hi
  rangeSize (lo, hi) =
    if hi < lo then 0 else fromIntegral hi - fromIntegral lo + 1
