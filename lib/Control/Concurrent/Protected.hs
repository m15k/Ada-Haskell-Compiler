module Control.Concurrent.Protected
  ( Protected
  , newProtected, reading, updating, entry
  ) where

-- Ada's protected object, pure-transition edition
-- (docs/concurrency-design-note.md section 6). A Protected s is
-- shared state whose every access is a protected action:
--
--   reading  p f   observes  (f :: s -> a, applied atomically)
--   updating p f   transitions (f :: s -> (s, r))
--   entry p g f    parks until barrier g holds, then transitions
--
-- Operations are PURE, so the no-blocking rule of Ada's protected
-- bodies is a type here, not a runtime check - an update cannot
-- send, recv, await, or perform any IO at all.
--
-- Contracts reach the state through ordinary machinery: name your
-- transition at top level and give it {-# PRE/POST #-}. Updates
-- force the new state to WHNF INSIDE the action, so a
-- transition's own contracts are checked before any other task
-- can see the state - a state-wide invariant belongs in POST,
-- the boundary-checked instrument. Refined fields on the state
-- type keep the extension's demand rule: the check travels with
-- the field and fires at first observation, so no task can ever
-- SEE an out-of-range field.
--
-- Waiting entries are served first-arrived, first-served, and the
-- queue is rescanned from the head after every commit (Ada's
-- eggshell epilogue, order pinned) - wake order is deterministic
-- and testable, like every schedule in this runtime.
--
-- Protected is ABSTRACT over an Int registry index (the Handle
-- discipline); the phantom parameter ties each value to its state
-- type.
--
-- MVar as sugar, for the record (not shipped until dogfooded):
--   type MVar a = Protected (Maybe a)
--   take p = entry p isJust (\(Just x) -> (Nothing, x))
--   put p x = entry p isNothing (\_ -> (Just x, ()))

data Protected s = MkProt Int

newProtected :: s -> IO (Protected s)
newProtected s = primProtNew s >>= \i -> return (MkProt i)

reading :: Protected s -> (s -> a) -> IO a
reading (MkProt p) f = primProtRead p f

updating :: Protected s -> (s -> (s, a)) -> IO a
updating (MkProt p) f = primProtUpdate p f

entry :: Protected s -> (s -> Bool) -> (s -> (s, a)) -> IO a
entry (MkProt p) g f = primProtEntry p g f
