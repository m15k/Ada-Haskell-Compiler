-- Schedule-SENSITIVE output, pinned as an AHC-only golden: the
-- deterministic round-robin scheduler makes an interleaving a
-- testable artifact (GHC cannot pin such a test at all -
-- docs/concurrency-design-note.md section 2.1). Scheduling points
-- are the IO bind boundaries plus the explicit yield.
import Control.Concurrent.Scoped

worker :: String -> Int -> IO ()
worker name n =
  mapM_ (\i -> putStrLn (name ++ " " ++ show i)) [1 .. n]

main :: IO ()
main = scope (\s -> do
  spawn s (worker "a" 3)
  spawn s (worker "b" 3)
  yield
  worker "main" 2)
