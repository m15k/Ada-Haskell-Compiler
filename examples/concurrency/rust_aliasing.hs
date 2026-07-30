-- RUST'S MODEL: the type system owns aliasing.
--
-- Rust's bet is the sharpest of the four. Data races need three
-- ingredients - aliasing, mutation, concurrency - and Rust
-- statically forbids the FIRST TWO from co-occurring: `&T` may
-- alias but not mutate, `&mut T` may mutate but not alias. Send
-- and Sync then lift that to threads, so "data race" becomes a
-- COMPILE ERROR for arbitrary data structures, at zero runtime
-- cost.
--
-- AHC reaches the same guarantee by deleting a different
-- ingredient. It does not track aliasing, because it does not
-- have to: values are IMMUTABLE, so aliasing is unlimited and
-- free, and the only mutable state in the language is a
-- Protected, whose transitions are pure. No aliasing analysis is
-- needed when there is nothing to alias mutably.
--
-- BE CLEAR ABOUT THE TRADE, in both directions:
--
--   Rust wins where mutation is the point. An in-place sort of a
--   10M-element vector across 8 threads is safe AND allocation-
--   free in Rust. Here the same job copies, and the collector
--   pays for it. AHC has no way to say "this thread has exclusive
--   access to this buffer, mutate it freely" - the guarantee comes
--   from the absence of the feature, not from mastering it.
--
--   AHC wins on what the guarantee costs to USE. Rust's discipline
--   is famously load-bearing on the programmer: lifetimes, Arc,
--   Mutex, interior mutability, Send/Sync bounds. Below, the
--   shared structure is passed to both tasks with no annotation of
--   any kind, and it is still race-free.
import Control.Concurrent.Scoped
import Control.Concurrent.Protected

-- Shared IMMUTABLE data. In Rust reaching this from several
-- threads means Arc<Vec<i32>> (or a scoped thread with &). Here
-- it is a plain value: aliasing an immutable structure needs no
-- permission, because no one can write through the alias.
table :: [Int]
table = [1 .. 20]

sumWhere :: (Int -> Bool) -> Int
sumWhere p = sum (filter p table)

main :: IO ()
main = do
  -- Two tasks read the SAME structure concurrently. No Arc, no
  -- clone, no lifetime, no Sync bound - and no race, because
  -- neither task can write to it.
  r <- scope (\s -> do
    t1 <- spawn s (return (sumWhere even))
    t2 <- spawn s (return (sumWhere odd))
    a <- await t1
    b <- await t2
    return (a, b))
  putStrLn "concurrent readers of one immutable structure:"
  print r

  -- Now the part that DOES mutate. This is AHC's whole answer to
  -- Rust's `Mutex<T>`: the state is reachable only through
  -- Protected, and the transition is a pure function.
  --
  -- The type is the enforcement. This does not compile:
  --
  --     updating acc (\n -> do putStrLn "peek"; return (n+1, ()))
  --
  -- not because a rule forbids IO in a critical section, but
  -- because `updating` wants `s -> (s, a)` and there is nowhere
  -- in that type to put an IO action. Rust's Mutex cannot say
  -- this: a Rust critical section can block, do IO, or lock a
  -- second mutex in the wrong order and deadlock.
  acc <- newProtected (0 :: Int)
  scope (\s -> do
    spawn s (mapM_ (\i -> updating acc (\n -> (n + i, ()))) [1 .. 50])
    spawn s (mapM_ (\i -> updating acc (\n -> (n + i, ()))) [51 .. 100])
    return ())
  total <- reading acc (\n -> n)
  putStrLn "100 interleaved updates, no lock in the source:"
  print total
