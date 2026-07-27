-- Sparks change wall time, never results: the same answer with
-- workers on (default) or off (AHC_WORKERS=0). Differential
-- against GHC via the shim's GHC.Conc re-export.
import Control.Parallel

fib :: Int -> Int
fib n = if n < 2 then n else fib (n - 1) + fib (n - 2)

pfib :: Int -> Int
pfib n =
  if n < 18
    then fib n
    else let a = pfib (n - 2)
             b = pfib (n - 1)
         in a `par` (b `pseq` (a + b))

main :: IO ()
main = do
  print (pfib 27)
  print (sum (map pfib [10 .. 20]))
