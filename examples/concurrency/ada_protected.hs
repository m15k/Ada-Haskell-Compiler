-- ADA'S MODEL: the protected object.
--
-- Ada's bet is that the LANGUAGE owns the tasks. Concurrency is
-- not a library - tasks, entries, and protected objects are
-- syntax, so the compiler can enforce rules about them. The
-- protected object is the good idea: shared state whose every
-- access is mutually exclusive by construction, with `entry`
-- barriers replacing condition variables.
--
-- AHC takes it and makes ONE improvement Ada cannot. In Ada,
-- "a protected body must not block" is a RULE - partly compiler-
-- checked (no accept, no entry call), partly a runtime bounded-
-- error you can still trip through a subprogram call. Here
-- transitions are PURE FUNCTIONS:
--
--     updating :: Protected s -> (s -> (s, a)) -> IO a
--
-- and s -> (s, a) has no IO in it. The no-blocking rule is not a
-- rule; it is a TYPE. You cannot send, recv, await, or print
-- inside a transition, because the type has nowhere to put them.
--
-- The second improvement is that contracts reach shared state.
-- Name a transition at top level, attach PRE/POST, and the check
-- fires INSIDE the protected action - so a state-wide invariant
-- is verified before any other task can observe the state.
import Control.Concurrent.Scoped
import Control.Concurrent.Protected

-- The state: a queue and its capacity.
type Buffer = ([Int], Int)

-- Barriers. In Ada these are the boolean expressions after
-- `when` on an entry; a task calling the entry parks until its
-- barrier holds, and the barriers are re-evaluated after every
-- commit.
notFull :: Buffer -> Bool
notFull (xs, cap) = length xs < cap

notEmpty :: Buffer -> Bool
notEmpty (xs, _) = not (null xs)

-- Transitions, with the invariant stated as a contract. POST is
-- the boundary-checked instrument: it fires inside the action,
-- so no task can ever SEE the buffer over capacity.
{-# POST push \x s r -> length (fst (fst r)) <= snd s #-}
push :: Int -> Buffer -> (Buffer, ())
push x (xs, cap) = ((xs ++ [x], cap), ())

-- The PRE is the specification; the second equation is what Ada
-- would write as `raise Program_Error` - unreachable, because the
-- notEmpty barrier is what admits a task to this transition in the
-- first place. Stating it keeps the function total (no warning)
-- without pretending the empty case is meaningful.
{-# PRE pop \s -> not (null (fst s)) #-}
pop :: Buffer -> (Buffer, Int)
pop (x : xs, cap) = ((xs, cap), x)
pop ([], _) = error "pop: barrier admitted an empty buffer"

main :: IO ()
main = do
  -- Capacity 2, six items: the producer MUST park on notFull,
  -- and the consumer MUST park on notEmpty. Neither holds a
  -- lock; both are woken by the deterministic epilogue, which
  -- rescans waiting entries from the head after every commit
  -- (Ada's "eggshell" rule, with the order pinned so wake order
  -- is a golden like every other schedule here).
  b <- newProtected ([], 2)
  scope (\s -> do
    spawn s (mapM_ (\i -> entry b notFull (push i)) [1 .. 6])
    spawn s (mapM_ (\_ -> entry b notEmpty pop >>= print) [1 .. 6 :: Int])
    return ())
  putStrLn "drained"

  -- `reading` observes without transitioning. It is separate from
  -- `updating` for the same reason Ada distinguishes functions
  -- from procedures on a protected type: readers do not have to
  -- exclude one another.
  c <- newProtected (0 :: Int)
  scope (\s -> do
    spawn s (mapM_ (\_ -> updating c (\n -> (n + 1, ()))) [1 .. 100 :: Int])
    spawn s (mapM_ (\_ -> updating c (\n -> (n + 1, ()))) [1 .. 100 :: Int])
    return ())
  total <- reading c (\n -> n)
  putStrLn "two tasks, 100 increments each:"
  print total
