-- Structured concurrency basics: spawn, await, results, and the
-- master rule (scope joins its children). Deterministic output;
-- also differential against GHC via tests/shim.
import Control.Concurrent.Scoped

main :: IO ()
main = do
  putStrLn "before"
  r <- scope (\s -> do
    t1 <- spawn s (return (2 + 3))
    t2 <- spawn s (putStrLn "child runs" >> return 10)
    a <- await t1
    b <- await t2
    inner <- scope (\s2 -> do
      t3 <- spawn s2 (return (a * b))
      await t3)
    return (a + b + inner))
  print r
  putStrLn "after"
