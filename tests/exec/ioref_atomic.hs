-- atomicModifyIORef' under two green tasks: the read and the write of
-- one modification are a single primitive step, so no bind (a
-- scheduling point) can separate them and no update is lost. The M139
-- review found the `writeIORef r y >> return b` version losing 999 of
-- 2000 increments.
import Control.Concurrent.Scoped
import Data.IORef

main :: IO ()
main = do
  r <- newIORef (0 :: Int)
  scope (\s -> do
    spawn s (mapM_ (\_ -> atomicModifyIORef' r (\x -> (x + 1, ()))) [1 .. 1000 :: Int])
    spawn s (mapM_ (\_ -> atomicModifyIORef' r (\x -> (x + 1, ()))) [1 .. 1000 :: Int])
    return ())
  readIORef r >>= print
  q <- newIORef (0 :: Int)
  scope (\s -> do
    spawn s (mapM_ (\_ -> atomicModifyIORef q (\x -> (x + 1, x))) [1 .. 500 :: Int])
    spawn s (mapM_ (\_ -> modifyIORef' q (+ 1)) [1 .. 500 :: Int])
    return ())
  readIORef q >>= print
