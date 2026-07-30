-- B2: WHAT IS MISSING, measured rather than asserted.
--
--     b2_smp par        [n]   pure parallelism  - SCALES
--     b2_smp spawn      [n]   task parallelism  - DOES NOT SCALE
--     b2_smp interleave       concurrency       - works fine
--
-- AHC's Phase B shipped in two stages and only the first is built.
--
--   B1 (SHIPPED) - sparks. Worker OS threads evaluate PURE thunks.
--                  `par` really does use every core.
--   B2 (NOT BUILT) - SMP scheduling. Green tasks would run on
--                  several OS threads, so IO-bearing concurrency
--                  could use more than one core.
--
-- Today every green task shares ONE OS thread. So AHC has real
-- CONCURRENCY (tasks interleave, block, and communicate) and real
-- PARALLELISM for pure code (sparks), but NO parallelism for
-- anything expressed as tasks. That is the whole gap, and the
-- first two modes below make it a number.
--
-- Measured, 6-core box, four fib 29s, interleaved runs:
--
--     workers:            1        2        4
--     own   par        7.61s    4.14s    1.85s   4.1x  B1 works
--     own   spawn      7.02s    6.53s    6.64s   flat  B2 MISSING
--     boehm par        7.05s   10.10s   12.83s   0.55x (!)
--     boehm spawn      6.80s    6.63s    6.57s   flat
--
-- Same answer, same total work, same machine. Two things to read
-- off it, not one:
--
-- 1. THE B2 GAP. own/par scales 4.1x; own/spawn is flat. The only
--    difference is which mechanism carries the work, and one of
--    them has nowhere to put a second core.
--
-- 2. WHY THE COLLECTOR CAMPAIGN HAPPENED. Under the DEFAULT build
--    (Boehm) par does not merely fail to scale - it gets WORSE
--    with every worker added. A graph reducer allocates on every
--    reduction, and Boehm anti-scales under parallel allocation
--    storms, so B1's own gate came back at 0.46-0.70x and the
--    honest default became AHC_WORKERS=0. Build with AHC_GC=own
--    to see B1 actually work. That is the whole reason AHC grew
--    its own collector (docs/collector-design-note.md).
--
-- WHY IT IS NOT BUILT, so this reads as a decision and not a TODO:
-- the deterministic schedule is the project's headline, and it is
-- exactly what a second scheduler thread costs. `--deterministic`
-- stays the default profile; B2 would have to be an opt-in mode
-- with its own weaker guarantee, and that is a design commitment
-- nobody has paid for yet. See docs/concurrency-design-note.md
-- section 7.
import Control.Concurrent.Scoped
import Control.Monad
import Control.Parallel
import System.Environment

fib :: Int -> Int
fib n = if n < 2 then n else fib (n - 1) + fib (n - 2)

-- Four independent chunks - embarrassingly parallel, no
-- dependency between them, nothing to synchronise. If any shape
-- can use four cores, it is this one.
chunks :: Int -> [Int]
chunks n = [n, n, n, n]

-- B1's mechanism: spark three, force the fourth here. Workers
-- take the sparks, so wall time falls as workers are added.
viaPar :: Int -> Int
viaPar n =
  let a = fib n
      b = fib n
      c = fib n
      d = fib n
  in a `par` (b `par` (c `par` (d `pseq` (a + b + c + d))))

-- The same work as tasks. Every spawn is a GREEN thread on the
-- main OS thread, and `await` demands the result there, so the
-- four chunks run one after another no matter how many workers
-- exist. This is the shape B2 would fix.
viaSpawn :: Int -> IO Int
viaSpawn n = scope (\s -> do
  ts <- mapM (\k -> spawn s (return (fib k))) (chunks n)
  rs <- mapM await ts
  return (sum rs))

-- ...and what DOES work, so the gap is not overstated. Tasks
-- interleave, block on channels, and are joined by their scope -
-- concurrency is not the thing that is missing. Only the ability
-- to spend more than one core on it is.
interleave :: IO ()
interleave = scope (\s -> do
  c <- newChan
  spawn s (mapM_ (\i -> send c ("A" ++ show i) >> yield) [1 .. 3 :: Int])
  spawn s (mapM_ (\i -> send c ("B" ++ show i) >> yield) [1 .. 3 :: Int])
  let grab 0 = return []
      grab k = recv c >>= \v -> grab (k - 1) >>= \vs -> return (v : vs)
  vs <- grab (6 :: Int)
  putStrLn (unwords vs))

digitVal :: Char -> Int
digitVal ch = fromEnum ch - fromEnum '0'

parseInt :: String -> Int
parseInt s = foldl (\acc ch -> acc * 10 + digitVal ch) 0 s

-- 27 keeps the goldens quick; pass 30 or more to see the timing
-- table above reproduce.
sizeOf :: [String] -> Int
sizeOf [_, s] = parseInt s
sizeOf _ = 27

main :: IO ()
main = do
  as <- getArgs
  let n = sizeOf as
  case as of
    ("par" : _) -> print (viaPar n)
    ("spawn" : _) -> viaSpawn n >>= print
    ("interleave" : _) -> interleave
    _ -> putStrLn "usage: b2_smp par|spawn|interleave [n]"
