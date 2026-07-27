-- GHC implementation of AHC's Control.Concurrent.Scoped, so that
-- concurrent programs whose OBSERVABLE OUTPUT is deterministic stay
-- differential-testable against the GHC oracle:
--
--   runghc -i tests/shim program.hs
--
-- (docs/concurrency-design-note.md section 2.2). Underneath it is
-- forkIO + MVar + Chan from base - the unstructured primitives this
-- module exists to invert. Schedule-SENSITIVE programs (interleaved
-- prints) are meaningless under GHC's nondeterministic scheduler;
-- those are pinned as AHC-only exec goldens instead.
--
-- Failure propagation carries GHC's exception text, not AHC's
-- "ahc: ..." format, so death messages are also not differential.
module Control.Concurrent.Scoped
  ( Scope, Task, Chan
  , scope, spawn, await, yield
  , newChan, send, recv
  ) where

import Control.Concurrent (forkIO)
import qualified Control.Concurrent as C
import Control.Concurrent.MVar
import qualified Control.Concurrent.Chan as Ch
import Control.Exception
import Data.IORef

data Child = Child (MVar (Either SomeException ())) (IORef Bool)

newtype Scope = MkScope (IORef [Child])

data Task a = MkTask (MVar (Either SomeException a)) (IORef Bool)

newtype Chan a = MkChan (Ch.Chan a)

-- Joins every child (in spawn order) before returning; a failed
-- child nobody awaited re-raises here - Ada's master rule.
scope :: (Scope -> IO a) -> IO a
scope f = do
  kids <- newIORef []
  r <- f (MkScope kids)
  cs <- readIORef kids
  mapM_ joinChild (reverse cs)
  return r
  where
    joinChild (Child done awaited) = do
      e <- readMVar done
      aw <- readIORef awaited
      case (e, aw) of
        (Left ex, False) -> throwIO ex
        _                -> return ()

spawn :: Scope -> IO a -> IO (Task a)
spawn (MkScope kids) act = do
  res <- newEmptyMVar
  done <- newEmptyMVar
  awaited <- newIORef False
  _ <- forkIO $ do
    e <- try act
    putMVar res e
    putMVar done (either Left (const (Right ())) e)
  modifyIORef kids (Child done awaited :)
  return (MkTask res awaited)

await :: Task a -> IO a
await (MkTask res awaited) = do
  writeIORef awaited True
  e <- readMVar res
  either throwIO return e

newChan :: IO (Chan a)
newChan = Ch.newChan >>= \c -> return (MkChan c)

send :: Chan a -> a -> IO ()
send (MkChan c) = Ch.writeChan c

recv :: Chan a -> IO a
recv (MkChan c) = Ch.readChan c

yield :: IO ()
yield = C.yield
