-- An IORef shared by green tasks under the deterministic scheduler:
-- reads and writes are not scheduling points, so each modify is
-- atomic with respect to the other tasks, and the schedule (spawn
-- order, yields at IO binds) fixes the interleaving - the same
-- numbers every run. (M139)
import Control.Concurrent.Scoped
import Data.IORef

main :: IO ()
main = do
  r <- newIORef (0 :: Int)
  log_ <- newIORef []
  scope (\s -> do
    spawn s (mapM_ (\i -> modifyIORef' r (+ i) >> modifyIORef log_ (("a" ++ show i) :)) [1 .. 3])
    spawn s (mapM_ (\i -> modifyIORef' r (* i) >> modifyIORef log_ (("b" ++ show i) :)) [2 .. 3])
    return ())
  readIORef r >>= print
  readIORef log_ >>= print . reverse
  -- a stale value is never observed: strict modify forces before store
  c <- newIORef (1 :: Integer)
  mapM_ (\_ -> modifyIORef' c (* 2)) [1 .. 64 :: Int]
  readIORef c >>= print
