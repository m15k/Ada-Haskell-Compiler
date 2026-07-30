-- GHC'S MODEL: deterministic parallelism over pure code.
--
-- GHC's bet is that the RUNTIME owns evaluation itself. Because
-- evaluation is graph reduction and the graph is immutable, two
-- threads racing to evaluate the same thunk is not a bug - they
-- compute the same value. That makes `par` an ADVISORY hint that
-- changes wall time and never results, which is the one form of
-- parallelism that needs no synchronisation in the source at all.
--
-- AHC copies this wholesale, because it is right, and it is the
-- one place where AHC's determinism story costs nothing: workers
-- evaluate PURE thunks only, all IO stays on the main capability
-- in the deterministic order, so every golden a program had
-- without workers it keeps with them.
--
-- Run it three ways and diff the output - it does not move:
--     AHC_WORKERS=0 ./parallel     (sparks all fizzle)
--     AHC_WORKERS=2 ./parallel
--     AHC_WORKERS=4 ./parallel
-- AHC_SPARK_STATS=1 prints created/converted/fizzled at exit.
-- Watch the FIZZLE rate, not just the clock: a spark demanded
-- before a worker reaches it did no parallel work.
import Control.Parallel

fib :: Int -> Int
fib n = if n < 2 then n else fib (n - 1) + fib (n - 2)

-- Below the threshold, sparking costs more than it saves - the
-- granularity problem every spark system has. Above it, `par`
-- hands `a` to the pool and `pseq` forces `b` here, so the two
-- halves overlap.
pfib :: Int -> Int
pfib n =
  if n < 18
    then fib n
    else let a = pfib (n - 2)
             b = pfib (n - 1)
         in a `par` (b `pseq` (a + b))

main :: IO ()
main = do
  putStrLn "pfib 27:"
  print (pfib 27)
  putStrLn "sum of pfib 10..20:"
  print (sum (map pfib [10 .. 20]))
