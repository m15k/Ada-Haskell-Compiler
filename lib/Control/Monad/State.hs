module Control.Monad.State
  ( StateT (..), State, runState, evalState, execState
  , evalStateT, execStateT, state, withState, mapState
  , get, put, modify, modify', gets, lift, liftIO
  , module Control.Monad
  ) where

-- mtl's State without the MonadState class (M142). Haskell 2010 has
-- no multi-parameter classes, so get/put/modify are plain functions on
-- StateT. Code written against `MonadState s m =>` does not compile
-- (EXCLUSIONS); code that uses State / StateT directly does.

import Control.Monad
import Data.Functor.Identity

newtype StateT s m a = StateT { runStateT :: s -> m (a, s) }

type State s = StateT s Identity

instance Monad m => Functor (StateT s m) where
  fmap f (StateT g) = StateT (\s -> g s >>= \(a, s') -> return (f a, s'))

instance Monad m => Applicative (StateT s m) where
  pure a = StateT (\s -> return (a, s))
  StateT mf <*> StateT mx = StateT (\s -> do
    (f, s1) <- mf s
    (x, s2) <- mx s1
    return (f x, s2))

instance Monad m => Monad (StateT s m) where
  return = pure
  StateT m >>= k = StateT (\s -> m s >>= \(a, s') -> runStateT (k a) s')

state :: Monad m => (s -> (a, s)) -> StateT s m a
state f = StateT (return . f)

runState :: State s a -> s -> (a, s)
runState m s = runIdentity (runStateT m s)

evalState :: State s a -> s -> a
evalState m s = fst (runState m s)

execState :: State s a -> s -> s
execState m s = snd (runState m s)

evalStateT :: Monad m => StateT s m a -> s -> m a
evalStateT m s = runStateT m s >>= \(a, _) -> return a

execStateT :: Monad m => StateT s m a -> s -> m s
execStateT m s = runStateT m s >>= \(_, s') -> return s'

withState :: (s -> s) -> State s a -> State s a
withState f m = modify f >> m

mapState :: ((a, s) -> (b, s)) -> State s a -> State s b
mapState f m = StateT (\s -> Identity (f (runState m s)))

get :: Monad m => StateT s m s
get = StateT (\s -> return (s, s))

put :: Monad m => s -> StateT s m ()
put s = StateT (\_ -> return ((), s))

modify :: Monad m => (s -> s) -> StateT s m ()
modify f = StateT (\s -> return ((), f s))

modify' :: Monad m => (s -> s) -> StateT s m ()
modify' f = StateT (\s -> let s' = f s in s' `seq` return ((), s'))

gets :: Monad m => (s -> a) -> StateT s m a
gets f = StateT (\s -> return (f s, s))

lift :: Monad m => m a -> StateT s m a
lift m = StateT (\s -> m >>= \a -> return (a, s))

liftIO :: IO a -> StateT s IO a
liftIO = lift
