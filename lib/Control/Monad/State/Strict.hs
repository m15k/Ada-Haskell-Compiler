module Control.Monad.State.Strict
  ( StateT (..), State, runState, evalState, execState
  , evalStateT, execStateT, mapStateT, withStateT
  , state, withState, mapState
  , get, put, modify, modify', gets, lift, liftIO
  , module Control.Monad
  ) where

-- mtl's Control.Monad.State.Strict (M142): transformers'
-- Control.Monad.Trans.State.Strict, a StateT of its own (a different
-- type from Control.Monad.State's, as in mtl) whose binds match the
-- state pair STRICTLY - the pair is forced at every step, the state
-- inside it is not. Without the MonadState class, as the lazy module.

import Control.Monad
import Data.Functor.Identity

newtype StateT s m a = StateT { runStateT :: s -> m (a, s) }

type State s = StateT s Identity

instance Monad m => Functor (StateT s m) where
  fmap f m = StateT (\s -> runStateT m s >>= \(a, s') -> return (f a, s'))

instance Monad m => Applicative (StateT s m) where
  pure a = StateT (\s -> return (a, s))
  StateT mf <*> StateT mx = StateT (\s -> do
    (f, s') <- mf s
    (x, s'') <- mx s'
    return (f x, s''))

instance Monad m => Monad (StateT s m) where
  return a = StateT (\s -> return (a, s))
  m >>= k = StateT (\s -> do
    (a, s') <- runStateT m s
    runStateT (k a) s')

state :: Monad m => (s -> (a, s)) -> StateT s m a
state f = StateT (return . f)

runState :: State s a -> s -> (a, s)
runState m s = runIdentity (runStateT m s)

evalState :: State s a -> s -> a
evalState m s = fst (runState m s)

execState :: State s a -> s -> s
execState m s = snd (runState m s)

evalStateT :: Monad m => StateT s m a -> s -> m a
evalStateT m s = do
  (a, _) <- runStateT m s
  return a

execStateT :: Monad m => StateT s m a -> s -> m s
execStateT m s = do
  (_, s') <- runStateT m s
  return s'

mapStateT :: (m (a, s) -> n (b, s)) -> StateT s m a -> StateT s n b
mapStateT f m = StateT (f . runStateT m)

withStateT :: (s -> s) -> StateT s m a -> StateT s m a
withStateT f m = StateT (runStateT m . f)

withState :: (s -> s) -> State s a -> State s a
withState = withStateT

mapState :: ((a, s) -> (b, s)) -> State s a -> State s b
mapState f = mapStateT (Identity . f . runIdentity)

get :: Monad m => StateT s m s
get = state (\s -> (s, s))

put :: Monad m => s -> StateT s m ()
put s = state (\_ -> ((), s))

modify :: Monad m => (s -> s) -> StateT s m ()
modify f = state (\s -> ((), f s))

modify' :: Monad m => (s -> s) -> StateT s m ()
modify' f = do
  s <- get
  put $! f s

gets :: Monad m => (s -> a) -> StateT s m a
gets f = state (\s -> (f s, s))

lift :: Monad m => m a -> StateT s m a
lift m = StateT (\s -> do
  a <- m
  return (a, s))

liftIO :: IO a -> StateT s IO a
liftIO = lift
