-- B1 gate workload 1 (design note 7.6): parallel fib with a grain
-- cutoff. Sparks: one per node above the cutoff.
import Control.Parallel

fib :: Int -> Int
fib n = if n < 2 then n else fib (n - 1) + fib (n - 2)

pfib :: Int -> Int
pfib n =
  if n < 25
    then fib n
    else let a = pfib (n - 2)
             b = pfib (n - 1)
         in a `par` (b `pseq` (a + b))

main :: IO ()
main = print (pfib 33)
