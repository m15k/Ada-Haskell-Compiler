-- A shared lazy thunk forced from two tasks: whichever forces
-- first owns the blackhole and updates it; the other sees the
-- indirection. Also a deep-evaluation check for the 64MB green
-- thread stacks (sum builds a 100k-deep thunk chain).
-- Deterministic result (differential against GHC).
import Control.Concurrent.Scoped

main :: IO ()
main = do
  let shared = sum [1 .. 100000 :: Int]
  scope (\s -> do
    t1 <- spawn s (yield >> return (shared + 1))
    t2 <- spawn s (return (shared + 2))
    a <- await t1
    b <- await t2
    print (a, b))
