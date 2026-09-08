-- An exception raised inside a Haskell callback that C is calling
-- (here libc's qsort comparator) cannot unwind through the foreign
-- frames: it is fatal at the callback boundary, even under a
-- Haskell catch around the C call (docs/exceptions-design-note.md).
-- Found by the M137 adversarial review: the wrapper armed no frame
-- and the longjmp skipped qsort's frames.
{-# LANGUAGE ForeignFunctionInterface #-}

foreign import ccall "qsort" c_qsort
  :: Ptr a -> CSize -> CSize
  -> FunPtr (Ptr a -> Ptr a -> IO CInt) -> IO ()
foreign import ccall "wrapper" mkCmp
  :: (Ptr a -> Ptr a -> IO CInt)
  -> IO (FunPtr (Ptr a -> Ptr a -> IO CInt))

main :: IO ()
main = do
  putStrLn "before"
  p <- mallocBytes 64
  cmp <- mkCmp (\_ _ -> primThrowIO (primExcErrorCall "from inside qsort"))
  primCatch (c_qsort p 8 8 cmp) (\_ -> putStrLn "unreached: caught across C")
  putStrLn "unreached"
