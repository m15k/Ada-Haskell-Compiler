-- M127: waitReadOr, all three arms pinned. A message beats a ready
-- fd at the pre-park check; after the park, whichever wake path ran
-- first in program order decided - and in arm 3 the fd IS readable
-- the whole time, but the sibling's send wakes the selector before
-- the run queue ever drains to a poll. That asymmetry is the
-- deterministic contract, not an accident.
{-# LANGUAGE ForeignFunctionInterface #-}
import Control.Concurrent.Scoped

foreign import ccall "pipe" c_pipe :: Ptr a -> IO CInt
foreign import ccall "write" c_write :: CInt -> String -> CInt -> IO CInt

main :: IO ()
main = do
  p <- mallocBytes 8
  _ <- c_pipe p
  rfd <- peekInt32 p 0
  wfd <- peekInt32 p 4
  free p
  q <- newChan
  send q "already"
  r1 <- waitReadOr (fromIntegral rfd) q
  print (r1 :: Maybe String)
  scope (\sc -> do
    _ <- spawn sc (c_write wfd "x" 1 >> return ())
    r2 <- waitReadOr (fromIntegral rfd) q
    print r2)
  scope (\sc -> do
    _ <- spawn sc (send q "late")
    r3 <- waitReadOr (fromIntegral rfd) q
    print r3)
