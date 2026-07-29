-- Third parallel shape, added to validate the worker governor:
-- embarrassingly parallel. Independent expensive computations with
-- no cross-dependencies, so nothing ever waits on anything and the
-- right worker count is "as many as the hardware has". b_parfib is
-- the opposite (fine grain, tight dependency, wants few) and
-- b_parsort is in between (coarse, front-loaded). A governor that
-- cannot reach the top on this one is not working.
import Control.Parallel

collatz :: Int -> Int
collatz n = go n 0
  where
    go 1 acc = acc
    go m acc =
      if even m then go (m `div` 2) (acc + 1)
                else go (3 * m + 1) (acc + 1)

chunk :: Int -> Int -> Int
chunk lo hi = sum (map collatz [lo .. hi])

-- spark every chunk, then demand them all
parChunks :: [(Int, Int)] -> Int
parChunks [] = 0
parChunks ((lo, hi) : rest) =
  let c = chunk lo hi
      r = parChunks rest
  in c `par` (r `pseq` (c + r))

main :: IO ()
main = print (parChunks [(i * 4000 + 1, (i + 1) * 4000) | i <- [0 .. 47]])
