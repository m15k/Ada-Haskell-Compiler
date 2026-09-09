-- Data.Bits over Int and the fixed-width types: masks, shifts that
-- wrap, complement staying in range, popCount of the width's bits.
import Data.Bits
import Data.Int
import Data.Word

main :: IO ()
main = do
  print (0xF0 .&. 0x3C :: Int, 0xF0 .|. 0x0F :: Int, xor 0xFF 0x0F :: Int)
  print (shiftL 1 10 :: Int, shiftR 1024 3 :: Int, complement 0 :: Int, popCount (255 :: Int))
  print (testBit (5 :: Int) 0, testBit (5 :: Int) 1, setBit (0 :: Int) 4, clearBit (31 :: Int) 0)
  print (complement 0 :: Word8, complement 0 :: Int8, shiftL 1 7 :: Int8, shiftL 200 1 :: Word8)
  print (shiftR (-128) 3 :: Int8, shiftR 128 3 :: Word8, popCount (-1 :: Int8), popCount (maxBound :: Word16))
  print ((0xAB :: Word8) .&. 0x0F, (0xAB :: Word8) .|. 0x0F, xor (0xAB :: Word8) 0xFF)
  print (bit 15 :: Word16, bit 15 :: Int16, testBit (128 :: Word8) 7, setBit (0 :: Int64) 63)
  print (complementBit (0 :: Word8) 3, finiteBitSize (0 :: Int32), zeroBits :: Word8)
  print (shift (1 :: Word32) 31, shift (0x80000000 :: Word32) (-31), shift (1 :: Int32) 31)
