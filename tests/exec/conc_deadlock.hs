-- recv on a channel nobody will ever send to: every green thread
-- is blocked, and the scheduler says so instead of hanging. The
-- six-hour-wedge lesson: a deadlock is a reported, reproducible
-- outcome, not a silent hang.
import Control.Concurrent.Scoped

main :: IO ()
main = do
  c <- newChan
  putStrLn "about to hang"
  (recv c :: IO Int) >>= print
