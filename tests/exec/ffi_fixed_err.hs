-- A literal beyond the declared C width WRAPS like GHC's fixed-width
-- types (M139): 3000000000 :: CInt is -1294967296 before the call ever
-- reaches C, and abs of that is 1294967296 - GHC prints the same. The
-- boundary's own range check stays as belt and braces; no Haskell
-- value can reach it out of range any more (until M139 the literal
-- stayed 3000000000 and died there: "FFI: Int32 argument out of range").
{-# LANGUAGE ForeignFunctionInterface #-}

foreign import ccall "abs" c_abs :: CInt -> CInt

main :: IO ()
main = do
  print (3000000000 :: CInt)
  print (c_abs 3000000000)
