-- A value outside the declared C width dies at the boundary rather
-- than truncating.
{-# LANGUAGE ForeignFunctionInterface #-}

foreign import ccall "abs" c_abs :: CInt -> CInt

main :: IO ()
main = print (c_abs 3000000000)
