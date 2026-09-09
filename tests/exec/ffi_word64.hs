-- A Word64 above 2^63 - a bignum in AHC's representation - crosses
-- the FFI boundary in both directions and through poke/peek (M139
-- review: the unboxing check demanded a plain Int and died "argument
-- out of range").
{-# LANGUAGE ForeignFunctionInterface #-}

foreign import ccall "llabs" c_llabs :: Int64 -> Int64

main :: IO ()
main = do
  p <- mallocBytes 16
  pokeWord64 p 0 (maxBound :: Word64)
  pokeWord64 p 8 (2 ^ 63 + 7 :: Word64)
  a <- peekWord64 p 0
  b <- peekWord64 p 8
  print (a, b, a == maxBound)
  print (c_llabs (minBound + 1), c_llabs (-5))
  pokeInt64 p 0 (minBound :: Int64)
  peekInt64 p 0 >>= print
