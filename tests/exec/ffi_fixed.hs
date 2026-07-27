-- Fixed-width C types: abs and toupper are int(int) - exactly the
-- signatures the Int=long model could not describe honestly. CInt
-- is a synonym of Int32; CSize of Word64.
{-# LANGUAGE ForeignFunctionInterface #-}

foreign import ccall "abs" c_abs :: CInt -> CInt
foreign import ccall "toupper" c_toupper :: CInt -> CInt
foreign import ccall "strlen" c_strlen :: String -> CSize

main :: IO ()
main = do
  print (c_abs (-7))
  print (c_toupper 97)
  print (c_strlen "fixed widths")
  print (fromIntegral (c_abs (-9)) + (1 :: Int))
  print (minBoundish, maxBoundish)
  where
    minBoundish = c_abs (-2147483647)
    maxBoundish = c_abs 2147483647
