-- Data.IORef: a mutable cell, lazy and strict modification, atomic
-- variants (plain ones under a deterministic scheduler), pointer
-- equality.
import Data.IORef
import Control.Monad

main :: IO ()
main = do
  r <- newIORef (0 :: Int)
  writeIORef r 41
  modifyIORef r (+ 1)
  readIORef r >>= print
  forM_ [1 .. 1000] (\i -> modifyIORef' r (+ i))
  readIORef r >>= print
  b <- atomicModifyIORef r (\x -> (x * 2, x))
  print b
  readIORef r >>= print
  c <- atomicModifyIORef' r (\x -> (x - 1, show x))
  putStrLn c
  atomicWriteIORef r 7
  readIORef r >>= print
  s <- newIORef "start"
  modifyIORef s (++ "!")
  readIORef s >>= putStrLn
  r2 <- newIORef (0 :: Int)
  print (r == r, r == r2)
  -- laziness: modifyIORef does not force; the value is a thunk until read
  lz <- newIORef (1 :: Int)
  modifyIORef lz (const (error "never forced"))
  writeIORef lz 3
  readIORef lz >>= print
  -- a counter shared by a list of actions
  counter <- newIORef (0 :: Int)
  let tick = modifyIORef' counter (+ 1)
  sequence_ (replicate 5 tick)
  readIORef counter >>= print
