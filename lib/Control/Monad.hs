module Control.Monad
  ( when, unless, void
  , mapM, mapM_, forM, forM_
  , sequence, sequence_
  , replicateM, replicateM_
  , filterM, foldM, zipWithM, zipWithM_
  , (>=>), (<=<), join
  , liftM, liftM2, ap
  , guard, MonadPlus (..), msum, mfilter
  ) where

import Control.Applicative (Alternative (..))

--  guard, as base has it since Alternative subsumed MonadPlus's
--  role here: pure () passes, empty prunes.
guard :: Alternative f => Bool -> f ()
guard True = pure ()
guard False = empty

--  MonadPlus: Alternative for monads. Both methods default, so the
--  Report-style `instance MonadPlus []` with no body is the whole
--  instance. IO's (exception-based in base) is absent, like its
--  Alternative.
class (Alternative m, Monad m) => MonadPlus m where
  mzero :: m a
  mzero = empty
  mplus :: m a -> m a -> m a
  mplus = (<|>)

instance MonadPlus Maybe
instance MonadPlus []

--  Base's is Foldable; list-only here, as asum.
msum :: MonadPlus m => [m a] -> m a
msum = foldr mplus mzero

mfilter :: MonadPlus m => (a -> Bool) -> m a -> m a
mfilter p ma = ma >>= \a -> if p a then return a else mzero

when :: Monad m => Bool -> m () -> m ()
when p act = if p then act else return ()

unless :: Monad m => Bool -> m () -> m ()
unless p act = if p then return () else act

void :: Monad m => m a -> m ()
void act = act >> return ()

--  mapM/mapM_/sequence/sequence_ are the Prelude's, re-exported.

forM :: Monad m => [a] -> (a -> m b) -> m [b]
forM xs f = mapM f xs

forM_ :: Monad m => [a] -> (a -> m b) -> m ()
forM_ xs f = mapM_ f xs

replicateM :: Monad m => Int -> m a -> m [a]
replicateM n act =
  if n <= 0 then return [] else sequence (replicate n act)

replicateM_ :: Monad m => Int -> m a -> m ()
replicateM_ n act =
  if n <= 0 then return () else act >> replicateM_ (n - 1) act

filterM :: Monad m => (a -> m Bool) -> [a] -> m [a]
filterM _ [] = return []
filterM p (x : xs) =
  p x >>= \keep ->
    filterM p xs >>= \ys ->
      return (if keep then x : ys else ys)

foldM :: Monad m => (b -> a -> m b) -> b -> [a] -> m b
foldM _ z [] = return z
foldM f z (x : xs) = f z x >>= \z2 -> foldM f z2 xs

zipWithM :: Monad m => (a -> b -> m c) -> [a] -> [b] -> m [c]
zipWithM f xs ys = sequence (zipWith f xs ys)

zipWithM_ :: Monad m => (a -> b -> m c) -> [a] -> [b] -> m ()
zipWithM_ f xs ys = sequence_ (zipWith f xs ys)

(>=>) :: Monad m => (a -> m b) -> (b -> m c) -> a -> m c
(>=>) f g x = f x >>= g

(<=<) :: Monad m => (b -> m c) -> (a -> m b) -> a -> m c
(<=<) g f x = f x >>= g

join :: Monad m => m (m a) -> m a
join m = m >>= \x -> x

liftM :: Monad m => (a -> b) -> m a -> m b
liftM f m = m >>= \x -> return (f x)

liftM2 :: Monad m => (a -> b -> c) -> m a -> m b -> m c
liftM2 f ma mb = ma >>= \a -> mb >>= \b -> return (f a b)

ap :: Monad m => m (a -> b) -> m a -> m b
ap mf ma = mf >>= \f -> ma >>= \a -> return (f a)
