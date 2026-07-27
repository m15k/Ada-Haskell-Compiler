-- freeHaskellFunPtr releases the trampoline slot; a later call
-- through the stale function pointer dies cleanly instead of
-- touching a collected closure.
{-# LANGUAGE ForeignFunctionInterface #-}

foreign import ccall "wrapper" mkSigH
  :: (Int -> IO ()) -> IO (FunPtr (Int -> IO ()))
foreign import ccall "signal" c_signal
  :: Int -> FunPtr (Int -> IO ()) -> IO (Ptr ())
foreign import ccall "raise" c_raise :: Int -> IO Int

main :: IO ()
main = do
  s <- mkSigH (\n -> putStrLn ("got " ++ show n))
  _ <- c_signal 2 s
  _ <- c_raise 2
  freeHaskellFunPtr s
  _ <- c_raise 2
  putStrLn "unreachable"
