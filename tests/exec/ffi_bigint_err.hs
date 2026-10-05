-- Since M146 Int wraps modulo 2^64 as GHC's, so `2 ^ 70 :: Int` is 0
-- and reaches the foreign call as 0 (GHC 9.4.8 prints 0). Before M146
-- Int promoted to a bignum here and the marshaller refused it; that
-- range check stays as a guard but Int can no longer reach it.
{-# LANGUAGE ForeignFunctionInterface #-}

foreign import ccall unsafe "labs" c_labs :: Int -> Int

main :: IO ()
main = print (c_labs (2 ^ 70))
