module Data.Bits
  ( Bits (..), shiftL, shiftR, popCount, zeroBits, finiteBitSize
  ) where

-- Report/base Data.Bits as a CLASS (M139; it was monomorphic at Int
-- before): instances at Int and the eight fixed-width types. The
-- fixed-width instances work on Int's representation and narrow the
-- result, so shifts wrap, complement stays in range, and popCount
-- counts the width's bits (popCount (-1 :: Int8) is 8). The unsigned
-- types shift right LOGICALLY (a Word64 above 2^63 has its sign bit
-- set in Int's view); testBit beyond the width is False, as GHC's.

infixl 8 `shiftL`, `shiftR`, `shift`
infixl 7 .&.
infixl 6 `xor`
infixl 5 .|.

class Eq a => Bits a where
  (.&.) :: a -> a -> a
  (.|.) :: a -> a -> a
  xor :: a -> a -> a
  complement :: a -> a
  shift :: a -> Int -> a
  bit :: Int -> a
  testBit :: a -> Int -> Bool
  setBit :: a -> Int -> a
  clearBit :: a -> Int -> a
  complementBit :: a -> Int -> a
  popCountBits :: a -> Int
  bitSizeOf :: a -> Int
  setBit x i = x .|. bit i
  clearBit x i = x .&. complement (bit i)
  complementBit x i = x `xor` bit i

-- A negative count is GHC's `arithmetic overflow`.
shiftL :: Bits a => a -> Int -> a
shiftL x i = if i < 0 then primThrow (primExcArith 0) else shift x i

shiftR :: Bits a => a -> Int -> a
shiftR x i = if i < 0 then primThrow (primExcArith 0) else shift x (negate i)

popCount :: Bits a => a -> Int
popCount = popCountBits

zeroBits :: Bits a => a
zeroBits = clearBit (bit 0) 0

finiteBitSize :: Bits a => a -> Int
finiteBitSize = bitSizeOf

instance Bits Int where
  (.&.) a b = primAndI a b
  (.|.) a b = primOrI a b
  xor a b = primXorI a b
  complement a = primComplementI a
  shift a i = if i >= 0 then primShiftLI a i else primShiftRI a (negate i)
  testBit a i = if i < 0 then primThrow (primExcArith 0)
                else i < 64 && primAndI (primShiftRI a i) 1 /= 0
  bit i = if i < 0 then primThrow (primExcArith 0) else primShiftLI 1 i
  popCountBits a = primPopCountI a
  bitSizeOf _ = 64

instance Bits Int8 where
  (.&.) a b = primFixCast (primNarrow 8 1 (primAndI (primFixCast a) (primFixCast b))) :: Int8
  (.|.) a b = primFixCast (primNarrow 8 1 (primOrI (primFixCast a) (primFixCast b))) :: Int8
  xor a b = primFixCast (primNarrow 8 1 (primXorI (primFixCast a) (primFixCast b))) :: Int8
  complement a = primFixCast (primNarrow 8 1 (primComplementI (primFixCast a))) :: Int8
  shift a i = primFixCast (primNarrow 8 1 (if i >= 0 then primShiftLI (primFixCast a) i
                                          else primShiftRI (primFixCast a) (negate i))) :: Int8
  bit i = if i < 0 then primThrow (primExcArith 0)
          else primFixCast (primNarrow 8 1 (primShiftLI 1 i)) :: Int8
  testBit a i = if i < 0 then primThrow (primExcArith 0)
                else i < 8 && primAndI (primShiftRI (primFixCast a :: Int) i) 1 /= 0
  popCountBits a = primPopCountI (primNarrow 8 0 (primFixCast a))
  bitSizeOf _ = 8

instance Bits Int16 where
  (.&.) a b = primFixCast (primNarrow 16 1 (primAndI (primFixCast a) (primFixCast b))) :: Int16
  (.|.) a b = primFixCast (primNarrow 16 1 (primOrI (primFixCast a) (primFixCast b))) :: Int16
  xor a b = primFixCast (primNarrow 16 1 (primXorI (primFixCast a) (primFixCast b))) :: Int16
  complement a = primFixCast (primNarrow 16 1 (primComplementI (primFixCast a))) :: Int16
  shift a i = primFixCast (primNarrow 16 1 (if i >= 0 then primShiftLI (primFixCast a) i
                                          else primShiftRI (primFixCast a) (negate i))) :: Int16
  bit i = if i < 0 then primThrow (primExcArith 0)
          else primFixCast (primNarrow 16 1 (primShiftLI 1 i)) :: Int16
  testBit a i = if i < 0 then primThrow (primExcArith 0)
                else i < 16 && primAndI (primShiftRI (primFixCast a :: Int) i) 1 /= 0
  popCountBits a = primPopCountI (primNarrow 16 0 (primFixCast a))
  bitSizeOf _ = 16

instance Bits Int32 where
  (.&.) a b = primFixCast (primNarrow 32 1 (primAndI (primFixCast a) (primFixCast b))) :: Int32
  (.|.) a b = primFixCast (primNarrow 32 1 (primOrI (primFixCast a) (primFixCast b))) :: Int32
  xor a b = primFixCast (primNarrow 32 1 (primXorI (primFixCast a) (primFixCast b))) :: Int32
  complement a = primFixCast (primNarrow 32 1 (primComplementI (primFixCast a))) :: Int32
  shift a i = primFixCast (primNarrow 32 1 (if i >= 0 then primShiftLI (primFixCast a) i
                                          else primShiftRI (primFixCast a) (negate i))) :: Int32
  bit i = if i < 0 then primThrow (primExcArith 0)
          else primFixCast (primNarrow 32 1 (primShiftLI 1 i)) :: Int32
  testBit a i = if i < 0 then primThrow (primExcArith 0)
                else i < 32 && primAndI (primShiftRI (primFixCast a :: Int) i) 1 /= 0
  popCountBits a = primPopCountI (primNarrow 32 0 (primFixCast a))
  bitSizeOf _ = 32

instance Bits Int64 where
  (.&.) a b = primFixCast (primNarrow 64 1 (primAndI (primFixCast a) (primFixCast b))) :: Int64
  (.|.) a b = primFixCast (primNarrow 64 1 (primOrI (primFixCast a) (primFixCast b))) :: Int64
  xor a b = primFixCast (primNarrow 64 1 (primXorI (primFixCast a) (primFixCast b))) :: Int64
  complement a = primFixCast (primNarrow 64 1 (primComplementI (primFixCast a))) :: Int64
  shift a i = primFixCast (primNarrow 64 1 (if i >= 0 then primShiftLI (primFixCast a) i
                                          else primShiftRI (primFixCast a) (negate i))) :: Int64
  bit i = if i < 0 then primThrow (primExcArith 0)
          else primFixCast (primNarrow 64 1 (primShiftLI 1 i)) :: Int64
  testBit a i = if i < 0 then primThrow (primExcArith 0)
                else i < 64 && primAndI (primShiftRI (primFixCast a :: Int) i) 1 /= 0
  popCountBits a = primPopCountI (primNarrow 64 0 (primFixCast a))
  bitSizeOf _ = 64

instance Bits Word8 where
  (.&.) a b = primFixCast (primNarrow 8 0 (primAndI (primFixCast a) (primFixCast b))) :: Word8
  (.|.) a b = primFixCast (primNarrow 8 0 (primOrI (primFixCast a) (primFixCast b))) :: Word8
  xor a b = primFixCast (primNarrow 8 0 (primXorI (primFixCast a) (primFixCast b))) :: Word8
  complement a = primFixCast (primNarrow 8 0 (primComplementI (primFixCast a))) :: Word8
  shift a i = primFixCast (primNarrow 8 0 (if i >= 0 then primShiftLI (primFixCast a) i
                                          else primShiftRU (primFixCast a) (negate i))) :: Word8
  bit i = if i < 0 then primThrow (primExcArith 0)
          else primFixCast (primNarrow 8 0 (primShiftLI 1 i)) :: Word8
  testBit a i = if i < 0 then primThrow (primExcArith 0)
                else i < 8 && primAndI (primShiftRU (primFixCast a :: Int) i) 1 /= 0
  popCountBits a = primPopCountI (primNarrow 8 0 (primFixCast a))
  bitSizeOf _ = 8

instance Bits Word16 where
  (.&.) a b = primFixCast (primNarrow 16 0 (primAndI (primFixCast a) (primFixCast b))) :: Word16
  (.|.) a b = primFixCast (primNarrow 16 0 (primOrI (primFixCast a) (primFixCast b))) :: Word16
  xor a b = primFixCast (primNarrow 16 0 (primXorI (primFixCast a) (primFixCast b))) :: Word16
  complement a = primFixCast (primNarrow 16 0 (primComplementI (primFixCast a))) :: Word16
  shift a i = primFixCast (primNarrow 16 0 (if i >= 0 then primShiftLI (primFixCast a) i
                                          else primShiftRU (primFixCast a) (negate i))) :: Word16
  bit i = if i < 0 then primThrow (primExcArith 0)
          else primFixCast (primNarrow 16 0 (primShiftLI 1 i)) :: Word16
  testBit a i = if i < 0 then primThrow (primExcArith 0)
                else i < 16 && primAndI (primShiftRU (primFixCast a :: Int) i) 1 /= 0
  popCountBits a = primPopCountI (primNarrow 16 0 (primFixCast a))
  bitSizeOf _ = 16

instance Bits Word32 where
  (.&.) a b = primFixCast (primNarrow 32 0 (primAndI (primFixCast a) (primFixCast b))) :: Word32
  (.|.) a b = primFixCast (primNarrow 32 0 (primOrI (primFixCast a) (primFixCast b))) :: Word32
  xor a b = primFixCast (primNarrow 32 0 (primXorI (primFixCast a) (primFixCast b))) :: Word32
  complement a = primFixCast (primNarrow 32 0 (primComplementI (primFixCast a))) :: Word32
  shift a i = primFixCast (primNarrow 32 0 (if i >= 0 then primShiftLI (primFixCast a) i
                                          else primShiftRU (primFixCast a) (negate i))) :: Word32
  bit i = if i < 0 then primThrow (primExcArith 0)
          else primFixCast (primNarrow 32 0 (primShiftLI 1 i)) :: Word32
  testBit a i = if i < 0 then primThrow (primExcArith 0)
                else i < 32 && primAndI (primShiftRU (primFixCast a :: Int) i) 1 /= 0
  popCountBits a = primPopCountI (primNarrow 32 0 (primFixCast a))
  bitSizeOf _ = 32

instance Bits Word64 where
  (.&.) a b = primFixCast (primNarrow 64 0 (primAndI (primFixCast a) (primFixCast b))) :: Word64
  (.|.) a b = primFixCast (primNarrow 64 0 (primOrI (primFixCast a) (primFixCast b))) :: Word64
  xor a b = primFixCast (primNarrow 64 0 (primXorI (primFixCast a) (primFixCast b))) :: Word64
  complement a = primFixCast (primNarrow 64 0 (primComplementI (primFixCast a))) :: Word64
  shift a i = primFixCast (primNarrow 64 0 (if i >= 0 then primShiftLI (primFixCast a) i
                                          else primShiftRU (primFixCast a) (negate i))) :: Word64
  bit i = if i < 0 then primThrow (primExcArith 0)
          else primFixCast (primNarrow 64 0 (primShiftLI 1 i)) :: Word64
  testBit a i = if i < 0 then primThrow (primExcArith 0)
                else i < 64 && primAndI (primShiftRU (primFixCast a :: Int) i) 1 /= 0
  popCountBits a = primPopCountI (primNarrow 64 0 (primFixCast a))
  bitSizeOf _ = 64
