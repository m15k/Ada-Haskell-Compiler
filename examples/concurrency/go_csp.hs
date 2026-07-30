-- GO'S MODEL: communicating sequential processes.
--
-- Go's bet is that the RUNTIME owns the stacks: goroutines are
-- cheap because the runtime grows and moves them, and channels are
-- the only sanctioned way to share. AHC takes the same shape -
-- lightweight tasks plus channels - and changes exactly one thing:
-- the scheduler is DETERMINISTIC. Go's `go f()` may interleave any
-- way the runtime likes and the race detector is a runtime tool you
-- remember to enable. Here the merge order below is a golden test.
--
-- The other difference is structural. Go has no join: a goroutine
-- outlives the function that started it unless you build a
-- WaitGroup by hand, and a leaked goroutine is the classic Go bug.
-- `scope` cannot return while a child runs, so the leak is not a
-- bug you avoid - it is a program you cannot write.
import Control.Concurrent.Scoped

-- Two producers feeding one consumer. In Go this is a select loop
-- over two channels; unbounded FIFO makes one channel enough.
main :: IO ()
main = scope (\s -> do
  c <- newChan
  spawn s (mapM_ (\i -> send c i) [1, 3, 5])
  spawn s (mapM_ (\i -> send c i) [2, 4, 6])
  let grab 0 = return []
      grab n = recv c >>= \v ->
               grab (n - 1) >>= \vs -> return (v : vs)
  vals <- grab (6 :: Int)
  -- The ORDER is schedule-dependent, and that is the point: under
  -- AHC it is the same every run, so it can be asserted. Under Go
  -- (or GHC) it is whatever the scheduler did this time.
  putStrLn "merge order (deterministic under AHC):"
  print vals
  -- The SUM is schedule-independent - true in any of the four
  -- languages, and the only thing a Go test could assert here.
  putStrLn "sum (schedule-independent):"
  print (sum vals))
