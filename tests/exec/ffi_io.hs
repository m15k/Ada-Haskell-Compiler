-- IO foreign imports: world-passing ordering, Ptr results, nullPtr,
-- peekCString. Uses an environment variable that is never set, so
-- the output is deterministic.
{-# LANGUAGE ForeignFunctionInterface #-}

foreign import ccall getenv :: String -> IO (Ptr Char)
foreign import ccall "srand" c_srand :: Int -> IO ()

main :: IO ()
main = do
  putStrLn "before"
  c_srand 42
  p <- getenv "AHC_TEST_VARIABLE_THAT_IS_NEVER_SET"
  print (p == nullPtr)
  putStrLn "after"
