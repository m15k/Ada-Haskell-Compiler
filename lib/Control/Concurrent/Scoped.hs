module Control.Concurrent.Scoped
  ( Scope, Task, Chan
  , scope, spawn, await, yield
  , newChan, send, recv
  ) where

-- Deterministic structured concurrency
-- (docs/concurrency-design-note.md). Green threads on one OS
-- thread; the scheduler is a strict FIFO round robin whose only
-- scheduling points are the IO bind boundaries, blocking
-- operations, and yield - so the same program on the same input
-- runs the same schedule, every run.
--
-- Structure is Ada's master rule: scope cannot return while its
-- children run, await re-raises a child's death, and a failed
-- child nobody awaited fails the scope itself. Threads cannot
-- leak by construction.
--
-- All three types are ABSTRACT: the constructors stay private, so
-- the only values in circulation come from scope, spawn, and
-- newChan. Underneath each is an index into a runtime registry -
-- never a raw pointer, so a Task or Scope leaked past its scope
-- fails with a clean message instead of undefined behavior. The
-- phantom parameters on Task and Chan restore the type safety the
-- Int-typed prims give away.

data Scope = MkScope Int

data Task a = MkTask Int

data Chan a = MkChan Int

-- scope f joins ALL children spawned in f before returning.
scope :: (Scope -> IO a) -> IO a
scope f = primScope (\i -> f (MkScope i))

-- The child runs when the spawner next reaches a scheduling
-- point; spawning itself does not switch.
spawn :: Scope -> IO a -> IO (Task a)
spawn (MkScope s) act = primSpawn s act >>= \i -> return (MkTask i)

-- Blocks until the task finishes; re-raises its failure.
await :: Task a -> IO a
await (MkTask i) = primAwait i

-- Unbounded FIFO channel: send never blocks, recv blocks while
-- the channel is empty. Parked receivers are served in arrival
-- order.
newChan :: IO (Chan a)
newChan = primChanNew >>= \i -> return (MkChan i)

send :: Chan a -> a -> IO ()
send (MkChan c) x = primChanSend c x

recv :: Chan a -> IO a
recv (MkChan c) = primChanRecv c

-- Give every other runnable task one turn.
yield :: IO ()
yield = primYield
