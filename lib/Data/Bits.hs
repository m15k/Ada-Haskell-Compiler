module Data.Bits
  ( (.&.), (.|.), xor, shiftL, shiftR, shift
  , complement, testBit, setBit, clearBit, bit, popCount
  ) where

infixl 8 `shiftL`, `shiftR`
infixl 7 .&.
infixl 6 `xor`
infixl 5 .|.

(.&.) :: Int -> Int -> Int
(.&.) a b = primAndI a b

(.|.) :: Int -> Int -> Int
(.|.) a b = primOrI a b

xor :: Int -> Int -> Int
xor a b = primXorI a b

shiftL :: Int -> Int -> Int
shiftL a n = primShiftLI a n

shiftR :: Int -> Int -> Int
shiftR a n = primShiftRI a n

shift :: Int -> Int -> Int
shift a n = if n >= 0 then shiftL a n else shiftR a (negate n)

complement :: Int -> Int
complement a = primComplementI a

bit :: Int -> Int
bit n = shiftL 1 n

testBit :: Int -> Int -> Bool
testBit a n = (a .&. bit n) /= 0

setBit :: Int -> Int -> Int
setBit a n = a .|. bit n

clearBit :: Int -> Int -> Int
clearBit a n = a .&. complement (bit n)

popCount :: Int -> Int
popCount a = primPopCountI a
