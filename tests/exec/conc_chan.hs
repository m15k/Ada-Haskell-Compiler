-- Channels: unbounded FIFO, send never blocks, recv parks until a
-- value arrives. Two producers, one consumer; the strict FIFO
-- scheduler fixes the merge order, so this output is a golden.
-- The sum is schedule-independent (differential against GHC).
import Control.Concurrent.Scoped

main :: IO ()
main = scope (\s -> do
  c <- newChan
  spawn s (mapM_ (\i -> send c i) [1, 3, 5])
  spawn s (mapM_ (\i -> send c i) [2, 4, 6])
  let grab 0 = return []
      grab n = recv c >>= \v ->
               grab (n - 1) >>= \vs -> return (v : vs)
  vals <- grab (6 :: Int)
  print (sum (vals :: [Int])))
