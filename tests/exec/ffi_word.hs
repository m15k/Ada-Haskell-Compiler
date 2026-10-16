-- Word (M150, its own type) crosses the FFI as uint64_t, as Word64
-- does: size_t in and out, including a Word above 2^63 (a bignum in
-- AHC's representation) as an argument.
{-# LANGUAGE ForeignFunctionInterface #-}

foreign import ccall "strnlen" c_strnlen :: String -> Word -> Word

main :: IO ()
main = do
  print (c_strnlen "fixed widths" 5)
  print (c_strnlen "abc" maxBound)
  print (c_strnlen "" 0, c_strnlen "twelve chars" 100 + 1)
