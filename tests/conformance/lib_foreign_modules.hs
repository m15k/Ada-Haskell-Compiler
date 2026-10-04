{-# LANGUAGE ForeignFunctionInterface #-}
-- M145: the GHC homes of the FFI names - Foreign.Ptr, Foreign.C.Types,
-- Foreign.C.String, Foreign.Marshal.Alloc - used through imports only.
import Foreign.C.String (newCString, peekCString)
import Foreign.C.Types
import Foreign.Marshal.Alloc (free, mallocBytes)
import Foreign.Ptr (Ptr, nullPtr, plusPtr)

foreign import ccall "abs" c_abs :: CInt -> CInt

main :: IO ()
main = do
  print (c_abs (-7))
  print (nullPtr == (nullPtr :: Ptr Int))
  p <- mallocBytes 16 :: IO (Ptr Int)
  print (p == nullPtr, plusPtr p 8 == p, plusPtr p 0 == p)
  free p
  s <- newCString "hello ffi"
  t <- peekCString s
  putStrLn t
  free s
