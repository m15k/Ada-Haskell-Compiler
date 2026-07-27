-- An error inside sparked pure code cannot surface from a worker:
-- the worker parks it in the value, and it re-raises exactly when
-- the program demands it - the failure point is deterministic, so
-- this is a golden. (The spark IS evaluated: the program keeps
-- running after it.)
import Control.Parallel

main :: IO ()
main = do
  let boom = error "sparked boom" :: Int
      ok = sum [1 .. 1000] :: Int
  boom `par` (ok `pseq` print ok)
  putStrLn "alive after the spark ran"
  print (boom + 1)
  putStrLn "unreached"
