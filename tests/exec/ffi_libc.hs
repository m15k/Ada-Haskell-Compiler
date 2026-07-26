-- Pure foreign imports against libc/libm: no extra link flags, no
-- extra headers. Sticks to long/double/pointer-shaped signatures
-- (the v1 Int=long type model).
{-# LANGUAGE ForeignFunctionInterface #-}

foreign import ccall unsafe "labs" c_labs :: Int -> Int
foreign import ccall unsafe "sin" c_sin :: Double -> Double
foreign import ccall unsafe "fabs" c_fabs :: Double -> Double
foreign import ccall unsafe "strlen" c_strlen :: String -> Int

main :: IO ()
main = do
  print (c_labs (-5))
  print (map c_labs [-3, 0, 7])
  print (c_sin 0.0)
  print (c_fabs (-2.5))
  print (c_strlen "hello, ffi")
  print (c_strlen "")
