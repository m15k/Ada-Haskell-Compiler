-- An entry whose barrier can never hold again: every task blocks,
-- and the scheduler reports it - same detector, new wait queue.
import Control.Concurrent.Protected

main :: IO ()
main = do
  p <- newProtected (0 :: Int)
  putStrLn "waiting for what never comes"
  entry p (\n -> n > 0) (\n -> (n, n)) >>= print
