-- GHC implementation of AHC's Control.Concurrent.Protected, for
-- differential testing of schedule-independent programs:
--
--   runghc -i tests/shim program.hs
--
-- The pleasing part (design note section 6.6): GHC's STM expresses
-- the entry barrier in one primitive - `retry`. What AHC builds
-- with a deterministic epilogue over a FIFO queue, the shim gets
-- from the transaction log. Wake ORDER is therefore not
-- differential (STM makes no fairness promise); only programs
-- whose observable output is order-independent belong under the
-- oracle.
module Control.Concurrent.Protected
  ( Protected
  , newProtected, reading, updating, entry
  ) where

import Control.Concurrent.STM

newtype Protected s = MkProt (TVar s)

newProtected :: s -> IO (Protected s)
newProtected s = s `seq` (newTVarIO s >>= \v -> return (MkProt v))

reading :: Protected s -> (s -> a) -> IO a
reading (MkProt v) f =
  atomically (readTVar v >>= \s -> return (f s))

updating :: Protected s -> (s -> (s, a)) -> IO a
updating (MkProt v) f =
  atomically (readTVar v >>= \s ->
    case f s of
      (s', r) -> s' `seq` (writeTVar v s' >> return r))

entry :: Protected s -> (s -> Bool) -> (s -> (s, a)) -> IO a
entry (MkProt v) g f =
  atomically (readTVar v >>= \s ->
    if g s
      then case f s of
             (s', r) -> s' `seq` (writeTVar v s' >> return r)
      else retry)
