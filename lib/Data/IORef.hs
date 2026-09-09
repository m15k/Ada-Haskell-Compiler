module Data.IORef
  ( IORef, newIORef, readIORef, writeIORef
  , modifyIORef, modifyIORef', atomicModifyIORef, atomicModifyIORef'
  , atomicWriteIORef
  ) where

-- A mutable cell in IO: base's Data.IORef over four primitives. The
-- runtime keeps the cell as a one-field node updated in place (behind
-- the own collector's write barrier). Green threads switch only at
-- their own scheduling points, never inside a read or a write, so the
-- "atomic" variants are the plain ones under AHC's deterministic
-- scheduler - and sparks are pure, so they never touch one.

newIORef :: a -> IO (IORef a)
newIORef = primNewIORef

readIORef :: IORef a -> IO a
readIORef = primReadIORef

writeIORef :: IORef a -> a -> IO ()
writeIORef = primWriteIORef

-- Lazy, like base's: the new value is a thunk over the old one.
modifyIORef :: IORef a -> (a -> a) -> IO ()
modifyIORef r f = readIORef r >>= \x -> writeIORef r (f x)

-- Strict: the new value is forced before it is stored, so a long
-- chain of modifications does not build a chain of thunks.
modifyIORef' :: IORef a -> (a -> a) -> IO ()
modifyIORef' r f = readIORef r >>= \x -> let y = f x in y `seq` writeIORef r y

atomicModifyIORef :: IORef a -> (a -> (a, b)) -> IO b
atomicModifyIORef r f =
  readIORef r >>= \x -> case f x of (y, b) -> writeIORef r y >> return b

atomicModifyIORef' :: IORef a -> (a -> (a, b)) -> IO b
atomicModifyIORef' r f =
  readIORef r >>= \x -> case f x of
    (y, b) -> y `seq` b `seq` (writeIORef r y >> return b)

atomicWriteIORef :: IORef a -> a -> IO ()
atomicWriteIORef = writeIORef

instance Eq (IORef a) where
  a == b = primSameIORef a b
