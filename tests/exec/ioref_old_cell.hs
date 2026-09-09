-- A write into an IORef cell that has lived through collections: the
-- young value stored into the OLD cell must be seen by the own
-- collector (the barrier belongs on the fields array whose word
-- changed, not on the node). The M139 review found the value lost
-- under AHC_GC=own with a paranoid verifier; this pins the read-back.
import Data.IORef

churn :: Int -> Int -> Int
churn i acc = if i == 0 then acc else churn (i - 1) (acc + length (show i))

main :: IO ()
main = do
  r <- newIORef (0 :: Int)
  print (churn 300000 0)               -- age the cell across collections
  let go :: Int -> IO ()
      go 0 = return ()
      go n = do
        writeIORef r (n * 3)
        modifyIORef' r (+ 1)
        _ <- return $! churn 200 0     -- allocate between writes
        go (n - 1)
  go 20000
  readIORef r >>= print
  rl <- newIORef []
  mapM_ (\i -> modifyIORef rl (i :)) [1 .. 50000 :: Int]
  xs <- readIORef rl
  print (sum xs, length xs)
