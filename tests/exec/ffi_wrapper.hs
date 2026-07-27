-- "wrapper" imports: Haskell closures as C function pointers, driven
-- back into the runtime by libc itself (signal delivered by raise,
-- atexit at process exit). SIGINT = 2 on every POSIX platform.
{-# LANGUAGE ForeignFunctionInterface #-}

foreign import ccall "wrapper" mkHandler :: IO () -> IO (FunPtr (IO ()))
foreign import ccall "wrapper" mkSigH
  :: (Int -> IO ()) -> IO (FunPtr (Int -> IO ()))
foreign import ccall atexit :: FunPtr (IO ()) -> IO Int
foreign import ccall "signal" c_signal
  :: Int -> FunPtr (Int -> IO ()) -> IO (Ptr ())
foreign import ccall "raise" c_raise :: Int -> IO Int

main :: IO ()
main = do
  h <- mkHandler (putStrLn "atexit: goodbye from a Haskell callback")
  _ <- atexit h
  s <- mkSigH (\n -> putStrLn ("signal handler got " ++ show n))
  _ <- c_signal 2 s
  _ <- c_raise 2
  print (h == nullFunPtr)
  putStrLn "main done"
