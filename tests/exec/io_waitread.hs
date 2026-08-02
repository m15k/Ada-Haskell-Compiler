-- M127: waitRead parks the reader on a pipe fd; the runq drains,
-- the scheduler polls, the sibling's write wakes it. The pipe is
-- the test's own FFI plumbing - the runtime never owns the fd.
{-# LANGUAGE ForeignFunctionInterface #-}
import Control.Concurrent.Scoped

foreign import ccall "pipe" c_pipe :: Ptr a -> IO CInt
foreign import ccall "write" c_write :: CInt -> String -> CInt -> IO CInt
foreign import ccall "read" c_read :: CInt -> Ptr a -> CInt -> IO CInt

main :: IO ()
main = do
  p <- mallocBytes 8
  _ <- c_pipe p
  rfd <- peekInt32 p 0
  wfd <- peekInt32 p 4
  free p
  scope (\sc -> do
    _ <- spawn sc (do
      putStrLn "writer: about to write"
      _ <- c_write wfd "ping" 4
      putStrLn "writer: wrote")
    putStrLn "reader: waiting"
    waitRead (fromIntegral rfd)
    buf <- mallocBytes 16
    n <- c_read rfd buf 16
    s <- peekCStringLen buf (fromIntegral n)
    free buf
    putStrLn ("reader: got " ++ s))
